# Quick Start Guide - Splunk Home Lab

Deploy your Splunk SIEM in under 10 minutes!

## Prerequisites

- [ ] 5 Ubuntu VMs (22.04 LTS) with Docker installed
- [ ] Docker Swarm initialized on your cluster
- [ ] SSH key-based authentication configured
- [ ] Network connectivity between all VMs

## Step 1: Configure Environment (30 seconds)

```bash
cd /home/zaid/Documents/Splunk

# Edit the configuration file with your settings
nano config/environment.env
```

Update these values:
```bash
INDEXER_IP=10.10.10.114           # Your Splunk indexer IP
FORWARDER_IPS="10.10.10.115 ..."  # Your forwarder IPs
SSH_KEY_PATH=~/.ssh/your_key      # Your SSH key
```

## Step 2: Deploy Splunk Indexer (3 minutes)

```bash
./scripts/deploy-indexer.sh
```

Wait for the script to complete. You'll see:
```
Splunk Enterprise Deployed Successfully!
Access Splunk Web: https://10.10.10.114:8000
```

## Step 3: Deploy Universal Forwarders (3 minutes)

```bash
./scripts/deploy-forwarders.sh
```

This deploys forwarders to all nodes and configures log collection.

## Step 4: Enable Swarm Monitoring (1 minute)

```bash
./scripts/setup-swarm-monitor.sh
```

This sets up Docker Swarm metrics collection.

## Step 5: Verify Deployment (30 seconds)

```bash
./scripts/check-status.sh
```

Or access Splunk Web and run:
```spl
index=* | stats count by index, host
```

## 🎉 Done!

Your Splunk SIEM is now monitoring:
- ✅ Docker Swarm nodes and services
- ✅ Container CPU/Memory stats
- ✅ System logs (syslog)
- ✅ Authentication logs (auth.log)
- ✅ Kernel logs (kern.log)

## Quick Commands

| Task | Command |
|------|---------|
| Check status | `./scripts/check-status.sh` |
| Fix permissions | `./scripts/fix-permissions.sh` |
| Clean up everything | `./scripts/cleanup.sh` |

## Access Details

| Service | URL | Credentials |
|---------|-----|-------------|
| Splunk Web | https://INDEXER_IP:8000 | admin / SplunkAdmin@2025 |

## Useful Searches

```spl
# All data summary
index=* | stats count by index, sourcetype, host

# Docker Swarm status
index=docker sourcetype="docker:swarm:node"

# Failed logins
index=security "Failed password"

# System errors
index=linux error OR fail
```

## Troubleshooting

If something doesn't work, check:
1. `./scripts/check-status.sh` for container status
2. `TROUBLESHOOTING.md` for common issues
3. Splunk Health dashboard in Splunk Web

---

**Happy Monitoring! 🔍**

