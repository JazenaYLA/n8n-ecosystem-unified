# n8n Configuration Guide

Post-install configuration steps for n8n inside the unified stack.
**Last updated:** 2026-03-19

---

## Step 1 — First Boot

1. Browse to `http://<N8N_LXC_IP>:5678`
2. Create owner account (email + strong password)
3. **Settings → API** → **Create API Key** → copy and store securely

---

## Step 2 — Set n8n Variables

**Settings → Variables → Add Variable** for each:

| Variable | Example Value | Notes |
|---|---|---|
| `POSTGREST_URL` | `http://postgrest.lab.local` | PostgREST REST API |
| `N8N_POSTGREST_JWT_SECRET` | `<from infra/.env>` | Same value as CTI infra stack |
| `MISP_URL` | `https://misp.lab.local` | |
| `MISP_API_KEY` | `<key>` | MISP → Administration → Auth Keys |
| `OPENCTI_URL` | `https://opencti.lab.local` | |
| `OPENCTI_API_KEY` | `<key>` | OpenCTI → Profile → API Access |
| `THEHIVE_URL` | `https://thehive.lab.local` | |
| `THEHIVE_API_KEY` | `<key>` | TheHive → Organisation → API Key |
| `CORTEX_URL` | `https://cortex.lab.local` | |
| `CORTEX_API_KEY` | `<key>` | Cortex → Organisation → API Key |
| `WAZUH_URL` | `https://wazuh.lab.local:55000` | |
| `WAZUH_USER` | `wazuh` | |
| `WAZUH_PASSWORD` | `<password>` | |
| `FLOWISE_URL` | `https://flowise.lab.local` | |
| `SEARXNG_URL` | `http://searxng:8888` | Internal Docker name |
| `TELEGRAM_CHAT_ID` | `<id>` | From `@userinfobot` on Telegram |
| `EVOLUTION_INSTANCE_NAME` | `<instance>` | WhatsApp Evolution API |
| `OLLAMA_URL` | `http://<PROXMOX_HOST_IP>:11434` | If running Ollama on host |

---

## Step 3 — Create Credentials

**Settings → Credentials → New Credential**

Create each with the **exact name shown** — workflow JSONs reference credentials by name.

### Messaging
| Name | Type | Key Field |
|---|---|---|
| `Telegram Bot` | Telegram API | Bot Token |
| `Evolution API` | HTTP Header Auth | `apikey: <key>` |

### LLM Providers
| Name | Type | Notes |
|---|---|---|
| `Anthropic API` | Anthropic API | Claude models |
| `Google Gemini` | Google Gemini API | Gemini Flash/Pro |
| `OpenRouter` | HTTP Header Auth | `Authorization: Bearer sk-or-...` |
| `OpenAI API` | OpenAI API | GPT-4o etc. |
| `Ollama Local` | HTTP Request (no auth) | Base URL: `http://<HOST>:11434` |
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

### Database & Email
| Name | Type | Details |
|---|---|---|
| `n8n Postgres` | Postgres | Host: CTI_LXC_IP, DB: n8n, User: n8n |
| `Gmail OAuth2` | Gmail OAuth2 | Client ID + Secret |
| `Stalwart Mail` | IMAP + SMTP | Host: mail.lab.local |

---

## Step 4 — Run DB Migrations

From the **CTI LXC terminal**:

```bash
# Run all three migration files against infra-postgres n8n database
for sql in 000_extensions.sql 001_schema.sql 002_seed.sql; do
  docker exec -i infra-postgres psql -U n8n -d n8n \
    < /path/to/n8n-ecosystem-unified/supabase/migrations/$sql
  echo "Applied: $sql"
done
```

Or from within n8n using an **Execute Command** node (if the migration
files are accessible from the n8n LXC):

```bash
psql -h <CTI_LXC_IP> -U n8n -d n8n -f /opt/stacks/n8n-unified/supabase/migrations/000_extensions.sql
psql -h <CTI_LXC_IP> -U n8n -d n8n -f /opt/stacks/n8n-unified/supabase/migrations/001_schema.sql
psql -h <CTI_LXC_IP> -U n8n -d n8n -f /opt/stacks/n8n-unified/supabase/migrations/002_seed.sql
```

---

## Step 5 — Import Workflows

In n8n UI → **Workflows → Import from File**, import in this order:

1. `workflows/unified/multi-channel-router.json`
2. `workflows/unified/tiered-model-router.json`
3. `workflows/unified/email-manager.json`
4. `workflows/unified/cti/misp-ioc-lookup.json` (when available)
5. Any templates from `n8n-claw-templates` repo

After import, activate each workflow using the toggle in the workflow list.

---

## Step 6 — Tiered Model Router Configuration

The tiered model router supports any combination of providers.
Edit the `tiered-model-router.json` workflow's **Switch** node to point
to your preferred credential names for each tier:

| Tier | Score | Default Provider | Credential Name |
|---|---|---|---|
| Fast / Local | 1–3 | Ollama (local) | `Ollama Local` |
| Mid | 4–6 | Gemini Flash or Haiku | `Google Gemini` |
| Heavy | 7–10 | Claude Sonnet or GPT-4o | `Anthropic API` |

To use **OpenRouter** as a unified gateway for all tiers instead:
- Point all three tiers to `OpenRouter` credential
- Set the model name per tier in the HTTP Request body:
  - Tier 1: `meta-llama/llama-3.1-8b-instruct:free`
  - Tier 2: `google/gemini-flash-1.5`
  - Tier 3: `anthropic/claude-sonnet-4-5`

---

## Ollama Setup (Optional — Local LLM)

If you want a fully local LLM tier, install Ollama on the Proxmox host
or a dedicated VM:

```bash
# On Proxmox host (or separate LXC/VM)
curl -fsSL https://ollama.ai/install.sh | sh

# Pull a model
ollama pull llama3.2
ollama pull nomic-embed-text  # for embeddings

# Verify API
curl http://localhost:11434/api/tags
```

In n8n Variables, set `OLLAMA_URL=http://<HOST_IP>:11434`.
Ollama is compatible with n8n's **OpenAI-compatible** credential type —
use base URL `http://<HOST_IP>:11434/v1` with any placeholder API key.
