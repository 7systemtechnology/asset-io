#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "======================================="
echo "    Assetio Agent Installation (macOS)"
echo "======================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERROR: This installer requires administrator privileges.${NC}"
    echo "Please run with sudo: sudo bash $0"
    echo ""
    exit 1
fi

echo "Installing Assetio Agent for macOS..."
echo "Please wait, this may take a few minutes..."
echo ""

# Set your server URL here
SERVER_URL="http://192.168.2.6/front/inventory.php"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    echo -e "${BLUE}Detected: Apple Silicon (M1/M2/M3)${NC}"
    PKG_ARCH="arm64"
elif [ "$ARCH" = "x86_64" ]; then
    echo -e "${BLUE}Detected: Intel Mac${NC}"
    PKG_ARCH="x86_64"
else
    echo -e "${RED}ERROR: Unsupported architecture: $ARCH${NC}"
    echo "Supported architectures: arm64 (Apple Silicon) or x86_64 (Intel)"
    exit 1
fi

echo ""

# Get the latest version
echo "Fetching latest Assetio Agent version..."
LATEST_VERSION=$(curl -s -L https://api.github.com/repos/glpi-project/glpi-agent/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '[:space:]')

if [ -z "$LATEST_VERSION" ]; then
    echo -e "${YELLOW}WARNING: Could not fetch latest version${NC}"
    echo "Using fallback version 1.10"
    LATEST_VERSION="1.10"
else
    echo -e "${GREEN}Latest version: $LATEST_VERSION${NC}"
fi

echo ""

# Construct download URL
PKG_NAME="GLPI-Agent-${LATEST_VERSION}_${PKG_ARCH}.pkg"
DOWNLOAD_URL="https://github.com/glpi-project/glpi-agent/releases/download/${LATEST_VERSION}/${PKG_NAME}"

echo "Downloading Assetio Agent..."
echo ""

# Create temporary directory
TMP_DIR="/tmp/assetio-agent-install-$$"
mkdir -p "$TMP_DIR"

if [ ! -d "$TMP_DIR" ]; then
    echo -e "${RED}[ERROR] Failed to create temporary directory${NC}"
    exit 1
fi

cd "$TMP_DIR" || exit 1

# Download with error handling (silent mode)
curl -L -f -s -o "$PKG_NAME" "$DOWNLOAD_URL" 2>&1 > /dev/null &
CURL_PID=$!

# Show progress
echo -n "Downloading... "
while kill -0 $CURL_PID 2>/dev/null; do
    echo -n "."
    sleep 1
done
wait $CURL_PID
DOWNLOAD_STATUS=$?
echo ""

if [ $DOWNLOAD_STATUS -ne 0 ]; then
    echo -e "${RED}[ERROR] Download failed${NC}"
    echo "Please check your internet connection and try again."
    cd /
    rm -rf "$TMP_DIR"
    exit 1
fi

if [ ! -f "$PKG_NAME" ]; then
    echo -e "${RED}[ERROR] Package file not found after download${NC}"
    cd /
    rm -rf "$TMP_DIR"
    exit 1
fi

# Check file size (should be at least 1MB for a valid package)
FILE_SIZE=$(stat -f%z "$PKG_NAME" 2>/dev/null || echo "0")
if [ "$FILE_SIZE" -lt 1000000 ]; then
    echo -e "${RED}[ERROR] Downloaded file is too small (possibly corrupted)${NC}"
    cd /
    rm -rf "$TMP_DIR"
    exit 1
fi

echo -e "${GREEN}[OK] Download completed successfully${NC}"
echo ""

# Install the package
echo "Installing Assetio Agent..."
installer -pkg "$PKG_NAME" -target / > /dev/null 2>&1

INSTALL_STATUS=$?

if [ $INSTALL_STATUS -eq 0 ]; then
    echo -e "${GREEN}[OK] Installation completed successfully${NC}"
else
    echo -e "${RED}[ERROR] Installation failed${NC}"
    echo "Please contact support for assistance."
    cd /
    rm -rf "$TMP_DIR"
    exit 1
fi

echo ""

# Wait for installation to complete
sleep 3

# Configure the agent
echo "Configuring Assetio Agent..."

# Try both possible config locations (older and newer versions)
CONFIG_DIR_NEW="/Applications/GLPI-Agent/etc"
CONFIG_DIR_OLD="/Applications/GLPI-Agent.app/Contents/Resources/etc"

if [ -d "$CONFIG_DIR_NEW" ]; then
    CONFIG_DIR="$CONFIG_DIR_NEW"
elif [ -d "$CONFIG_DIR_OLD" ]; then
    CONFIG_DIR="$CONFIG_DIR_OLD"
else
    # Create new style directory
    CONFIG_DIR="$CONFIG_DIR_NEW"
    mkdir -p "$CONFIG_DIR"
fi

CONFIG_FILE="$CONFIG_DIR/agent.cfg"

# Backup existing config if present
if [ -f "$CONFIG_FILE" ]; then
    BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "Existing configuration backed up"
    fi
fi

# Write configuration
cat > "$CONFIG_FILE" << 'EOF'
# Assetio Agent Configuration

server = http://192.168.2.6/front/inventory.php
tag = assetio
delaytime = 3600
lazy = 0

# Enable local inventory interface
httpd-trust = 127.0.0.1/32
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Configuration completed successfully${NC}"
else
    echo -e "${YELLOW}[WARNING] Could not write configuration file${NC}"
fi

echo ""

# Start the service - check both possible plist locations
echo "Starting Assetio Agent service..."

PLIST_FILE_NEW="/Library/LaunchDaemons/com.teclib.glpi-agent.plist"
PLIST_FILE_OLD="/Library/LaunchDaemons/org.glpi-project.glpi-agent.plist"

if [ -f "$PLIST_FILE_NEW" ]; then
    PLIST_FILE="$PLIST_FILE_NEW"
elif [ -f "$PLIST_FILE_OLD" ]; then
    PLIST_FILE="$PLIST_FILE_OLD"
else
    PLIST_FILE=""
fi

if [ -n "$PLIST_FILE" ]; then
    # Unload if already loaded (ignore errors)
    launchctl unload "$PLIST_FILE" 2>/dev/null
    
    # Small delay
    sleep 2
    
    # Load the service
    launchctl load "$PLIST_FILE" > /dev/null 2>&1
    LOAD_STATUS=$?
    
    if [ $LOAD_STATUS -eq 0 ]; then
        echo -e "${GREEN}[OK] Service started successfully${NC}"
    else
        echo -e "${GREEN}[OK] Service configured (will start on next boot)${NC}"
    fi
else
    echo -e "${YELLOW}[WARNING] Service file not found${NC}"
    echo "The agent is installed and will start on next boot."
fi

echo ""

# Check server connectivity
echo "Verifying connection to Assetio server..."
echo ""

# Test connectivity with timeout
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 "$SERVER_URL" 2>/dev/null)
CURL_EXIT=$?

