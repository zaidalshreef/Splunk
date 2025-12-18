#!/bin/bash
# =============================================================================
# Splunk Deployment Cleanup Script
# =============================================================================

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
echo "  Splunk Deployment Cleanup"
echo "=============================================="
echo ""
echo "WARNING: This will remove all Splunk containers and data!"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""

# Cleanup Forwarders
echo "=== Removing Universal Forwarders ==="
for IP in $FORWARDER_IPS; do
    echo ">>> Cleaning up ${IP}..."
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${IP} << EOF
docker rm -f ${SPLUNK_UF_CONTAINER_NAME} 2>/dev/null || true
rm -rf ${SPLUNKUF_DATA_DIR} 2>/dev/null || true
rm -f /etc/rsyslog.d/50-world-readable.conf 2>/dev/null || true
systemctl restart rsyslog 2>/dev/null || true
echo "✓ Cleaned up \$(hostname)"
EOF
done

echo ""

# Cleanup Indexer
echo "=== Removing Splunk Enterprise ==="
ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${INDEXER_IP} << EOF
# Stop and remove containers
docker rm -f ${SPLUNK_CONTAINER_NAME} 2>/dev/null || true
docker rm -f ${SPLUNK_UF_CONTAINER_NAME} 2>/dev/null || true

# Stop swarm monitor
systemctl stop swarm-monitor.timer 2>/dev/null || true
systemctl disable swarm-monitor.timer 2>/dev/null || true
rm -f /etc/systemd/system/swarm-monitor.* 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true

# Remove data directories
rm -rf ${SPLUNK_DATA_DIR} 2>/dev/null || true
rm -rf ${SPLUNKUF_DATA_DIR} 2>/dev/null || true
rm -rf /opt/docker-swarm-monitor 2>/dev/null || true

echo "✓ Cleaned up indexer"
EOF

echo ""
echo "=============================================="
echo "  Cleanup Complete"
echo "=============================================="
echo ""
echo "Note: Docker images are still present. To remove them:"
echo "  docker rmi ${SPLUNK_IMAGE}"
echo "  docker rmi ${SPLUNK_UF_IMAGE}"

