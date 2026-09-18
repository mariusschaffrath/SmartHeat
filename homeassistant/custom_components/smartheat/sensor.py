"""Sensor platform for SmartHeat Dielle Pellet Stove."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Optional

from homeassistant.components.sensor import (
    SensorDeviceClass,
    SensorEntity,
    SensorEntityDescription,
    SensorStateClass,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import UnitOfTemperature, UnitOfMass, UnitOfTime, PERCENTAGE
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import SmartHeatCoordinator


@dataclass
class SmartHeatSensorEntityDescription(SensorEntityDescription):
    """Class describing SmartHeat sensor entities."""
    value_fn: Callable[[dict[str, Any]], Any] = lambda data: None
    object_id: str = ""


SENSOR_DESCRIPTIONS: tuple[SmartHeatSensorEntityDescription, ...] = (
    SmartHeatSensorEntityDescription(
        key="room_temperature",
        name="Raumtemperatur",
        object_id="raumtemperatur",
        native_unit_of_measurement=UnitOfTemperature.CELSIUS,
        device_class=SensorDeviceClass.TEMPERATURE,
        state_class=SensorStateClass.MEASUREMENT,
        icon="mdi:home-thermometer-outline",
        value_fn=lambda d: d.get("room_temperature"),
    ),
    SmartHeatSensorEntityDescription(
        key="exhaust_temperature",
        name="Abgastemperatur",
        object_id="abgastemperatur",
        native_unit_of_measurement=UnitOfTemperature.CELSIUS,
        device_class=SensorDeviceClass.TEMPERATURE,
        state_class=SensorStateClass.MEASUREMENT,
        icon="mdi:fire",
        value_fn=lambda d: d.get("exhaust_temperature"),
    ),
    SmartHeatSensorEntityDescription(
        key="target_temperature",
        name="Solltemperatur",
        object_id="solltemperatur",
        native_unit_of_measurement=UnitOfTemperature.CELSIUS,
        device_class=SensorDeviceClass.TEMPERATURE,
        icon="mdi:thermostat",
        value_fn=lambda d: d.get("target_temperature"),
    ),
    SmartHeatSensorEntityDescription(
        key="status_text",
        name="Betriebsstatus",
        object_id="betriebsstatus",
        icon="mdi:power",
        value_fn=lambda d: d.get("status_text"),
    ),
    SmartHeatSensorEntityDescription(
        key="power_level",
        name="Leistungsstufe",
        object_id="leistungsstufe",
        icon="mdi:speedometer",
        value_fn=lambda d: d.get("power_level"),
    ),
    SmartHeatSensorEntityDescription(
        key="fan_flur",
        name="Gebläse Flur (Kanal 1)",
        object_id="geblase_flur_kanal_1",
        icon="mdi:fan",
        value_fn=lambda d: d.get("fan_flur"),
    ),
    SmartHeatSensorEntityDescription(
        key="fan_kanal2",
        name="Gebläse Kanal 2",
        object_id="geblase_kanal_2",
        icon="mdi:fan",
        value_fn=lambda d: d.get("fan_kanal2"),
    ),
    SmartHeatSensorEntityDescription(
        key="pellet_level_kg",
        name="Pellet-Vorrat",
        object_id="pellet_vorrat",
        native_unit_of_measurement=UnitOfMass.KILOGRAMS,
        state_class=SensorStateClass.MEASUREMENT,
        icon="mdi:pail-outline",
        value_fn=lambda d: d.get("pellet_level_kg"),
    ),
    SmartHeatSensorEntityDescription(
        key="pellet_percent",
        name="Pellet-Füllstand",
        object_id="pellet_fullstand",
        native_unit_of_measurement=PERCENTAGE,
        state_class=SensorStateClass.MEASUREMENT,
        icon="mdi:gauge",
        value_fn=lambda d: d.get("pellet_percent"),
    ),
    SmartHeatSensorEntityDescription(
        key="pellet_remaining_hours",
        name="Pellet-Restlaufzeit",
        object_id="pellet_restlaufzeit",
        native_unit_of_measurement=UnitOfTime.HOURS,
        device_class=SensorDeviceClass.DURATION,
        state_class=SensorStateClass.MEASUREMENT,
        icon="mdi:clock-outline",
        value_fn=lambda d: d.get("pellet_remaining_hours"),
    ),
    SmartHeatSensorEntityDescription(
        key="is_wood_mode",
        name="Scheitholzbetrieb",
        object_id="scheitholzbetrieb",
        icon="mdi:wood",
        value_fn=lambda d: "Aktiv" if d.get("is_wood_mode") else "Inaktiv",
    ),
)


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up SmartHeat sensor platform."""
    coordinator: SmartHeatCoordinator = hass.data[DOMAIN][entry.entry_id]
    device_id = entry.data.get("device_id") or entry.data.get("host") or "smartheat"

    entities = [
        SmartHeatSensor(coordinator, description, device_id)
        for description in SENSOR_DESCRIPTIONS
    ]

    async_add_entities(entities)


class SmartHeatSensor(CoordinatorEntity[SmartHeatCoordinator], SensorEntity):
    """Representation of a SmartHeat sensor with matching entity_id."""

    entity_description: SmartHeatSensorEntityDescription

    def __init__(
        self,
        coordinator: SmartHeatCoordinator,
        description: SmartHeatSensorEntityDescription,
        device_id: str,
    ) -> None:
        super().__init__(coordinator)
        self.entity_description = description
        self._device_id = device_id
        self._attr_unique_id = f"{device_id}_{description.key}"
        self.entity_id = f"sensor.smartheat_{description.object_id}"
        self._attr_name = description.name

    @property
    def native_value(self) -> Any:
        """Return native sensor value from coordinator data."""
        if not self.coordinator.data:
            return None
        return self.entity_description.value_fn(self.coordinator.data)

    @property
    def device_info(self) -> DeviceInfo:
        """Return device information."""
        return DeviceInfo(
            identifiers={(DOMAIN, self._device_id)},
            name="Dielle Pelletofen",
            manufacturer="Dielle",
            model="Ghibli Kombi 10 kW",
            sw_version="1.0.0",
        )
