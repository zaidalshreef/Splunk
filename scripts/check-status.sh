#!/bin/bash
# =============================================================================
# Splunk Deployment Status Check Script
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
echo "  Splunk Deployment Status Check"
echo "=============================================="
echo ""

# Check Indexer
echo "=== Splunk Enterprise (Indexer) ==="
echo "Host: ${INDEXER_IP}"
ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${INDEXER_IP} \
    "docker ps --filter name=${SPLUNK_CONTAINER_NAME} --format 'Status: {{.Status}}'" 2>/dev/null || echo "Could not connect"

echo ""

# Check Forwarders
echo "=== Universal Forwarders ==="
for IP in $FORWARDER_IPS; do
    echo -n "${IP}: "
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${IP} \
        "docker ps --filter name=${SPLUNK_UF_CONTAINER_NAME} --format '{{.Status}}'" 2>/dev/null || echo "Could not connect"
done

echo ""

# Check data ingestion
echo "=== Data Ingestion Status ==="
RESULT=$(curl -sk -u ${SPLUNK_ADMIN_USER}:${SPLUNK_ADMIN_PASSWORD} \
    "https://${INDEXER_IP}:${SPLUNK_MGMT_PORT}/services/search/jobs/export" \
    -d search="search index=* earliest=-5m | stats count by index, host" \
    -d output_mode=csv 2>/dev/null)

if [[ -n "$RESULT" ]]; then
    echo "$RESULT"
else
    echo "Could not retrieve data ingestion status"
fi

echo ""

# Check forwarder connections
echo "=== Forwarder Connections ==="
ssh -i "$SSH_KEY_PATH" ${SSH_USER}@${INDEXER_IP} \
    "cat /opt/splunk/var/log/splunk/metrics.log 2>/dev/null | grep 'group=tcpin_connections' | tail -5" 2>/dev/null

echo ""
echo "=============================================="
echo "  Status Check Complete"
echo "=============================================="

