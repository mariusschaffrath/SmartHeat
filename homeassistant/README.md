# SmartHeat Home Assistant Integration

Offizielle Home Assistant Integration für den **Dielle Pelletofen (Ghibli Kombi 10 kW)** über das Dielle / 4Heat Cloud-Protokoll (`wifi4heat.azurewebsites.net`).

---

## 🌟 Features

- **Sensoren:**
  - `sensor.smartheat_raumtemperatur`: Raumtemperatur in °C
  - `sensor.smartheat_abgastemperatur`: Abgastemperatur in °C
  - `sensor.smartheat_solltemperatur`: Eingestellte Zieltemperatur in °C
  - `sensor.smartheat_betriebsstatus`: Klartext-Status (*Aus*, *Zündung*, *Heizbetrieb*, *Standby*, *Modulation*, etc.)
  - `sensor.smartheat_leistungsstufe`: Aktuelle Brennstufe (P1 bis P5)
  - `sensor.smartheat_geblase_flur_kanal_1`: Lüfterkanal 1 (Flur) Stufe 0..5 oder Auto
  - `sensor.smartheat_pellet_vorrat`: Verbleibende Pellets in Kilogramm (kg)
  - `sensor.smartheat_pellet_fullstand`: Füllstand in Prozent (%)
  - `sensor.smartheat_pellet_restlaufzeit`: Restbrenndauer in Stunden (h) basierend auf aktuellem Verbrauch
  - `sensor.smartheat_scheitholzbetrieb`: Zeigt an, ob Scheitholz aktiv verbrannt wird (pausiert Pelletverbrauch)

- **Thermostat / Climate Entity:**
  - `climate.smartheat_pelletofen`:
    - Ein- und Ausschalten des Ofens (*Heat* / *Off*)
    - Zieltemperatur per Schieberegler oder Apple HomeKit einstellen (16°C – 28°C)
    - Gebläsestufe für den Flur regeln (Stufe 1–5, Auto, Aus)

- **Services:**
  - `smartheat.refill_bag`: +15 kg Pellets nachfüllen (Deckelung bei 20 kg)
  - `smartheat.refill_full`: Voll befüllen (20 kg / 100%)

---

## 🚀 Installation

### Option 1: Custom Component (Empfohlen)

1. Kopiere den Ordner `custom_components/smartheat` in das Verzeichnis `/config/custom_components/` deiner Home Assistant Installation (z. B. auf `192.168.178.131:8123`).
2. Starte Home Assistant neu (**Einstellungen** -> **System** -> **Neu starten**).
3. Gehe zu **Einstellungen** -> **Geräte & Dienste** -> **Integration hinzufügen**.
4. Suche nach **SmartHeat Dielle Pellet Stove**.
5. Gib deine Dielle Zugangsdaten (E-Mail und Passwort) ein. Die Device-ID wird automatisch ermittelt!

### Option 2: Schneller REST-Sensor via `configuration.yaml` (Ohne Custom Component)

Falls du keine Dateien auf den Server kopieren möchtest, kannst du folgende Sensoren direkt in `/config/configuration.yaml` einfügen:

```yaml
# In configuration.yaml
rest:
  - resource: "https://wifi4heat.azurewebsites.net/api/devices/Summary?ids=DEINE_DEVICE_KEY"
    scan_interval: 30
    headers:
      Authorization: "Bearer DEIN_CLOUD_TOKEN"
      Accept: "application/json"
    sensor:
      - name: "Pelletofen Raumtemperatur"
        value_template: >-
          {{ ((value_json[0].Values[0][20:24] | int(base=16)) * 0.1) | round(1) }}
        unit_of_measurement: "°C"
        device_class: temperature

      - name: "Pelletofen Abgastemperatur"
        value_template: >-
          {{ (value_json[0].Values[2][6:10] | int(base=16)) | round(1) }}
        unit_of_measurement: "°C"
        device_class: temperature

      - name: "Pelletofen Solltemperatur"
        value_template: >-
          {{ ((value_json[0].Values[1][24:28] | int(base=16)) * 0.1) | round(1) }}
        unit_of_measurement: "°C"
        device_class: temperature

      - name: "Pelletofen Status Code"
        value_template: >-
          {{ value_json[0].Values[0][10:12] | int(base=16) }}
```

---

## 🍎 Apple Home / Siri Integration via Home Assistant

Sobald `climate.smartheat_pelletofen` in Home Assistant eingerichtet ist, wird der Ofen automatisch an die **HomeKit Bridge** von Home Assistant übergeben.
Damit kannst du den Ofen auch direkt mit Siri auf deinem HomePod / iPhone steuern:
- *„Hey Siri, stelle den Pelletofen auf 22 Grad.“*
- *„Hey Siri, schalte den Pelletofen ein.“*
