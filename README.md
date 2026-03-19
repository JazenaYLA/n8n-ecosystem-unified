# n8n-ecosystem-unified

A self-hosted n8n AI agent and CTI automation stack for **Proxmox VE homelabs**.
Designed to integrate natively with [threatlabs-cti-stack](https://github.com/JazenaYLA/threatlabs-cti-stack).

This is a **ground-up original project** — not derived from any upstream fork.
It uses the MCP skill pattern pioneered by the n8n community, adapted for a
zero-trust, multi-LXC Proxmox homelab with CTI-first workflows.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  PROXMOX VE HOST                                                 │
│                                                                  │
│  ┌─────────────┐  ┌──────────────────────┐  ┌───────────────┐  │
│  │  Caddy LXC  │  │      CTI LXC         │  │   n8n LXC     │  │
│  │             │  │  (threatlabs-cti)    │  │               │  │
│  │ :80/:443    │  │  infra-postgres      │  │  n8n :5678    │  │
│  │ :2019 API   │  │  infra-postgrest     │  │  email-bridge │  │
│  │ CaddyManager│  │  infra-pgadmin       │  │  crawl4ai     │  │
│  │ CaddyGen    │  │  es7/es8, valkey     │  │               │  │
│  └──────┬──────┘  │  MISP, OpenCTI       │  └───────────────┘  │
│         │         │  TheHive, Cortex      │                      │
│         │         │  Shuffle, DFIR-IRIS   │  ┌───────────────┐  │
│         │         └──────────────────────┘  │  SearXNG LXC  │  │
│         │                                    │  (Dockge stk) │  │
│         │                                    │  :8888        │  │
│         │                                    └───────────────┘  │
│         │                                    ┌───────────────┐  │
│         │                                    │  Flowise LXC  │  │
│         │                                    │  (helper-scr) │  │
│         │                                    │  :3000        │  │
│         │                                    └───────────────┘  │
│                                                                  │
│  DNS: *.lab.local CNAMEs → caddy.lab.local (single A record)    │
└─────────────────────────────────────────────────────────────────┘
```

**Integration model:** n8n workflows call CTI tools over HTTP API using
`*.lab.local` Caddy domain names. No shared Docker networks across LXC
boundaries — all cross-LXC communication is via HTTP/REST.

---

## Stack Components

| Component | Where | Purpose |
|---|---|---|
| **n8n** | n8n LXC — Dockge | Orchestration, automation, MCP skill host |
| **email-bridge** | n8n LXC — Dockge | IMAP/SMTP REST microservice |
| **crawl4ai** | n8n LXC — Dockge | Web page → clean markdown |
| **SearXNG** | Separate Dockge stack | Private web search (JSON API) |
| **Flowise** | Dedicated LXC (helper script) | Conversational AI / RAG chatflows |
| **infra-postgres (pgvector)** | CTI LXC — infra stack | Shared DB: n8n, Flowise, OpenClaw |
| **infra-postgrest** | CTI LXC — infra stack | REST API over n8n database |
| **infra-pgadmin** | CTI LXC — infra stack | Database management UI |
| **MISP** | CTI LXC | Malware Information Sharing Platform |
| **OpenCTI** | CTI LXC | Threat intelligence platform |
| **TheHive** | CTI LXC | Case management |
| **Cortex** | CTI LXC | Observable analysis/enrichment |
| **Wazuh** | Wazuh LXC | SIEM / EDR |

---

## Multi-LLM Support

This stack is **LLM-agnostic**. All model calls are routed through n8n's
native credential system. Supported providers:

| Provider | n8n Credential Type | Local/Cloud |
|---|---|---|
| **Ollama** | HTTP Request (no auth) | ☁️ Local — runs on Proxmox host or LXC |
| **Gemini / Google AI** | Google PaLM / Gemini API | ☁️ Cloud |
| **Anthropic Claude** | Anthropic API | ☁️ Cloud |
| **OpenRouter** | HTTP Header Auth | ☁️ Cloud (multi-model gateway) |
| **OpenAI** | OpenAI API | ☁️ Cloud |
| **LM Studio** | HTTP Request (OpenAI-compat.) | 🏠 Local |
| **Mistral** | HTTP Header Auth | ☁️ Cloud |

The **Tiered Model Router** workflow selects provider by task complexity
(score 1–10): Ollama/local for score ≤3, mid-tier (Gemini Flash/Haiku)
for 4–6, heavyweight (Claude Sonnet/Opus, GPT-4o) for ≥7.

---

## Quick Start

### Prerequisites
- Proxmox VE host with:
  - `threatlabs-cti-stack` enterprise branch deployed on CTI LXC
  - Caddy LXC running with CaddyManager
  - UniFi (or equivalent) local DNS for `*.lab.local`
- See `docs/PROXMOX_SETUP.md` for n8n LXC creation
- See `docs/FLOWISE_SETUP.md` for Flowise LXC creation

### Step 1 — Create n8n LXC

On Proxmox host:
```bash
# Option A: Proxmox helper script (recommended)
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/docker.sh)"
# Set hostname: n8n-unified, RAM: 4096MB, Cores: 4, Disk: 32GB
```

Or manual:
```bash
pct create 200 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname n8n-unified --memory 4096 --cores 4 \
  --rootfs local-lvm:32 --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1 --unprivileged 1
