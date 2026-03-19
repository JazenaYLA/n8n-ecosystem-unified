# Setup Checklist — n8n LXC Platform

> **Last updated:** 2026-03-19  
> **Covers:** n8n-ecosystem-unified + YAOC2 brain workflow + infra-postgres migration  
> **Antigravity shortcut:** See `docs/ANTIGRAVITY_RECONFIGURE.md`

---

## 🔴 Phase 1 — dockge-cti LXC (do first)

### 1. Pull & recreate infra-postgres with pgvector image

The `pgvector/pgvector:pg17` image change is already committed to `threatlabs-cti-stack`.
On the dockge-cti LXC, wherever Dockge manages the infra stack (typically `/opt/stacks/infra`):

```bash
cd /opt/stacks/infra
docker compose pull postgres
docker compose up -d postgres
```

Verify pgvector is available (not just postgres version):

```bash
docker exec infra-postgres psql -U postgres -c \
  'CREATE EXTENSION IF NOT EXISTS vector; SELECT extversion FROM pg_extension WHERE extname = '"'"'vector'"'"';'
# Expected: a version string like 0.8.0
```

### 2. Note your credentials from infra/.env

```bash
grep -E 'N8N_DB_PASSWORD|POSTGRES_ROOT|DOCKGE' /opt/stacks/infra/.env
```

Capture:
- `N8N_DB_PASSWORD` — needed for Phase 2
- dockge-cti LXC IP — needed for Phase 2 + 3

---

## 🟡 Phase 2 — n8n LXC (choose Path A or B, not both)

### 3. Export n8n backup FIRST

n8n UI → **Settings → Export** → Download JSON.  
Save as `n8n-backup-YYYYMMDD.json` before touching anything.

### Path A — Automated (recommended): run the migration script

This handles `/opt/n8n.env` rewrite, systemd restart, AND runs the three SQL migrations.
**If you use Path A, skip Phase 3 entirely.**

```bash
git clone https://github.com/JazenaYLA/n8n-ecosystem-unified.git /tmp/n8n-unified
bash /tmp/n8n-unified/migrate-to-postgres.sh
```

The script prompts for: dockge-cti IP, `N8N_DB_PASSWORD`, CTI URLs, Telegram tokens, LLM keys.  
It tests connectivity, backs up SQLite, writes `/opt/n8n.env`, restarts n8n, runs SQL migrations.

### Path B — Manual: write /opt/n8n.env yourself

If you prefer full control, follow `docs/ANTIGRAVITY_RECONFIGURE.md` Steps 3–4 to write
`/opt/n8n.env` manually, then proceed to Phase 3 to run SQL migrations separately.

---

## 🟡 Phase 3 — DB Migrations (from dockge-cti LXC)

**Skip this phase if you used Path A in Phase 2.**

### 4. Run n8n-unified SQL migrations

> ⚠️ `000_extensions.sql` requires superuser (`postgres`). `001` and `002` run as `n8n` user.

```bash
git clone https://github.com/JazenaYLA/n8n-ecosystem-unified.git /tmp/n8n-unified

# Extensions — must run as postgres superuser
docker exec -i infra-postgres psql -U postgres -d n8n \
  < /tmp/n8n-unified/migrations/000_extensions.sql

# Schema + seed — run as n8n user
docker exec -i infra-postgres psql -U n8n -d n8n \
  < /tmp/n8n-unified/migrations/001_schema.sql

docker exec -i infra-postgres psql -U n8n -d n8n \
  < /tmp/n8n-unified/migrations/002_seed.sql
```

### 5. Run YAOC2 schema migration

This is a separate migration that creates the `yaoc2` schema, policy sets, audit log,
and conversation memory tables. Must run as `postgres` superuser (creates extensions + roles).

```bash
git clone https://github.com/JazenaYLA/YAOC2.git /tmp/yaoc2

docker exec -i infra-postgres psql -U postgres \
  < /tmp/yaoc2/infra/migrations/000_yaoc2_schema.sql
```

Verify:
```bash
docker exec infra-postgres psql -U postgres -c \
  '\dn' | grep yaoc2
# Should show: yaoc2 schema

docker exec infra-postgres psql -U postgres -c \
  '\dt yaoc2.*'
# Should show: audit_log, conversation_memory, policy_sets
```

---

## 🟢 Phase 4 — n8n UI (after Postgres migration)

### 6. First boot setup

