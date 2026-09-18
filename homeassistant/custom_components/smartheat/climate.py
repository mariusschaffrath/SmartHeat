"""Climate platform for SmartHeat Dielle Pellet Stove."""
from __future__ import annotations

import logging
from typing import Any, List, Optional

from homeassistant.components.climate import (
    ClimateEntity,
    ClimateEntityFeature,
    HVACAction,
    HVACMode,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import UnitOfTemperature, ATTR_TEMPERATURE
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import SmartHeatCoordinator

_LOGGER = logging.getLogger(__name__)

FAN_MODE_MAPPINGS = {
    "Aus": 0,
    "Stufe 1": 1,
    "Stufe 2": 2,
    "Stufe 3": 3,
    "Stufe 4": 4,
    "Stufe 5": 5,
    "Auto": 6,
}
REVERSE_FAN_MAPPINGS = {v: k for k, v in FAN_MODE_MAPPINGS.items()}


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up SmartHeat climate platform."""
    coordinator: SmartHeatCoordinator = hass.data[DOMAIN][entry.entry_id]
    device_id = entry.data.get("device_id") or entry.data.get("host") or "smartheat"
    async_add_entities([SmartHeatClimate(coordinator, device_id)])


class SmartHeatClimate(CoordinatorEntity[SmartHeatCoordinator], ClimateEntity):
    """Representation of the Dielle Pellet Stove as a Climate Entity."""

    _attr_temperature_unit = UnitOfTemperature.CELSIUS
    _attr_min_temp = 16.0
    _attr_max_temp = 28.0
    _attr_target_temperature_step = 0.5
    _attr_hvac_modes = [HVACMode.OFF, HVACMode.HEAT]
    _attr_fan_modes = list(FAN_MODE_MAPPINGS.keys())
    _attr_supported_features = (
        ClimateEntityFeature.TARGET_TEMPERATURE
        | ClimateEntityFeature.FAN_MODE
        | ClimateEntityFeature.TURN_ON
        | ClimateEntityFeature.TURN_OFF
    )

    def __init__(self, coordinator: SmartHeatCoordinator, device_id: str) -> None:
        super().__init__(coordinator)
        self._device_id = device_id
        self._attr_unique_id = f"{device_id}_climate"
        self.entity_id = "climate.smartheat_pelletofen"
        self._attr_name = "Dielle Pelletofen"

    @property
    def device_info(self) -> DeviceInfo:
        return DeviceInfo(
            identifiers={(DOMAIN, self._device_id)},
            name="Dielle Pelletofen",
            manufacturer="Dielle",
            model="Ghibli Kombi 10 kW",
            sw_version="1.0.0",
        )

    @property
    def current_temperature(self) -> Optional[float]:
        """Return the current room temperature from stove probe."""
        if self.coordinator.data:
            return self.coordinator.data.get("room_temperature")
        return None

    @property
    def target_temperature(self) -> Optional[float]:
        """Return the target temperature."""
        if self.coordinator.data:
            return self.coordinator.data.get("target_temperature")
        return None

    @property
    def hvac_mode(self) -> HVACMode:
        """Return current HVAC mode (HEAT or OFF)."""
        if not self.coordinator.data:
            return HVACMode.OFF
        status = self.coordinator.data.get("status_code", 0)
        if status == 0:
            return HVACMode.OFF
        return HVACMode.HEAT

    @property
    def hvac_action(self) -> Optional[HVACAction]:
        """Return current running action (HEATING, IDLE, OFF)."""
        if not self.coordinator.data:
            return HVACAction.OFF
        status = self.coordinator.data.get("status_code", 0)
        if status == 0:
            return HVACAction.OFF
        elif status in (1, 2, 3, 4, 5, 6):
            return HVACAction.HEATING
        elif status == 11:
            return HVACAction.IDLE
        return HVACAction.IDLE

    @property
    def fan_mode(self) -> Optional[str]:
        """Return the current fan speed for Kanal 1 (Flur)."""
        if self.coordinator.data:
            speed = self.coordinator.data.get("fan_flur", 1)
            return REVERSE_FAN_MAPPINGS.get(speed, "Stufe 1")
        return None

    async def async_set_temperature(self, **kwargs: Any) -> None:
        """Set new target temperature."""
        temp = kwargs.get(ATTR_TEMPERATURE)
        if temp is not None:
            await self.coordinator.async_set_target_temperature(float(temp))

    async def async_set_hvac_mode(self, hvac_mode: HVACMode) -> None:
        """Set new HVAC mode."""
        if hvac_mode == HVACMode.HEAT:
            await self.coordinator.async_turn_on()
        elif hvac_mode == HVACMode.OFF:
            await self.coordinator.async_turn_off()

    async def async_set_fan_mode(self, fan_mode: str) -> None:
        """Set new fan mode for Flur (Kanal 1)."""
        if fan_mode in FAN_MODE_MAPPINGS:
            speed = FAN_MODE_MAPPINGS[fan_mode]
            await self.coordinator.async_set_flur_fan(speed)
