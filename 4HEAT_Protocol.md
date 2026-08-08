# 4HEAT Protocol Documentation (Dielle Stove)

This document contains the reverse-engineered communication basics for the SmartHeat APP.

## 1. Connection Methods

### Local (WLAN)
- **Protocol:** TCP Sockets
- **Port:** 80
- **Format:** JSON Array containing the command string.
- **Example:** `["j30253000000000001"]`
- **Discovery:** UDP Broadcast to `255.255.255.255` on Port 6666. Response on Port 5555.

### Remote (Cloud)
- **Endpoint:** `https://wifi4heat.azurewebsites.net/api/devices/command`
- **Method:** POST
- **Body:**
  ```json
  {
    "id": "YOUR_DEVICE_ID",
    "comando": ["1", "j30253000000000001"]
  }
  ```
- **Auth:** HTTP Header `Authorization: Bearer <Token>`

## 2. Command String Structure (18 Characters)

Commands always start with a specific letter followed by a numeric sequence.

| Prefix | Function | Description |
| :--- | :--- | :--- |
| **I** | Information | Request current status or sensor values |
| **A** | Read | Read specific configuration parameters |
| **B** | Write | Set a specific parameter (e.g., target temperature) |
| **j / J** | Control | Execution commands (On/Off/Unlock) |

### Essential Command List

| Command | String Code |
| :--- | :--- |
| **Turn ON** | `j30253000000000001` |
| **Turn OFF** | `j30254000000000001` |
| **Unlock (Reset Error)** | `j30255000000000001` |
| **Read Status** | `I30001000000000000` |
| **Smoke Temp** | `I30005000000000000` |
| **Water Temp** | `I30017000000000000` |
| **Target Temp (Read)** | `A20180000000000000` |
| **Target Temp (Write)** | `B20180000000000000` (value needs to be encoded in trailing zeros) |

## 3. Data Encoding & Decoding

- **Multipliers:** The second digit of the response determines the scaling.
  - Type `5`: Value / 100 (Common for temperatures like 22.50 °C -> `2250`)
  - Type `3`: Direct integer value.
- **Padding:** Values are typically padded with leading zeros to maintain fixed string length.

## 4. Hardware Details
- **Module:** ESP32 (Espressif)
- **Security:** Support for Protocomm Sec0 (Plaintext) and Sec1 (Curve25519 + AES-256-CTR).
