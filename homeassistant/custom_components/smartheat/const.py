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
