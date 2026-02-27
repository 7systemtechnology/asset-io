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

# Get the latest version from GitHub API
echo "Fetching latest Assetio Agent version..."
LATEST_VERSION=$(curl -s -L https://api.github.com/repos/glpi-project/glpi-agent/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '[:space:]')

if [ -z "$LATEST_VERSION" ]; then
    echo -e "${YELLOW}WARNING: Could not fetch latest version from GitHub${NC}"
    echo "Using fallback version 1.10"
    LATEST_VERSION="1.10"
else
    echo -e "${GREEN}Latest version: $LATEST_VERSION${NC}"
fi

echo ""

# Construct download URL (note: macOS packages use underscore, not dash)
PKG_NAME="GLPI-Agent-${LATEST_VERSION}_${PKG_ARCH}.pkg"
DOWNLOAD_URL="https://github.com/glpi-project/glpi-agent/releases/download/${LATEST_VERSION}/${PKG_NAME}"

echo "Downloading Assetio Agent..."
echo "Source: GitHub GLPI-Project"
echo ""

# Create temporary directory
TMP_DIR="/tmp/assetio-agent-install-$$"
mkdir -p "$TMP_DIR"

if [ ! -d "$TMP_DIR" ]; then
    echo -e "${RED}[ERROR] Failed to create temporary directory${NC}"
    exit 1
fi

cd "$TMP_DIR" || exit 1

# Download with error handling
echo "Downloading from: $DOWNLOAD_URL"
curl -L -f -o "$PKG_NAME" "$DOWNLOAD_URL" 2>&1

DOWNLOAD_STATUS=$?

if [ $DOWNLOAD_STATUS -ne 0 ]; then
    echo -e "${RED}[ERROR] Download failed (curl exit code: $DOWNLOAD_STATUS)${NC}"
    echo "Please check:"
    echo "  - Your internet connection"
    echo "  - GitHub is accessible"
    echo "  - The release exists for version $LATEST_VERSION"
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
installer -pkg "$PKG_NAME" -target / 2>&1

INSTALL_STATUS=$?

if [ $INSTALL_STATUS -eq 0 ]; then
    echo -e "${GREEN}[OK] Installation completed successfully${NC}"
else
    echo -e "${RED}[ERROR] Installation failed (exit code: $INSTALL_STATUS)${NC}"
    echo "Please check system logs for more details"
    cd /
    rm -rf "$TMP_DIR"
    exit 1
fi

echo ""

# Wait for installation to complete
sleep 3

# Configure the agent
echo "Configuring Assetio Agent..."

CONFIG_DIR="/Applications/GLPI-Agent.app/Contents/Resources/etc"
CONFIG_FILE="$CONFIG_DIR/agent.cfg"

# Create config directory if it doesn't exist
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}[WARNING] Could not create config directory${NC}"
        echo "Path: $CONFIG_DIR"
    fi
fi

# Backup existing config if present
if [ -f "$CONFIG_FILE" ]; then
    BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "Existing configuration backed up to: $BACKUP_FILE"
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
    echo -e "${GREEN}[OK] Configuration file created successfully${NC}"
else
    echo -e "${YELLOW}[WARNING] Could not write configuration file${NC}"
fi

echo ""

# Start the service
echo "Starting Assetio Agent service..."

PLIST_FILE="/Library/LaunchDaemons/org.glpi-project.glpi-agent.plist"

if [ -f "$PLIST_FILE" ]; then
    # Unload if already loaded (ignore errors)
    launchctl unload "$PLIST_FILE" 2>/dev/null
    
    # Small delay
    sleep 2
    
    # Load the service
    launchctl load "$PLIST_FILE" 2>&1
    LOAD_STATUS=$?
    
    if [ $LOAD_STATUS -eq 0 ]; then
        echo -e "${GREEN}[OK] Service started successfully${NC}"
    else
        echo -e "${YELLOW}[WARNING] Service load returned code: $LOAD_STATUS${NC}"
        echo "The service may already be running or may start on next boot"
    fi
