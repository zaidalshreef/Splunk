#!/bin/bash
# =============================================================================
# Docker Swarm Monitoring Setup Script
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
echo "  Docker Swarm Monitoring Setup"
echo "=============================================="
echo ""

ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${INDEXER_IP} << EOF
# Create monitoring directory
mkdir -p /opt/docker-swarm-monitor

# Create the monitoring script
cat > /opt/docker-swarm-monitor/swarm_monitor.sh << 'MONITOR'
#!/bin/bash

SPLUNK_HEC_URL="https://localhost:${SPLUNK_HEC_PORT}/services/collector/event"
SPLUNK_HEC_TOKEN="${SPLUNK_HEC_TOKEN}"
HOSTNAME=\$(hostname)

# Function to send data to Splunk HEC
send_to_splunk() {
    local sourcetype=\$1
    local data=\$2
    curl -sk -X POST "\$SPLUNK_HEC_URL" \\
        -H "Authorization: Splunk \$SPLUNK_HEC_TOKEN" \\
        -d "{\"event\": \$data, \"sourcetype\": \"\$sourcetype\", \"index\": \"docker\", \"host\": \"\$HOSTNAME\"}"
}

# Collect Docker Swarm node info
docker node ls --format '{"id":"{{.ID}}","hostname":"{{.Hostname}}","status":"{{.Status}}","availability":"{{.Availability}}","manager_status":"{{.ManagerStatus}}"}' 2>/dev/null | while read line; do
    send_to_splunk "docker:swarm:node" "\$line"
done

# Collect Docker Swarm service info
docker service ls --format '{"id":"{{.ID}}","name":"{{.Name}}","mode":"{{.Mode}}","replicas":"{{.Replicas}}","image":"{{.Image}}"}' 2>/dev/null | while read line; do
    send_to_splunk "docker:swarm:service" "\$line"
done

# Collect running containers
docker ps --format '{"id":"{{.ID}}","names":"{{.Names}}","image":"{{.Image}}","status":"{{.Status}}","ports":"{{.Ports}}"}' 2>/dev/null | while read line; do
    send_to_splunk "docker:container:status" "\$line"
done

# Collect Docker stats
docker stats --no-stream --format '{"name":"{{.Name}}","cpu":"{{.CPUPerc}}","mem_usage":"{{.MemUsage}}","mem_perc":"{{.MemPerc}}","net_io":"{{.NetIO}}","block_io":"{{.BlockIO}}"}' 2>/dev/null | while read line; do
    send_to_splunk "docker:stats" "\$line"
done

echo "\$(date): Swarm monitoring data sent to Splunk"
MONITOR

chmod +x /opt/docker-swarm-monitor/swarm_monitor.sh

# Create systemd service
cat > /etc/systemd/system/swarm-monitor.service << 'SERVICE'
[Unit]
Description=Docker Swarm Monitoring for Splunk
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/docker-swarm-monitor/swarm_monitor.sh
SERVICE

# Create systemd timer
cat > /etc/systemd/system/swarm-monitor.timer << 'TIMER'
[Unit]
Description=Run Docker Swarm Monitor every minute

[Timer]
OnCalendar=*:*:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER

# Enable and start the timer
systemctl daemon-reload
systemctl enable swarm-monitor.timer
systemctl start swarm-monitor.timer

# Run initial collection
echo "Running initial data collection..."
/opt/docker-swarm-monitor/swarm_monitor.sh

echo "✓ Docker Swarm monitoring configured"
EOF

echo ""
echo "=============================================="
echo "  Swarm Monitoring Setup Complete!"
echo "=============================================="
echo ""
echo "Data will be collected every ${SWARM_MONITOR_INTERVAL} seconds"
echo "View data with: index=docker sourcetype=docker:swarm:*"

