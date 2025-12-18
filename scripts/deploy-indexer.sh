#!/bin/bash
# =============================================================================
# Splunk Enterprise Indexer Deployment Script
# =============================================================================

set -e

# Load environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/environment.env"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    echo "Please copy config/environment.env.example to config/environment.env"
    exit 1
fi

echo "=============================================="
echo "  Splunk Enterprise Indexer Deployment"
echo "=============================================="
echo ""
echo "Target: ${SSH_USER}@${INDEXER_IP}"
echo ""

# Deploy Splunk Enterprise
ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${INDEXER_IP} << EOF
echo "=== Creating Splunk directories ==="
mkdir -p ${SPLUNK_DATA_DIR}/{etc,var}
chmod -R 755 ${SPLUNK_DATA_DIR}

echo ""
echo "=== Stopping existing Splunk container (if any) ==="
docker rm -f ${SPLUNK_CONTAINER_NAME} 2>/dev/null || true

echo ""
echo "=== Pulling Splunk Enterprise image ==="
docker pull ${SPLUNK_IMAGE}

echo ""
echo "=== Starting Splunk Enterprise container ==="
docker run -d \\
  --name ${SPLUNK_CONTAINER_NAME} \\
  --hostname splunk-indexer \\
  --restart unless-stopped \\
  -p ${SPLUNK_WEB_PORT}:8000 \\
  -p ${SPLUNK_MGMT_PORT}:8089 \\
  -p ${SPLUNK_RECV_PORT}:9997 \\
  -p ${SPLUNK_HEC_PORT}:8088 \\
  -p ${SPLUNK_SYSLOG_PORT}:514/udp \\
  -v ${SPLUNK_DATA_DIR}/etc:/opt/splunk/etc \\
  -v ${SPLUNK_DATA_DIR}/var:/opt/splunk/var \\
  -v /var/log:/host/var/log:ro \\
  -v /var/run/docker.sock:/var/run/docker.sock:ro \\
  -e SPLUNK_GENERAL_TERMS='--accept-sgt-current-at-splunk-com' \\
  -e SPLUNK_START_ARGS='--accept-license' \\
  -e SPLUNK_PASSWORD='${SPLUNK_ADMIN_PASSWORD}' \\
  -e SPLUNK_ENABLE_LISTEN=${SPLUNK_RECV_PORT} \\
  -e SPLUNK_HEC_TOKEN='${SPLUNK_HEC_TOKEN}' \\
  ${SPLUNK_IMAGE}

echo ""
echo "=== Waiting for Splunk to initialize (90 seconds) ==="
sleep 90

echo ""
echo "=== Checking container status ==="
docker ps --filter name=${SPLUNK_CONTAINER_NAME} --format "table {{.Names}}\t{{.Status}}"

echo ""
echo "=== Verifying Splunk Web UI ==="
curl -sk --connect-timeout 5 https://localhost:${SPLUNK_WEB_PORT}/en-US/account/login -o /dev/null && echo "✓ Splunk Web UI is accessible!" || echo "✗ Splunk Web UI not ready yet"
EOF

echo ""
echo "=== Creating custom indexes ==="
for INDEX in $SPLUNK_INDEXES; do
    echo "Creating index: $INDEX"
    ssh -i "$SSH_KEY_PATH" ${SSH_USER}@${INDEXER_IP} \
        "curl -sk -u ${SPLUNK_ADMIN_USER}:${SPLUNK_ADMIN_PASSWORD} https://localhost:${SPLUNK_MGMT_PORT}/servicesNS/nobody/system/data/indexes -d name=$INDEX -d datatype=event" > /dev/null 2>&1
done

echo ""
echo "=============================================="
echo "  Splunk Enterprise Deployed Successfully!"
echo "=============================================="
echo ""
echo "Access Splunk Web: https://${INDEXER_IP}:${SPLUNK_WEB_PORT}"
echo "Username: ${SPLUNK_ADMIN_USER}"
echo "Password: ${SPLUNK_ADMIN_PASSWORD}"
echo ""

