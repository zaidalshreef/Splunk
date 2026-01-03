#!/bin/bash
# =============================================================================
# Fresh Splunk Deployment Script
# =============================================================================
# This script:
# 1. Stops and removes old Splunk containers/volumes
# 2. Deploys fresh Splunk Enterprise with HEC
# 3. Creates required indexes
# 4. Deploys Universal Forwarders to all nodes
# =============================================================================

set -e

# Configuration
SPLUNK_HOST="10.10.10.114"
SPLUNK_PASSWORD="SplunkAdmin123!"
SSH_KEY="~/.ssh/key_10.10.10.114"
FORWARDER_HOSTS=("10.10.10.114" "10.10.10.115" "10.10.10.116" "10.10.10.117" "10.10.10.118")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Step 1: Clean up old Splunk on indexer
# =============================================================================
cleanup_splunk() {
    log "Cleaning up old Splunk installation..."
    
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$SPLUNK_HOST '
        # Stop and remove Splunk container
        docker stop splunk-enterprise 2>/dev/null || true
        docker rm splunk-enterprise 2>/dev/null || true
        
        # Remove old volumes (keeping data optional)
        docker volume rm splunk-etc splunk-var 2>/dev/null || true
        docker volume rm splunk-etc-fresh splunk-var-fresh 2>/dev/null || true
        
        echo "Old Splunk cleaned up"
    '
}

# =============================================================================
# Step 2: Copy configuration files to indexer
# =============================================================================
copy_configs() {
    log "Copying configuration files to Splunk host..."
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    
    # Create deployment directory on remote
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$SPLUNK_HOST 'mkdir -p /opt/splunk-deploy/config /opt/splunk-deploy/dashboards'
    
    # Copy files
    scp -i $SSH_KEY -o StrictHostKeyChecking=no "$PROJECT_DIR/docker-compose.yml" root@$SPLUNK_HOST:/opt/splunk-deploy/
    scp -i $SSH_KEY -o StrictHostKeyChecking=no "$PROJECT_DIR/config/splunk-"*.conf root@$SPLUNK_HOST:/opt/splunk-deploy/config/
    scp -i $SSH_KEY -o StrictHostKeyChecking=no "$PROJECT_DIR/dashboards/"*.xml root@$SPLUNK_HOST:/opt/splunk-deploy/dashboards/ 2>/dev/null || true
    
    log "Configuration files copied"
}

# =============================================================================
# Step 3: Deploy Splunk Enterprise
# =============================================================================
deploy_splunk() {
    log "Deploying Splunk Enterprise..."
    
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$SPLUNK_HOST '
        cd /opt/splunk-deploy
        
        # Start Splunk
        docker-compose up -d
        
        # Wait for Splunk to be ready
        echo "Waiting for Splunk to start (this takes ~2 minutes)..."
        for i in {1..60}; do
            if docker exec splunk-enterprise /opt/splunk/bin/splunk status 2>/dev/null | grep -q "running"; then
                echo "Splunk is running!"
                break
            fi
            sleep 5
            echo -n "."
        done
        echo ""
    '
}

# =============================================================================
# Step 4: Create indexes
# =============================================================================
create_indexes() {
    log "Creating Splunk indexes..."
    
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$SPLUNK_HOST "
        # Wait a bit more for Splunk to fully initialize
        sleep 10
        
        # Create indexes via CLI
        docker exec splunk-enterprise /opt/splunk/bin/splunk add index docker -auth admin:$SPLUNK_PASSWORD 2>/dev/null || echo 'Index docker exists'
        docker exec splunk-enterprise /opt/splunk/bin/splunk add index linux -auth admin:$SPLUNK_PASSWORD 2>/dev/null || echo 'Index linux exists'
        docker exec splunk-enterprise /opt/splunk/bin/splunk add index security -auth admin:$SPLUNK_PASSWORD 2>/dev/null || echo 'Index security exists'
        docker exec splunk-enterprise /opt/splunk/bin/splunk add index traefik -auth admin:$SPLUNK_PASSWORD 2>/dev/null || echo 'Index traefik exists'
        docker exec splunk-enterprise /opt/splunk/bin/splunk add index network -auth admin:$SPLUNK_PASSWORD 2>/dev/null || echo 'Index network exists'
        docker exec splunk-enterprise /opt/splunk/bin/splunk add index apps -auth admin:$SPLUNK_PASSWORD 2>/dev/null || echo 'Index apps exists'
        
        echo 'Indexes created'
    "
}

