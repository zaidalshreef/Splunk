# Splunk SIEM Home Lab - Docker Swarm Deployment

A comprehensive Splunk SIEM deployment for monitoring Docker Swarm clusters with Universal Forwarders collecting system logs, container logs, Docker metrics, and application logs.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Docker Swarm Cluster                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   ┌─────────────────────┐                                                       │
│   │       mgr-1         │   Port 8000 (Web UI)                                  │
│   │    10.10.10.114     │   Port 9997 (Forwarder Receiving)                     │
│   │                     │   Port 8088 (HEC)                                      │
│   │ ┌─────────────────┐ │                                                       │
│   │ │ Splunk Enterprise│◄────────────────────────────────────────────────┐      │
│   │ │    (Indexer)    │ │                                                │      │
│   │ └─────────────────┘ │                                                │      │
│   │ ┌─────────────────┐ │                                                │      │
│   │ │  Splunk UF +    │ │                                                │      │
│   │ │ Docker Metrics  │─┘                                                │      │
│   │ │   Collector     │                                                  │      │
│   │ └─────────────────┘                                                  │      │
│   └─────────────────────┘                                                │      │
│                                                                          │      │
│   ┌───────────────┐ ┌───────────────┐ ┌───────────────┐ ┌──────────────┐│      │
│   │     mgr-2     │ │     mgr-3     │ │   worker-1    │ │    node1     ││      │
│   │  10.10.10.115 │ │  10.10.10.116 │ │  10.10.10.117 │ │ 10.10.10.118 ││      │
│   │ ┌───────────┐ │ │ ┌───────────┐ │ │ ┌───────────┐ │ │ ┌──────────┐ ││      │
│   │ │ Splunk UF │ │ │ │ Splunk UF │ │ │ │ Splunk UF │ │ │ │Splunk UF │ ││      │
│   │ │ + Docker  │ │ │ │ + Docker  │ │ │ │ + Docker  │ │ │ │+ Docker  │ │├──────┘
│   │ │ Metrics   │ │ │ │ Metrics   │ │ │ │ Metrics   │ │ │ │Metrics   │ ││
│   │ └───────────┘ │ │ └───────────┘ │ │ └───────────┘ │ │ └──────────┘ ││
│   └───────────────┘ └───────────────┘ └───────────────┘ └──────────────┘│
└─────────────────────────────────────────────────────────────────────────────────┘
```

## 📊 Data Sources Collected

| Data Source | Index | Sourcetype | Description |
|-------------|-------|------------|-------------|
| System Logs | linux | syslog | /var/log/syslog |
| Auth Logs | security | linux_secure | /var/log/auth.log |
| Kernel Logs | linux | linux_kernel | /var/log/kern.log |
| Docker Metrics | docker | docker:metrics | Container health, CPU, memory, Swarm status |
| Container Logs | docker | docker:container:json | Container stdout/stderr (JSON format) |
| Traefik Logs | traefik | traefik:access | HTTP proxy access logs |
| Dokploy App Logs | docker | dokploy:app | Application deployment logs |

## 🖥️ Modern Dashboards

| Dashboard | Description |
|-----------|-------------|
| 🏠 Executive Overview | KPIs, event volume, security summary, quick navigation |
| 🔒 Security Overview | Failed/successful logins, sudo commands, brute force detection |
| 🐳 Docker Swarm & Containers | Container health, Swarm nodes, CPU/memory usage |
| 🌐 Traefik Proxy | HTTP traffic, response times, error rates, top paths |
| 📋 System Logs | Syslog, kernel messages, service events |
| ⚡ Audit & Compliance | Command execution, sudo activity, user tracking |
| 📈 Performance | Events/sec, resource usage, index statistics |
| 🌍 Network Monitoring | Firewall events, SSH attempts, connections |
| 📱 Application Logs | Container stdout/stderr with error detection |
| 🔑 Login Activity | SSH sessions, authentication timeline |
| 🚨 Threat Detection | Active threats, suspicious activity |
| 🏗️ Infrastructure Health | VM status, Swarm cluster, service discovery |
| 📦 Container Logs Explorer | Search and filter container logs with drill-down |

### Dashboard Features
- ✅ Interactive time range picker
- ✅ Host and container filters
- ✅ Health status filters
- ✅ Search text input
- ✅ Drilldown to detail views
- ✅ Auto-refresh (30s intervals)
- ✅ Dark theme modern design
- ✅ Quick navigation links

## 🚀 Quick Start

### 1. Clone this repository
```bash
git clone <your-repo-url>
cd splunk-homelab
```

### 2. Configure your environment
```bash
cp config/environment.env.example config/environment.env
nano config/environment.env
```

### 3. Deploy Splunk Enterprise (Indexer)
```bash
./scripts/deploy-indexer.sh
```

### 4. Deploy Universal Forwarders to all nodes
```bash
./scripts/deploy-forwarders.sh
```

### 5. Access Splunk Web UI
```
URL: http://10.10.10.114:8000
Username: admin
Password: SplunkAdmin@2025
```

## 📁 Repository Structure

```
splunk-homelab/
├── README.md                           # This file
├── TROUBLESHOOTING.md                  # Common issues and solutions
├── DASHBOARDS.md                       # Dashboard documentation
├── config/
│   ├── environment.env.example         # Environment variables template
│   ├── environment.env                 # Your configuration (gitignored)
│   ├── inputs.conf                     # Forwarder inputs configuration
│   ├── outputs.conf                    # Forwarder outputs configuration
│   └── props.conf                      # Data parsing configuration
├── scripts/
│   ├── deploy-indexer.sh               # Deploy Splunk Enterprise
│   ├── deploy-forwarders.sh            # Deploy Universal Forwarders
│   ├── docker-metrics-collector.sh     # Docker metrics collection script
│   ├── copy-dashboards.sh              # Copy dashboards to Splunk
│   ├── fix-permissions.sh              # Fix log file permissions
│   └── cleanup.sh                      # Remove all Splunk components
└── dashboards/
    ├── 00-executive-overview.xml       # Main dashboard
    ├── 01-security-overview.xml        # Security monitoring
    ├── 02-docker-swarm.xml             # Docker & Swarm health
    ├── 03-traefik-proxy.xml            # HTTP traffic
    ├── 04-system-logs.xml              # System logs
    ├── 05-audit-compliance.xml         # Audit & compliance
    ├── 06-performance.xml              # Performance metrics
    ├── 07-network-monitoring.xml       # Network monitoring
    ├── 08-application-logs.xml         # Application logs
    ├── 09-login-activity.xml           # Login activity
    ├── 10-threat-detection.xml         # Threat detection
    ├── 11-infrastructure.xml           # Infrastructure health
    └── 12-container-logs.xml           # Container logs explorer
