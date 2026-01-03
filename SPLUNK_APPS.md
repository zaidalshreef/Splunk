# Splunk Apps - Best Practices Guide

## App Naming Conventions

Splunk uses a standard naming convention for apps:

| Prefix | Type | Purpose |
|--------|------|---------|
| **TA-** | Technology Add-on | Data collection, parsing, field extractions. Usually invisible to end-users |
| **SA-** | Supporting Add-on | Application-specific knowledge objects, saved searches, macros |
| **DA-** | Dashboard App | Dashboards and visualizations |

## Created Apps Structure

### 1. TA-infrastructure-monitoring (Technology Add-on)
**Purpose:** Collect and parse infrastructure data

```
TA-infrastructure-monitoring/
├── default/
│   ├── app.conf          # App metadata
│   ├── inputs.conf        # Data inputs (monitors)
│   ├── props.conf         # Field extractions & parsing
│   └── transforms.conf    # Lookups & transforms
├── metadata/
│   └── default.meta       # Permissions
└── lookups/               # CSV lookup files
```

**Collected Data:**
- Docker container logs (`docker:container:json`)
- System logs (`syslog`, `linux_secure`)
- Network security metrics (`network:security`)
- Traefik proxy logs (`traefik:access`)

### 2. SA-bookingapp (Supporting Add-on)
**Purpose:** NestJS/NextJS application-specific monitoring

```
SA-bookingapp/
├── default/
│   ├── app.conf           # App metadata
│   ├── inputs.conf        # Application-specific inputs
│   ├── props.conf         # NestJS/NextJS parsing rules
│   ├── savedsearches.conf # Alerts and reports
│   └── macros.conf        # Reusable search macros
├── metadata/
│   └── default.meta       # Permissions
└── lookups/
```

**Features:**
- NestJS JSON log parsing (Winston/Pino format)
- NextJS log extraction
- PostgreSQL query performance monitoring
- Redis operation tracking
- Pre-built alerts for:
  - High error rates
  - Slow API responses
  - Database connection issues
  - Redis memory warnings
- Macros for common searches:
  - `bookingapp_api` - NestJS API logs
  - `bookingapp_errors` - Error logs only
  - `bookingapp_slow_requests(1000)` - Slow requests over threshold

### 3. DA-operations-dashboard (Dashboard App)
**Purpose:** Centralized monitoring dashboards

```
DA-operations-dashboard/
├── default/
│   ├── app.conf
│   └── data/
│       └── ui/
│           ├── nav/
│           │   └── default.xml    # Navigation menu
│           └── views/
│               ├── 00-executive-overview.xml
│               ├── 01-security-overview.xml
│               ├── 02-docker-swarm.xml
│               ├── 03-traefik-proxy.xml
│               ├── 04-network-security.xml
│               ├── 05-audit-compliance.xml
│               ├── 11-infrastructure.xml
│               ├── 12-container-logs.xml
│               └── 13-bookingapp.xml
├── metadata/
│   └── default.meta
└── static/                # Images, CSS, JS
```

## How to Create Apps for New Applications

### Example: Creating an App for a New NestJS Service

1. **Create the TA (Technology Add-on) for data collection:**

```bash
mkdir -p apps/TA-myservice/{default,metadata,lookups}
```

2. **Configure inputs.conf:**

```ini
# apps/TA-myservice/default/inputs.conf
[monitor:///var/log/myservice]
disabled = false
index = apps
sourcetype = myservice:json
```

3. **Configure props.conf for parsing:**

```ini
# apps/TA-myservice/default/props.conf
[myservice:json]
KV_MODE = json
SHOULD_LINEMERGE = false
TIME_FORMAT = %Y-%m-%dT%H:%M:%S.%3NZ
TIME_PREFIX = "timestamp":"
```

4. **Create the SA (Supporting Add-on) for knowledge objects:**

```bash
mkdir -p apps/SA-myservice/{default,metadata}
```

5. **Define macros.conf:**

```ini
# apps/SA-myservice/default/macros.conf
[myservice_logs]
definition = index=apps sourcetype=myservice:json
iseval = 0

[myservice_errors]
definition = `myservice_logs` level=error
iseval = 0
```

6. **Define savedsearches.conf for alerts:**

```ini
# apps/SA-myservice/default/savedsearches.conf
[MyService - High Error Rate Alert]
search = `myservice_errors` earliest=-5m | stats count | where count > 50
alert.severity = 4
cron_schedule = */5 * * * *
enableSched = 1
```

## Deployment

### Manual Deployment
```bash
# Create tarball
cd apps
tar -czf MyApp.tar.gz MyApp/

# Copy to Splunk server
scp MyApp.tar.gz splunk-server:/tmp/

# SSH and install
ssh splunk-server
tar -xzf /tmp/MyApp.tar.gz -C /opt/splunk/etc/apps/
/opt/splunk/bin/splunk restart
```

### Using Splunk REST API
```bash
curl -k -u admin:password \
  "https://splunk:8089/services/apps/local" \
  -d name=MyApp \
  -d filename=true \
  --data-urlencode update=1
```

## Directory Locations

| Location | Purpose |
|----------|---------|
| `/opt/splunk/etc/apps/` | Enterprise apps directory |
| `/opt/splunkforwarder/etc/apps/` | Forwarder apps directory |
| `default/` | Base configuration (don't modify) |
| `local/` | Custom configuration (override default) |

## Access the Apps

1. **Operations Command Center:** http://10.10.10.114:8000/app/DA-operations-dashboard
2. **BookingApp Dashboard:** http://10.10.10.114:8000/app/DA-operations-dashboard/13-bookingapp

## Splunk App Indexes

| Index | Purpose |
|-------|---------|
| `docker` | Container logs, Docker metrics |
| `linux` | System logs (syslog) |
| `security` | Auth logs, audit logs |
| `network` | Network security metrics |
| `traefik` | Traefik proxy logs |
| `apps` | Application logs (NestJS, NextJS) |

