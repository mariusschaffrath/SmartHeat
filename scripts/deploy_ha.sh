#!/usr/bin/env bash
# ==============================================================================
# SmartHeat Home Assistant Deployment Script
# Automatically mirrors custom_components/smartheat to Home Assistant (192.168.178.131)
# ==============================================================================
set -euo pipefail

HA_HOST="${HA_HOST:-192.168.178.131}"
HA_PORT="${HA_PORT:-8123}"
HA_URL="http://${HA_HOST}:${HA_PORT}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${PROJECT_ROOT}/homeassistant/custom_components/smartheat"
HACTL="/Users/mariusschaffrath/.local/bin/hactl"

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== SmartHeat Home Assistant Deployer ===${NC}"
echo -e "Target Home Assistant: ${YELLOW}${HA_URL}${NC}"
echo -e "Source Component:      ${YELLOW}${SOURCE_DIR}${NC}\n"

# 1. Connectivity Check
echo -e "${BLUE}[1/4] Checking Home Assistant connectivity...${NC}"
if ! nc -z -w 3 "${HA_HOST}" "${HA_PORT}" 2>/dev/null; then
    echo -e "${RED}Error: Cannot reach Home Assistant at ${HA_URL}${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Home Assistant is online and reachable.${NC}"

# 2. Sync to Config Mount
echo -e "\n${BLUE}[2/4] Verifying file storage mount...${NC}"
TARGET_MOUNT="/Volumes/config"
if [ ! -d "${TARGET_MOUNT}" ]; then
    echo -e "${YELLOW}Notice: ${TARGET_MOUNT} is not currently mounted.${NC}"
    echo -e "Attempting to mount smb://${HA_HOST}/config ..."
    osascript -e "tell application \"Finder\" to open location \"smb://${HA_HOST}/config\"" 2>/dev/null || true
    sleep 2
fi

if [ -d "${TARGET_MOUNT}/custom_components" ]; then
    DEST_DIR="${TARGET_MOUNT}/custom_components/smartheat"
    echo -e "Target directory: ${DEST_DIR}"
    mkdir -p "${DEST_DIR}"
    rsync -av --delete --exclude '__pycache__' --exclude '.DS_Store' "${SOURCE_DIR}/" "${DEST_DIR}/"
    echo -e "${GREEN}✓ Files successfully mirrored to ${DEST_DIR}${NC}"
else
    echo -e "${YELLOW}Mount /Volumes/config is not directly accessible right now.${NC}"
    echo -e "Please ensure Samba share 'smb://${HA_HOST}/config' is connected in Finder."
fi

# 3. Validate HA Configuration
echo -e "\n${BLUE}[3/4] Validating Home Assistant Configuration via hactl...${NC}"
if [ -x "${HACTL}" ]; then
    "${HACTL}" check-config || {
        echo -e "${RED}Configuration check reported issues. Please check logs!${NC}"
        exit 1
    }
else
    echo -e "${YELLOW}hactl CLI not found at ${HACTL}, skipping check-config.${NC}"
fi

# 4. Reload Component
echo -e "\n${BLUE}[4/4] Reloading Home Assistant integration...${NC}"
if [ -x "${HACTL}" ]; then
    echo "Triggering config reload..."
    "${HACTL}" call homeassistant.reload_all || true
    echo -e "${GREEN}✓ SmartHeat deployment complete!${NC}"
else
    echo -e "${YELLOW}Deployment finished. Remember to reload or restart Home Assistant.${NC}"
fi
