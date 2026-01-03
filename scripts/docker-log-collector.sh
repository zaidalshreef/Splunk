#!/bin/bash
# =============================================================================
# Docker Log Collector for Splunk
# =============================================================================
# Reads Docker container logs and sends clean messages to Splunk via HEC
# Strips the Docker JSON wrapper and sends just the log content
# Detects JSON logs (NestJS) vs plain text logs
#
# Run via systemd timer or cron every 30 seconds
# =============================================================================

# Configuration
SPLUNK_HEC_URL="${SPLUNK_HEC_URL:-https://10.10.10.114:8088/services/collector/event}"
SPLUNK_HEC_TOKEN="${SPLUNK_HEC_TOKEN:-a1b2c3d4-e5f6-7890-abcd-ef1234567890}"
STATE_DIR="/var/lib/splunk-collector"
BATCH_SIZE=100

# Create state directory
mkdir -p "$STATE_DIR"

# Get container name from ID
get_container_name() {
    local container_id="$1"
    docker inspect --format '{{.Name}}' "$container_id" 2>/dev/null | sed 's/^\///' || echo "unknown"
}

# Get container service name (for swarm)
get_service_name() {
    local container_id="$1"
    docker inspect --format '{{index .Config.Labels "com.docker.swarm.service.name"}}' "$container_id" 2>/dev/null || echo ""
}

# Detect if log message is JSON (for NestJS)
is_json_log() {
    echo "$1" | python3 -c "import sys,json; json.loads(sys.stdin.read())" 2>/dev/null && return 0 || return 1
}

# Send batch of events to Splunk
send_to_splunk() {
    local events="$1"
    
    if [ -z "$events" ]; then
        return
    fi
    
    curl -s -k \
        -H "Authorization: Splunk $SPLUNK_HEC_TOKEN" \
        -X POST "$SPLUNK_HEC_URL" \
        -d "$events" > /dev/null 2>&1
}

# Process a single log file
process_log_file() {
    local log_file="$1"
    local container_id=$(basename $(dirname "$log_file"))
    local short_id="${container_id:0:12}"
    local state_file="$STATE_DIR/$short_id.pos"
    local last_pos=0
    
    # Get container info
    local container_name=$(get_container_name "$container_id")
    local service_name=$(get_service_name "$container_id")
    
    # Skip if container is splunk itself
    if [[ "$container_name" == *"splunk"* ]]; then
        return
    fi
    
    # Read last position
    if [ -f "$state_file" ]; then
        last_pos=$(cat "$state_file")
    fi
    
    # Get current file size
    local current_size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
    
    # If file was rotated (smaller than last pos), reset
    if [ "$current_size" -lt "$last_pos" ]; then
        last_pos=0
    fi
    
    # Skip if no new data
    if [ "$current_size" -eq "$last_pos" ]; then
        return
    fi
    
    # Read new lines and process
    local events=""
    local count=0
    local hostname=$(hostname)
    
    tail -c +$((last_pos + 1)) "$log_file" | head -n $BATCH_SIZE | while IFS= read -r line; do
        # Parse Docker JSON log line
        # Format: {"log":"message\n","stream":"stdout","time":"2024-01-01T00:00:00.000000000Z"}
        
        # Extract fields using jq if available, else use python
        if command -v jq &> /dev/null; then
            log_msg=$(echo "$line" | jq -r '.log // empty' 2>/dev/null | sed 's/\\n$//')
            stream=$(echo "$line" | jq -r '.stream // "stdout"' 2>/dev/null)
            timestamp=$(echo "$line" | jq -r '.time // empty' 2>/dev/null)
        else
            log_msg=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('log','').rstrip('\\n'))" 2>/dev/null)
            stream=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('stream','stdout'))" 2>/dev/null)
            timestamp=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('time',''))" 2>/dev/null)
        fi
        
        # Skip empty messages
        if [ -z "$log_msg" ]; then
            continue
        fi
        
        # Determine sourcetype based on content
        local sourcetype="docker:container"
        if echo "$log_msg" | grep -qE '^\{.*"level".*"message".*\}$'; then
            sourcetype="nestjs:json"
        elif echo "$log_msg" | grep -qE '(▲ Next\.js|ready started|GET |POST |PUT |DELETE )'; then
            sourcetype="nextjs:log"
        fi
        
        # Determine index based on service
        local index="docker"
        if [ -n "$service_name" ]; then
            if [[ "$service_name" == *"nestjs"* ]]; then
                index="apps"
            elif [[ "$service_name" == *"nextjs"* ]]; then
                index="apps"
            elif [[ "$service_name" == *"postgres"* ]]; then
                index="docker"
            elif [[ "$service_name" == *"redis"* ]]; then
                index="docker"
            fi
        fi
        
        # Build Splunk HEC event
        # Escape special characters in log message for JSON
        local escaped_msg=$(echo "$log_msg" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null | sed 's/^"//;s/"$//')
        
        local event="{\"time\":\"$timestamp\",\"host\":\"$hostname\",\"source\":\"docker:$container_name\",\"sourcetype\":\"$sourcetype\",\"index\":\"$index\",\"event\":{\"message\":$escaped_msg,\"container_name\":\"$container_name\",\"container_id\":\"$short_id\",\"service_name\":\"$service_name\",\"stream\":\"$stream\"}}"
        
        # Send event
        curl -s -k \
            -H "Authorization: Splunk $SPLUNK_HEC_TOKEN" \
            -X POST "$SPLUNK_HEC_URL" \
            -d "$event" > /dev/null 2>&1
        
        count=$((count + 1))
    done
    
    # Update position
    echo "$current_size" > "$state_file"
    
    if [ $count -gt 0 ]; then
        echo "Processed $count logs from $container_name"
    fi
}

# Main
main() {
    # Find all Docker log files
    for log_file in /var/lib/docker/containers/*/*-json.log; do
        if [ -f "$log_file" ]; then
            process_log_file "$log_file"
        fi
    done
}

main "$@"

