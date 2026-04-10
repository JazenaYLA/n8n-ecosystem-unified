# n8n-ecosystem-unified

A self-hosted n8n AI agent and CTI automation stack for **Proxmox VE homelabs**.
Designed to integrate natively with [threatlabs-cti-stack](https://github.com/JazenaYLA/threatlabs-cti-stack).

n8n is installed as a **native systemd service** on a dedicated LXC using the
[Proxmox community helper script](https://github.com/community-scripts/ProxmoxVE/blob/main/ct/n8n.sh).
This repo provides configuration guides, migration scripts, and workflow files —
not a Docker deployment.

---

## Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│  PROXMOX VE HOST                                                 │
│                                                                  │
│  ┌─────────────┐  ┌──────────────────────┐  ┌───────────────┐  │
│  │  caddy LXC  │  │    dockge-cti LXC    │  │   n8n LXC     │  │
│  │             │  │  (threatlabs-cti)    │  │               │  │
│  │ :80/:443    │  │                      │  │  systemd n8n  │  │
│  │ *.lab.local │  │  infra-postgres:5432 │  │  :5678        │  │
│  │             │  │  infra-valkey:6379   │◄─┤               │  │
│  └──────┬─────┘  │  es7/es8             │  │  /opt/n8n.env │  │
│         │         │                      │  └───────────────┘  │
│         │         │  misp, opencti       │                      │
│         │         │  thehive, dfir-iris  │  ┌───────────────┐  │
│         │         │  flowintel, lacus    │  │  flowise LXC  │  │
│         │         └──────────────────────┘  │  systemd      │  │
│         │                                    │  :3000        │  │
│         │                                    └───────────────┘  │
│         │                                    ┌───────────────┐  │
│         │                                    │  wazuh LXC    │  │
│         │                                    │  + forgejo    │  │
│         │                                    │  + others     │  │
│         │                                    └───────────────┘  │
│                                                                  │
│  DNS: *.lab.local CNAMEs → caddy.lab.local (single A record)    │
└───────────────────────────────────────────────────────────────────┘
```

**Integration model:** n8n workflows call CTI tools over HTTP API using
`*.lab.local` Caddy domain names. All cross-LXC communication is via
HTTP/REST. n8n connects directly to `infra-postgres` on the dockge-cti
LXC over port 5432 on the shared VLAN.

---

## Architecture & Integration with YAOC2

`n8n-ecosystem-unified` is the **shared AI platform**: a collection of generic n8n workflows that
provide multi-channel routing, tiered model selection, and autonomous agents. It is designed to be
**YAOC2-agnostic** but plugs into the [YAOC2](https://github.com/JazenaYLA/YAOC2) gateway via a
small, well-defined contract.

### Layers in This Repo

**1. Core Engine (`workflows/freddy/`)**

Upstream n8n-claw engine workflows: main orchestrator agent, sub-agent runner, MCP builder/client,
memory consolidation, workflow builder, etc. These flows are generic and must not contain
YAOC2-specific logic.

**2. Multi-Channel + Monolith Reference (`workflows/shabbir/`)**

`shabbir/n8nClaw.json` — Shabbir's monolithic multi-channel workflow (Telegram + WhatsApp + Email +
Heartbeat + multiple worker agents). Kept as a reference; not directly modified.

**3. Unified Custom Layer (`workflows/unified/`)**

| Workflow | Purpose |
|---|---|
| `unified/multi-channel-router.json` | Receives Telegram/WhatsApp (and future Discord/Slack), normalises them into `{ userMessage, chatId, userId, source }`, calls the Tiered Model Router, and routes responses back to the correct channel. |
| `unified/tiered-model-router.json` | Routes tasks to Claude Haiku/Sonnet/Opus by complexity score (1–10). All three agents share Window Buffer memory, SearXNG web search, and YAOC2 MCP tools. |
| `unified/email-manager.json` | Polls unread Gmail, classifies emails, replies/drafts/deletes under strict security guardrails, logs to Supabase. |

### How This Repo Integrates with YAOC2

**Ingress**

[YAOC2](https://github.com/JazenaYLA/YAOC2) Receptionists forward normalised messages to a Brain
workflow that calls `unified/multi-channel-router.json` (or a YAOC2-specific wrapper around it).

Message envelope shape from YAOC2 Receptionists:

```json
{
  "userMessage": "string",
  "chatId": "string",
  "userId": "string",
  "source": "telegram|whatsapp|discord|slack",
  "metadata": { "raw": { "...": "..." } }
}
```

**Reasoning Output**

The Tiered Model Router produces `{ output, tier, complexity }`. For YAOC2, an additional
"intent → ProposedAction mapper" workflow (kept in the YAOC2 repo) converts this output into a full
`ProposedAction` object for the Policy Gateway.

**Tools (MCP)**

The Brain's agents call YAOC2-controlled CTI tools only via MCP:

- MCP endpoint: `https://gateway.lab.threatresearcher.net/rest/mcp/sse`
- Auth: `Authorization: Bearer {{ $env.GATEWAY_MCP_TOKEN }}`
- Store the token in `/opt/n8n.env` on the Brain LXC; rotate via Infisical.
- From this repo's perspective these are generic virtual tools (`misp_enrich`, `opencti_sync`, etc.).
  The actual implementations live as sandbox workflows in the YAOC2 repo.

**Design Principles**

- This repo is **reusable and product-agnostic** — no YAOC2-specific URLs, policy sets, or CTI details are hardcoded here.
- All secrets (OpenRouter API keys, MCP JWTs, Supabase keys, Gmail credentials, Telegram IDs) must be pulled from environment variables or a secret manager, never committed to git.
- Product-specific behaviour (e.g., what to do with an IOC enrichment request) belongs in the YAOC2 repo, not here.

---

## Repo Contents

| Path | Purpose |
|---|---|
| `migrate-to-postgres.sh` | Interactive migration script — moves n8n from SQLite to infra-postgres |
| `migrations/` | SQL migration files run against infra-postgres after migration |
| `workflows/unified/` | n8n workflow JSON files ready to import |
| `docs/ANTIGRAVITY_RECONFIGURE.md` | **Full playbook for automated reconfiguration** |
| `docs/PROXMOX_SETUP.md` | LXC install guide for all services |
| `docs/N8N_CONFIGURATION.md` | Post-install n8n configuration (Variables, Credentials, migrations) |
| `docs/FLOWISE_SETUP.md` | Flowise LXC setup and n8n integration |
| `docs/CADDY_ROUTES.md` | Caddy reverse proxy routes for `*.lab.local` |
| `docs/SEARXNG_SETUP.md` | SearXNG private search setup |
| `docs/COMPARISON.md` | n8n-claw vs OpenClaw feature comparison |

---

## Current State vs Target State

| | Current (post helper-script install) | Target (after migration) |
|---|---|---|
| **Database** | SQLite at `/.n8n/database.sqlite` | PostgreSQL on infra-postgres |
| **Config** | `/opt/n8n.env` (4 vars) | `/opt/n8n.env` (full config) |
| **Vector search** | Not available | pgvector via infra-postgres |
| **n8n memory** | Not available | Available after DB migrations |

---

## Quick Start

### Prerequisites

- Proxmox VE host with `threatlabs-cti-stack` running on a dockge-cti LXC
- `infra` stack running (`infra-postgres` healthy) — see [threatlabs-cti-stack](https://github.com/JazenaYLA/threatlabs-cti-stack)
- n8n LXC already installed via helper script (see below)
- Caddy LXC running with `*.lab.local` DNS

### Step 1 — Install n8n LXC (if not already done)

On Proxmox host shell:

```bash
bash -c "$(curl -fsSL https://github.com/community-scripts/ProxmoxVE/raw/main/ct/n8n.sh)"
```

Recommended: 4GB RAM, 4 cores, 20GB disk, unprivileged, same VLAN as dockge-cti.

After install, n8n is immediately available at `http://<N8N_LXC_IP>:5678`
using SQLite. You can use it in this state indefinitely.

### Step 2 — First Boot (SQLite mode)

1. Browse to `http://<N8N_LXC_IP>:5678`
2. Create owner account
3. **Settings → API** → Create API Key → store in Infisical
4. **Settings → Export** → Download backup JSON (save before migration)

### Step 3 — Update infra-postgres to pgvector (on dockge-cti LXC)

This is a **one-time change** to enable n8n vector/memory features.
Existing data is preserved.

```bash
# On dockge-cti LXC — in threatlabs-cti-stack/infra/
# The docker-compose.yml already has the pgvector image.
# If infra-postgres is running, recreate it:
docker compose up -d postgres
```

Verify:
```bash
docker exec infra-postgres psql -U postgres -c 'SELECT version();'
# Should show PostgreSQL 17 from pgvector/pgvector:pg17
```

### Step 4 — Migrate n8n to Postgres (on n8n LXC)

```bash
# On n8n LXC as root
git clone https://github.com/JazenaYLA/n8n-ecosystem-unified.git /tmp/n8n-unified
bash /tmp/n8n-unified/migrate-to-postgres.sh
```

The script prompts for:
- dockge-cti LXC IP
- `N8N_DB_PASSWORD` (from `infra/.env` on dockge-cti)
- All CTI platform URLs
- Messaging tokens, LLM API keys

It tests connectivity, backs up SQLite, writes `/opt/n8n.env`, and restarts n8n.

### Step 5 — Run DB Migrations (on dockge-cti LXC)

```bash
git clone https://github.com/JazenaYLA/n8n-ecosystem-unified.git /tmp/n8n-unified
for sql in 000_extensions.sql 001_schema.sql 002_seed.sql; do
  docker exec -i infra-postgres psql -U n8n -d n8n \
    < /tmp/n8n-unified/migrations/$sql
done
```

### Step 6 — Configure n8n UI

See `docs/N8N_CONFIGURATION.md` for:
- Variables to set (CTI URLs, Telegram ID, etc.)
- Credentials to create (MISP, OpenCTI, TheHive, Cortex, LLM providers)
- Workflow import order

### Step 7 — Add Caddy Routes + DNS

See `docs/CADDY_ROUTES.md` for route config.

In UniFi (or router) local DNS:
```
n8n.lab.local      CNAME  caddy.lab.local
flowise.lab.local  CNAME  caddy.lab.local
searxng.lab.local  CNAME  caddy.lab.local
```

---

## Automated Reconfiguration (Antigravity)

For automated agent-driven reconfiguration, see
**`docs/ANTIGRAVITY_RECONFIGURE.md`** — a complete step-by-step playbook
that any AI coding agent (Antigravity, Copilot, etc.) can follow to:

- Read live credentials from dockge-cti LXC `infra/.env`
- Write the complete target `/opt/n8n.env` on the n8n LXC
- Apply DB migrations
- Verify and report

---

## Multi-LLM Support

The stack is **LLM-agnostic**. All model calls route through n8n credentials.

| Provider | Type | Mode |
|---|---|---|
| **Ollama** | OpenAI-compatible | Local (Proxmox host or LXC) |
| **Google Gemini** | Gemini API | Cloud |
| **Anthropic Claude** | Anthropic API | Cloud |
| **OpenRouter** | HTTP Header Auth | Cloud (multi-model gateway) |
| **OpenAI** | OpenAI API | Cloud |
| **Mistral** | HTTP Header Auth | Cloud |

The **Tiered Model Router** workflow selects model by task complexity
(score 1–10): Haiku ≤3, Sonnet 4–7, Opus ≥8. Complexity is derived
automatically from task keywords if not provided explicitly.

---

## Flowise Integration

Flowise runs on a dedicated LXC (native Node.js, no Docker) and integrates
with n8n at three points:

1. **n8n → Flowise** — complex queries forwarded to Flowise chatflows
2. **CTI document RAG** — Flowise ingests threat reports into pgvector
3. **Flowise → n8n webhooks** — Flowise triggers n8n workflows

See `docs/FLOWISE_SETUP.md`.

---

## Related Repositories

| Repo | Purpose |
|---|---|
| [threatlabs-cti-stack](https://github.com/JazenaYLA/threatlabs-cti-stack) | CTI platform stack — hosts infra-postgres and all CTI tools |
| [YAOC2](https://github.com/JazenaYLA/YAOC2) | Policy-governed CTI bridge built on top of this platform |
| [n8n-claw-templates](https://github.com/JazenaYLA/n8n-claw-templates) | n8n MCP skill template library (CTI + general) |

---

## Credits

Original project by [@JazenaYLA](https://github.com/JazenaYLA).
MCP skill pattern inspired by the broader n8n community.
