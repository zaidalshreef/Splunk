#!/bin/bash
# =============================================================================
# Network Security Metrics Collector for Splunk
# =============================================================================
# Collects: Open ports, iptables rules, netstat connections, firewall status
# Run via systemd timer every minute
# =============================================================================

LOG_FILE="/var/log/network-security.log"
HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Function to log JSON events
log_event() {
    echo "$1" >> "$LOG_FILE"
}

# =============================================================================
# Collect Open Ports (Listening Services)
# =============================================================================
ss -tlnp 2>/dev/null | tail -n +2 | while read -r line; do
    STATE=$(echo "$line" | awk '{print $1}')
    LOCAL_ADDR=$(echo "$line" | awk '{print $4}')
    PORT=$(echo "$LOCAL_ADDR" | rev | cut -d: -f1 | rev)
    BIND_ADDR=$(echo "$LOCAL_ADDR" | rev | cut -d: -f2- | rev)
    PROCESS=$(echo "$line" | awk '{print $6}' | sed 's/users:((//' | sed 's/))//' | cut -d, -f1 | tr -d '"')
    PID=$(echo "$line" | grep -oP 'pid=\K\d+' | head -1)
    
    log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"open_port\",\"protocol\":\"tcp\",\"state\":\"$STATE\",\"port\":$PORT,\"bind_address\":\"$BIND_ADDR\",\"process\":\"$PROCESS\",\"pid\":\"$PID\"}"
done

# UDP Listening Ports
ss -ulnp 2>/dev/null | tail -n +2 | while read -r line; do
    STATE=$(echo "$line" | awk '{print $1}')
    LOCAL_ADDR=$(echo "$line" | awk '{print $4}')
    PORT=$(echo "$LOCAL_ADDR" | rev | cut -d: -f1 | rev)
    BIND_ADDR=$(echo "$LOCAL_ADDR" | rev | cut -d: -f2- | rev)
    PROCESS=$(echo "$line" | awk '{print $6}' | sed 's/users:((//' | sed 's/))//' | cut -d, -f1 | tr -d '"')
    
    log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"open_port\",\"protocol\":\"udp\",\"state\":\"$STATE\",\"port\":$PORT,\"bind_address\":\"$BIND_ADDR\",\"process\":\"$PROCESS\"}"
done

# =============================================================================
# Collect Active Network Connections
# =============================================================================
ss -tnp 2>/dev/null | tail -n +2 | head -100 | while read -r line; do
    STATE=$(echo "$line" | awk '{print $1}')
    LOCAL=$(echo "$line" | awk '{print $4}')
    REMOTE=$(echo "$line" | awk '{print $5}')
    LOCAL_PORT=$(echo "$LOCAL" | rev | cut -d: -f1 | rev)
    REMOTE_IP=$(echo "$REMOTE" | rev | cut -d: -f2- | rev)
    REMOTE_PORT=$(echo "$REMOTE" | rev | cut -d: -f1 | rev)
    PROCESS=$(echo "$line" | awk '{print $6}' | sed 's/users:((//' | sed 's/))//' | cut -d, -f1 | tr -d '"')
    
    log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"network_connection\",\"state\":\"$STATE\",\"local_port\":$LOCAL_PORT,\"remote_ip\":\"$REMOTE_IP\",\"remote_port\":$REMOTE_PORT,\"process\":\"$PROCESS\"}"
done

# =============================================================================
# Connection Statistics Summary
# =============================================================================
ESTABLISHED=$(ss -tn state established 2>/dev/null | wc -l)
TIME_WAIT=$(ss -tn state time-wait 2>/dev/null | wc -l)
CLOSE_WAIT=$(ss -tn state close-wait 2>/dev/null | wc -l)
LISTENING=$(ss -tln 2>/dev/null | tail -n +2 | wc -l)
TOTAL_CONNECTIONS=$(ss -tn 2>/dev/null | tail -n +2 | wc -l)

log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"connection_stats\",\"established\":$ESTABLISHED,\"time_wait\":$TIME_WAIT,\"close_wait\":$CLOSE_WAIT,\"listening\":$LISTENING,\"total_connections\":$TOTAL_CONNECTIONS}"

