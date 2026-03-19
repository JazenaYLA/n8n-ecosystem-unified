# SearXNG Setup Guide

SearXNG runs as a **standalone Dockge stack** on a dedicated LXC
(or the n8n LXC if resources allow). It provides a private,
no-rate-limit JSON search API for n8n workflows.

**Last updated:** 2026-03-19

---

## LXC Setup

```bash
# On Proxmox host
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/docker.sh)"
# Hostname: searxng, RAM: 1024, CPU: 2, Disk: 8
```

---

## Dockge Stack Files

Create these two files in `/opt/stacks/searxng/` on the SearXNG LXC:

### `docker-compose.yml`

```yaml
services:
  searxng:
    image: searxng/searxng:latest
    container_name: searxng
    restart: unless-stopped
    ports:
      - "127.0.0.1:8888:8080"
    volumes:
      - ./settings.yml:/etc/searxng/settings.yml:ro

```

### `settings.yml`

```yaml
use_default_settings: true
server:
  bind_address: "0.0.0.0"
  port: 8080
  # Generate: openssl rand -hex 32
  secret_key: "REPLACE_WITH_openssl_rand_hex_32"
search:
  formats: [html, json]
  default_lang: "en"
engines:
  - name: google
    engine: google
    disabled: false
  - name: duckduckgo
    engine: duckduckgo
    disabled: false
  - name: bing
    engine: bing
    disabled: false
  - name: brave
    engine: brave
    disabled: false
  - name: wikipedia
    engine: wikipedia
    disabled: false
  - name: arxiv
    engine: arxiv
    disabled: false
  - name: github
    engine: github
    disabled: false
```

---

## Start the Stack

```bash
cd /opt/stacks/searxng
docker compose up -d
```

Test: `curl 'http://localhost:8888/search?q=test&format=json'`

---

## Caddy Route

In CaddyManager, add:
```caddy
searxng.lab.local {
    reverse_proxy <SEARXNG_LXC_IP>:8888
}
```

## DNS Record

In UniFi local DNS:
```
searxng.lab.local   CNAME   caddy.lab.local
```

---

## Using SearXNG in n8n Workflows

In any n8n HTTP Request node:
- **Method:** GET
- **URL:** `http://searxng.lab.local/search`
- **Query Params:** `q={{ $json.query }}`, `format=json`, `engines=google,bing`, `language=en`

The JSON response includes `results[]` with `title`, `url`, `content` fields.
