"""Binary sensor platform for SmartHeat Dielle Pellet Stove."""
from __future__ import annotations

from homeassistant.components.binary_sensor import (
    BinarySensorDeviceClass,
    BinarySensorEntity,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from typing import Any

from .const import DOMAIN, DIELLE_ALARM_MAPPINGS
from .coordinator import SmartHeatCoordinator


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up SmartHeat binary sensor platform."""
    coordinator: SmartHeatCoordinator = hass.data[DOMAIN][entry.entry_id]
    device_id = entry.data.get("device_id") or entry.data.get("host") or "smartheat"

    async_add_entities(
        [
            SmartHeatProblemSensor(coordinator, device_id),
            SmartHeatWoodModeBinarySensor(coordinator, device_id),
        ]
    )


class SmartHeatProblemSensor(CoordinatorEntity[SmartHeatCoordinator], BinarySensorEntity):
    """Binary sensor indicating hardware error or security lockout."""

    _attr_device_class = BinarySensorDeviceClass.PROBLEM

    def __init__(self, coordinator: SmartHeatCoordinator, device_id: str) -> None:
        super().__init__(coordinator)
        self._device_id = device_id
        self._attr_unique_id = f"{device_id}_alarm_problem"
        self.entity_id = "binary_sensor.smartheat_storung"
        self._attr_name = "Ofen Störung"
        self._attr_icon = "mdi:alert-circle-outline"

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
        """Return True if stove has an active alarm or error."""
        if not self.coordinator.data:
            return False
        err = self.coordinator.data.get("error_code", 0)
        status = self.coordinator.data.get("status_code", 0)
        return err > 0 or status in (8, 9)


class SmartHeatWoodModeBinarySensor(CoordinatorEntity[SmartHeatCoordinator], BinarySensorEntity):
    """Binary sensor indicating active wood/firewood burning mode."""

    def __init__(self, coordinator: SmartHeatCoordinator, device_id: str) -> None:
        super().__init__(coordinator)
        self._device_id = device_id
        self._attr_unique_id = f"{device_id}_wood_mode_binary"
        self.entity_id = "binary_sensor.smartheat_scheitholzbetrieb"
        self._attr_name = "Scheitholzbetrieb"
        self._attr_icon = "mdi:wood"

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
        """Return True if stove is actively burning firewood (status 13)."""
        if not self.coordinator.data:
            return False
        return self.coordinator.data.get("is_wood_mode", False)