if [ $CURL_EXIT -ne 0 ]; then
    HTTP_CODE="000"
fi

# Check the response
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "405" ]; then
    echo -e "${GREEN}[OK] Successfully connected to Assetio server${NC}"
    echo ""
elif [ "$HTTP_CODE" = "000" ]; then
    echo -e "${YELLOW}[WARNING] Unable to reach Assetio server${NC}"
    echo ""
    echo "Possible reasons:"
    echo "  - Server is offline or unreachable"
    echo "  - Not connected to the correct network"
    echo "  - Firewall blocking connection"
    echo ""
    echo "The agent is installed and will connect automatically"
    echo "when the server becomes reachable."
else
    echo -e "${YELLOW}[WARNING] Server check returned status: $HTTP_CODE${NC}"
    echo "The agent is installed and will retry automatically."
fi

echo ""

# Force an immediate inventory (try both possible locations)
echo "Attempting initial inventory sync..."

AGENT_PATH_NEW="/Applications/GLPI-Agent/bin/glpi-agent"
AGENT_PATH_OLD="/Applications/GLPI-Agent.app/Contents/MacOS/glpi-agent"

if [ -f "$AGENT_PATH_NEW" ]; then
    AGENT_PATH="$AGENT_PATH_NEW"
elif [ -f "$AGENT_PATH_OLD" ]; then
    AGENT_PATH="$AGENT_PATH_OLD"
else
    AGENT_PATH=""
fi

if [ -n "$AGENT_PATH" ]; then
    # Run agent silently
    timeout 30 "$AGENT_PATH" --server="$SERVER_URL" --force > /dev/null 2>&1
    AGENT_EXIT=$?
    
    if [ $AGENT_EXIT -eq 0 ]; then
        echo -e "${GREEN}[OK] Initial inventory sent successfully${NC}"
    else
        echo -e "${YELLOW}[INFO] Initial inventory will be sent when server is reachable${NC}"
    fi
else
    echo -e "${YELLOW}[INFO] Inventory will be sent automatically${NC}"
fi

echo ""
echo -e "${GREEN}Assetio Agent installation completed successfully!${NC}"
echo ""

# Show service status
echo "Service status:"
if launchctl list 2>/dev/null | grep -q "glpi-agent"; then
    echo -e "${GREEN}✓ Assetio Agent is running${NC}"
else
    echo -e "${GREEN}✓ Assetio Agent is installed and will start automatically${NC}"
fi

echo ""
echo "========================================="
echo "Installation Summary"
echo "========================================="
echo "Agent Version:      $LATEST_VERSION"
echo "Architecture:       $PKG_ARCH"
echo "Status:             Installed"
echo ""
echo "The Assetio Agent will automatically:"
echo "  • Connect to your asset management server"
echo "  • Send inventory updates hourly"
echo "  • Run in the background"
echo ""
echo "========================================="
echo ""

# Cleanup
cd /
rm -rf "$TMP_DIR"

echo "Installation complete!"
echo ""

exit 0
