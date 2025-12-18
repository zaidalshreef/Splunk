#!/bin/bash
# =============================================================================
# Fix Log File Permissions Script
# =============================================================================

set -e

# Load environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/environment.env"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

echo "=============================================="
echo "  Fixing Log File Permissions"
echo "=============================================="
echo ""

# Fix permissions on all nodes
for IP in $FORWARDER_IPS; do
    echo ">>> Fixing permissions on ${IP}..."
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${IP} << 'EOF'
# Make current log files readable
chmod 644 /var/log/syslog /var/log/auth.log /var/log/kern.log 2>/dev/null || true

# Configure rsyslog to create files with world-readable permissions
echo '$FileCreateMode 0644' > /etc/rsyslog.d/50-world-readable.conf

# Restart rsyslog to apply changes
systemctl restart rsyslog 2>/dev/null || service rsyslog restart 2>/dev/null || true

echo "✓ Fixed on $(hostname)"
EOF

done

echo ""
echo "=============================================="
echo "  Permissions Fixed Successfully!"
echo "=============================================="

