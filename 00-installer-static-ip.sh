#!/usr/bin/env bash
#
# 00-installer-static-ip.sh
# Interactively configures a static IP address on Ubuntu LTS via Netplan.
#
# Usage:
#   sudo ./00-installer-static-ip.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

if ! command -v netplan >/dev/null 2>&1; then
    echo "netplan not found. This script targets Ubuntu LTS with netplan installed." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Search for existing netplan config file(s)
# ---------------------------------------------------------------------------
echo "Searching for existing netplan configuration files in /etc/netplan..."
mapfile -t EXISTING_CONFIGS < <(find /etc/netplan -maxdepth 1 -name "*.yaml" -type f 2>/dev/null | sort)

if [[ ${#EXISTING_CONFIGS[@]} -eq 0 ]]; then
    echo "No existing netplan config found. A new one will be created."
    NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"
else
    echo "Found existing netplan config file(s):"
    for i in "${!EXISTING_CONFIGS[@]}"; do
        printf "  [%d] %s\n" "$((i+1))" "${EXISTING_CONFIGS[$i]}"
    done
    echo "  [n] Create a new file instead"
    read -rp "Select the config file to overwrite [1-${#EXISTING_CONFIGS[@]}/n]: " CONFIG_CHOICE

    if [[ "$CONFIG_CHOICE" =~ ^[Nn]$ ]]; then
        NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"
    elif [[ "$CONFIG_CHOICE" =~ ^[0-9]+$ ]] && (( CONFIG_CHOICE >= 1 && CONFIG_CHOICE <= ${#EXISTING_CONFIGS[@]} )); then
        NETPLAN_FILE="${EXISTING_CONFIGS[$((CONFIG_CHOICE-1))]}"
    else
        echo "Invalid selection." >&2
        exit 1
    fi
fi
echo "Using config file: $NETPLAN_FILE"
echo

# ---------------------------------------------------------------------------
# Step 2: List available network interfaces and ask user to choose
# ---------------------------------------------------------------------------
echo "Available network interfaces:"
mapfile -t INTERFACES < <(ip -brief link show | awk '{print $1}' | grep -v '^lo$')

if [[ ${#INTERFACES[@]} -eq 0 ]]; then
    echo "No network interfaces found (other than loopback)." >&2
    exit 1
fi

for i in "${!INTERFACES[@]}"; do
    IFACE_NAME="${INTERFACES[$i]}"
    IFACE_STATE=$(ip -brief link show "$IFACE_NAME" | awk '{print $2}')
    IFACE_MAC=$(ip link show "$IFACE_NAME" | awk '/link\/ether/{print $2}')
    printf "  [%d] %-12s state=%-8s mac=%s\n" "$((i+1))" "$IFACE_NAME" "$IFACE_STATE" "${IFACE_MAC:-n/a}"
done

read -rp "Select the interface to configure [1-${#INTERFACES[@]}]: " IFACE_CHOICE
if ! [[ "$IFACE_CHOICE" =~ ^[0-9]+$ ]] || (( IFACE_CHOICE < 1 || IFACE_CHOICE > ${#INTERFACES[@]} )); then
    echo "Invalid selection." >&2
    exit 1
fi
IFACE="${INTERFACES[$((IFACE_CHOICE-1))]}"
echo "Selected interface: $IFACE"
echo

# ---------------------------------------------------------------------------
# Step 3: Ask for IP, subnet, gateway, DNS servers
# ---------------------------------------------------------------------------
read -rp "Enter static IP address (e.g. 192.168.1.50): " IP_ADDR
read -rp "Enter subnet mask or CIDR prefix (e.g. 255.255.255.0 or 24): " SUBNET
read -rp "Enter gateway (e.g. 192.168.1.1): " GATEWAY
read -rp "Enter DNS server(s), comma separated (e.g. 1.1.1.1,8.8.8.8): " DNS_SERVERS

# Convert dotted-decimal subnet mask to CIDR prefix length if needed
if [[ "$SUBNET" =~ ^[0-9]+$ ]]; then
    CIDR="$SUBNET"
elif [[ "$SUBNET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    CIDR=$(python3 - "$SUBNET" <<'PYEOF'
import sys
mask = sys.argv[1].split('.')
bits = sum(bin(int(o)).count('1') for o in mask)
print(bits)
PYEOF
)
else
    echo "Invalid subnet mask/prefix format." >&2
    exit 1
fi

STATIC_IP="${IP_ADDR}/${CIDR}"

echo
echo "Configuration summary:"
echo "  Interface : $IFACE"
echo "  Address   : $STATIC_IP"
echo "  Gateway   : $GATEWAY"
echo "  DNS       : $DNS_SERVERS"
echo "  Config    : $NETPLAN_FILE"
read -rp "Proceed with this configuration? [y/N]: " CONFIRM
if ! [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# ---------------------------------------------------------------------------
# Backup any existing netplan config
# ---------------------------------------------------------------------------
if [[ -f "$NETPLAN_FILE" ]]; then
    cp -a "$NETPLAN_FILE" "${NETPLAN_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    echo "Existing config backed up."
fi

# ---------------------------------------------------------------------------
# Build DNS YAML list from comma-separated input
# ---------------------------------------------------------------------------
DNS_YAML=$(printf '%s' "$DNS_SERVERS" | awk -F',' '{
    printf "["
    for (i=1;i<=NF;i++) {
        gsub(/^ +| +$/,"",$i)
        printf "%s%s", (i>1?",":""), $i
    }
    printf "]"
}')

# ---------------------------------------------------------------------------
# Write netplan config
# ---------------------------------------------------------------------------
cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses:
        - ${STATIC_IP}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: ${DNS_YAML}
EOF

chmod 600 "$NETPLAN_FILE"

echo "Netplan config written. Validating and applying..."

netplan generate
netplan apply

echo "Done. Verify with: ip -brief addr show ${IFACE}"
