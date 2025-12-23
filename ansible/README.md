# Splunk Home Lab - Ansible Automation

This directory contains Ansible playbooks and configurations for managing the Splunk SIEM home lab deployment.

## Quick Start

```bash
# 1. Install Ansible (if not already installed)
sudo apt update && sudo apt install -y ansible python3-pip
pip3 install docker

# 2. Install required Ansible collections
cd /home/zaid/Documents/Splunk/ansible
ansible-galaxy collection install -r requirements.yml

# 3. Test connectivity to all VMs
ansible all -m ping

# 4. Deploy complete Splunk infrastructure
ansible-playbook playbooks/site.yml
```

## Directory Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── requirements.yml         # Galaxy dependencies
├── README.md               # This file
├── inventory/
│   └── hosts.yml           # VM inventory (10.10.10.114-118)
├── group_vars/
│   ├── all.yml             # Global variables
│   └── splunk_forwarders.yml  # Forwarder-specific vars
├── playbooks/
│   ├── site.yml            # Master playbook (deploys everything)
│   ├── deploy-indexer.yml  # Deploy Splunk Enterprise
│   ├── deploy-forwarders.yml  # Deploy Universal Forwarders
│   ├── update-dashboards.yml  # Update Splunk dashboards
│   └── appdynamics-deploy.yml # Deploy AppDynamics APM
└── roles/                  # Custom roles (future)
```

## Inventory

The inventory defines 5 VMs in your Docker Swarm cluster:

| Hostname | IP Address | Role |
|----------|------------|------|
| mgr-1 | 10.10.10.114 | Swarm Manager (Leader) + Splunk Indexer |
| mgr-2 | 10.10.10.115 | Swarm Manager |
| mgr-3 | 10.10.10.116 | Swarm Manager |
| node1 | 10.10.10.117 | Swarm Worker |
| worker-1 | 10.10.10.118 | Swarm Worker |

## Playbooks

### Deploy Everything
```bash
ansible-playbook playbooks/site.yml
```

### Deploy Only Indexer
```bash
ansible-playbook playbooks/deploy-indexer.yml
```

### Deploy Only Forwarders
```bash
ansible-playbook playbooks/deploy-forwarders.yml
```

### Update Dashboards
```bash
ansible-playbook playbooks/update-dashboards.yml
```

### Deploy AppDynamics APM
```bash
# Edit playbooks/appdynamics-deploy.yml with your AppDynamics credentials first
ansible-playbook playbooks/appdynamics-deploy.yml
```

## Targeting Specific Hosts

```bash
# Deploy forwarder to single host
ansible-playbook playbooks/deploy-forwarders.yml --limit mgr-2

# Deploy to all managers only
ansible-playbook playbooks/deploy-forwarders.yml --limit swarm_managers

# Deploy to workers only
ansible-playbook playbooks/deploy-forwarders.yml --limit swarm_workers
```

## Variables

### Global Variables (`group_vars/all.yml`)

| Variable | Default | Description |
|----------|---------|-------------|
| `splunk_admin_password` | `SplunkAdmin@2025` | Splunk admin password |
| `splunk_indexer_ip` | `10.10.10.114` | Indexer IP address |
| `splunk_indexer_port` | `9997` | Data receiving port |
| `splunk_web_port` | `8000` | Web UI port |

### Forwarder Inputs

The forwarders are configured to collect:

| Source | Sourcetype | Index |
|--------|------------|-------|
| `/var/log/syslog` | syslog | linux |
| `/var/log/auth.log` | linux_secure | security |
| `/var/log/audit/audit.log` | linux_audit | security |
| `/var/log/docker-metrics.log` | docker:metrics | docker |
| `/var/lib/docker/containers/*/*-json.log` | docker:container:json | docker |
| `/etc/dokploy/traefik/dynamic/access.log` | traefik:access | traefik |
| `/etc/dokploy/logs/*/*.log` | dokploy:app | application |

## Integration with Official Splunk Role

For bare-metal (non-Docker) Splunk installations, you can use Splunk's official Ansible role:

```bash
# Clone the official role
git clone https://github.com/splunk/ansible-role-for-splunk.git roles/splunk

# Or install via Galaxy
ansible-galaxy install -r requirements.yml
```

See: [splunk/ansible-role-for-splunk](https://github.com/splunk/ansible-role-for-splunk)

## AppDynamics Integration

The `appdynamics-deploy.yml` playbook deploys AppDynamics Machine Agents for APM:

1. Edit `playbooks/appdynamics-deploy.yml`
2. Update the controller credentials:
   ```yaml
   appdynamics_controller_host: "your-controller.saas.appdynamics.com"
   appdynamics_account_name: "your-account"
   appdynamics_account_access_key: "your-access-key"
   ```
3. Run the playbook:
   ```bash
   ansible-playbook playbooks/appdynamics-deploy.yml
   ```

### What AppDynamics Provides

| Splunk SIEM | AppDynamics APM |
|-------------|-----------------|
| Log aggregation | Application tracing |
| Security events | Code-level diagnostics |
| Infrastructure monitoring | Business transactions |
| Compliance auditing | End-user monitoring |

Together, they provide complete observability for your Docker Swarm cluster.

## Troubleshooting

### SSH Connection Issues
```bash
# Test SSH connectivity
ssh -i ~/.ssh/key_10.10.10.114 root@10.10.10.114

# If using password auth
ansible all -m ping --ask-pass
```

### Docker Module Issues
```bash
# Install Docker Python library
pip3 install docker
```

### Check Ansible Version
```bash
ansible --version
# Requires Ansible 2.9+
```

## Resources

- [Splunk Docker Documentation](https://github.com/splunk/docker-splunk)
- [Splunk Ansible Role](https://github.com/splunk/ansible-role-for-splunk)
- [AppDynamics Docker Hub](https://hub.docker.com/u/appdynamics)
- [Ansible Docker Collection](https://docs.ansible.com/ansible/latest/collections/community/docker/)

