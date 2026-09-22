"""DataUpdateCoordinator for SmartHeat Dielle Pellet Stove."""
from __future__ import annotations

import asyncio
import json
import logging
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
import aiohttp

from homeassistant.core import HomeAssistant
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .const import (
    DOMAIN,
    CONF_HOST,
    CONF_PORT,
    DEFAULT_HOST,
    DEFAULT_PORT,
    DEFAULT_BASE_URL,
    SCAN_INTERVAL,
    STATUS_MAPPINGS,
    CONSUMPTION_RATES,
    DEFAULT_TANK_CAPACITY_KG,
    DEFAULT_BAG_WEIGHT_KG,
    CMD_TURN_ON,
    CMD_TURN_OFF,
    CMD_SET_TEMP_PREFIX,
    CMD_SET_FAN_FLUR_PREFIX,
    CMD_SET_FAN_KANAL1_PREFIX,
    CMD_SET_FAN_KANAL2_PREFIX,
    CMD_SET_POWER_PREFIX,
)

_LOGGER = logging.getLogger(__name__)


def _extract_hex(hex_str: str, start: int, length: int) -> Optional[str]:
    if start + length <= len(hex_str):
        return hex_str[start : start + length]
    return None


def _extract_signed_int16(hex_str: str, start: int) -> Optional[int]:
    hex_part = _extract_hex(hex_str, start, 4)
    if not hex_part:
        return None
    try:
        unsigned = int(hex_part, 16)
        if unsigned >= 0x8000:
            return unsigned - 0x10000
        return unsigned
    except ValueError:
        return None