# =============================================================================
# Step 5: Deploy Universal Forwarders
# =============================================================================
deploy_forwarders() {
    log "Deploying Universal Forwarders to all nodes..."
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    
    for host in "${FORWARDER_HOSTS[@]}"; do
        log "Configuring forwarder on $host..."
        
        # Copy forwarder configs
        scp -i $SSH_KEY -o StrictHostKeyChecking=no \
            "$PROJECT_DIR/config/forwarder-inputs.conf" \
            "$PROJECT_DIR/config/forwarder-props.conf" \
            "$PROJECT_DIR/config/forwarder-outputs.conf" \
            root@$host:/tmp/
        
        ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$host '
            # Install Universal Forwarder if not present
            if [ ! -d /opt/splunkforwarder ]; then
                echo "Installing Universal Forwarder..."
                cd /tmp
                if [ ! -f splunkforwarder-9.3.2-d8bb32809498-linux-amd64.tgz ]; then
                    wget -q "https://download.splunk.com/products/universalforwarder/releases/9.3.2/linux/splunkforwarder-9.3.2-d8bb32809498-linux-amd64.tgz"
                fi
                tar -xzf splunkforwarder-9.3.2-d8bb32809498-linux-amd64.tgz -C /opt/
            fi
            
            # Stop forwarder if running
            /opt/splunkforwarder/bin/splunk stop 2>/dev/null || true
            
            # Copy configs
            mkdir -p /opt/splunkforwarder/etc/system/local
            cp /tmp/forwarder-inputs.conf /opt/splunkforwarder/etc/system/local/inputs.conf
            cp /tmp/forwarder-props.conf /opt/splunkforwarder/etc/system/local/props.conf
            cp /tmp/forwarder-outputs.conf /opt/splunkforwarder/etc/system/local/outputs.conf
            
            # Set hostname
            HOSTNAME=$(hostname)
            sed -i "s/\$decideOnStartup/$HOSTNAME/g" /opt/splunkforwarder/etc/system/local/inputs.conf
            
            # Accept license and start
            /opt/splunkforwarder/bin/splunk start --accept-license --answer-yes --no-prompt --seed-passwd "SplunkForwarder123!" 2>/dev/null || \
            /opt/splunkforwarder/bin/splunk start
            
            # Enable boot-start
            /opt/splunkforwarder/bin/splunk enable boot-start -user root 2>/dev/null || true
            
            echo "Forwarder configured on $(hostname)"
        '
    done
}

# =============================================================================
# Step 6: Deploy dashboards
# =============================================================================
deploy_dashboards() {
    log "Deploying dashboards..."
    
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$SPLUNK_HOST '
        # Create dashboard directory
        docker exec -u splunk splunk-enterprise mkdir -p /opt/splunk/etc/apps/search/local/data/ui/views
        
        # Copy dashboards
        for f in /opt/splunk-deploy/dashboards/*.xml; do
            if [ -f "$f" ]; then
                docker cp "$f" splunk-enterprise:/opt/splunk/etc/apps/search/local/data/ui/views/
            fi
        done
        
        # Fix permissions
        docker exec splunk-enterprise chown -R splunk:splunk /opt/splunk/etc/apps/search/local/data/ui/views/
        
        echo "Dashboards deployed"
    '
}

# =============================================================================
# Main
# =============================================================================
main() {
    log "Starting fresh Splunk deployment..."
    
    cleanup_splunk
    copy_configs
    deploy_splunk
    create_indexes
    deploy_forwarders
    deploy_dashboards
    
    log "==========================================="
    log "Deployment complete!"
    log "==========================================="
    log "Splunk Web UI: http://$SPLUNK_HOST:8000"
    log "Username: admin"
    log "Password: $SPLUNK_PASSWORD"
    log "HEC Token: a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    log "HEC URL: http://$SPLUNK_HOST:8088/services/collector"
    log "==========================================="
}

main "$@"

