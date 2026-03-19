# n8n-ecosystem-unified

> A unified n8n AI agent stack combining the best of [JazenaYLA/n8n-claw](https://github.com/JazenaYLA/n8n-claw) (n8n-claw) and Shabbir's OpenCLAW multi-channel patterns.
> Designed for **Proxmox LXC homelabs** with Caddy TLS, multi-channel messaging, tiered model routing, autonomous email management, and CTI (Cyber Threat Intelligence) integration.

---

## What's Inside

| Component | Description |
|---|---|
| **Multi-Channel Router** | Telegram + WhatsApp (Evolution API) normalized to same `{userMessage, chatId, userId, source}` struct |
| **Tiered Model Router** | Routes tasks to Haiku / Sonnet / Opus by complexity score (1–10) |
| **Email Manager** | Autonomous Gmail manager with safety guardrails (draft + Telegram notify for sensitive replies) |
| **CTI Skills** | MISP, Wazuh, OpenCTI, TheHive, Cortex integration workflows (in `docs/CTI_SKILLS_ROADMAP.md`) |
| **Supabase Stack** | Full self-hosted Supabase (Postgres + pgvector + PostgREST + Kong + Studio) |
| **SearXNG** | Private web search engine (Google + Bing + DuckDuckGo + Brave) |
| **email-bridge** | Stateless IMAP/SMTP REST microservice for non-Gmail email workflows |
| **Crawl4AI** | Web content reader — returns clean markdown from any URL |

---

## vs. n8n-claw

| Feature | n8n-claw | n8n-ecosystem-unified |
|---|---|---|
| Messaging channels | Telegram only | Telegram + WhatsApp (Evolution API) |
| Model routing | Single model | Haiku / Sonnet / Opus by complexity |
| Email | email-bridge (IMAP/SMTP) | email-bridge + autonomous Gmail manager |
| Reverse proxy | Nginx + certbot | **Caddy** (auto TLS, no certbot) |
| Target platform | Bare VPS (Ubuntu/Debian) | **Proxmox LXC** (Debian 12) |
| CTI integration | — | MISP, Wazuh, OpenCTI, TheHive, Cortex |
| DB schema extras | Core tables | + `email_log`, `channel_sessions`, `cti_events` |
| Seed locale | German | English |

---

## Quick Start

### Prerequisites
- Proxmox VE host with a Debian 12 LXC (see `docs/PROXMOX_SETUP.md`)
- LXC created with `--features nesting=1` (required for Docker)
- A domain pointing to your public IP (or local DNS override for homelab)

### 1. Clone the repo inside the LXC

```bash
git clone https://github.com/JazenaYLA/n8n-ecosystem-unified.git
cd n8n-ecosystem-unified
```

### 2. Run setup

```bash
sudo bash setup.sh
```

The interactive installer will:
- Install Docker and Caddy
- Collect all required credentials interactively
- Generate secrets (`N8N_ENCRYPTION_KEY`, `SUPABASE_JWT_SECRET`, `POSTGRES_PASSWORD`, etc.)
- Write `.env` and `supabase/kong.deployed.yml`
- Start the full Docker stack
- Configure Caddy for HTTPS

### 3. Open n8n

```
https://your-n8n-domain.com
```

Complete initial account setup, then generate your API key under **Settings → API**.

### 4. Import workflows

Import these via **n8n UI → Import Workflow** in order:

1. `workflows/unified/multi-channel-router.json`
2. `workflows/unified/tiered-model-router.json`
3. `workflows/unified/email-manager.json`
4. `workflows/freddy/n8n-claw-agent.json` (main orchestrator)
5. Any CTI skill workflows from `workflows/unified/cti/`

### 5. Set n8n Variables

In n8n → **Settings → Variables**, add:

| Variable | Value |
|---|---|
| `TELEGRAM_CHAT_ID` | Your Telegram chat ID |
| `EVOLUTION_INSTANCE_NAME` | Your Evolution API instance (WhatsApp) |
| `WHATSAPP_PHONE` | Your WhatsApp number (digits only) |
| `SUPABASE_URL` | `http://kong:8000` |
| `SUPABASE_SERVICE_KEY` | From your `.env` |

### 6. Create n8n Credentials

Create credentials with **exactly these names** (must match workflow JSON):

| Credential Name | Type |
|---|---|
| `Telegram Bot` | Telegram API |
| `OpenRouter` | OpenRouter API |
| `Google AI` | Google PaLM API |
| `Anthropic API` | Anthropic API |
| `Supabase Postgres` | Postgres |
| `Gmail` | Gmail OAuth2 |
| `Evolution API` | HTTP Header Auth |

---

## Repository Structure

```
n8n-ecosystem-unified/
├── docker-compose.yml          # Full stack definition
├── setup.sh                    # Interactive installer (Proxmox LXC edition)
├── .env.example                # All environment variables documented
├── .gitignore
├── email-bridge/               # IMAP/SMTP REST microservice
│   ├── Dockerfile
│   ├── package.json
│   └── server.js
├── searxng/
│   └── settings.yml             # SearXNG engine config
├── supabase/
│   ├── kong.yml                 # Kong gateway template (run setup.sh to deploy)
│   └── migrations/
│       ├── 000_extensions.sql   # Roles + uuid-ossp
│       ├── 001_schema.sql       # Full schema (pgvector, all tables, RPC)
│       └── 002_seed.sql         # Default soul, agents, tools_config entries
├── workflows/
│   ├── freddy/                  # Upstream n8n-claw workflows (reference)
│   └── unified/                 # New unified workflows
│       ├── multi-channel-router.json
│       ├── tiered-model-router.json
│       └── email-manager.json
└── docs/
    ├── PROXMOX_SETUP.md         # Detailed LXC deployment guide
    └── CTI_SKILLS_ROADMAP.md    # Planned CTI skill workflows
```

---

## Architecture

```
[Telegram] ──┐
             ├──► [multi-channel-router] ──► {userMessage, chatId, userId, source}
[WhatsApp] ──┘                                        │
                                                       ▼
                                          [n8n-claw Agent (main)]
                                                       │
                                    ┌──────────────────┼──────────────────┐
                                    ▼                  ▼                  ▼
                          [Web Search]     [Expert Agent]        [CTI Tools]
                          [Crawl4AI]       [Tiered Router]       [MISP/Wazuh]
                          [Email Bridge]   Haiku/Sonnet/Opus     [OpenCTI]
                                                                  [TheHive]
                                    └──────────────────┼──────────────────┘
                                                       ▼
                                         [Response Router]
                                          /           \
                                   [Telegram]     [WhatsApp]
```

---

## Upgrading from n8n-claw

If you have an existing n8n-claw deployment:

1. Export your n8n-claw `.env` values
2. Run `setup.sh` in this repo — it generates new secrets but prompts for all credential values
3. Your existing Supabase data is **not affected** unless you drop and recreate the DB
4. The unified `001_schema.sql` adds 3 new tables (`email_log`, `channel_sessions`, `cti_events`) via `CREATE TABLE IF NOT EXISTS` — safe to run against an existing n8n-claw schema

---

## Credits

- **n8n-claw** by [@freddy-schuetz](https://github.com/freddy-schuetz/n8n-claw) / [JazenaYLA fork](https://github.com/JazenaYLA/n8n-claw) — core agent architecture
- **OpenCLAW** by Shabbir (n8n community) — multi-channel routing and tiered model patterns
- **Proxmox LXC adaptation** by [@JazenaYLA](https://github.com/JazenaYLA)
