# BookingApp APM - Splunk Monitoring Solution

A complete APM (Application Performance Monitoring) solution for the Flawless BookingApp using **Splunk Universal Forwarder** with native JSON log parsing.

## 🎯 Key Features

- **Zero Parsing Required**: NestJS logs are JSON format, Splunk auto-extracts all fields
- **Full APM Tracing**: correlationId, traceId, spanId for distributed tracing
- **14 Purpose-Built Dashboards**: From overview to deep-dive analysis
- **Simple Architecture**: Just Splunk UF → Splunk Enterprise (no Fluent Bit needed)

## 📊 Log Format (Already in Your NestJS App)

Your logs are **perfect for APM** - no changes needed:

```json
{
  "correlationId": "76052cf2-6863-4f6e-b1ea-4a452f2f56d9",
  "env": "development",
  "hostname": "BOOKINGAPP",
  "level": "info",
  "message": "HTTP GET /api/v1/tenant/privacy-policy 200 85.97ms",
  "metadata": {
    "context": "HTTP",
    "service": "flawless-api",
    "timeSincePreviousLog": "+1ms"
  },
  "pid": 1950527,
  "spanId": "8adff5d247fff252",
  "timestamp": "2026-01-03T19:18:45.615+03:00",
  "traceId": "70e0517bf78fbd81551871a49a501671",
  "method": "GET",
  "url": "/api/v1/tenant/privacy-policy",
  "statusCode": 200,
  "duration": "85.97ms",
  "ip": "46.152.9.124",
  "userAgent": "node"
}
```

## 🗂️ Available Fields (Auto-Extracted by Splunk)

| Field | Description |
|-------|-------------|
| `correlationId` | Request correlation ID |
| `traceId` | Distributed trace ID |
| `spanId` | Span ID within trace |
| `level` | Log level (info, warn, error) |
| `message` | Log message |
| `metadata.context` | Logging context (HTTP, RedisIoAdapter, etc.) |
| `metadata.service` | Service name (flawless-api) |
| `method` | HTTP method (GET, POST, etc.) |
| `url` | Request URL |
| `statusCode` | HTTP status code |
| `duration` | Request duration |
| `ip` | Client IP |
| `trace` | Stack trace (for errors) |

## 📁 Project Structure

```
bookingapp/
├── splunk/
│   └── SA-bookingapp-apm/          # Splunk App
│       ├── default/
│       │   ├── app.conf            # App configuration
│       │   ├── props.conf          # Field extractions (KV_MODE=json)
│       │   ├── indexes.conf        # Index definition
│       │   ├── macros.conf         # Search macros
│       │   └── data/ui/views/      # 14 Dashboards
│       ├── local/
│       │   └── inputs.conf         # Log file monitoring
│       └── lookups/                # Lookup tables
├── nestjs/                         # Reference NestJS logging code
└── README.md
```

## 🚀 Deployment

### 1. Install Splunk Universal Forwarder on BookingApp VM

```bash
# SSH to BookingApp VM
ssh zaid@10.10.10.150

# Download and install Splunk UF
wget -O splunkforwarder.deb 'https://download.splunk.com/products/universalforwarder/releases/9.2.0/linux/splunkforwarder-9.2.0-1fff88043d5f-linux-2.6-amd64.deb'
sudo dpkg -i splunkforwarder.deb

# Start and enable
sudo /opt/splunkforwarder/bin/splunk start --accept-license
sudo /opt/splunkforwarder/bin/splunk enable boot-start
```

### 2. Configure Forwarder to Send to Splunk

```bash
# Add your Splunk server as receiving indexer
sudo /opt/splunkforwarder/bin/splunk add forward-server 10.10.10.114:9997 -auth admin:changeme
```

### 3. Deploy the Splunk App

```bash
# From your local machine
scp -r /home/zaid/Documents/Splunk/bookingapp/splunk/SA-bookingapp-apm zaid@10.10.10.150:/tmp/

# On BookingApp VM - copy to UF
sudo cp -r /tmp/SA-bookingapp-apm /opt/splunkforwarder/etc/apps/

# Restart UF
sudo /opt/splunkforwarder/bin/splunk restart
```

### 4. Deploy App to Splunk Enterprise (for dashboards)

```bash
# Copy app to Splunk server
scp -r /home/zaid/Documents/Splunk/bookingapp/splunk/SA-bookingapp-apm zaid@10.10.10.114:/tmp/

# On Splunk server
sudo docker cp /tmp/SA-bookingapp-apm splunk:/opt/splunk/etc/apps/
sudo docker exec splunk /opt/splunk/bin/splunk restart
```

## 📈 Dashboards

| Dashboard | Description |
|-----------|-------------|
| **00-apm-overview** | Executive overview with APDEX, error rate, latency |
| **01-service-performance** | Per-service metrics |
| **02-endpoint-analysis** | Individual endpoint performance |
| **03-latency-analysis** | P50/P75/P90/P95/P99 latency |
| **04-error-tracking** | Error aggregation and trends |
| **05-error-details** | Stack traces and affected endpoints |
| **06-distributed-traces** | Trace listing and filtering |
| **07-trace-details** | Individual trace visualization |
| **08-database-performance** | PostgreSQL query analysis |
| **09-cache-performance** | Redis monitoring |
| **10-external-services** | Traefik/load balancer metrics |
| **11-container-metrics** | Docker container health |
| **12-host-metrics** | CPU, memory, disk, network |
| **13-logs-explorer** | Full-text log search |

## 🔍 Example Searches

```spl
# Find all errors with traces
index=bookingapp level=error 
| table _time, correlationId, traceId, message, trace

# Calculate APDEX score
index=bookingapp statusCode=* duration=*
| eval satisfied=if(duration<500, 1, 0), tolerating=if(duration>=500 AND duration<2000, 1, 0)
| stats sum(satisfied) as satisfied, sum(tolerating) as tolerating, count as total
| eval apdex=(satisfied + (tolerating/2)) / total

# Trace a request across services
index=bookingapp traceId="70e0517bf78fbd81551871a49a501671"
| sort _time
| table _time, spanId, metadata.context, message, duration

# Find slow requests
index=bookingapp duration=*
| eval duration_ms=tonumber(replace(duration, "ms", ""))
| where duration_ms > 1000
| table _time, method, url, statusCode, duration, correlationId
```

## ✅ Why This Approach?

| Feature | Fluent Bit | Splunk UF |
|---------|------------|-----------|
| JSON Parsing | Manual config | **Automatic** (KV_MODE=json) |
| Complexity | High | **Low** |
| Maintenance | Another process | **Native** |
| Resource Usage | ~10MB | ~50MB |
| Field Extraction | Lua scripts | **Built-in** |

**Bottom Line**: Your NestJS logs are already JSON with all APM fields. Splunk parses them automatically - no external tools needed!
