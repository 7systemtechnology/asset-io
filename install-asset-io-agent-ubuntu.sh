#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================="
echo "    Assetio Agent Installation"
echo "======================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERROR: This installer requires root privileges.${NC}"
    echo "Please run with sudo: sudo bash $0"
    echo ""
    exit 1
fi

echo "Installing Assetio Agent..."
echo "Please wait, this may take a few minutes..."
echo ""

# Set your server URL here
SERVER_URL="http://192.168.2.6/front/inventory.php"
SERVER_IP="192.168.2.6"

# Detect the Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    echo -e "${RED}ERROR: Cannot detect Linux distribution${NC}"
    exit 1
fi

# Install GLPI Agent based on distribution
case $OS in
    ubuntu|debian)
        echo "Detected: $PRETTY_NAME"
        echo "Installing GLPI Agent via APT..."
        
        # Update package list
        apt-get update > /dev/null 2>&1
        
        # Install dependencies
        apt-get install -y curl wget gnupg2 > /dev/null 2>&1
        
        # Add GLPI Agent repository
        curl -sS https://raw.githubusercontent.com/glpi-project/glpi-agent/develop/contrib/unix/glpi-agent-repository | bash > /dev/null 2>&1
        
        # Install the agent
        apt-get update > /dev/null 2>&1
        apt-get install -y glpi-agent > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[OK] Installation completed${NC}"
        else
            echo -e "${RED}[ERROR] Installation failed${NC}"
            exit 1
        fi
        ;;
        
    centos|rhel|fedora)
        echo "Detected: $PRETTY_NAME"
        echo "Installing GLPI Agent via YUM/DNF..."
        
        # Install dependencies
        if command -v dnf &> /dev/null; then
            dnf install -y curl wget > /dev/null 2>&1
        else
            yum install -y curl wget > /dev/null 2>&1
        fi
        
        # Add GLPI Agent repository
        curl -sS https://raw.githubusercontent.com/glpi-project/glpi-agent/develop/contrib/unix/glpi-agent-repository | bash > /dev/null 2>&1
        
        # Install the agent
        if command -v dnf &> /dev/null; then
            dnf install -y glpi-agent > /dev/null 2>&1
        else
            yum install -y glpi-agent > /dev/null 2>&1
        fi
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[OK] Installation completed${NC}"
        else
            echo -e "${RED}[ERROR] Installation failed${NC}"
            exit 1
        fi
        ;;
        
    *)
        echo -e "${RED}ERROR: Unsupported distribution: $OS${NC}"
        echo "Supported distributions: Ubuntu, Debian, CentOS, RHEL, Fedora"
        exit 1
        ;;
esac

echo ""

# Configure the agent
echo "Configuring agent..."

# Create or update the configuration file
CONFIG_FILE="/etc/glpi-agent/agent.cfg"

if [ -f "$CONFIG_FILE" ]; then
    # Backup existing config
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Write configuration
cat > "$CONFIG_FILE" << EOF
# GLPI Agent Configuration
# Managed by Assetio

server = $SERVER_URL
tag = assetio
delaytime = 3600
lazy = 0

# Enable modules
httpd-trust = 127.0.0.1/32
EOF

echo -e "${GREEN}[OK] Configuration completed${NC}"
echo ""

# Enable and start the service
echo "Starting Assetio Agent service..."

systemctl enable glpi-agent > /dev/null 2>&1
systemctl restart glpi-agent > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Service started successfully${NC}"
else
    echo -e "${RED}[ERROR] Failed to start service${NC}"
    exit 1
fi

echo ""

# Check server connectivity
echo "Verifying connection to: $SERVER_URL"
echo ""

# Test connectivity
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$SERVER_URL" 2>/dev/null)

if [ -z "$HTTP_CODE" ]; then
    HTTP_CODE="000"
fi

# Check the response
if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "400" ] || [ "$HTTP_CODE" == "405" ]; then
    echo -e "${GREEN}[OK] Connected to asset management server successfully${NC}"
    echo "Server URL: $SERVER_URL"
    echo "HTTP Status: $HTTP_CODE"
elif [ "$HTTP_CODE" == "000" ]; then
    echo -e "${YELLOW}[WARNING] Unable to reach asset management server${NC}"
    echo "Server URL: $SERVER_URL"
    echo ""
    echo "Possible reasons:"
    echo "- Server is offline or unreachable"
    echo "- Firewall blocking connection"
    echo "- Incorrect URL configured"
    echo ""
    echo "The agent is installed but may not send inventory until server is reachable."
else
    echo -e "${YELLOW}[WARNING] Server responded with HTTP code: $HTTP_CODE${NC}"
    echo "Server URL: $SERVER_URL"
    echo ""
    echo "The agent is installed but server connectivity should be verified."
fi

echo ""

# Force an immediate inventory
echo "Running initial inventory..."
glpi-agent --server="$SERVER_URL" --force > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Initial inventory sent successfully${NC}"
else
    echo -e "${YELLOW}[WARNING] Initial inventory may have failed${NC}"
    echo "The agent will retry automatically."
fi

echo ""
echo -e "${GREEN}Assetio Agent is now monitoring this computer.${NC}"
echo ""

# Show service status
echo "Service status:"
systemctl status glpi-agent --no-pager | head -n 5

echo ""
echo "Installation complete!"
echo ""
echo "Useful commands:"
echo "  Check status:    sudo systemctl status glpi-agent"
echo "  View logs:       sudo journalctl -u glpi-agent -f"
echo "  Force inventory: sudo glpi-agent --server=$SERVER_URL --force"
echo ""

exit 0
