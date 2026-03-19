# n8n Configuration Guide

Post-install configuration for the n8n LXC (systemd native install).
**Last updated:** 2026-03-19

---

## Current State vs Target State

| | Current (post helper-script install) | Target (after migration) |
|---|---|---|
| **Database** | SQLite at `/.n8n/database.sqlite` | PostgreSQL on infra-postgres |
| **Config file** | `/opt/n8n.env` (4 vars) | `/opt/n8n.env` (full config) |
| **Vector search** | Not available | pgvector via infra-postgres |
| **Memory tables** | Not available | Available after migrations |

---

## Step 1 — First Boot (SQLite, pre-migration)

1. Browse to `http://<N8N_LXC_IP>:5678`
2. Create owner account (email + strong password)
3. **Settings → API** → **Create API Key** → copy and store securely in Infisical
4. **Settings → Export** → Download backup JSON — save this before migrating to Postgres

---

## Step 2 — Migrate to infra-postgres

> **See `docs/ANTIGRAVITY_RECONFIGURE.md`** for the complete migration
> playbook including pre-checks, `/opt/n8n.env` full target content,
> connectivity tests, and the Antigravity task summary.

Short version — on the n8n LXC as root:

```bash
# Clone this repo
git clone https://github.com/JazenaYLA/n8n-ecosystem-unified.git /tmp/n8n-unified

# Run migration script (interactive — prompts for DB password and all URLs)
bash /tmp/n8n-unified/migrate-to-postgres.sh
```

The migration script:
- Tests connectivity to infra-postgres before making any changes
- Backs up `/.n8n/database.sqlite`
- Appends all DB + config vars to `/opt/n8n.env`
- Restarts n8n and verifies it comes up on Postgres

---

## Step 3 — Set n8n Variables

After migration, in n8n UI: **Settings → Variables → Add Variable**

Mirror these from `/opt/n8n.env` into n8n Variables so workflows
can access them via `$vars.VARIABLE_NAME`:

| Variable | Source | Notes |
|---|---|---|
| `MISP_URL` | `/opt/n8n.env` | e.g. `https://misp.lab.local` |
| `MISP_API_KEY` | Infisical / enterprise secrets | MISP → Administration → Auth Keys |
| `OPENCTI_URL` | `/opt/n8n.env` | |
| `OPENCTI_API_KEY` | Infisical | OpenCTI → Profile → API Access |
| `THEHIVE_URL` | `/opt/n8n.env` | |
| `THEHIVE_API_KEY` | Infisical | TheHive → Organisation → API Key |
| `CORTEX_URL` | `/opt/n8n.env` | |
| `CORTEX_API_KEY` | Infisical | |
| `WAZUH_URL` | `/opt/n8n.env` | e.g. `https://wazuh.lab.local:55000` |
| `WAZUH_USER` | Infisical | |
| `WAZUH_PASSWORD` | Infisical | |
| `FLOWISE_URL` | `/opt/n8n.env` | e.g. `https://flowise.lab.local` |
| `SEARXNG_URL` | `/opt/n8n.env` | e.g. `http://searxng.lab.local` |
| `OLLAMA_URL` | `/opt/n8n.env` | e.g. `http://<HOST>:11434` |
| `TELEGRAM_CHAT_ID` | Infisical | From `@userinfobot` |
| `EVOLUTION_INSTANCE_NAME` | Infisical | WhatsApp instance name |

---

## Step 4 — Create Credentials

**Settings → Credentials → New Credential**

Create each with the **exact name shown** — workflow JSONs reference credentials by name.

### Messaging
| Name | Type | Key Field |
|---|---|---|
| `Telegram Bot` | Telegram API | Bot Token from `/opt/n8n.env` |
| `Evolution API` | HTTP Header Auth | `apikey: <EVOLUTION_API_KEY>` |

