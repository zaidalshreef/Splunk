# Splunk Home Lab - Troubleshooting Guide

## Common Issues and Solutions

---

## 🔴 KV Store Failed

### Symptoms
```
Failed to start KV Store process. See mongod.log and splunkd.log for details.
KV Store process terminated abnormally (exit code 4, status PID killed by signal 4: Illegal instruction)
```

### Cause
The KV Store (MongoDB) requires certain CPU features that may not be available in virtualized environments or older CPUs.

### Solutions

#### Option 1: Disable KV Store (if not needed)
```bash
# SSH into the indexer
ssh -i ~/.ssh/key_10.10.10.114 root@10.10.10.114

# Disable KV Store
docker exec splunk-enterprise /opt/splunk/bin/splunk disable kvstore -auth admin:SplunkAdmin@2025

# Or add to server.conf
docker exec splunk-enterprise bash -c 'echo "[kvstore]
disabled = true" >> /opt/splunk/etc/system/local/server.conf'

# Restart Splunk
docker restart splunk-enterprise
```

#### Option 2: Use Splunk with compatible CPU
Ensure your VM or host has:
- AVX (Advanced Vector Extensions) support
- SSE 4.2 support

Check CPU features:
```bash
cat /proc/cpuinfo | grep -E "avx|sse4_2"
```

---

## 🟡 IOWait Warning

### Symptoms
```
Resource Usage > IOWait: Red
- Maximum per-cpu iowait reached red threshold of 10
- Sum of 3 highest per-cpu iowaits reached red threshold of 15
```

### Cause
High disk I/O during initial data ingestion, especially when forwarders are reading large historical log files.

### Solutions

#### Option 1: Wait it out
IOWait typically decreases after initial data ingestion completes (15-30 minutes).

#### Option 2: Adjust thresholds
```bash
# SSH into indexer
ssh -i ~/.ssh/key_10.10.10.114 root@10.10.10.114

# Increase thresholds in health.conf
docker exec splunk-enterprise bash -c 'cat >> /opt/splunk/etc/system/local/health.conf << EOF
[health:iowait]
red = 20
yellow = 15
EOF'

# Restart Splunk
docker restart splunk-enterprise
```

#### Option 3: Use SSD storage
If possible, use SSD storage for `/opt/splunk/var` to reduce I/O latency.

---

## 🔴 Forwarders Not Connecting

### Symptoms
- No data from forwarders in Splunk
- Forwarders show as healthy but no events

### Diagnosis
```bash
# Check indexer metrics for connections
ssh -i ~/.ssh/key_10.10.10.114 root@10.10.10.114 \
  "cat /opt/splunk/var/log/splunk/metrics.log | grep tcpin_connections | tail -5"
```

### Solutions

#### Check outputs.conf on forwarder
```bash
ssh -i ~/.ssh/key_10.10.10.114 root@10.10.10.115 \
  "cat /opt/splunkforwarder/etc/system/local/outputs.conf"
```

Should contain:
```ini
[tcpout]
defaultGroup = default-autolb-group

[tcpout:default-autolb-group]
server = 10.10.10.114:9997
```

#### Check network connectivity
```bash
# From forwarder node
nc -zv 10.10.10.114 9997
```

#### Check receiving is enabled on indexer
```bash
ssh -i ~/.ssh/key_10.10.10.114 root@10.10.10.114 \
  "docker exec splunk-enterprise cat /opt/splunk/etc/system/local/inputs.conf"
```

Should contain:
```ini
[splunktcp://9997]
disabled = 0
```

---

## 🔴 Cannot Read Log Files (Permission Denied)

### Symptoms
```
WARN FileClassifierManager - Unable to open '/var/log/syslog'
ERROR TailReader - error from read call from '/var/log/syslog'
```

### Cause
The Splunk user inside the container doesn't have permission to read log files owned by syslog:adm.

### Solution
```bash
# Make log files world-readable
ssh -i ~/.ssh/key_10.10.10.114 root@TARGET_IP << 'EOF'
chmod 644 /var/log/syslog /var/log/auth.log /var/log/kern.log

# Make this permanent by configuring rsyslog
echo '$FileCreateMode 0644' > /etc/rsyslog.d/50-world-readable.conf
systemctl restart rsyslog
EOF
```

