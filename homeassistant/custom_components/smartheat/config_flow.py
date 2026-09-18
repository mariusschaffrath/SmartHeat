"""Config flow for SmartHeat Dielle Pellet Stove integration."""
from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, Dict, Optional
import voluptuous as vol
import aiohttp

from homeassistant import config_entries
from homeassistant.const import CONF_HOST, CONF_PORT, CONF_USERNAME, CONF_PASSWORD
from homeassistant.data_entry_flow import FlowResult
from homeassistant.helpers.aiohttp_client import async_get_clientsession

from .const import (
    DOMAIN,
    CONF_DEVICE_ID,
    CONF_BASE_URL,
    DEFAULT_HOST,
    DEFAULT_PORT,
    DEFAULT_BASE_URL,
)

_LOGGER = logging.getLogger(__name__)

STEP_USER_DATA_SCHEMA = vol.Schema(
    {
        vol.Required(CONF_HOST, default=DEFAULT_HOST): str,
        vol.Required(CONF_PORT, default=DEFAULT_PORT): int,
        vol.Optional(CONF_USERNAME, default=""): str,
        vol.Optional(CONF_PASSWORD, default=""): str,
        vol.Optional(CONF_DEVICE_ID, default=""): str,
        vol.Optional(CONF_BASE_URL, default=DEFAULT_BASE_URL): str,
    }
)


class SmartHeatConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    """Handle a config flow for SmartHeat."""

    VERSION = 1

    async def async_step_user(
        self, user_input: Optional[Dict[str, Any]] = None
    ) -> FlowResult:
        """Handle the initial step."""
        errors: Dict[str, str] = {}

        if user_input is not None:
            host = user_input.get(CONF_HOST, "").strip()
            port = user_input.get(CONF_PORT, DEFAULT_PORT)
            username = user_input.get(CONF_USERNAME, "").strip()
            password = user_input.get(CONF_PASSWORD, "").strip()
            device_id = user_input.get(CONF_DEVICE_ID, "").strip()
            base_url = user_input.get(CONF_BASE_URL, DEFAULT_BASE_URL).rstrip("/")

            # 1. Test Local Socket Connection
            local_success = False
            if host:
                try:
                    reader, writer = await asyncio.wait_for(
                        asyncio.open_connection(host, port),
                        timeout=4.0,
                    )
                    writer.write(b'["2WL","0"]\n')
                    await writer.drain()
                    raw = await asyncio.wait_for(reader.read(1024), timeout=3.0)
                    writer.close()
                    try:
                        await writer.wait_closed()
                    except Exception:
                        pass

                    text = raw.decode("utf-8", errors="ignore")
                    if "2WL" in text or "[" in text:
                        local_success = True
                except Exception as ex:
                    _LOGGER.warning("Local test connection to %s:%s failed: %s", host, port, ex)

            # 2. Test Cloud if local didn't succeed and credentials provided
            cloud_success = False
            if not local_success and username and password:
                session = async_get_clientsession(self.hass)
                token_url = f"{base_url}/Token"
                payload = {
                    "grant_type": "password",
                    "username": username,
                    "password": password,
                }
                headers = {"Content-Type": "application/x-www-form-urlencoded"}
                try:
                    async with session.post(token_url, data=payload, headers=headers, timeout=8) as resp:
                        if resp.status == 200:
                            cloud_success = True
                        elif resp.status in (400, 401):
                            errors["base"] = "invalid_auth"
                        else:
                            errors["base"] = "cannot_connect"
                except Exception:
                    errors["base"] = "cannot_connect"

            if not local_success and not cloud_success and "base" not in errors:
                errors["base"] = "cannot_connect"

            if not errors:
                unique_id = f"smartheat_{host}" if local_success else (device_id or username)
                await self.async_set_unique_id(unique_id)
                self._abort_if_unique_id_configured()

                title = f"Dielle Pelletofen ({host})" if local_success else f"Dielle Pelletofen ({username})"
                return self.async_create_entry(
                    title=title,
                    data={
                        CONF_HOST: host if local_success else "",
                        CONF_PORT: port if local_success else DEFAULT_PORT,
                        CONF_USERNAME: username,
                        CONF_PASSWORD: password,
                        CONF_DEVICE_ID: device_id,
                        CONF_BASE_URL: base_url,
                    },
                )

        return self.async_show_form(
            step_id="user",
            data_schema=STEP_USER_DATA_SCHEMA,
            errors=errors,
        )
