#!/bin/bash
# =============================================================================
# Configure Docker to send logs directly to Splunk
# =============================================================================
# This configures the Docker daemon to use the Splunk logging driver
# All container stdout/stderr will be sent directly to Splunk HEC
# =============================================================================

set -e

SPLUNK_HOST="${SPLUNK_HOST:-10.10.10.114}"
SPLUNK_HEC_TOKEN="${SPLUNK_HEC_TOKEN:-a1b2c3d4-e5f6-7890-abcd-ef1234567890}"
SSH_KEY="${SSH_KEY:-~/.ssh/key_10.10.10.114}"

# Hosts to configure (all swarm nodes)
HOSTS=("10.10.10.114" "10.10.10.115" "10.10.10.116" "10.10.10.117" "10.10.10.118")

echo "=== Configuring Docker logging driver on all nodes ==="

for host in "${HOSTS[@]}"; do
    echo ""
    echo "--- Configuring $host ---"
    
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$host "
        # Backup existing daemon.json
        cp /etc/docker/daemon.json /etc/docker/daemon.json.bak 2>/dev/null || true
        
        # Check if daemon.json exists and has content
        if [ -f /etc/docker/daemon.json ] && [ -s /etc/docker/daemon.json ]; then
            # Merge with existing config using jq
            if command -v jq &> /dev/null; then
                cat /etc/docker/daemon.json | jq '. + {
                    \"log-driver\": \"splunk\",
                    \"log-opts\": {
                        \"splunk-token\": \"$SPLUNK_HEC_TOKEN\",
                        \"splunk-url\": \"https://$SPLUNK_HOST:8088\",
                        \"splunk-index\": \"docker\",
                        \"splunk-sourcetype\": \"docker:container\",
                        \"splunk-format\": \"json\",
                        \"splunk-verify-connection\": \"false\",
                        \"splunk-gzip\": \"true\",
                        \"tag\": \"{{.Name}}/{{.ID}}\"
                    }
                }' > /etc/docker/daemon.json.new
                mv /etc/docker/daemon.json.new /etc/docker/daemon.json
            else
                echo 'jq not installed, creating new config'
                cat > /etc/docker/daemon.json << 'DAEMON'
{
  \"log-driver\": \"splunk\",
  \"log-opts\": {
    \"splunk-token\": \"$SPLUNK_HEC_TOKEN\",
    \"splunk-url\": \"https://$SPLUNK_HOST:8088\",
    \"splunk-index\": \"docker\",
    \"splunk-sourcetype\": \"docker:container\",
    \"splunk-format\": \"json\",
    \"splunk-verify-connection\": \"false\",
    \"splunk-gzip\": \"true\",
    \"tag\": \"{{.Name}}/{{.ID}}\"
  }
}
DAEMON
            fi
        else
            cat > /etc/docker/daemon.json << 'DAEMON'
{
  \"log-driver\": \"splunk\",
  \"log-opts\": {
    \"splunk-token\": \"$SPLUNK_HEC_TOKEN\",
    \"splunk-url\": \"https://$SPLUNK_HOST:8088\",
    \"splunk-index\": \"docker\",
    \"splunk-sourcetype\": \"docker:container\",
    \"splunk-format\": \"json\",
    \"splunk-verify-connection\": \"false\",
    \"splunk-gzip\": \"true\",
    \"tag\": \"{{.Name}}/{{.ID}}\"
  }
}
DAEMON
        fi
        
        echo 'Docker daemon.json updated'
        cat /etc/docker/daemon.json
        
        echo ''
        echo 'Reloading Docker daemon...'
        systemctl reload docker || systemctl restart docker
        
        echo 'Docker reloaded on \$(hostname)'
    "
done

echo ""
echo "=== Docker logging configured on all nodes ==="
echo "New containers will send logs directly to Splunk"
echo ""
echo "To apply to existing containers, restart them:"
echo "  docker service update --force <service-name>"

