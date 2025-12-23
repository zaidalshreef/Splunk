#!/bin/bash
# =============================================================================
# Splunk Universal Forwarder Deployment Script
# =============================================================================
# Deploys Universal Forwarders with Docker metrics collection to all VMs

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
    
    # Copy the docker metrics collector script
    scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "${SCRIPT_DIR}/docker-metrics-collector.sh" ${SSH_USER}@${IP}:/opt/docker-metrics-collector.sh
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${IP} << 'REMOTE_SCRIPT'
# ============================================================
# PART 1: Deploy Docker Metrics Collector
# ============================================================

echo "Setting up Docker metrics collector..."
chmod +x /opt/docker-metrics-collector.sh

# Create systemd service
cat > /etc/systemd/system/docker-metrics.service << 'SERVICE'
[Unit]
Description=Docker Metrics Collector for Splunk
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/docker-metrics-collector.sh
SERVICE

# Create systemd timer
cat > /etc/systemd/system/docker-metrics.timer << 'TIMER'
[Unit]
Description=Run Docker Metrics Collector every minute

[Timer]
OnBootSec=60
OnUnitActiveSec=60
AccuracySec=1s

[Install]
WantedBy=timers.target
TIMER

# Enable and start the timer
systemctl daemon-reload
systemctl enable docker-metrics.timer
systemctl start docker-metrics.timer

# Run collector once to generate initial data
/opt/docker-metrics-collector.sh 2>/dev/null || true

# ============================================================
# PART 2: Make logs readable
# ============================================================

echo "Configuring log permissions..."
chmod 644 /var/log/syslog /var/log/auth.log /var/log/kern.log 2>/dev/null || true

# Configure rsyslog for world-readable logs
echo '$FileCreateMode 0644' > /etc/rsyslog.d/50-world-readable.conf
systemctl restart rsyslog 2>/dev/null || service rsyslog restart 2>/dev/null || true

# ============================================================
# PART 3: Deploy Universal Forwarder
# ============================================================

echo "Stopping existing forwarder..."
docker stop splunk-uf 2>/dev/null || true
docker rm splunk-uf 2>/dev/null || true
docker volume rm splunk-uf-etc splunk-uf-var 2>/dev/null || true

# Create fresh volumes
docker volume create splunk-uf-etc
docker volume create splunk-uf-var

echo "Pulling Universal Forwarder image..."
docker pull splunk/universalforwarder:latest

# Find Traefik log path if exists
TRAEFIK_LOG="/etc/dokploy/traefik/dynamic/access.log"
TRAEFIK_MOUNT=""
if [[ -f "$TRAEFIK_LOG" ]]; then
    TRAEFIK_MOUNT="-v $(dirname $TRAEFIK_LOG):$(dirname $TRAEFIK_LOG):ro"
fi

echo "Starting Universal Forwarder container..."
docker run -d \
  --name splunk-uf \
  --hostname $(hostname)-uf \
  --restart unless-stopped \
  -e SPLUNK_START_ARGS=--accept-license \
  -e SPLUNK_GENERAL_TERMS=--accept-sgt-current-at-splunk-com \
  -e SPLUNK_PASSWORD="$SPLUNK_ADMIN_PASSWORD" \
  -e SPLUNK_FORWARD_SERVER="$INDEXER_IP:9997" \
  -v splunk-uf-etc:/opt/splunkforwarder/etc \
  -v splunk-uf-var:/opt/splunkforwarder/var \
  -v /var/log/syslog:/var/log/syslog:ro \
  -v /var/log/auth.log:/var/log/auth.log:ro \
  -v /var/log/kern.log:/var/log/kern.log:ro \
  -v /var/log/docker-metrics.log:/var/log/docker-metrics.log:ro \
  -v /var/lib/docker/containers:/var/lib/docker/containers:ro \
  $TRAEFIK_MOUNT \
  splunk/universalforwarder:latest

echo "Waiting for forwarder to initialize (90 seconds)..."
sleep 90

# ============================================================
# PART 4: Configure Forwarder via CLI
# ============================================================

echo "Configuring forwarder..."

# Add forward server
docker exec -u splunk splunk-uf /opt/splunkforwarder/bin/splunk add forward-server $INDEXER_IP:9997 -auth admin:$SPLUNK_ADMIN_PASSWORD 2>&1 || true

# Add monitor inputs
docker exec -u splunk splunk-uf /opt/splunkforwarder/bin/splunk add monitor /var/log/syslog -index linux -sourcetype syslog -auth admin:$SPLUNK_ADMIN_PASSWORD 2>&1 || true
docker exec -u splunk splunk-uf /opt/splunkforwarder/bin/splunk add monitor /var/log/auth.log -index security -sourcetype linux_secure -auth admin:$SPLUNK_ADMIN_PASSWORD 2>&1 || true
docker exec -u splunk splunk-uf /opt/splunkforwarder/bin/splunk add monitor /var/log/kern.log -index linux -sourcetype linux_kernel -auth admin:$SPLUNK_ADMIN_PASSWORD 2>&1 || true
docker exec -u splunk splunk-uf /opt/splunkforwarder/bin/splunk add monitor /var/log/docker-metrics.log -index docker -sourcetype docker:metrics -auth admin:$SPLUNK_ADMIN_PASSWORD 2>&1 || true

# Add Traefik monitor if log exists
if [[ -f "$TRAEFIK_LOG" ]]; then
    docker exec -u splunk splunk-uf /opt/splunkforwarder/bin/splunk add monitor $TRAEFIK_LOG -index traefik -sourcetype traefik:access -auth admin:$SPLUNK_ADMIN_PASSWORD 2>&1 || true
fi

# Restart forwarder to apply changes
docker exec -u splunk splunk-uf /opt/splunkforwarder/bin/splunk restart 2>&1

echo ""
echo "✓ Universal Forwarder deployed on $(hostname)"
REMOTE_SCRIPT

done

echo ""
echo "=============================================="
echo "  Waiting for forwarders to connect..."
echo "=============================================="
sleep 30

echo ""
echo "=== Verifying forwarder connections ==="
ssh -i "$SSH_KEY_PATH" ${SSH_USER}@${INDEXER_IP} \
    "docker exec splunk-enterprise /opt/splunk/bin/splunk search '| metadata type=hosts | table host recentTime' -auth admin:${SPLUNK_ADMIN_PASSWORD} 2>/dev/null"

echo ""
echo "=============================================="
echo "  Universal Forwarders Deployed Successfully!"
echo "=============================================="
echo ""
echo "Data collection includes:"
echo "  - System logs (syslog, auth.log, kern.log)"
echo "  - Docker metrics (container health, Swarm status, CPU/memory)"
echo "  - Traefik access logs (if available)"
echo ""
