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

from .const import DOMAIN, DIELLE_ALARM_MAPPINGS
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
        name="Gebläse Flur (Luftheizung)",
        object_id="geblase_flur_kanal_1",
        icon="mdi:fan",
        value_fn=lambda d: d.get("fan_flur"),
    ),
    SmartHeatSensorEntityDescription(
        key="fan_luftzufuhr1",
        name="Gebläse Luftzufuhr 1",
        object_id="geblase_luftzufuhr_1",
        icon="mdi:fan",
        value_fn=lambda d: d.get("fan_luftzufuhr1"),
    ),
    SmartHeatSensorEntityDescription(
        key="fan_kanal2",
        name="Gebläse Luftzufuhr 2",
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
        key="effective_power_display",
        name="Aktuelle Ist-Leistung",
        object_id="aktuelle_istleistung",
        icon="mdi:fire-circle",
        value_fn=lambda d: d.get("effective_power_display"),
    ),
    SmartHeatSensorEntityDescription(
        key="consumption_rate",
        name="Pellet-Verbrauch stündlich",
        object_id="pellet_verbrauch_stundlich",
        native_unit_of_measurement="kg/h",
        state_class=SensorStateClass.MEASUREMENT,
        icon="mdi:fire-alert",
        value_fn=lambda d: d.get("consumption_rate"),
    ),
    SmartHeatSensorEntityDescription(
        key="is_wood_mode",
        name="Scheitholzbetrieb",
        object_id="scheitholzbetrieb",
        icon="mdi:wood",
        value_fn=lambda d: "Aktiv" if d.get("is_wood_mode") else "Inaktiv",
    ),
    SmartHeatSensorEntityDescription(
        key="daily_consumption",
        name="Pellet-Tagesverbrauch",
        object_id="pellet_tagesverbrauch",
        native_unit_of_measurement=UnitOfMass.KILOGRAMS,
        state_class=SensorStateClass.TOTAL_INCREASING,
        icon="mdi:chart-timeline-variant",
        value_fn=lambda d: d.get("daily_consumption"),
    ),
    SmartHeatSensorEntityDescription(
        key="alarm",
        name="Alarm",
        object_id="alarm",
        icon="mdi:alert-octagon",
        value_fn=lambda d: DIELLE_ALARM_MAPPINGS.get(d.get("error_code", 0), {}).get("name", "Kein Fehler" if d.get("error_code", 0) == 0 else f"Er{d.get('error_code', 0):02d}"),
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
        """Return native sensor value from coordinator data with immediate restore fallback."""
        if not self.coordinator.data:
            if self.entity_description.key == "pellet_level_kg":
                return round(self.coordinator.pellet_level, 2)
            if self.entity_description.key == "pellet_percent":
                return round((self.coordinator.pellet_level / self.coordinator.tank_capacity) * 100.0, 1)
            if self.entity_description.key == "daily_consumption":
                return round(self.coordinator.daily_consumption, 2)
            return None
        return self.entity_description.value_fn(self.coordinator.data)

    @property
    def extra_state_attributes(self) -> dict[str, Any] | None:
        """Return entity specific state attributes."""
        if not self.coordinator.data:
            return None
        data = self.coordinator.data
        if self.entity_description.key == "power_level":
            return {
                "soll_stufe": data.get("power_level"),
                "ist_stufe": data.get("effective_power_level"),
                "ist_leistung_display": data.get("effective_power_display"),
                "is_auto": data.get("power_level") == 6,
                "modulation_aktiv": data.get("status_code") == 6,
                "verbrauch_kgh": data.get("consumption_rate"),
                "delta_t": data.get("delta_temp"),
            }
        elif self.entity_description.key == "effective_power_display":
            return {
                "soll_stufe": data.get("power_level"),
                "ist_stufe": data.get("effective_power_level"),
                "verbrauch_kgh": data.get("consumption_rate"),
                "delta_t": data.get("delta_temp"),
                "geblase_brennraum_max": max(data.get("fan_luftzufuhr1", 1), data.get("fan_luftzufuhr2", 1)),
            }
        elif self.entity_description.key == "alarm":
            err_code = data.get("error_code", 0)
            alarm_info = DIELLE_ALARM_MAPPINGS.get(err_code, {})
            return {
                "error_code": err_code,
                "code_string": f"Er{err_code:02d}" if err_code > 0 else "None",
                "name": alarm_info.get("name", "Kein Alarm" if err_code == 0 else f"Unbekannter Fehler ({err_code})"),
                "beschreibung": alarm_info.get("beschreibung", "Keine Störung aktiv." if err_code == 0 else "Unbekannter Fehlercode."),
                "abhilfe": alarm_info.get("abhilfe", "Keine Maßnahme erforderlich." if err_code == 0 else "Ofen prüfen und entsperren."),
            }
        return None

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
