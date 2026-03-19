# Proxmox LXC Setup Guide

**Target:** Proxmox VE host with multiple LXCs  
**Last updated:** 2026-03-19

---

## LXC Overview

This project uses **three dedicated LXCs** on your Proxmox host:

| LXC | Hostname | RAM | CPU | Disk | Purpose |
|---|---|---|---|---|---|
| n8n LXC | `n8n-unified` | 4GB | 4 | 32GB | n8n, email-bridge, crawl4ai |
| SearXNG LXC | `searxng` | 1GB | 2 | 8GB | SearXNG private search |
| Flowise LXC | `flowise` | 4GB | 4 | 20GB | Flowise AI (helper script) |

The **CTI LXC** (from `threatlabs-cti-stack`) hosts all CTI platform
services and the shared `infra-postgres` database. See the
[threatlabs-cti-stack README](https://github.com/JazenaYLA/threatlabs-cti-stack)
for CTI LXC setup.

---

## n8n LXC Setup

### Option A — Proxmox Helper Script (Recommended)

```bash
# On Proxmox host shell
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/docker.sh)"
```

When prompted:
- **Hostname:** `n8n-unified`
- **RAM:** `4096`
- **CPU:** `4`
- **Disk:** `32`
- **Unprivileged:** Yes

### Option B — Manual

```bash
pct create 200 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname n8n-unified \
  --memory 4096 \
  --cores 4 \
  --rootfs local-lvm:32 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1 \
  --unprivileged 1
pct start 200
```

**VLAN tagging** (UniFi segmented network):
```bash
--net0 name=eth0,bridge=vmbr0,tag=<VLAN_ID>,ip=dhcp
```

### Inside n8n LXC — Docker Install

```bash
apt update && apt install -y curl git ca-certificates gnupg
curl -fsSL https://get.docker.com | sh
systemctl enable docker && systemctl start docker

# Install Dockge (optional — for stack management UI)
mkdir -p /opt/stacks /opt/dockge
curl https://raw.githubusercontent.com/louislam/dockge/master/compose.yaml \
  --output /opt/dockge/compose.yaml
cd /opt/dockge && docker compose up -d
```

### Deploy n8n Stack

```bash
git clone https://github.com/JazenaYLA/n8n-ecosystem-unified.git /opt/stacks/n8n-unified
cd /opt/stacks/n8n-unified
cp .env.example .env

# Generate secrets and fill into .env
echo "N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)"
echo "N8N_POSTGREST_JWT_SECRET=$(openssl rand -hex 32)"

nano .env  # fill all values

docker compose up -d
```

---

## SearXNG LXC Setup

SearXNG runs as a **separate Dockge stack** on a dedicated LXC.

```bash
# On Proxmox host — create LXC via helper script
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/docker.sh)"
# Hostname: searxng, RAM: 1024, CPU: 2, Disk: 8
```

Then see `docs/SEARXNG_SETUP.md` for the stack deploy.

---

## Flowise LXC Setup

Flowise is installed on a dedicated LXC using the **Proxmox helper script**:

```bash
# On Proxmox host shell
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/flowise.sh)"
```

When prompted:
- **Hostname:** `flowise`
- **RAM:** `4096`
- **CPU:** `4`
- **Disk:** `20`

The helper script installs Flowise natively (Node.js, no Docker needed).
After installation Flowise is available at `http://<FLOWISE_LXC_IP>:3000`.

See `docs/FLOWISE_SETUP.md` for post-install configuration and n8n integration.

---

## Network Requirements

All LXCs must be able to reach:
- **CTI LXC IP** — for `infra-postgres` on port `5432` and PostgREST on port `3000`
- **Caddy LXC IP** — for `*.lab.local` domain routing

If using UniFi VLAN segmentation, ensure inter-VLAN routing rules permit
traffic between the n8n, Flowise, SearXNG, and CTI VLANs.
