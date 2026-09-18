"""Switch platform for SmartHeat Dielle Pellet Stove."""
from __future__ import annotations

from typing import Any

from homeassistant.components.switch import SwitchEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import SmartHeatCoordinator


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up SmartHeat switch platform."""
    coordinator: SmartHeatCoordinator = hass.data[DOMAIN][entry.entry_id]
    device_id = entry.data.get("device_id") or entry.data.get("host") or "smartheat"
    async_add_entities([SmartHeatPowerSwitch(coordinator, device_id)])


class SmartHeatPowerSwitch(CoordinatorEntity[SmartHeatCoordinator], SwitchEntity):
    """Switch representation to toggle Dielle Pellet Stove power."""

    def __init__(self, coordinator: SmartHeatCoordinator, device_id: str) -> None:
        super().__init__(coordinator)
        self._device_id = device_id
        self._attr_unique_id = f"{device_id}_power_switch"
        self.entity_id = "switch.smartheat_power"
        self._attr_name = "Ofen Power"
        self._attr_icon = "mdi:power"

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
    def is_on(self) -> bool:
        """Return true if stove is currently running (status > 0)."""
        if not self.coordinator.data:
            return False
        return self.coordinator.data.get("status_code", 0) > 0

    async def async_turn_on(self, **kwargs: Any) -> None:
        """Turn the stove on."""
        await self.coordinator.async_turn_on()

    async def async_turn_off(self, **kwargs: Any) -> None:
        """Turn the stove off."""
        await self.coordinator.async_turn_off()