```

## 🔐 Access Credentials

| Service | URL | Username | Password |
|---------|-----|----------|----------|
| Splunk Web UI | http://10.10.10.114:8000 | admin | SplunkAdmin@2025 |
| Management API | https://10.10.10.114:8089 | admin | SplunkAdmin@2025 |

## 📊 Index Summary

| Index | Purpose | Typical Volume |
|-------|---------|----------------|
| `linux` | System logs (syslog, kernel) | ~15M events |
| `docker` | Container logs & metrics | ~1.5M events |
| `security` | Auth logs | ~10K events |
| `traefik` | HTTP proxy logs | ~10K events |

## 🔍 Sample Searches

### Docker Container Health
```spl
index=docker sourcetype="docker:metrics" event_type="docker_container"
| dedup container_name
| stats count by health
```

### Container Logs with Errors
```spl
index=docker sourcetype="docker:container:json" (error OR ERROR OR exception)
| table _time source stream log
```

### Swarm Services Status
```spl
index=docker sourcetype="docker:metrics" event_type="docker_swarm_service"
| dedup service_name
| table service_name replicas_running replicas_desired
```

### Failed SSH Logins
```spl
index=security (failed OR "authentication failure")
| rex "from (?<src_ip>\d+\.\d+\.\d+\.\d+)"
| stats count by src_ip
```

### Traefik Response Times
```spl
index=traefik
| spath Duration
| eval duration_ms = Duration / 1000000
| timechart avg(duration_ms) as "Avg Response Time (ms)"
```

## ⚠️ Known Issues

1. **KV Store may fail** on some systems - See TROUBLESHOOTING.md
2. **Docker container logs require root** - Forwarders run with --user root
3. **Swarm node health** shows based on manager_status field interpretation

## 📝 License

MIT License - Feel free to use and modify for your home lab.
