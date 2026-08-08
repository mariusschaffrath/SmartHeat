#!/usr/bin/env python3
"""
🔥 SmartHeat Stove & Cloud Simulator (Gegenspieler)
Simuliert sowohl ein lokales 4Heat/Dielle WLAN-Socket-Modul (Port 8080)
als auch die 4Heat Azure Cloud REST API (Port 8000).
"""

import sys
import os
import time
import json
import socket
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

# --- Simulierter Zustand des Ofens ---
class StoveState:
    def __init__(self):
        self.lock = threading.Lock()
        self.status = 11         # 0=AUS, 2=Zündung, 5=Betrieb, 6=Modulation, 11=Standby, 9=Blockierung
        self.room_temp = 21.5    # in °C
        self.target_temp = 22.0  # in °C
        self.exhaust_temp = 24.0 # in °C
        self.water_temp = 45.0   # in °C
        self.water_pressure = 1.5# in bar
        self.device_key = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
        self.serial_number = "25016460"
        self.device_name = "Dielle Simulator-Ofen"
        self.is_water_stove = True

    def get_status_str(self):
        mapping = {0: "AUS", 1: "Check Up", 2: "Zündung", 3: "Stabilisierung", 5: "Betrieb", 6: "Modulation", 7: "Reinigung", 8: "Sicherheit", 9: "Blockierung", 11: "Standby"}
        return mapping.get(self.status, f"Code {self.status}")

    def generate_hex_array(self):
        with self.lock:
            # 1. Hauptwerte (Block 0)
            status_hex = f"{self.status:02x}"
            exhaust_hex = f"{int(self.exhaust_temp * 10):04x}"
            room_hex = f"{int(self.room_temp * 10):04x}"
            
            # Format: 0000000000 + Status(2) + Exhaust(4) + 0000 + Room(4) + ...
            main_block = f"0000000000{status_hex}{exhaust_hex}0000{room_hex}000000000000000000000000"
            
            # 2. Parameter Blöcke (0e01ed -> Target Room Temp, 0e0180 -> Water Target)
            target_hex = f"{int(self.target_temp * 10):04x}"
            target_block = f"0e01ed{target_hex}"
            
            water_hex = f"{int(self.water_temp * 10):04x}"
            water_block = f"0e0180{water_hex}"
            
            # Array aus 14 Blöcken simulieren
            hex_array = [main_block] + ["00000000000000"] * 12 + [target_block, water_block]
            return hex_array

stove = StoveState()

