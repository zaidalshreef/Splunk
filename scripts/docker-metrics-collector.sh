#!/bin/bash
# Docker Metrics Collector for Splunk
# Collects: container health, status, stats, Swarm nodes, services
# Run via systemd timer every minute

LOG_FILE="/var/log/docker-metrics.log"
HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Function to log JSON events
log_event() {
    echo "$1" >> "$LOG_FILE"
}

# Collect Container Health and Status
echo "# Collecting container metrics at $TIMESTAMP" >> "$LOG_FILE"

for container_id in $(docker ps -q 2>/dev/null); do
    INSPECT=$(docker inspect "$container_id" 2>/dev/null)
    
    NAME=$(echo "$INSPECT" | jq -r ".[0].Name" | sed "s/^\///")
    STATUS=$(echo "$INSPECT" | jq -r ".[0].State.Status")
    HEALTH=$(echo "$INSPECT" | jq -r ".[0].State.Health.Status // \"no_healthcheck\"")
    STARTED_AT=$(echo "$INSPECT" | jq -r ".[0].State.StartedAt")
    RESTART_COUNT=$(echo "$INSPECT" | jq -r ".[0].RestartCount")
    IMAGE=$(echo "$INSPECT" | jq -r ".[0].Config.Image")
    
    # Get container stats (CPU, Memory)
    STATS=$(docker stats "$container_id" --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}}" 2>/dev/null)
    CPU_PERC=$(echo "$STATS" | cut -d, -f1 | tr -d "%")
    MEM_USAGE=$(echo "$STATS" | cut -d, -f2)
    MEM_PERC=$(echo "$STATS" | cut -d, -f3 | tr -d "%")
    NET_IO=$(echo "$STATS" | cut -d, -f4)
    BLOCK_IO=$(echo "$STATS" | cut -d, -f5)
    
    log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"docker_container\",\"container_id\":\"$container_id\",\"container_name\":\"$NAME\",\"status\":\"$STATUS\",\"health\":\"$HEALTH\",\"started_at\":\"$STARTED_AT\",\"restart_count\":$RESTART_COUNT,\"image\":\"$IMAGE\",\"cpu_percent\":\"$CPU_PERC\",\"mem_usage\":\"$MEM_USAGE\",\"mem_percent\":\"$MEM_PERC\",\"net_io\":\"$NET_IO\",\"block_io\":\"$BLOCK_IO\"}"
done

# Collect Docker Swarm Node Status (only on manager nodes)
if docker node ls &>/dev/null; then
    docker node ls --format "{{.ID}},{{.Hostname}},{{.Status}},{{.Availability}},{{.ManagerStatus}}" 2>/dev/null | while IFS=, read -r id hostname status availability manager_status; do
        log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"docker_swarm_node\",\"node_id\":\"$id\",\"node_hostname\":\"$hostname\",\"node_status\":\"$status\",\"availability\":\"$availability\",\"manager_status\":\"$manager_status\"}"
    done
    
    # Collect Docker Swarm Services
    docker service ls --format "{{.ID}},{{.Name}},{{.Mode}},{{.Replicas}},{{.Image}}" 2>/dev/null | while IFS=, read -r id name mode replicas image; do
        RUNNING=$(echo "$replicas" | cut -d/ -f1)
        DESIRED=$(echo "$replicas" | cut -d/ -f2 | cut -d" " -f1)
        log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"docker_swarm_service\",\"service_id\":\"$id\",\"service_name\":\"$name\",\"mode\":\"$mode\",\"replicas_running\":$RUNNING,\"replicas_desired\":$DESIRED,\"image\":\"$image\"}"
    done
fi

# Docker daemon info
DOCKER_INFO=$(docker info --format "{{json .}}" 2>/dev/null)
if [ -n "$DOCKER_INFO" ]; then
    CONTAINERS=$(echo "$DOCKER_INFO" | jq ".Containers")
    RUNNING=$(echo "$DOCKER_INFO" | jq ".ContainersRunning")
    PAUSED=$(echo "$DOCKER_INFO" | jq ".ContainersPaused")
    STOPPED=$(echo "$DOCKER_INFO" | jq ".ContainersStopped")
    IMAGES=$(echo "$DOCKER_INFO" | jq ".Images")
    
    log_event "{\"timestamp\":\"$TIMESTAMP\",\"host\":\"$HOSTNAME\",\"event_type\":\"docker_daemon\",\"containers_total\":$CONTAINERS,\"containers_running\":$RUNNING,\"containers_paused\":$PAUSED,\"containers_stopped\":$STOPPED,\"images\":$IMAGES}"
fi

