#!/bin/bash
# =============================================================================
# Simple Docker Log Collector for Splunk
# =============================================================================
# Tail Docker logs and send to Splunk HEC in real-time
# Extracts just the message from Docker JSON format
#
# Usage: Run in background on each Docker host
#   nohup ./docker-log-collector-simple.sh &
# =============================================================================

SPLUNK_HEC_URL="${SPLUNK_HEC_URL:-https://10.10.10.114:8088/services/collector/event}"
SPLUNK_HEC_TOKEN="${SPLUNK_HEC_TOKEN:-a1b2c3d4-e5f6-7890-abcd-ef1234567890}"
HOSTNAME=$(hostname)

echo "Starting Docker log collector on $HOSTNAME"
echo "Sending logs to: $SPLUNK_HEC_URL"

# Create a named pipe for processing
PIPE="/tmp/docker-log-pipe"
rm -f "$PIPE"
mkfifo "$PIPE"

# Function to get container info
get_container_info() {
    local container_id="$1"
    docker inspect --format '{{.Name}}|{{index .Config.Labels "com.docker.swarm.service.name"}}' "$container_id" 2>/dev/null | sed 's/^\///'
}

# Cache container names
declare -A CONTAINER_CACHE

# Process logs from pipe
process_logs() {
    while IFS= read -r line; do
        # Parse the log line (format: container_id|log_json)
        container_id="${line%%|*}"
        log_json="${line#*|}"
        
        # Get container info from cache or docker
        if [ -z "${CONTAINER_CACHE[$container_id]}" ]; then
            CONTAINER_CACHE[$container_id]=$(get_container_info "$container_id")
        fi
        
        container_info="${CONTAINER_CACHE[$container_id]}"
        container_name="${container_info%%|*}"
        service_name="${container_info#*|}"
        
        # Skip splunk's own logs
        [[ "$container_name" == *"splunk"* ]] && continue
        
        # Extract log message from Docker JSON
        # {"log":"message\n","stream":"stdout","time":"..."}
        log_msg=$(echo "$log_json" | jq -r '.log // empty' 2>/dev/null | sed 's/\\n$//')
        stream=$(echo "$log_json" | jq -r '.stream // "stdout"' 2>/dev/null)
        timestamp=$(echo "$log_json" | jq -r '.time // empty' 2>/dev/null)
        
        [ -z "$log_msg" ] && continue
        
        # Determine sourcetype
        sourcetype="docker:container"
        if echo "$log_msg" | grep -qE '^\{.*"level"'; then
            sourcetype="nestjs:json"
        fi
        
        # Build and send event
        # For JSON logs (NestJS), send the raw JSON as the event
        if [ "$sourcetype" = "nestjs:json" ]; then
            event="{\"time\":\"$timestamp\",\"host\":\"$HOSTNAME\",\"source\":\"$container_name\",\"sourcetype\":\"$sourcetype\",\"index\":\"apps\",\"event\":$log_msg}"
        else
            # For plain text logs, wrap in a simple structure
            escaped_msg=$(echo "$log_msg" | jq -Rs '.' | sed 's/^"//;s/"$//')
            event="{\"time\":\"$timestamp\",\"host\":\"$HOSTNAME\",\"source\":\"$container_name\",\"sourcetype\":\"$sourcetype\",\"index\":\"docker\",\"event\":{\"message\":\"$escaped_msg\",\"container\":\"$container_name\",\"service\":\"$service_name\",\"stream\":\"$stream\"}}"
        fi
        
        # Send to Splunk
        curl -s -k \
            -H "Authorization: Splunk $SPLUNK_HEC_TOKEN" \
            -X POST "$SPLUNK_HEC_URL" \
            -d "$event" > /dev/null 2>&1
            
    done < "$PIPE"
}

# Start processor in background
process_logs &

# Tail all container logs
for log_file in /var/lib/docker/containers/*/*-json.log; do
    if [ -f "$log_file" ]; then
        container_id=$(basename $(dirname "$log_file"))
        short_id="${container_id:0:12}"
        
        # Start tailing this log file
        (tail -F "$log_file" 2>/dev/null | while IFS= read -r line; do
            echo "$short_id|$line" > "$PIPE"
        done) &
    fi
done

echo "Tailing $(ls /var/lib/docker/containers/*/\*-json.log 2>/dev/null | wc -l) container logs"
echo "Press Ctrl+C to stop"

# Wait for all background processes
wait