# --- 1. LOKALER TCP SOCKET SERVER (Port 8080) ---
class StoveSocketServer(threading.Thread):
    def __init__(self, host="0.0.0.0", port=8080):
        super().__init__(daemon=True)
        self.host = host
        self.port = port

    func_map = {}

    def run(self):
        server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_socket.bind((self.host, self.port))
        server_socket.listen(5)
        print(f"✅ WLAN TCP Socket-Simulator gestartet auf {self.host}:{self.port}")

        while True:
            try:
                client_sock, addr = server_socket.accept()
                print(f"\n[WLAN SOCKET] 🔌 Neue Verbindung von {addr[0]}:{addr[1]}")
                threading.Thread(target=self.handle_client, args=(client_sock, addr), daemon=True).start()
            except Exception as e:
                print(f"[WLAN SOCKET ERROR] {e}")
                break

    def handle_client(self, sock, addr):
        buffer = ""
        while True:
            try:
                data = sock.recv(1024)
                if not data:
                    break
                
                buffer += data.decode('utf-8', errors='ignore')
                
                # Zeilenumbruch-getrennte Pakete verarbeiten
                while '\n' in buffer or ']' in buffer:
                    if '\n' in buffer:
                        packet, buffer = buffer.split('\n', 1)
                    else:
                        break
                    
                    packet = packet.strip()
                    if not packet:
                        continue
                    
                    print(f"[WLAN RECV] ➔ {packet}")
                    response = self.process_packet(packet)
                    if response:
                        print(f"[WLAN SEND] ⬅️ {response.strip()}")
                        sock.sendall(response.encode('utf-8'))
            except Exception as e:
                print(f"[WLAN SOCKET CLIENT ERROR] {e}")
                break
        sock.close()
        print(f"[WLAN SOCKET] ❌ Verbindung geschlossen: {addr[0]}")

    def process_packet(self, packet):
        try:
            # Erwarte JSON Array Format ["SEL","0"] oder ["SEC","1","..."]
            data = json.loads(packet)
            cmd = data[0] if isinstance(data, list) and len(data) > 0 else ""
            
            if cmd == "SEL":
                hex_array = stove.generate_hex_array()
                # Format: ["SEL","0",["block1","block2",...]]
                resp = ["SEL", "0", hex_array]
                return json.dumps(resp) + "\n"
                
            elif cmd == "SEC":
                raw_code = data[2] if len(data) > 2 else ""
                print(f"  [EXEC COMMAND] SEC Code: {raw_code}")
                
                # Einschalten J30253
                if "J30253" in raw_code:
                    stove.status = 2 # Zündung
                    print("  🔥 Ofen-Status geändert: ZÜNDUNG")
                    threading.Thread(target=self.simulate_ignition_sequence, daemon=True).start()
                    return json.dumps(["SEC", "1", ["J30253000000000001", "1"]]) + "\n"
                
                # Ausschalten J30254
                elif "J30254" in raw_code:
                    stove.status = 7 # Reinigung / Ausschalten
                    print("  ❄️ Ofen-Status geändert: REINIGUNG / AUSSCHALTEN")
                    threading.Thread(target=self.simulate_cooldown_sequence, daemon=True).start()
                    return json.dumps(["SEC", "1", ["J30254000000000001", "1"]]) + "\n"
                
                # Sollwert ändern B20493000000000220
                elif raw_code.startswith("B20493"):
                    val_raw = raw_code[7:]
                    val_num = int(val_raw) / 10.0
                    stove.target_temp = val_num
                    print(f"  🌡️ Ziel-Temperatur geändert auf {val_num}°C")
                    return json.dumps(["SEC", "1", [raw_code, "1"]]) + "\n"
                
                return json.dumps(["SEC", "1", [raw_code, "1"]]) + "\n"
                
            elif cmd.startswith("I") or cmd.startswith("A"):
                return json.dumps([cmd, "0"]) + "\n"

        except Exception as e:
            print(f"  [PACKET PARSE ERROR] {e}")
        return json.dumps(["ERR", "99"]) + "\n"

    def simulate_ignition_sequence(self):
        time.sleep(4)
        if stove.status == 2:
            stove.status = 3 # Stabilisierung
            print("  🔥 Ofen-Status: STABILISIERUNG")
            time.sleep(4)
            stove.status = 5 # Betrieb
            stove.exhaust_temp = 140.0
            stove.room_temp += 0.5
            print("  🔥 Ofen-Status: BETRIEB (140°C Abgas)")

    def simulate_cooldown_sequence(self):
        time.sleep(4)
        if stove.status == 7:
            stove.status = 0 # AUS
            stove.exhaust_temp = 25.0
            print("  ❄️ Ofen-Status: AUS")


# --- 2. CLOUD REST API MOCK SERVER (Port 8000) ---
class CloudRESTHandler(BaseHTTPRequestHandler):
    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))

    def do_POST(self):
        path = urlparse(self.path).path
        content_len = int(self.headers.get('Content-Length', 0))
        body_bytes = self.rfile.read(content_len) if content_len > 0 else b''
        
        print(f"\n[CLOUD REST POST] ➔ {path}")

        # 1. Login Token Endpoint
        if path == "/Token":
            print("  [CLOUD AUTH] Token-Anfrage empfangen.")
            response = {
                "access_token": "mock_bearer_token_secret_12345",
                "token_type": "bearer",
                "expires_in": 86400,
                "userName": "marius@example.com"
            }
            self._send_json(response, 200)
            return

        # 2. Command Endpoint
        elif path.endswith("/command") or path.endswith("/Command"):
            try:
                body_json = json.loads(body_bytes.decode('utf-8'))
                device_id = body_json.get("DeviceId") or body_json.get("DeviceKey")
                comando = body_json.get("Comando") or body_json.get("Command")
                
                print(f"  [CLOUD CMD] Gerät: {device_id}, Befehl: {comando}")
                
                if isinstance(comando, list) and len(comando) > 1:
                    raw_cmd = comando[1]
                    if "J30253" in raw_cmd:
                        stove.status = 5
                        stove.exhaust_temp = 145.0
                        print("  🔥 Cloud-Befehl: EINSCHALTEN -> BETRIEB")
                    elif "J30254" in raw_cmd:
                        stove.status = 0
                        stove.exhaust_temp = 25.0
                        print("  ❄️ Cloud-Befehl: AUSSCHALTEN -> AUS")
                    elif raw_cmd.startswith("B20493"):
                        val_num = int(raw_cmd[7:]) / 10.0
                        stove.target_temp = val_num
                        print(f"  🌡️ Cloud-Befehl: ZIELTEMP -> {val_num}°C")

                self._send_json({"Result": "OK", "Status": 200}, 200)
            except Exception as e:
                self._send_json({"Error": str(e)}, 400)
            return

        self._send_json({"Message": "Not Found"}, 404)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        print(f"\n[CLOUD REST GET] ➔ {path} Query: {query}")

        # 1. Device List Endpoint
        if path.endswith("/devices") or path.endswith("/Devices"):
            response = [
                {
                    "DeviceKey": stove.device_key,
                    "Name": stove.device_name,
                    "SerialNumber": stove.serial_number,
                    "IsConnected": True
                }
            ]
            self._send_json(response, 200)
            return

        # 2. Device Summary / Telemetry Endpoint
        elif path.endswith("/Summary") or path.endswith("/summary"):
            hex_array = stove.generate_hex_array()
            response = [
                {
                    "DeviceKey": stove.device_key,
                    "Values": hex_array
                }
            ]
            self._send_json(response, 200)
            return

        self._send_json({"Message": "Not Found"}, 404)

    def log_message(self, format, *args):
        return # Standard HTTP Access-Logs unterdrücken