- Create owner account
- **Settings → API** → Create API key → store in Infisical

### 7. Settings → Variables

Set all CTI platform URLs, Telegram Chat ID, Ollama URL etc.  
Full list: [`docs/N8N_CONFIGURATION.md` Step 3](https://github.com/JazenaYLA/n8n-ecosystem-unified/blob/main/docs/N8N_CONFIGURATION.md)

Also add these YAOC2-specific variables:

| Variable | Value |
|---|---|
| `GATEWAY_WEBHOOK_URL` | `https://n8n-gateway.lab.local` |
| `GATEWAY_WEBHOOK_SECRET` | Generate: `openssl rand -hex 32` |
| `APPROVAL_CHAT_ID` | Your Telegram analyst chat ID |

### 8. Settings → Credentials

Create all credentials — exact names matter as workflows reference by name:
- MISP, OpenCTI, TheHive, Cortex, Wazuh, Flowise
- All LLM providers (OpenRouter, Anthropic, Google AI, Ollama)
- Telegram Bot
- infra-postgres (host: dockge-cti IP, port: 5432, DB: postgres, user: yaoc2, schema: n8n_gateway)
- Gateway Webhook Secret (HTTP Header Auth)

Full credential list: [`docs/N8N_CONFIGURATION.md` Step 3](https://github.com/JazenaYLA/n8n-ecosystem-unified/blob/main/docs/N8N_CONFIGURATION.md)

### 9. Import workflows — ORDER MATTERS

Sub-workflows must exist before the workflows that call them:

```
1. [UNIFIED] Tiered Model Router          ← first (called by all agents)
2. [UNIFIED] Multi-Channel Router
3. [UNIFIED] Email Manager
4. [YAOC2] Brain — OpenClaw Agent         ← last (calls all above)
```

Workflow files:
- `workflows/unified/` — this repo
- `n8n/brain/workflows/` — YAOC2 repo

---

## 🔵 Phase 5 — YAOC2 Gateway (on dockge-cti LXC via Dockge)

### 10. Deploy the gateway Dockge stack

```bash
# Copy stack files to Dockge stacks directory
cp -r /tmp/yaoc2/infra/dockge/yaoc2-gateway /opt/stacks/

# Edit .env
cp /opt/stacks/yaoc2-gateway/.env.example /opt/stacks/yaoc2-gateway/.env
nano /opt/stacks/yaoc2-gateway/.env
```

Then in Dockge UI: **Compose Up** on `yaoc2-gateway`.

### 11. Import gateway workflow

In the gateway n8n instance (`https://n8n-gateway.lab.local`):
1. Import `n8n/gateway/workflows/yaoc2-policy-gateway.json` from YAOC2 repo
2. Replace all `REPLACE_*` credential placeholders
3. Activate the workflow

---

## 🤖 Alternative — Hand to Antigravity

Skip Phases 2–3 manually by telling Antigravity:

> *"Follow `docs/ANTIGRAVITY_RECONFIGURE.md` in `n8n-ecosystem-unified`. Read `N8N_DB_PASSWORD` from `infra/.env` on the dockge-cti LXC, reconfigure the n8n LXC, run all DB migrations including YAOC2, and report back."*

---

## Blocking Items at a Glance

| Item | Status |
|---|---|
| infra pgvector image committed | ✅ Ready — just needs `docker compose up -d postgres` |
| n8n DB + user in infra-postgres | ✅ Already created by `init-dbs.sh` |
| YAOC2 schema migration committed | ✅ In YAOC2 repo `infra/migrations/` |
| YAOC2 brain workflow committed | ✅ In YAOC2 repo `n8n/brain/workflows/` |
| YAOC2 gateway workflow committed | ✅ In YAOC2 repo `n8n/gateway/workflows/` |
| Port 5432 reachable from n8n LXC | ⚠️ Verify: `nc -zv <DOCKGE_CTI_IP> 5432` |
| n8n SQLite backup exported | 🔴 Not done |
| `/opt/n8n.env` Postgres migration | 🔴 Not done |
| n8n-unified DB schema migrations | 🔴 Not done |
| YAOC2 schema migration applied | 🔴 Not done |
| n8n UI Variables + Credentials | 🔴 Not done |
| YAOC2 gateway workflow imported + active | 🔴 Not done |
| YAOC2 brain workflow imported + active | 🔴 Not done |
| YAOC2 sandbox workflows imported | 🔴 Not done |
