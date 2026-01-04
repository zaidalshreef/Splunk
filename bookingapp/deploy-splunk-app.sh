#!/bin/bash
# =============================================================================
# Deploy BookingApp APM Splunk App
# =============================================================================

set -e

SPLUNK_HOST="${SPLUNK_HOST:-10.10.10.114}"
SPLUNK_USER="${SPLUNK_USER:-root}"
SPLUNK_APP_DIR="/opt/splunk/etc/apps"
APP_NAME="SA-bookingapp-apm"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================="
echo "BookingApp APM Splunk App Deployment"
echo "============================================="
echo ""

# Check if app directory exists
if [ ! -d "${SCRIPT_DIR}/splunk/${APP_NAME}" ]; then
    echo "ERROR: App directory not found: ${SCRIPT_DIR}/splunk/${APP_NAME}"
    exit 1
fi

echo "1. Creating app tarball..."
cd "${SCRIPT_DIR}/splunk"
tar -czf "${APP_NAME}.tar.gz" "${APP_NAME}"
echo "   Created: ${APP_NAME}.tar.gz"

echo ""
echo "2. Copying app to Splunk server..."
scp "${APP_NAME}.tar.gz" "${SPLUNK_USER}@${SPLUNK_HOST}:/tmp/"
echo "   Copied to: ${SPLUNK_HOST}:/tmp/${APP_NAME}.tar.gz"

echo ""
echo "3. Installing app on Splunk server..."
ssh "${SPLUNK_USER}@${SPLUNK_HOST}" << 'ENDSSH'
    set -e
    
    # Extract app
    cd /tmp
    tar -xzf SA-bookingapp-apm.tar.gz
    
    # Remove old app if exists
    rm -rf /opt/splunk/etc/apps/SA-bookingapp-apm
    
    # Install new app
    mv SA-bookingapp-apm /opt/splunk/etc/apps/
    
    # Set permissions
    chown -R splunk:splunk /opt/splunk/etc/apps/SA-bookingapp-apm
    
    # Cleanup
    rm -f /tmp/SA-bookingapp-apm.tar.gz
    
    echo "   App installed to /opt/splunk/etc/apps/SA-bookingapp-apm"
ENDSSH

echo ""
echo "4. Restarting Splunk..."
ssh "${SPLUNK_USER}@${SPLUNK_HOST}" "docker exec splunk-enterprise /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt" || true

echo ""
echo "============================================="
echo "Deployment Complete!"
echo "============================================="
echo ""
echo "Next steps:"
echo "1. Create 'bookingapp' index in Splunk"
echo "2. Create HEC token for bookingapp"
echo "3. Update .env with HEC token"
echo "4. Start the BookingApp stack: docker compose up -d"
echo ""
echo "Access Splunk: http://${SPLUNK_HOST}:8000"
echo "App: BookingApp APM"

