# Proxmox LXC Setup Guide

**Target:** Proxmox VE homelab — enterprise VLAN topology  
**Last updated:** 2026-03-19

---

## Architecture Overview

This project spans multiple dedicated LXCs on the same VLAN, managed
through the `threatlabs-cti-stack` Dockge instance.

### LXCs in the Enterprise Stack

| LXC | Install Method | Purpose |
|---|---|---|
| `dockge-cti` | Manual | Hosts Dockge + all CTI Docker stacks (infra, misp, xtm, thehive, etc.) |
| `n8n` | Proxmox helper script | n8n automation — native systemd, **no Docker** |
| `flowise` | Proxmox helper script | Flowise AI — native Node.js, **no Docker** |
| `wazuh` | Proxmox helper script | Wazuh SIEM — native install |
| `forgejo` | Proxmox helper script | Forgejo git server — native install |
| `ail-project` | Manual LXC | AIL Project dark web analysis |
| `lookyloo` | Proxmox helper script | Lookyloo URL capture |
| `caddy` | Proxmox helper script | Caddy reverse proxy — serves `*.lab.local` |
| `infisical` | Proxmox helper script | Infisical secrets manager |
| `stalwart` | Proxmox helper script | Stalwart mail server |
| `pmg` | Proxmox PMG ISO | Proxmox Mail Gateway |
| `cortex` | Docker in LXC | Cortex analyzers |

> The enterprise branch topology is documented in the private Forgejo
> `enterprise` branch of `threatlabs-cti-stack`. This public doc describes
> the pattern without private IPs or credentials.

---

## n8n LXC — Install

n8n is installed using the **Proxmox community helper script**.
This installs n8n as a native systemd service (Node.js, no Docker).

```bash
# On Proxmox host shell
bash -c "$(curl -fsSL https://github.com/community-scripts/ProxmoxVE/raw/main/ct/n8n.sh)"
```

Recommended LXC resources:
- **RAM:** 4096 MB
- **CPU:** 4 cores
- **Disk:** 20 GB
- **Unprivileged:** Yes
- **VLAN tag:** same as dockge-cti LXC

### What the helper script creates

- Installs Node.js 24 + n8n globally via npm
- Creates `/opt/n8n.env` with 4 base vars
- Creates `/etc/systemd/system/n8n.service` pointing to `/opt/n8n.env`
- n8n starts on port `5678` using **SQLite** by default

### Post-install configuration

All configuration is done by editing `/opt/n8n.env` and restarting:

```bash
systemctl restart n8n
journalctl -u n8n -f  # watch logs
```

See `docs/ANTIGRAVITY_RECONFIGURE.md` for the complete reconfiguration
playbook including Postgres migration.

---

## Flowise LXC — Install

```bash
# On Proxmox host shell
bash -c "$(curl -fsSL https://github.com/community-scripts/ProxmoxVE/raw/main/ct/flowise.sh)"
```

- Installs Flowise as native Node.js service (no Docker)
- Available at `http://<FLOWISE_LXC_IP>:3000` after install
- Config lives in the Flowise `.env` in the install directory

See `docs/FLOWISE_SETUP.md` for post-install Postgres + n8n integration.

---

## dockge-cti LXC — infra Stack

The `infra` Dockge stack (in `threatlabs-cti-stack/infra/`) hosts:

| Service | Container | Port | Used By |
|---|---|---|---|
| PostgreSQL 17 | `infra-postgres` | 5432 | n8n, flowintel, openclaw, openaev |
| Valkey (Redis) | `infra-valkey` | 6379 | OpenCTI, TheHive connectors |
| Elasticsearch 7 | `es7-cti` | varies | TheHive (legacy) |
| Elasticsearch 8 | `es8-cti` | varies | OpenCTI, Wazuh indexer |

The `infra` stack creates the shared `cti-net` Docker network that all
other Dockge stacks attach to.

### infra-postgres databases

Created automatically by `infra/vol/postgres-init/init-dbs.sh` on first boot:

| Database | User | Purpose |
|---|---|---|
| `n8n` | `n8n` | n8n workflows, credentials, execution history |
| `flowintel` | `flowintel` | FlowIntel case management |
| `openclaw` | `openclaw` | OpenClaw/n8n-claw skill registry |
| `openaev` | `openaev` | OpenCTI/OpenAEV |

### Required change — add pgvector

The current `postgres:17-alpine` image does **not** include pgvector.
n8n's memory/embedding features require it. Change the image:

```yaml
# infra/docker-compose.yml
image: pgvector/pgvector:pg17   # was: postgres:17-alpine
```

This is safe — existing volume data (`./vol/postgres/data`) is preserved.
Restart: `docker compose up -d postgres` on dockge-cti LXC.

---

## Network Requirements

All LXCs are on the same VLAN. Key connectivity requirements:

| From | To | Port | Reason |
|---|---|---|---|
| n8n LXC | dockge-cti LXC | 5432 | infra-postgres |
| n8n LXC | dockge-cti LXC | 6379 | Valkey (if needed) |
| n8n LXC | flowise LXC | 3000 | Flowise API |
| n8n LXC | caddy LXC | 80/443 | *.lab.local routing |
| n8n LXC | wazuh LXC | 55000 | Wazuh API |
| flowise LXC | dockge-cti LXC | 5432 | infra-postgres (optional) |

If inter-VLAN routing is restricted (UniFi firewall rules), ensure the
above port pairs are permitted between the relevant VLAN segments.