### LLM Providers
| Name | Type | Notes |
|---|---|---|
| `Anthropic API` | Anthropic API | Claude models |
| `Google Gemini` | Google Gemini API | Gemini Flash/Pro |
| `OpenRouter` | HTTP Header Auth | `Authorization: Bearer <OPENROUTER_API_KEY>` |
| `OpenAI API` | OpenAI API | GPT-4o etc. |
| `Ollama Local` | OpenAI-compatible | Base URL: `http://<HOST>:11434/v1`, any placeholder key |
| `Mistral API` | HTTP Header Auth | `Authorization: Bearer <key>` |

### CTI Platforms
| Name | Type | Header |
|---|---|---|
| `MISP API` | HTTP Header Auth | `Authorization: <MISP_API_KEY>` |
| `OpenCTI API` | HTTP Header Auth | `Authorization: Bearer <key>` |
| `TheHive API` | HTTP Header Auth | `Authorization: Bearer <key>` |
| `Cortex API` | HTTP Header Auth | `Authorization: Bearer <key>` |
| `Wazuh API` | HTTP Request (basic auth) | User + Password |
| `Flowise API` | HTTP Header Auth | `Authorization: Bearer <key>` |

### Database
| Name | Type | Details |
|---|---|---|
| `n8n Postgres` | Postgres | Host: dockge-cti LXC IP, DB: `n8n`, User: `n8n` |

---

## Step 5 — Run DB Migrations

> **Prerequisites:** infra-postgres must be running `pgvector/pgvector:pg17`
> image (not `postgres:17-alpine`). See `docs/PROXMOX_SETUP.md`.

From **dockge-cti LXC** (where infra-postgres runs as a Docker container):

```bash
git clone https://github.com/JazenaYLA/n8n-ecosystem-unified.git /tmp/n8n-unified

for sql in 000_extensions.sql 001_schema.sql 002_seed.sql; do
  echo "Applying: $sql"
  docker exec -i infra-postgres psql -U n8n -d n8n \
    < /tmp/n8n-unified/migrations/$sql
done
```

Or from the **n8n LXC** with psql client:

```bash
apt-get install -y postgresql-client

for sql in 000_extensions.sql 001_schema.sql 002_seed.sql; do
  psql -h <DOCKGE_CTI_LXC_IP> -U n8n -d n8n \
    -f /tmp/n8n-unified/migrations/$sql
done
```

Verify tables were created:
```bash
docker exec infra-postgres psql -U n8n -d n8n -c '\dt public.*'
```

---

## Step 6 — Import Workflows

In n8n UI → **Workflows → Import from File**:

1. `workflows/unified/multi-channel-router.json`
2. `workflows/unified/tiered-model-router.json`
3. `workflows/unified/email-manager.json`
4. CTI skill workflows (from `n8n-claw-templates` when available)

After import, activate each workflow via the toggle in the workflow list.

---

## Step 7 — Tiered Model Router

| Tier | Score | Default Provider | Credential Name |
|---|---|---|---|
| Fast / Local | 1–3 | Ollama (local) | `Ollama Local` |
| Mid | 4–6 | Gemini Flash | `Google Gemini` |
| Heavy | 7–10 | Claude Sonnet | `Anthropic API` |

To use **OpenRouter** as a unified gateway for all tiers:
- Set all three tiers to `OpenRouter` credential
- Tier 1 model: `meta-llama/llama-3.1-8b-instruct:free`
- Tier 2 model: `google/gemini-flash-1.5`
- Tier 3 model: `anthropic/claude-sonnet-4-5`

---

## Useful Service Commands

```bash
# Check n8n status
systemctl status n8n

# View live logs
journalctl -u n8n -f

# View last 50 log lines
journalctl -u n8n -n 50 --no-pager

# Restart after env changes
systemctl daemon-reload && systemctl restart n8n

# Check current env
cat /opt/n8n.env

# Update n8n to latest version
bash -c "$(curl -fsSL https://github.com/community-scripts/ProxmoxVE/raw/main/ct/n8n.sh)" -- --update
```
