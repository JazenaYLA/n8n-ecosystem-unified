# Proxmox LXC Setup Guide

**Replaces:** Freddy's `setup.sh` (bare VPS assumptions, Nginx, basic Docker)  
**Target:** Proxmox VE LXC container running Debian 12 (bookworm)  
**Last updated:** 2026-03-18  

---

## Pre-requisites (Proxmox Host)

```bash
# On Proxmox host — create the LXC container
pct create 200 /var/lib/vz/template/cache/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname n8n-unified \
  --memory 4096 \
  --cores 4 \
  --rootfs local-lvm:32 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1 \
  --unprivileged 1
pct start 200
```

**VLAN tagging** (if using UniFi VLAN segmentation):  
Add `--net0 name=eth0,bridge=vmbr0,tag=YOUR_VLAN_ID,ip=dhcp` to the above command.

---

## Inside the LXC Container

```bash
apt update && apt install -y curl git ca-certificates gnupg lsb-release

# Install Docker (official method)
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker && systemctl start docker
```

---

## Directory Structure

```bash
mkdir -p /opt/n8n-unified/{n8n,supabase,searxng,crawl4ai,caddy}
```

---

## Docker Compose (Unified Stack)

Create `/opt/n8n-unified/docker-compose.yml`:

```yaml
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    environment:
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${N8N_HOST}/
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=supabase-db
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_LOG_LEVEL=info
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=none
      - N8N_RUNNERS_ENABLED=true
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
    volumes:
      - /opt/n8n-unified/n8n:/home/node/.n8n
    ports:
      - "5678:5678"
    networks:
      - n8n-internal
    depends_on:
      - supabase-db

  supabase-db:
    image: supabase/postgres:15.6.1.143
    container_name: supabase-db
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_DB: postgres
      JWT_SECRET: ${SUPABASE_JWT_SECRET}
      ANON_KEY: ${SUPABASE_ANON_KEY}
      SERVICE_ROLE_KEY: ${SUPABASE_SERVICE_KEY}
    volumes:
      - /opt/n8n-unified/supabase:/var/lib/postgresql/data
    networks:
      - n8n-internal

  searxng:
    image: searxng/searxng:latest
    container_name: searxng
    restart: unless-stopped
    volumes:
      - /opt/n8n-unified/searxng:/etc/searxng
    networks:
      - n8n-internal
    environment:
      - SEARXNG_BASE_URL=http://searxng:8080

  crawl4ai:
    image: unclecode/crawl4ai:latest
    container_name: crawl4ai
    restart: unless-stopped
    networks:
      - n8n-internal

networks:
  n8n-internal:
    driver: bridge
```

---

## Caddy Reverse Proxy (replaces Nginx from Freddy's setup.sh)

Install Caddy on the **Proxmox host** or in a separate LXC (recommended if using Caddy for the entire homelab):

```bash
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install caddy
```

Add to `/etc/caddy/Caddyfile`:

```
n8n.yourdomain.com {
    reverse_proxy localhost:5678
    encode gzip
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
    }
}
```

Caddy auto-provisions Let's Encrypt TLS — no certbot needed.

---

## Environment File

Create `/opt/n8n-unified/.env`:

```bash
# n8n
N8N_HOST=n8n.yourdomain.com
N8N_ENCRYPTION_KEY=GENERATE_WITH: openssl rand -hex 32
N8N_API_KEY=GENERATE_IN_N8N_UI
N8N_INTERNAL_URL=http://localhost:5678

# Supabase / Postgres
POSTGRES_USER=postgres
POSTGRES_PASSWORD=GENERATE_STRONG_PASSWORD
SUPABASE_URL=http://supabase-db:5432
SUPABASE_JWT_SECRET=GENERATE_WITH: openssl rand -hex 32
SUPABASE_ANON_KEY=GENERATE_VIA_SUPABASE_CLI
SUPABASE_SERVICE_KEY=GENERATE_VIA_SUPABASE_CLI

# Telegram
TELEGRAM_CHAT_ID=YOUR_TELEGRAM_CHAT_ID

# Evolution API (WhatsApp)
EVOLUTION_INSTANCE_NAME=YOUR_INSTANCE_NAME
WHATSAPP_PHONE=YOUR_PHONE_NUMBER

# OpenRouter
OPENROUTER_API_KEY=YOUR_KEY
```

---

## Differences from Freddy's setup.sh

| Freddy's setup.sh | This guide |
|---|---|
| Bare VPS (Ubuntu/Debian) | Proxmox LXC (Debian 12, unprivileged) |
| Nginx reverse proxy | Caddy (auto TLS, simpler config) |
| SQLite / n8n internal DB | Supabase Postgres (persistent, vectorized) |
| Manual TLS (certbot) | Caddy auto Let's Encrypt |
| No VLAN awareness | UniFi VLAN tagging on LXC net0 |
| Single Docker network | n8n-internal isolated bridge network |
| No crawl4ai | crawl4ai container for Web Reader tool |

---

## After Deployment

1. Start the stack: `cd /opt/n8n-unified && docker compose up -d`
2. Open n8n at `https://n8n.yourdomain.com` and complete setup
3. Import workflows from `workflows/unified/` via n8n UI → Import Workflow
4. Import `workflows/freddy/n8n-claw-agent.json` as the main agent
5. Wire `tiered-model-router.json` as the `Expert Agent` tool target
6. Wire `email-manager.json` as a standalone active workflow
7. Set n8n Variables: `TELEGRAM_CHAT_ID`, `EVOLUTION_INSTANCE_NAME`, `WHATSAPP_PHONE`
8. Run the Supabase SQL schema from `workflows/unified/email-manager.json` → `_supabase_schema_note`