pct start 200
```

### Step 2 — Deploy n8n Stack via Dockge

Inside the n8n LXC:
```bash
# Install Docker
curl -fsSL https://get.docker.com | sh

# Clone repo into Dockge stacks directory
git clone https://github.com/JazenaYLA/n8n-ecosystem-unified.git /opt/stacks/n8n-unified
cd /opt/stacks/n8n-unified

# Copy and fill env
cp .env.example .env
nano .env   # fill CTI_LXC_IP, N8N_DB_PASSWORD, LLM keys

# Generate secrets
echo "N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)"
echo "N8N_POSTGREST_JWT_SECRET=$(openssl rand -hex 32)"

# Start
docker compose up -d
```

### Step 3 — Deploy SearXNG (separate Dockge stack)

See `docs/SEARXNG_SETUP.md`.

### Step 4 — n8n First-Boot Setup

1. Browse to `http://<N8N_LXC_IP>:5678` (or `http://n8n.lab.local` after DNS)
2. Create owner account
3. **Settings → API** → Create API Key → copy it
4. Set Variables (Settings → Variables) — see `docs/N8N_CONFIGURATION.md`
5. Create Credentials — see `docs/N8N_CONFIGURATION.md`
6. Run DB migrations — see `docs/N8N_CONFIGURATION.md`
7. Import workflows from `workflows/unified/`

### Step 5 — Add Caddy Routes

In CaddyManager UI, add routes from `docs/CADDY_ROUTES.md`.

### Step 6 — Add DNS Records

In UniFi (or router) local DNS:
```
n8n.lab.local       CNAME  caddy.lab.local
flowise.lab.local   CNAME  caddy.lab.local
searxng.lab.local   CNAME  caddy.lab.local
postgrest.lab.local CNAME  caddy.lab.local
pgadmin.lab.local   CNAME  caddy.lab.local
```

---

## Related Repositories

| Repo | Purpose |
|---|---|
| [threatlabs-cti-stack](https://github.com/JazenaYLA/threatlabs-cti-stack) | CTI platform stack (enterprise branch for Proxmox) |
| [n8n-claw-templates](https://github.com/JazenaYLA/n8n-claw-templates) | n8n MCP skill template library (CTI + general) |

---

## Flowise Integration

Flowise runs in its own dedicated LXC (installed via Proxmox helper script)
and integrates with n8n at three points:

1. **n8n as gateway, Flowise as RAG brain** — complex queries (score ≥7)
   are forwarded to a Flowise chatflow via `POST /api/v1/prediction/<id>`
2. **CTI document RAG** — Flowise ingests MISP/OpenCTI reports into
   pgvector and answers n8n queries about threat actors, IOCs, TTPs
3. **Flowise → n8n webhooks** — Flowise custom tool nodes trigger n8n
   workflows (e.g., create TheHive case from chat finding)

See `docs/FLOWISE_SETUP.md` for full setup and integration patterns.

---

## Credits

Original project by [@JazenaYLA](https://github.com/JazenaYLA).
MCP skill pattern inspired by the broader n8n community.