class SmartHeatCoordinator(DataUpdateCoordinator[Dict[str, Any]]):
    """Coordinator that polls Dielle Stove (via Local TCP or Cloud API) and decodes SERVIZI2W telemetry."""

    def __init__(
        self,
        hass: HomeAssistant,
        host: Optional[str] = None,
        port: int = DEFAULT_PORT,
        username: Optional[str] = None,
        password: Optional[str] = None,
        device_id: Optional[str] = None,
        base_url: str = DEFAULT_BASE_URL,
    ) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name=DOMAIN,
            update_interval=SCAN_INTERVAL,
        )
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.device_id = device_id
        self.base_url = base_url.rstrip("/")
        self.session = async_get_clientsession(hass)
        self.token: Optional[str] = None

        # Pellet Tank Tracking State
        self.tank_capacity = DEFAULT_TANK_CAPACITY_KG
        self.pellet_level = DEFAULT_TANK_CAPACITY_KG
        self.last_update_time: Optional[datetime] = None

        # Optimistic Confirmation / Pending State (verhindert Zurückspringen alter Werte)
        self.pending_flur_fan: Optional[int] = None
        self.pending_flur_fan_time: Optional[float] = None
        self.pending_target_temp: Optional[float] = None
        self.pending_target_temp_time: Optional[float] = None

    async def _async_query_local_socket(self) -> List[str]:
        """Query stove directly over local TCP socket using Dielle 2WL protocol."""
        host = self.host or DEFAULT_HOST
        port = self.port or DEFAULT_PORT

        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(host, port),
            timeout=5.0,
        )
        try:
            # Query command for 2ways live telemetry
            writer.write(b'["2WL","0"]\n')
            await writer.drain()

            raw = b""
            while True:
                chunk = await asyncio.wait_for(reader.read(4096), timeout=3.0)
                if not chunk:
                    break
                raw += chunk
                if b"]" in chunk:
                    break

            text = raw.decode("utf-8", errors="ignore").strip()
            data = json.loads(text)
            if isinstance(data, list) and len(data) >= 3:
                # Format is ["2WL", "25", "10...", "0c81...", ...]
                return data[2:]
            elif isinstance(data, list):
                return data
            return []
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

    async def async_authenticate_cloud(self) -> str:
        """Authenticate with Dielle Azure Cloud and retrieve Bearer token."""
        url = f"{self.base_url}/Token"
        payload = {
            "grant_type": "password",
            "username": self.username,
            "password": self.password,
        }
        headers = {"Content-Type": "application/x-www-form-urlencoded"}

        try:
            async with self.session.post(url, data=payload, headers=headers, timeout=10) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    self.token = data.get("access_token")
                    _LOGGER.info("Successfully authenticated with Dielle Cloud API")
                    return self.token
                elif resp.status in (400, 401):
                    raise UpdateFailed("Ungültige Cloud-Anmeldedaten")
                else:
                    raise UpdateFailed(f"Cloud-Authentifizierung fehlgeschlagen: HTTP {resp.status}")
        except aiohttp.ClientError as err:
            raise UpdateFailed(f"Netzwerkfehler bei Cloud-Authentifizierung: {err}") from err

    async def _async_query_cloud(self) -> List[str]:
        """Fetch telemetry from Dielle Azure Cloud."""
        if not self.token:
            await self.async_authenticate_cloud()

        endpoints = [
            f"{self.base_url}/api/devices/Summary?ids={self.device_id}",
            f"{self.base_url}/api/devices/RealTime?id={self.device_id}",
        ]

        last_error = None
        for _ in range(2):
            for endpoint in endpoints:
                headers = {
                    "Authorization": f"Bearer {self.token}",
                    "Accept": "application/json",
                }
                try:
                    async with self.session.get(endpoint, headers=headers, timeout=10) as resp:
                        if resp.status == 401:
                            await self.async_authenticate_cloud()
                            break
                        if resp.status == 200:
                            json_data = await resp.json()
                            if isinstance(json_data, list) and json_data:
                                item = json_data[0]
                                vals = item.get("Values")
                                if not vals and "LastMessageReceived" in item:
                                    lmr = json.loads(item["LastMessageReceived"])
                                    vals = lmr.get("Values")
                                if vals:
                                    return vals
                            elif isinstance(json_data, dict):
                                vals = json_data.get("Values")
                                if vals:
                                    return vals
                except Exception as ex:
                    last_error = ex
                    continue

        raise UpdateFailed(f"Konnte Telemetrie nicht von Cloud abrufen: {last_error}")

    async def _async_update_data(self) -> Dict[str, Any]:
        """Fetch latest telemetry from Local Socket or Cloud and decode hex values."""
        raw_blocks: List[str] = []
        is_online = True

        # Try Local TCP first if host configured
        if self.host:
            try:
                raw_blocks = await self._async_query_local_socket()
            except Exception as ex:
                _LOGGER.warning("Lokale Socket-Abfrage an %s fehlgeschlagen: %s", self.host, ex)
                if self.username and self.password and self.device_id:
                    _LOGGER.info("Verwende Cloud-Fallback...")
                    raw_blocks = await self._async_query_cloud()
                else:
                    raise UpdateFailed(f"Konnte Ofen über {self.host}:{self.port} nicht erreichen: {ex}") from ex
        elif self.username and self.password:
            raw_blocks = await self._async_query_cloud()
        else:
            raise UpdateFailed("Weder lokale IP noch Cloud-Anmeldedaten für SmartHeat konfiguriert")

        if not raw_blocks:
            raise UpdateFailed("Keine gültigen Telemetrieblöcke vom Ofen erhalten")

        parsed = self._decode_telemetry_blocks(raw_blocks, is_online=is_online)
        return parsed

    def _decode_telemetry_blocks(self, values: List[str], is_online: bool = True) -> Dict[str, Any]:
        """Decodes SERVIZI2W telemetry hex blocks according to official Dielle specification."""
        room_temp = 0.0
        exhaust_temp = 0.0
        target_temp = 20.0
        status_code = 0
        error_code = 0
        power_level = 1
        fan_flur = 1
        fan_luftzufuhr1 = 1
        fan_luftzufuhr2 = 1
        fan_kanal2 = 1
        is_wood = False

        for idx, block in enumerate(values):
            if not block:
                continue

            # 1. Block 0: 519_MAINVALUES (prefix "10")
            if block.startswith("10") or idx == 0:
                st_hex = _extract_hex(block, 10, 2)
                if st_hex:
                    try:
                        status_code = int(st_hex, 16)
                        if status_code == 13:
                            is_wood = True
                    except ValueError:
                        pass

                err_hex = _extract_hex(block, 12, 2)
                if err_hex:
                    try:
                        error_code = int(err_hex, 16)
                    except ValueError:
                        pass

                mult_temp = 0.1
                if len(block) >= 38:
                    pp_hex = _extract_hex(block, 36, 2)
                    if pp_hex:
                        try:
                            pp = int(pp_hex, 16)
                            mult_temp = {0: 1.0, 1: 0.1, 2: 0.01, 3: 0.001}.get(pp, 0.1)
                        except ValueError:
                            pass

                tp_raw = _extract_signed_int16(block, 20)
                if tp_raw is not None and tp_raw > 0 and tp_raw != -127:
                    room_temp = round(float(tp_raw) * mult_temp, 1)

                ts_raw = _extract_signed_int16(block, 6)
                if ts_raw is not None and ts_raw > 0 and exhaust_temp == 0:
                    exhaust_temp = round(float(ts_raw) * mult_temp, 1)

            # 2. Block 1: state_info_81 (prefix "0c81")
            elif block.startswith("0c81"):
                # Power level from ASCII at offset 6..8 (e.g. 0x31 = '1')
                pwr_hex = _extract_hex(block, 6, 2)
                if pwr_hex:
                    try:
                        pwr_char = chr(int(pwr_hex, 16))
                        if pwr_char.isdigit() and 1 <= int(pwr_char) <= 5:
                            power_level = int(pwr_char)
                        elif pwr_char in ("A", "a", "6"):
                            power_level = 1 if status_code == 6 else 6
                    except (ValueError, OverflowError):
                        pass

                mult_target = 0.1
                if len(block) >= 30:
                    pp_hex = _extract_hex(block, 28, 2)
                    if pp_hex:
                        try:
                            pp = int(pp_hex, 16)
                            mult_target = {0: 1.0, 1: 0.1, 2: 0.01, 3: 0.001}.get(pp, 0.1)
                        except ValueError:
                            pass

                tt_hex = _extract_hex(block, 24, 4)
                if tt_hex:
                    try:
                        raw_tt = int(tt_hex, 16)
                        if raw_tt > 0:
                            target_temp = round(float(raw_tt) * mult_target, 1)
                    except ValueError:
                        pass

            # 3. Sensor Blocks (prefix "12")
            elif block.startswith("12"):
                sensor_id = (_extract_hex(block, 2, 4) or "").lower()
                mult = 1.0
                if len(block) >= 22:
                    pp_hex = _extract_hex(block, 20, 2)
                    if pp_hex:
                        try:
                            pp = int(pp_hex, 16)
                            mult = {0: 1.0, 1: 0.1, 2: 0.01, 3: 0.001}.get(pp, 1.0)
                        except ValueError:
                            pass

                raw_val = _extract_signed_int16(block, 6)
                if raw_val is not None and raw_val > 0:
                    if sensor_id == "ffff":  # Exhaust sensor
                        exhaust_temp = round(float(raw_val) * mult, 1)
                    elif sensor_id == "fff7":  # Dedicated room temp sensor
                        room_temp = round(float(raw_val) * mult, 1)

            # 4. Parameter Blocks (prefix "0e")
            elif block.startswith("0e"):
                param_id = (_extract_hex(block, 2, 4) or "").lower()
                mult = 0.1
                if len(block) >= 22:
                    pp_hex = _extract_hex(block, 20, 2)
                    if pp_hex:
                        try:
                            pp = int(pp_hex, 16)
                            mult = {0: 1.0, 1: 0.1, 2: 0.01}.get(pp, 0.1)
                        except ValueError:
                            pass

                raw_val = _extract_signed_int16(block, 6)
                if raw_val is not None:
                    if param_id == "01ed" and raw_val > 0:  # Target room temp
                        target_temp = round(float(raw_val) * mult, 1)
                    elif param_id == "016c" and 1 <= raw_val <= 6:
                        power_level = raw_val
                    elif param_id == "023f":  # Luftheizung Flur (Riscaldamento / Heating Fan)
                        fan_flur = raw_val
                    elif param_id == "0266":  # Luftzufuhr 1 (Brennraum / Canalizzata 1)
                        fan_luftzufuhr1 = raw_val
                    elif param_id == "027e":  # Luftzufuhr 2 (Brennraum / Canalizzata 2)
                        fan_luftzufuhr2 = raw_val
                        fan_kanal2 = raw_val
                    elif param_id == "017d" and fan_flur == 1:
                        fan_flur = raw_val

        # Power adjustment during modulation
        if status_code == 6:
            power_level = 1

        # Pellet consumption tracking
        now = datetime.now(timezone.utc)
        hourly_rate = 0.0
        if not is_wood and status_code in (1, 2, 3, 4, 5, 6):
            effective_power = 1 if status_code == 6 else (1 if power_level == 6 else power_level)
            hourly_rate = CONSUMPTION_RATES.get(effective_power, 0.65)

            if self.last_update_time:
                elapsed_seconds = (now - self.last_update_time).total_seconds()
                if 0 < elapsed_seconds < 300:  # reasonable interval
                    consumed_kg = (hourly_rate / 3600.0) * elapsed_seconds
                    self.pellet_level = max(0.0, self.pellet_level - consumed_kg)

        self.last_update_time = now

        pellet_percent = round((self.pellet_level / self.tank_capacity) * 100.0, 1)
        remaining_hours = (
            round(self.pellet_level / hourly_rate, 1) if hourly_rate > 0 else 999.0
        )

        # Optimistic Confirmation Check for Flur Fan (verhindert Zurückspringen alter Werte)
        cur_ts = time.time()
        if self.pending_flur_fan is not None:
            if fan_flur == self.pending_flur_fan:
                _LOGGER.info("SYNC: Flur-Gebläse Stufe %s vom Ofen bestätigt!", fan_flur)
                self.pending_flur_fan = None
                self.pending_flur_fan_time = None
            elif self.pending_flur_fan_time and (cur_ts - self.pending_flur_fan_time) < 45.0:
                _LOGGER.debug(
                    "SYNC: Halte optimistische Flur-Gebläsestufe %s (Ofen meldet noch %s)",
                    self.pending_flur_fan,
                    fan_flur,
                )
                fan_flur = self.pending_flur_fan
            else:
                self.pending_flur_fan = None
                self.pending_flur_fan_time = None

        # Optimistic Confirmation Check for Target Temperature
        if self.pending_target_temp is not None:
            if abs(target_temp - self.pending_target_temp) < 0.2:
                _LOGGER.info("SYNC: Zieltemperatur %.1f°C vom Ofen bestätigt!", target_temp)
                self.pending_target_temp = None
                self.pending_target_temp_time = None
            elif self.pending_target_temp_time and (cur_ts - self.pending_target_temp_time) < 45.0:
                _LOGGER.debug(
                    "SYNC: Halte optimistische Zieltemperatur %.1f°C (Ofen meldet noch %.1f°C)",
                    self.pending_target_temp,
                    target_temp,
                )
                target_temp = self.pending_target_temp
            else:
                self.pending_target_temp = None
                self.pending_target_temp_time = None

        status_text = STATUS_MAPPINGS.get(status_code, f"Unbekannt ({status_code})")

        return {
            "is_online": is_online,
            "room_temperature": room_temp,
            "exhaust_temperature": exhaust_temp,
            "target_temperature": target_temp,
            "status_code": status_code,
            "status_text": status_text,
            "error_code": error_code,
            "power_level": power_level,
            "fan_flur": fan_flur,
            "fan_kanal2": fan_kanal2,
            "fan_luftzufuhr1": fan_luftzufuhr1,
            "fan_luftzufuhr2": fan_luftzufuhr2,
            "is_wood_mode": is_wood,
            "pellet_level_kg": round(self.pellet_level, 2),
            "pellet_percent": pellet_percent,
            "pellet_remaining_hours": remaining_hours,
            "consumption_rate": hourly_rate,
        }

    async def async_send_command(self, cmd_hex: str, skip_immediate_refresh: bool = False) -> bool:
        """Send a 2WC command string via Local TCP socket or Cloud."""
        # 1. Local socket sending
        if self.host:
            host = self.host
            port = self.port or DEFAULT_PORT
            payload = f'["2WC","1","{cmd_hex}"]\n'
            try:
                reader, writer = await asyncio.wait_for(
                    asyncio.open_connection(host, port),
                    timeout=5.0,
                )
                writer.write(payload.encode("utf-8"))
                await writer.drain()

                raw = b""
                while True:
                    chunk = await asyncio.wait_for(reader.read(4096), timeout=3.0)
                    if not chunk:
                        break
                    raw += chunk
                    if b"]" in chunk:
                        break

                writer.close()
                try:
                    await writer.wait_closed()
                except Exception:
                    pass

                _LOGGER.info("Local command %s successfully sent to stove", cmd_hex)
                if not skip_immediate_refresh:
                    await asyncio.sleep(1.0)
                    await self.async_request_refresh()
                return True
            except Exception as ex:
                _LOGGER.error("Failed to send local command %s: %s", cmd_hex, ex)

        # 2. Cloud sending
        if self.username and self.password and self.device_id:
            if not self.token:
                await self.async_authenticate_cloud()

            url = f"{self.base_url}/api/devices/command"
            headers = {
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
            }
            body = {
                "id": self.device_id,
                "comando": ["2WC", "1", cmd_hex],
            }

            try:
                async with self.session.post(url, json=body, headers=headers, timeout=10) as resp:
                    if resp.status == 200:
                        if not skip_immediate_refresh:
                            await asyncio.sleep(1.0)
                            await self.async_request_refresh()
                        return True
            except Exception as ex:
                _LOGGER.error("Failed to send cloud command %s: %s", cmd_hex, ex)

        return False

    async def async_send_command_with_burst(self, cmd_hex: str) -> bool:
        """Send command and run burst verification polls (1.5s, 3.5s, 6.0s) like in iOS App."""
        success = await self.async_send_command(cmd_hex, skip_immediate_refresh=True)
        if success:
            async def _burst():
                delays = [1.5, 2.0, 2.5]
                for delay in delays:
                    await asyncio.sleep(delay)
                    await self.async_request_refresh()
                    if self.pending_flur_fan is None and self.pending_target_temp is None:
                        break
            asyncio.create_task(_burst())
        return success

    async def async_set_target_temperature(self, temp: float) -> bool:
        """Set target thermostat temperature with optimistic lock and burst verification."""
        clamped = max(10.0, min(35.0, temp))
        self.pending_target_temp = clamped
        self.pending_target_temp_time = time.time()
        if self.data:
            self.data["target_temperature"] = clamped
            self.async_update_listeners()

        raw_val = int(round(clamped * 10.0))
        cmd = f"{CMD_SET_TEMP_PREFIX}{raw_val:04x}"
        return await self.async_send_command_with_burst(cmd)

    async def async_set_flur_fan(self, speed: int) -> bool:
        """Set Flur Luftheizung fan speed (0=Aus, 1..6=P1..P6, 7=Auto) with optimistic lock and burst verification."""
        speed_clamped = max(0, min(7, speed))
        self.pending_flur_fan = speed_clamped
        self.pending_flur_fan_time = time.time()
        if self.data:
            self.data["fan_flur"] = speed_clamped
            self.async_update_listeners()

        cmd = f"{CMD_SET_FAN_FLUR_PREFIX}{speed_clamped:04x}"
        return await self.async_send_command_with_burst(cmd)

    async def async_set_luftzufuhr1_fan(self, speed: int) -> bool:
        """Set Luftzufuhr 1 (Brennraum / 0266) fan speed (0=Aus, 1..5=P1..P5, 6=Auto)."""
        speed_clamped = max(0, min(6, speed))
        cmd = f"{CMD_SET_FAN_KANAL1_PREFIX}{speed_clamped:04x}"
        return await self.async_send_command(cmd)

    async def async_set_kanal2_fan(self, speed: int) -> bool:
        """Set Luftzufuhr 2 (Brennraum / 027e) fan speed (0=Aus, 1..5=P1..P5, 6=Auto)."""
        speed_clamped = max(0, min(6, speed))
        cmd = f"{CMD_SET_FAN_KANAL2_PREFIX}{speed_clamped:04x}"
        return await self.async_send_command(cmd)

    async def async_set_power_level(self, level: int) -> bool:
        """Set combustion power level (1..5 or 6=Auto)."""
        clamped = max(1, min(6, level))
        cmd = f"{CMD_SET_POWER_PREFIX}{clamped:04x}"
        return await self.async_send_command(cmd)

    async def async_turn_on(self) -> bool:
        """Turn on the stove."""
        return await self.async_send_command(CMD_TURN_ON)

    async def async_turn_off(self) -> bool:
        """Turn off the stove."""
        return await self.async_send_command(CMD_TURN_OFF)

    def refill_bag(self) -> None:
        """Add 1 bag (15kg) of pellets."""
        self.pellet_level = min(self.tank_capacity, self.pellet_level + DEFAULT_BAG_WEIGHT_KG)
        if self.data:
            self.data["pellet_level_kg"] = round(self.pellet_level, 2)
            self.data["pellet_percent"] = round((self.pellet_level / self.tank_capacity) * 100.0, 1)
        self.async_set_updated_data(self.data)

    def refill_full(self) -> None:
        """Refill tank to full 20kg."""
        self.pellet_level = self.tank_capacity
        if self.data:
            self.data["pellet_level_kg"] = round(self.pellet_level, 2)
            self.data["pellet_percent"] = 100.0
        self.async_set_updated_data(self.data)
