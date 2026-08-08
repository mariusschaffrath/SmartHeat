# 🔥 SmartHeat – Dielle & 4Heat Smart Heating System (iOS & macOS)

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-16.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B-lightgrey.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**SmartHeat** ist eine hochmoderne, nativ in Swift & SwiftUI entwickelte Anwendung zur Steuerung und Überwachung von **Dielle & 4Heat** Pellet- und Wasseröfen. Die App vereint lokale Echtzeit-Steuerung über das WLAN-Netzwerk mit weltweit verfügbarer Steuerung über die 4Heat Azure Cloud API.

---

## 🌟 Hauptfunktionen (Features)

- 📊 **Echtzeit-Telemetrie & Dashboard**: Live-Anzeige von Raumtemperatur, Abgastemperatur, Kesseltemperatur (bei Wasseröfen), Wasserdruck und Betriebsstatus (*Zündung, Betrieb, Modulation, Standby, etc.*).
- 🎛️ **Präzises Thermostat**: Interaktives Thermostat-Wählrad zur Einstellung der Zieltemperatur in 0,5°C-Schritten.
- ⚡ **Multi-Kanal Protokoll-Architektur**:
  - **Lokale TCP-Sockets (Port 80)**: Geringste Latenz im Heimnetzwerk mit automatischer UDP-Discovery.
  - **4Heat Azure Cloud REST API**: Sichere Fernsteuerung von unterwegs über OAuth2 Bearer-Tokens.
- 🚨 **Robustes Fehlercode-System (`ERR-101` bis `ERR-302`)**: Endkundenfreundliche Popup-Meldungen mit eindeutigen Fehlercodes, detaillierter Ursachenanalyse und konkreten Handlungsempfehlungen.
- 🔒 **Interaktions-Sperre & Hysterese-Schutz**: Verhindert versehentliche Mehrfachbefehle und schützt den Ofen vor zu schnellen Schaltzyklen.

---

## 🏗️ Systemarchitektur

```mermaid
graph TD
    UI[ContentView / DashboardView] --> VM[StoveViewModel]
    
    subgraph Services Layer
        VM --> AUTH[AuthService]
        VM --> CLOUD[CloudService]
        VM --> SOCKET[StoveSocketService]
        VM --> UDP[UDPDiscoveryService]
        VM --> ERR[StoveError System]
    END
    
    AUTH -->|OAuth2 /Token| AZURE[4Heat Azure Cloud]
    CLOUD -->|REST GET Summary / POST command| AZURE
    SOCKET -->|TCP Port 80 + \\n Delimiter| STOVE[Dielle / 4Heat Wi-Fi Module]
    UDP -->|UDP Broadcast| STOVE
```

---

## 🌐 4Heat Cloud REST API Spezifikation

Die Anwendung kommuniziert mit dem 4Heat-Server unter `https://wifi4heat.azurewebsites.net`:

| Endpunkt | Methode | Beschreibung | Authentifizierung |
| :--- | :--- | :--- | :--- |
| `/Token` | `POST` | Erzeugt ein OAuth2 `access_token` | Form-URL-Encoded (`grant_type=password`) |
| `/api/devices` | `GET` | Liefert die Liste aller registrierten Öfen inkl. `DeviceKey` (GUID) | `Bearer <token>` |
| `/api/devices/Summary?id={DeviceKey}` | `GET` | Liefert Telemetriedaten & Sensorwerte als Hex-Array | `Bearer <token>` |
| `/api/devices/command` | `POST` | Sendet Schaltbefehle (EIN, AUS, Sollwert) | `Bearer <token>` + JSON Body |

### Command Payload Format:
```json
{
  "DeviceId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "Comando": ["1", "J30253000000000001"]
}
```

---

## 🔌 Lokales TCP Socket-Protokoll

Bei direkter WLAN-Verbindung kommuniziert die App über **TCP Port 80**:
- **Format**: JSON-Array als UTF-8 mit zwingendem Zeilenumbruch-Delimiter (`\n`).
- **Abfrage-Befehl**: `["SEL","0"]\n`
- **Schalt-Befehl (SEC-Layer)**: `["SEC","1","J30253000000000001"]\n`
- **Parameter-Schreiben (SEC-Layer)**: `["SEC","1","B20493000000000220"]\n` (Sollwert 22.0°C)

---

## 🚨 Fehlercode-Referenz (Endkunden-Diagnose)

Wenn Störungen auftreten, zeigt die App ein zentrales Popup-Fenster mit konkreten Hilfe-Hinweisen an:

| Fehlercode | Titel | Ursache / Beschreibung | Empfohlene Behebung |
| :--- | :--- | :--- | :--- |
| **`ERR-101`** | **Anmeldefehler (Cloud)** | Ungültige E-Mail-Adresse oder Passwort. | Zugangsdaten in den Einstellungen prüfen. |
| **`ERR-102`** | **Keine Cloud-Verbindung** | Server offline oder Smartphone hat kein Internet. | Internetverbindung / WLAN / Mobilfunk prüfen. |
| **`ERR-103`** | **Kein Ofen gefunden** | Keine verknüpfte GUID im Konto vorhanden. | Ofen in der 4Heat App mit Konto verknüpfen. |
| **`ERR-201`** | **WLAN-Verbindung fehlgeschlagen** | Socket-Verbindung an Port 80 abgelehnt. | Prüfen, ob Smartphone im selben WLAN ist. |
| **`ERR-202`** | **Keine Antwort vom Ofen** | Ofen reagiert nicht auf WLAN-Anfragen. | WLAN-Modul des Ofens kurz vom Strom trennen. |
| **`ERR-301`** | **Schaltbefehl fehlgeschlagen** | Befehl konnte nicht übermittelt werden. | Prüfen, ob Ofen eingeschaltet & online ist. |
| **`ERR-302`** | **Sitzung abgelaufen** | Cloud-Security-Token ist abgelaufen. | In den Einstellungen ab- und neu anmelden. |

---

## 💻 Entwicklung & Kompilierung

### Voraussetzungen:
- macOS 14.0 oder neuer
- Xcode 15.0 oder neuer
- Swift 5.9 / 6.0

### Projekt bauen:
```bash
git clone https://github.com/marschaff/SmartHeat.git
cd SmartHeat
xcodebuild -project SmartHeat.xcodeproj -scheme SmartHeat -sdk iphonesimulator build
```

---

## 📄 Lizenz & Urheberrecht

© 2026 Marius Schaffrath. Alle Rechte vorbehalten.
Erstellt für die Steuerung von Dielle & 4Heat Heizsystemen.
