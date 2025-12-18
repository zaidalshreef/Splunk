#!/bin/bash
# =============================================================================
# Splunk Universal Forwarder Deployment Script
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
echo "  Splunk Universal Forwarder Deployment"
echo "=============================================="
echo ""

# Convert space-separated lists to arrays
IFS=' ' read -ra IP_ARRAY <<< "$FORWARDER_IPS"
IFS=' ' read -ra HOSTNAME_ARRAY <<< "$FORWARDER_HOSTNAMES"

# Deploy to each forwarder node
for i in "${!IP_ARRAY[@]}"; do
    IP="${IP_ARRAY[$i]}"
    HOSTNAME="${HOSTNAME_ARRAY[$i]}"
    
    echo ""
    echo "=== Deploying to ${HOSTNAME} (${IP}) ==="
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${IP} << EOF
echo "Creating directories..."
mkdir -p ${SPLUNKUF_DATA_DIR}/etc/system/local
mkdir -p ${SPLUNKUF_DATA_DIR}/etc/apps/myinputs/{local,default,metadata}
mkdir -p ${SPLUNKUF_DATA_DIR}/var

# Create outputs.conf
cat > ${SPLUNKUF_DATA_DIR}/etc/system/local/outputs.conf << 'OUTPUTS'
[tcpout]
defaultGroup = default-autolb-group

[tcpout:default-autolb-group]
server = ${INDEXER_IP}:${SPLUNK_RECV_PORT}
OUTPUTS

# Create inputs.conf
cat > ${SPLUNKUF_DATA_DIR}/etc/apps/myinputs/local/inputs.conf << 'INPUTS'
[default]
host = ${HOSTNAME}

[monitor:///var/log/syslog]
disabled = false
index = linux
sourcetype = syslog

[monitor:///var/log/auth.log]
disabled = false
index = security
sourcetype = linux_secure

[monitor:///var/log/kern.log]
disabled = false
index = linux
sourcetype = linux_kernel
INPUTS

# Create app.conf
cat > ${SPLUNKUF_DATA_DIR}/etc/apps/myinputs/default/app.conf << 'APP'
[install]
is_configured = 1
state = enabled

[package]
check_for_updates = 0

[ui]
is_visible = 0
label = Custom Inputs
APP

# Create metadata
cat > ${SPLUNKUF_DATA_DIR}/etc/apps/myinputs/metadata/default.meta << 'META'
[]
export = system
META

# Set permissions for splunk user (uid 41812)
chown -R 41812:41812 ${SPLUNKUF_DATA_DIR}

# Get group IDs for log access
ADM_GID=\$(getent group adm | cut -d: -f3)
SYSLOG_GID=\$(getent group syslog | cut -d: -f3 2>/dev/null || echo "104")

# Make log files readable
chmod 644 /var/log/syslog /var/log/auth.log /var/log/kern.log 2>/dev/null || true

# Configure rsyslog for world-readable logs
echo '\$FileCreateMode 0644' > /etc/rsyslog.d/50-world-readable.conf
systemctl restart rsyslog 2>/dev/null || service rsyslog restart 2>/dev/null || true

# Stop existing container
docker rm -f ${SPLUNK_UF_CONTAINER_NAME} 2>/dev/null || true

# Pull image
docker pull ${SPLUNK_UF_IMAGE}

# Run forwarder
docker run -d \\
  --name ${SPLUNK_UF_CONTAINER_NAME} \\
  --hostname ${HOSTNAME}-uf \\
  --restart unless-stopped \\
  --network host \\
  --group-add \$ADM_GID \\
  --group-add \$SYSLOG_GID \\
  -v ${SPLUNKUF_DATA_DIR}/etc:/opt/splunkforwarder/etc \\
  -v ${SPLUNKUF_DATA_DIR}/var:/opt/splunkforwarder/var \\
  -v /var/log/syslog:/var/log/syslog:ro \\
  -v /var/log/auth.log:/var/log/auth.log:ro \\
  -v /var/log/kern.log:/var/log/kern.log:ro \\
  -e SPLUNK_GENERAL_TERMS='--accept-sgt-current-at-splunk-com' \\
  -e SPLUNK_START_ARGS='--accept-license' \\
  -e SPLUNK_PASSWORD='${SPLUNK_ADMIN_PASSWORD}' \\
  ${SPLUNK_UF_IMAGE}

echo "✓ Universal Forwarder deployed on \$(hostname)"
EOF

done

echo ""
echo "=============================================="
echo "  Waiting for forwarders to initialize..."
echo "=============================================="
sleep 60

echo ""
echo "=== Verifying forwarder connections ==="
ssh -i "$SSH_KEY_PATH" ${SSH_USER}@${INDEXER_IP} \
    "cat /opt/splunk/var/log/splunk/metrics.log 2>/dev/null | grep 'group=tcpin_connections' | tail -10"

echo ""
echo "=============================================="
echo "  Universal Forwarders Deployed Successfully!"
echo "=============================================="