else
    echo -e "${YELLOW}[WARNING] LaunchDaemon file not found at: $PLIST_FILE${NC}"
    echo "The agent was installed but the service may need to be configured manually."
fi

echo ""

# Check server connectivity
echo "Verifying connection to Assetio server..."
echo "Testing: $SERVER_URL"
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
    echo "Server URL: $SERVER_URL"
    echo "HTTP Status: $HTTP_CODE"
    echo ""
    echo "Note: HTTP 400/405 responses are normal - they indicate the server"
    echo "is reachable and will accept inventory data from the agent."
elif [ "$HTTP_CODE" = "000" ]; then
    echo -e "${YELLOW}[WARNING] Unable to reach Assetio server${NC}"
    echo "Server URL: $SERVER_URL"
    echo ""
    echo "Possible reasons:"
    echo "  - Server is offline or unreachable"
    echo "  - Firewall or network blocking connection"
    echo "  - Incorrect URL configured"
    echo "  - DNS resolution issues"
    echo ""
    echo "The agent is installed and will retry automatically."
    echo "Please verify the server is accessible from this machine."
else
    echo -e "${YELLOW}[WARNING] Server responded with HTTP code: $HTTP_CODE${NC}"
    echo "Server URL: $SERVER_URL"
    echo ""
    echo "The agent is installed. Please verify server configuration."
fi

echo ""

# Force an immediate inventory
echo "Attempting to send initial inventory..."

AGENT_PATH="/Applications/GLPI-Agent.app/Contents/MacOS/glpi-agent"

if [ -f "$AGENT_PATH" ]; then
    # Run agent with timeout
    timeout 30 "$AGENT_PATH" --server="$SERVER_URL" --force 2>&1 | head -n 10
    AGENT_EXIT=${PIPESTATUS[0]}
    
    if [ $AGENT_EXIT -eq 0 ]; then
        echo ""
        echo -e "${GREEN}[OK] Initial inventory sent successfully${NC}"
    else
        echo ""
        echo -e "${YELLOW}[WARNING] Initial inventory returned code: $AGENT_EXIT${NC}"
        echo "The agent will retry automatically on its schedule."
    fi
else
    echo -e "${YELLOW}[WARNING] Agent executable not found at: $AGENT_PATH${NC}"
    echo "The agent may be installed in a different location."
fi

echo ""
echo -e "${GREEN}Assetio Agent installation completed!${NC}"
echo ""

# Show service status
echo "Service status:"
if launchctl list 2>/dev/null | grep -q "org.glpi-project.glpi-agent"; then
    echo -e "${GREEN}✓ Assetio Agent service is loaded and running${NC}"
else
    echo -e "${YELLOW}⚠ Service may not be running (will start on next boot)${NC}"
fi

echo ""
echo "========================================="
echo "Installation Summary"
echo "========================================="
echo "Agent Version:    $LATEST_VERSION"
echo "Architecture:     $PKG_ARCH"
echo "Server URL:       $SERVER_URL"
echo "Config File:      $CONFIG_FILE"
echo "Service File:     $PLIST_FILE"
echo ""
echo "Useful Assetio Agent commands:"
echo ""
echo "  Check if service is loaded:"
echo "    sudo launchctl list | grep glpi-agent"
echo ""
echo "  View agent logs:"
echo "    sudo tail -f /var/log/glpi-agent.log"
echo ""
echo "  Force manual inventory:"
echo "    sudo $AGENT_PATH --server=$SERVER_URL --force"
echo ""
echo "  Restart service:"
echo "    sudo launchctl unload $PLIST_FILE"
echo "    sudo launchctl load $PLIST_FILE"
echo ""
echo "  Check agent version:"
echo "    $AGENT_PATH --version"
echo ""
echo "========================================="
echo ""

# Cleanup
echo "Cleaning up temporary files..."
cd /
rm -rf "$TMP_DIR"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Cleanup completed${NC}"
else
    echo -e "${YELLOW}Note: Some temporary files may remain in /tmp${NC}"
fi

echo ""
echo "Installation complete! You may close this window."
echo ""

exit 0
