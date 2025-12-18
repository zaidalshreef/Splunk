# Splunk SIEM Home Lab - Docker Swarm Deployment

A complete Splunk SIEM deployment for monitoring Docker Swarm clusters with Universal Forwarders collecting system and container logs.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Docker Swarm Cluster                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌──────────────────┐                                              │
│   │    mgr-1         │                                              │
│   │  10.10.10.114    │◄──────────────────────────────────┐          │
│   │                  │                                    │          │
│   │ ┌──────────────┐ │   Port 9997 (TCP Receiver)        │          │
│   │ │   Splunk     │ │◄──────────────────────────────────┤          │
│   │ │  Enterprise  │ │                                    │          │
│   │ │  (Indexer)   │ │   Port 8088 (HEC)                 │          │
│   │ └──────────────┘ │◄──────────────────────────────────┤          │
│   │                  │                                    │          │
│   │ ┌──────────────┐ │   Docker Swarm Metrics            │          │
│   │ │   Swarm      │ │───────────────────────────────────┘          │
│   │ │   Monitor    │ │                                              │
│   │ └──────────────┘ │                                              │
│   └──────────────────┘                                              │
│                                                                      │
│   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌────────────┐ │
│   │    mgr-2     │ │    mgr-3     │ │   worker-1   │ │   node1    │ │
│   │ 10.10.10.115 │ │ 10.10.10.116 │ │ 10.10.10.117 │ │10.10.10.118│ │
│   │              │ │              │ │              │ │            │ │
│   │┌────────────┐│ │┌────────────┐│ │┌────────────┐│ │┌──────────┐│ │
│   ││ Splunk UF  ││ ││ Splunk UF  ││ ││ Splunk UF  ││ ││Splunk UF ││ │
│   │└────────────┘│ │└────────────┘│ │└────────────┘│ │└──────────┘│ │
│   └──────────────┘ └──────────────┘ └──────────────┘ └────────────┘ │
│          │                │                │               │         │
│          └────────────────┴────────────────┴───────────────┘         │
│                           ▼                                          │
│              System Logs (syslog, auth.log, kern.log)               │
└─────────────────────────────────────────────────────────────────────┘
```

## 📋 Requirements

### Hardware
- **5 VMs** running Ubuntu 22.04 LTS
- **Minimum 4GB RAM** per VM (8GB recommended for indexer)
- **50GB disk space** per VM
- Network connectivity between all VMs

### Software
- Docker Engine 24.0+
- Docker Swarm (initialized)
- SSH access with key-based authentication

## 🚀 Quick Start

### 1. Clone this repository
```bash
git clone <your-repo-url>
cd splunk-homelab
```

### 2. Configure your environment
```bash
cp config/environment.env.example config/environment.env
# Edit with your IP addresses and credentials
nano config/environment.env
```

### 3. Deploy Splunk Enterprise (Indexer)
```bash
./scripts/deploy-indexer.sh
```

### 4. Deploy Universal Forwarders
```bash
./scripts/deploy-forwarders.sh
```

### 5. Configure Swarm Monitoring
```bash
./scripts/setup-swarm-monitor.sh
```

## 📁 Repository Structure

```
splunk-homelab/
├── README.md                    # This file
├── TROUBLESHOOTING.md           # Common issues and solutions
├── config/
│   ├── environment.env.example  # Environment variables template
│   ├── inputs.conf              # Forwarder inputs configuration
│   ├── outputs.conf             # Forwarder outputs configuration
│   └── props.conf               # Data parsing configuration
├── scripts/
│   ├── deploy-indexer.sh        # Deploy Splunk Enterprise
│   ├── deploy-forwarders.sh     # Deploy Universal Forwarders
│   ├── setup-swarm-monitor.sh   # Configure Swarm monitoring
│   ├── fix-permissions.sh       # Fix log file permissions
│   └── cleanup.sh               # Remove all Splunk components
└── dashboards/
    └── docker-swarm-overview.xml # Sample dashboard
```

## 🔐 Access Credentials

| Service | URL | Username | Password |
|---------|-----|----------|----------|
| Splunk Web UI | https://INDEXER_IP:8000 | admin | SplunkAdmin@2025 |
| Management API | https://INDEXER_IP:8089 | admin | SplunkAdmin@2025 |
| HEC Token | - | - | a1b2c3d4-e5f6-7890-abcd-ef1234567890 |

## 📊 Indexes

| Index | Purpose | Data Sources |
|-------|---------|--------------|
| `docker` | Container & Swarm metrics | HEC, Swarm Monitor |
| `linux` | System logs | syslog, kern.log |
| `security` | Authentication logs | auth.log |
| `network` | Network logs | Future use |

## 🔍 Sample Searches

### Docker Swarm Status
```spl
index=docker sourcetype="docker:swarm:node" 
| table hostname status availability manager_status
```

### Container Resource Usage
```spl
index=docker sourcetype="docker:stats" 
| rex field=cpu "(?<cpu_pct>[\d.]+)%" 
| rex field=mem_perc "(?<mem_pct>[\d.]+)%" 
| table name cpu_pct mem_pct
```

### Failed SSH Logins
```spl
index=security sourcetype=linux_secure "Failed password" 
| stats count by src_ip user
```

### System Errors
```spl
index=linux sourcetype=syslog error OR fail OR critical 
| timechart count by host
```

## 🛠️ Maintenance

### Restart Forwarders on All Nodes
```bash
./scripts/restart-forwarders.sh
```

### Check Forwarder Status
```bash
./scripts/check-status.sh
```

### Update Configuration
```bash
./scripts/update-config.sh
```

## 📚 References

- [Splunk SIEM Home Lab Guide](https://github.com/0xrajneesh/Splunk-SIEM-Home-Lab)
- [Splunk Documentation](https://docs.splunk.com/)
- [Splunk Lantern - Lab Setup](https://lantern.splunk.com/Splunk_Success_Framework/Platform_Management/Setting_up_a_lab_environment)

## ⚠️ Known Issues

1. **KV Store may fail** on some systems - See TROUBLESHOOTING.md
2. **IOWait warnings** are normal during initial data ingestion
3. **Log file permissions** need to be set to 644 for Splunk to read them

## 📝 License

MIT License - Feel free to use and modify for your home lab.

