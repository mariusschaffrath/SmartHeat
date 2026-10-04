"""Constants for the SmartHeat integration."""
from datetime import timedelta

DOMAIN = "smartheat"

CONF_HOST = "host"
CONF_PORT = "port"
CONF_DEVICE_ID = "device_id"
CONF_BASE_URL = "base_url"
CONF_CONNECTION_MODE = "connection_mode"

MODE_LOCAL = "local"
MODE_CLOUD = "cloud"

DEFAULT_HOST = "192.168.178.188"
DEFAULT_PORT = 80
DEFAULT_BASE_URL = "https://wifi4heat.azurewebsites.net"
SCAN_INTERVAL = timedelta(seconds=30)

# Dielle Status Codes
STATUS_MAPPINGS = {
    0: "Aus",
    1: "Zündung Phase 1",
    2: "Zündung Phase 2",
    3: "Zündung Phase 3",
    4: "Stabilisierung",
    5: "Heizbetrieb",
    6: "Modulation",
    7: "Ausschalten",
    8: "Sicherheit",
    9: "Blockiert",
    10: "Warten",
    11: "Standby",
    12: "Ascheentleerung",
    13: "Scheitholzbetrieb",
}

# Dielle Commands
CMD_TURN_ON = "05040000"
CMD_TURN_OFF = "05050000"
CMD_SET_TEMP_PREFIX = "050e01ed"
CMD_SET_FAN_FLUR_PREFIX = "050e023f"  # Luftheizung Flur (Riscaldamento / 023f)
CMD_SET_FAN_KANAL1_PREFIX = "050e0266"  # Luftzufuhr 1 (Brennraum / 0266)
CMD_SET_FAN_KANAL2_PREFIX = "050e027e"  # Luftzufuhr 2 (Brennraum / 027e)
CMD_SET_POWER_PREFIX = "050e016c"

# Pellets Tank Configuration
DEFAULT_TANK_CAPACITY_KG = 20.0
DEFAULT_BAG_WEIGHT_KG = 15.0

# Hourly Consumption Rates (kg/h) based on Ghibli Kombi 10kW
CONSUMPTION_RATES = {
    1: 0.65,
    2: 0.95,
    3: 1.35,
    4: 1.80,
    5: 2.25,
    6: 0.65,  # Auto / Modulation
}

# Dielle Hardware Alarm Mappings (Er01..Er42)
DIELLE_ALARM_MAPPINGS = {
    1: {
        "name": "Überhitzungsthermostat Kessel/Wasser",
        "beschreibung": "Überhitzung Wassertasche / Kesselkörper festgestellt.",
        "abhilfe": "Abkühlung abwarten, Pumpe & Vorlauf prüfen. Alarm quittieren.",
    },
    2: {
        "name": "Sicherheitsdruckwächter Wasserdruck",
        "beschreibung": "Druckfehler im Wasserkreislauf.",
        "abhilfe": "Anlagendruck prüfen (Soll: 1.2–1.5 bar) und Alarm quittieren.",
    },
    3: {
        "name": "Erloschene Flamme / Pellets leer",
        "beschreibung": "Keine Flamme im Heizbetrieb oder Pellettank leer.",
        "abhilfe": "Pellets nachfüllen, Brenner kontrollieren und Alarm quittieren.",
    },
    4: {
        "name": "Fehlzündung",
        "beschreibung": "Temperaturanstieg bei Zündung zu gering.",
        "abhilfe": "Brennraum reinigen, Glühkerze prüfen und Zündung erneut starten.",
    },
    5: {
        "name": "Rauchgastemperaturfühler defekt",
        "beschreibung": "Rauchgastemperaturfühler defekt oder unterbrochen.",
        "abhilfe": "Fühleranschluss an Platine sowie Verkabelung prüfen.",
    },
    7: {
        "name": "Abgasgebläse Drehzahlfehler",
        "beschreibung": "Der Drehzahlgeber (Encoder) des Abgasventilators meldet eine Blockade oder Unregelmäßigkeit.",
        "abhilfe": "Rauchgasventilator auf Verschmutzung oder mechanische Blockade prüfen.",
    },
    8: {
        "name": "Rauchgas-Übertemperatur",
        "beschreibung": "Die Rauchgastemperatur hat den zulässigen Maximalwert überschritten.",
        "abhilfe": "Ofen abkühlen lassen, Wärmetauscher und Kaminrohr auf Verrußung prüfen.",
    },
    12: {
        "name": "Pelletmangel / Dosierer",
        "beschreibung": "Pelletförderung unzureichend oder Zündtopf nicht befüllt.",
        "abhilfe": "Pelletbehälter prüfen, Pellets nachfüllen und Alarm quittieren.",
    },
    39: {
        "name": "Unterdruckwächter Brennraum / Kaminzug",
        "beschreibung": "Schornsteinzug unzureichend oder Brennraumtür/Aschelade undicht.",
        "abhilfe": "Brennraumtür schließen, Dichtungen und Schornsteinzug prüfen.",
    },
    41: {
        "name": "Luftstrom-Minimum unterschritten",
        "beschreibung": "Verbrennungsluftstrom liegt unter dem Schwellwert.",
        "abhilfe": "Luftansaugrohr und Gebläse auf Verstopfung prüfen.",
    },
    42: {
        "name": "Maximaler Luftstrom / Tür offen",
        "beschreibung": "Luftstrom über Schwellwert oder Brennraumtür steht offen.",
        "abhilfe": "Brennraumtür schließen und Sensor prüfen.",
    },
}