Or use the provided script:
```bash
./scripts/fix-permissions.sh
```

---

## 🔴 Inputs Not Being Monitored

### Symptoms
- inputs.conf is configured but files are not being monitored
- `splunk list monitor` doesn't show custom inputs

### Diagnosis
```bash
# Check btool for inputs
docker exec splunk-uf /opt/splunkforwarder/bin/splunk cmd btool inputs list --debug | grep monitor
```

### Solutions

#### Ensure app structure is correct
```bash
# The app directory should have this structure:
/opt/splunkforwarder/etc/apps/myinputs/
├── default/
│   └── app.conf
├── local/
│   └── inputs.conf
└── metadata/
    └── default.meta
```

#### Fix app.conf
```bash
cat > /opt/splunkforwarder/etc/apps/myinputs/default/app.conf << 'EOF'
[install]
is_configured = 1
state = enabled

[package]
check_for_updates = 0

[ui]
is_visible = 0
label = Custom Inputs
EOF
```

#### Restart forwarder
```bash
docker restart splunk-uf
```

---

## 🟡 Email Domain Warning

### Symptoms
```
Security risk warning: Found an empty value for 'allowedDomainList' in alert_actions.conf
```

### Solution
```bash
# SSH into indexer and configure allowed domains
docker exec splunk-enterprise bash -c 'cat >> /opt/splunk/etc/system/local/alert_actions.conf << EOF
[email]
allowedDomainList = yourdomain.com, gmail.com
EOF'

docker restart splunk-enterprise
```

Or via Splunk Web:
1. Go to **Settings** > **Server Settings** > **Email Settings**
2. Add allowed domains in **Email Domains**

---

## 🔴 Container Keeps Restarting

### Symptoms
Splunk container restarts repeatedly.

### Diagnosis
```bash
# Check container logs
docker logs splunk-enterprise 2>&1 | tail -50

# Check container health
docker inspect splunk-enterprise --format '{{.State.Health.Status}}'
```

### Common Causes & Solutions

#### Insufficient Memory
```bash
# Check container memory
docker stats splunk-enterprise --no-stream

# Increase memory limit if needed (requires container recreation)
```

#### License Issues
Ensure the license is accepted:
```bash
docker run ... \
  -e SPLUNK_GENERAL_TERMS='--accept-sgt-current-at-splunk-com' \
  -e SPLUNK_START_ARGS='--accept-license' \
  ...
```

#### Corrupted Configuration
```bash
# Backup and reset local config
docker exec splunk-enterprise mv /opt/splunk/etc/system/local /opt/splunk/etc/system/local.bak
docker restart splunk-enterprise
```

---

## 🔧 Useful Diagnostic Commands

### Check Splunk Status
```bash
# On indexer
docker exec splunk-enterprise /opt/splunk/bin/splunk status

# On forwarder
docker exec splunk-uf /opt/splunkforwarder/bin/splunk status
```

### View Splunk Logs
```bash
# splunkd.log
docker exec splunk-enterprise tail -100 /opt/splunk/var/log/splunk/splunkd.log

# metrics.log
docker exec splunk-enterprise tail -50 /opt/splunk/var/log/splunk/metrics.log
```

### Check Data Ingestion via REST API
```bash
curl -sk -u admin:SplunkAdmin@2025 \
  "https://10.10.10.114:8089/services/search/jobs/export" \
  -d search="search index=* | stats count by index, host" \
  -d output_mode=csv
```

### List All Indexes
```bash
curl -sk -u admin:SplunkAdmin@2025 \
  "https://10.10.10.114:8089/services/data/indexes" \
  -d output_mode=json | python3 -c "import sys,json; [print(e['name']) for e in json.load(sys.stdin)['entry']]"
```

---

## 📞 Getting Help

1. Check Splunk Answers: https://community.splunk.com/
2. Splunk Documentation: https://docs.splunk.com/
3. Open an issue in this repository

