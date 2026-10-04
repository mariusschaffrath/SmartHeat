"""SmartHeat Dielle Pellet Stove Integration for Home Assistant."""
from __future__ import annotations

import logging
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform, CONF_HOST, CONF_PORT
from homeassistant.core import HomeAssistant, ServiceCall

from .const import (
    DOMAIN,
    CONF_DEVICE_ID,
    CONF_BASE_URL,
    DEFAULT_PORT,
    DEFAULT_BASE_URL,
)
from .coordinator import SmartHeatCoordinator

_LOGGER = logging.getLogger(__name__)

PLATFORMS: list[Platform] = [
    Platform.SENSOR,
    Platform.CLIMATE,
    Platform.SWITCH,
    Platform.BINARY_SENSOR,
]


async def async_setup(hass: HomeAssistant, config: dict) -> bool:
    """Set up the SmartHeat component from configuration.yaml (if any)."""
    hass.data.setdefault(DOMAIN, {})
    return True


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Set up SmartHeat from a config entry."""
    host = entry.data.get(CONF_HOST)
    port = entry.data.get(CONF_PORT, DEFAULT_PORT)
    username = entry.data.get("username")
    password = entry.data.get("password")
    device_id = entry.data.get(CONF_DEVICE_ID)
    base_url = entry.data.get(CONF_BASE_URL, DEFAULT_BASE_URL)

    coordinator = SmartHeatCoordinator(
        hass=hass,
        host=host,
        port=port,
        username=username,
        password=password,
        device_id=device_id,
        base_url=base_url,
    )

    # Initial load of persistent pellet storage before first refresh (Hürde 3.1)
    await coordinator.async_load()

    # Initial fetch
    await coordinator.async_config_entry_first_refresh()

    hass.data.setdefault(DOMAIN, {})
    hass.data[DOMAIN][entry.entry_id] = coordinator

    # Forward setup to sensor and climate platforms
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)

    # Register custom Home Assistant services
    async def handle_refill_bag(call: ServiceCall) -> None:
        """Service to add 1 bag (15kg) of pellets."""
        coordinator.refill_bag()
        _LOGGER.info("SmartHeat: 15kg Pellets nachgefüllt.")

    async def handle_refill_full(call: ServiceCall) -> None:
        """Service to set pellet tank to full 20kg."""
        coordinator.refill_full()
        _LOGGER.info("SmartHeat: Pellet-Tank voll befüllt (20kg).")

    async def handle_set_pellet_level(call: ServiceCall) -> None:
        """Service to set pellet level in kg (Hürde 3.1)."""
        level = call.data.get("level")
        if level is None:
            level = call.data.get("pellet_level_kg")
        if level is not None:
            await coordinator.async_set_pellet_level(float(level))
            _LOGGER.info("SmartHeat: Pellet-Füllstand manuell gesetzt auf %.2f kg.", float(level))

    hass.services.async_register(DOMAIN, "refill_bag", handle_refill_bag)
    hass.services.async_register(DOMAIN, "refill_full", handle_refill_full)
    hass.services.async_register(DOMAIN, "set_pellet_level", handle_set_pellet_level)

    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    """Unload a config entry."""
    unload_ok = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unload_ok:
        coordinator: SmartHeatCoordinator = hass.data[DOMAIN].pop(entry.entry_id, None)
        if coordinator:
            await coordinator.async_close_local_socket()
    return unload_ok