# =============================================================================
# Collect iptables Rules
# =============================================================================
if command -v iptables &> /dev/null; then
    # Count rules per chain
    for chain in INPUT OUTPUT FORWARD; do
        RULE_COUNT=$(iptables -L $chain -n 2>/dev/null | tail -n +3 | wc -l)
        POLICY=$(iptables -L $chain -n 2>/dev/null | head -1 | grep -oP '\(policy \K\w+')
        log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"iptables_chain\",\"chain\":\"$chain\",\"policy\":\"$POLICY\",\"rule_count\":$RULE_COUNT}"
    done
    
    # Log individual iptables rules (INPUT chain - most security relevant)
    iptables -L INPUT -n -v 2>/dev/null | tail -n +3 | head -50 | while read -r line; do
        PKTS=$(echo "$line" | awk '{print $1}')
        BYTES=$(echo "$line" | awk '{print $2}')
        TARGET=$(echo "$line" | awk '{print $3}')
        PROT=$(echo "$line" | awk '{print $4}')
        SOURCE=$(echo "$line" | awk '{print $8}')
        DEST=$(echo "$line" | awk '{print $9}')
        EXTRA=$(echo "$line" | awk '{for(i=10;i<=NF;i++) printf $i" "; print ""}' | xargs)
        
        if [ -n "$TARGET" ]; then
            log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"iptables_rule\",\"chain\":\"INPUT\",\"packets\":\"$PKTS\",\"bytes\":\"$BYTES\",\"target\":\"$TARGET\",\"protocol\":\"$PROT\",\"source\":\"$SOURCE\",\"destination\":\"$DEST\",\"options\":\"$EXTRA\"}"
        fi
    done
fi

# =============================================================================
# Collect UFW Firewall Status (Ubuntu)
# =============================================================================
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1 | awk '{print $2}')
    UFW_RULES=$(ufw status numbered 2>/dev/null | grep -c "^\[")
    
    log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"ufw_status\",\"status\":\"$UFW_STATUS\",\"rule_count\":$UFW_RULES}"
    
    # Log UFW rules
    ufw status verbose 2>/dev/null | tail -n +5 | while read -r line; do
        if [ -n "$line" ]; then
            TO=$(echo "$line" | awk '{print $1}')
            ACTION=$(echo "$line" | awk '{print $2}')
            FROM=$(echo "$line" | awk '{print $3}')
            log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"ufw_rule\",\"to\":\"$TO\",\"action\":\"$ACTION\",\"from\":\"$FROM\"}"
        fi
    done
fi

# =============================================================================
# Collect Network Interface Statistics
# =============================================================================
for iface in $(ls /sys/class/net/ 2>/dev/null | grep -v lo); do
    RX_BYTES=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
    TX_BYTES=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
    RX_PACKETS=$(cat /sys/class/net/$iface/statistics/rx_packets 2>/dev/null || echo 0)
    TX_PACKETS=$(cat /sys/class/net/$iface/statistics/tx_packets 2>/dev/null || echo 0)
    RX_ERRORS=$(cat /sys/class/net/$iface/statistics/rx_errors 2>/dev/null || echo 0)
    TX_ERRORS=$(cat /sys/class/net/$iface/statistics/tx_errors 2>/dev/null || echo 0)
    RX_DROPPED=$(cat /sys/class/net/$iface/statistics/rx_dropped 2>/dev/null || echo 0)
    TX_DROPPED=$(cat /sys/class/net/$iface/statistics/tx_dropped 2>/dev/null || echo 0)
    
    # Get IP address
    IP_ADDR=$(ip addr show $iface 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -1)
    
    log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"network_interface\",\"interface\":\"$iface\",\"ip_address\":\"$IP_ADDR\",\"rx_bytes\":$RX_BYTES,\"tx_bytes\":$TX_BYTES,\"rx_packets\":$RX_PACKETS,\"tx_packets\":$TX_PACKETS,\"rx_errors\":$RX_ERRORS,\"tx_errors\":$TX_ERRORS,\"rx_dropped\":$RX_DROPPED,\"tx_dropped\":$TX_DROPPED}"
done

# =============================================================================
# Collect Failed Connection Attempts (from kernel logs if available)
# =============================================================================
if [ -f /var/log/kern.log ]; then
    # Count recent blocked connections
    BLOCKED_COUNT=$(grep -c "BLOCK" /var/log/kern.log 2>/dev/null || echo 0)
    log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"firewall_blocked\",\"blocked_count\":$BLOCKED_COUNT}"
fi

# =============================================================================
# Detect Potential Port Scans (many connections from same IP)
# =============================================================================
ss -tn 2>/dev/null | tail -n +2 | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10 | while read count ip; do
    if [ "$count" -gt 10 ] && [ -n "$ip" ]; then
        log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"potential_scan\",\"source_ip\":\"$ip\",\"connection_count\":$count}"
    fi
done

echo "# Network security metrics collected at $TIMESTAMP" >> "$LOG_FILE"