class CloudServer(threading.Thread):
    def __init__(self, host="0.0.0.0", port=8000):
        super().__init__(daemon=True)
        self.host = host
        self.port = port

    def run(self):
        httpd = HTTPServer((self.host, self.port), CloudRESTHandler)
        print(f"✅ Cloud REST API Simulator gestartet auf http://{self.host}:{self.port}")
        httpd.serve_forever()


# --- 3. INTERAKTIVE STEUERUNGS-KONSOLE FOR MARIUS ---
def interactive_console():
    time.sleep(1)
    print("\n=======================================================")
    print("🔥 SMARTHEAT OFEN-SIMULATOR STEUERZENTRALE")
    print("=======================================================")
    print("Mit dieser Konsole kannst du Messwerte und Fehler simulieren,")
    print("um die Reaktionen der SmartHeat-App live zu testen!\n")
    
    while True:
        print(f"\nAktueller Status: [{stove.get_status_str()}] | Raum: {stove.room_temp}°C | Ziel: {stove.target_temp}°C | Abgas: {stove.exhaust_temp}°C")
        print("  [1] Raumtemperatur ändern")
        print("  [2] Ofen-Status ändern (Standby, Zündung, Betrieb, Blockierung)")
        print("  [3] Abgastemperatur ändern")
        print("  [4] Fehler-Zustand auslösen (Code 9: Blockierung)")
        print("  [5] Ofen ausschalten")
        print("  [q] Beenden")
        
        choice = input("Wähle eine Option (1-5/q): ").strip()
        
        if choice == "1":
            try:
                val = float(input("Neue Raumtemperatur in °C (z. B. 23.5): "))
                stove.room_temp = val
                print(f"✅ Raumtemperatur auf {val}°C gesetzt.")
            except ValueError:
                print("Ungültige Zahl.")
        elif choice == "2":
            print("Status-Codes: 0=AUS, 2=Zündung, 5=Betrieb, 6=Modulation, 9=Blockierung, 11=Standby")
            try:
                val = int(input("Status-Code eingeben: "))
                stove.status = val
                print(f"✅ Status auf Code {val} ({stove.get_status_str()}) gesetzt.")
            except ValueError:
                print("Ungültige Zahl.")
        elif choice == "3":
            try:
                val = float(input("Neue Abgastemperatur in °C: "))
                stove.exhaust_temp = val
                print(f"✅ Abgastemperatur auf {val}°C gesetzt.")
            except ValueError:
                print("Ungültige Zahl.")
        elif choice == "4":
            stove.status = 9
            print("⚠️ FEHLER SIMULIERT: Code 9 (Blockierung). Die App sollte jetzt den Zustand anzeigen.")
        elif choice == "5":
            stove.status = 0
            stove.exhaust_temp = 20.0
            print("❄️ Ofen auf AUS gesetzt.")
        elif choice.lower() == "q":
            print("Beende Simulator...")
            os._exit(0)

if __name__ == "__main__":
    print("Starte SmartHeat Gegenspieler-Simulator...")
    
    # 1. Start Socket Server (Port 8080)
    socket_server = StoveSocketServer(port=8080)
    socket_server.start()
    
    # 2. Start Cloud REST Server (Port 8000)
    cloud_server = CloudServer(port=8000)
    cloud_server.start()
    
    # 3. Start Interactive Console
    interactive_console()
