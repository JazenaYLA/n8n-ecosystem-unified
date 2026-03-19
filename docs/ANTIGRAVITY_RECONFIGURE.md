# Antigravity Reconfiguration Guide — n8n LXC

This document is the **instruction set for Antigravity (or any AI coding agent)**
to reconfigure the live n8n LXC after the infra stack has been updated.

**Last updated:** 2026-03-19  
**Status:** Ready to execute after infra-postgres migration

---

## Context

n8n was installed on its own Proxmox LXC using the community helper script:
```
bash -c "$(curl -fsSL https://github.com/community-scripts/ProxmoxVE/raw/main/ct/n8n.sh)"
```

This installs n8n as a **native systemd service** (no Docker). The configuration
lives entirely in one file: `/opt/n8n.env`

The systemd unit is at: `/etc/systemd/system/n8n.service`
The n8n data dir is at: `/.n8n/`
The current database is: `/.n8n/database.sqlite` (SQLite — **migration target: infra-postgres**)

---

## Current `/opt/n8n.env` State (as of investigation 2026-03-19)

```bash
N8N_SECURE_COOKIE=false
N8N_PORT=5678
N8N_PROTOCOL=http
N8N_HOST=<LXC_IP>   # set to LXC local IP at install time
```

These 4 lines are all that exists. Everything below must be **appended**.

---

## Step 1 — Pre-Migration Checklist

Before Antigravity touches `/opt/n8n.env`, verify:

```bash
# 1. infra-postgres is running on dockge-cti LXC
ssh dockge-cti "cd /opt/stacks/infra && docker compose ps postgres"

# 2. n8n database exists in infra-postgres
ssh dockge-cti "docker exec infra-postgres psql -U postgres -c '\\l' | grep n8n"

# 3. n8n LXC can reach infra-postgres
ssh n8n "nc -zv <DOCKGE_CTI_IP> 5432"

# 4. Export n8n backup from UI
# n8n UI -> Settings -> Export -> Download JSON
# Save as: n8n-backup-YYYYMMDD.json
```

---

## Step 2 — Variables to Read from infra/.env

Antigravity must SSH to the dockge-cti LXC and read these values:

```bash
ssh dockge-cti "grep -E 'N8N_DB_PASSWORD|POSTGRES_ROOT' /opt/stacks/infra/.env"
```

Capture:
- `N8N_DB_PASSWORD` → used as `DB_POSTGRESDB_PASSWORD`
- `DOCKGE_CTI_IP` → the IP of the dockge-cti LXC on the shared VLAN

---

## Step 3 — Full Target `/opt/n8n.env`

Antigravity should **replace** `/opt/n8n.env` with the following,
substituting `<PLACEHOLDER>` values from infra/.env and enterprise secrets:

```bash
# ── n8n Base (from helper script install — preserve these) ────
N8N_SECURE_COOKIE=false
N8N_PORT=5678
N8N_PROTOCOL=http
N8N_HOST=<N8N_LXC_IP>

# ── n8n Core Extensions ───────────────────────────────────────
WEBHOOK_URL=https://n8n.lab.local
N8N_ENCRYPTION_KEY=<generate: openssl rand -hex 32>
GENERIC_TIMEZONE=America/Chicago
N8N_LOG_LEVEL=info
N8N_RUNNERS_ENABLED=true
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
N8N_METRICS=true
N8N_AI_ENABLED=true
EXECUTIONS_PROCESS=main
EXECUTIONS_DATA_SAVE_ON_ERROR=all
EXECUTIONS_DATA_SAVE_ON_SUCCESS=none
EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true

# ── Database — infra-postgres on dockge-cti LXC ───────────────
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=<DOCKGE_CTI_LXC_IP>
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=<N8N_DB_PASSWORD from infra/.env>

# ── CTI Platform URLs ─────────────────────────────────────────
# These become n8n Variables — set them here for systemd env,
# then mirror them in n8n UI: Settings -> Variables
MISP_URL=https://misp.lab.local
OPENCTI_URL=https://opencti.lab.local
THEHIVE_URL=https://thehive.lab.local
CORTEX_URL=https://cortex.lab.local
WAZUH_URL=https://wazuh.lab.local:55000
FLOWISE_URL=https://flowise.lab.local
SEARXNG_URL=http://searxng.lab.local

# ── Messaging ─────────────────────────────────────────────────
TELEGRAM_BOT_TOKEN=<from enterprise secrets>
TELEGRAM_CHAT_ID=<from enterprise secrets>
EVOLUTION_API_URL=<from enterprise secrets or blank>
EVOLUTION_API_KEY=<from enterprise secrets or blank>
EVOLUTION_INSTANCE_NAME=<from enterprise secrets or blank>

# ── LLM Provider API Keys ─────────────────────────────────────
# Store here for systemd environment access by n8n workflows.
# Also create matching Credentials in n8n UI.
OPENROUTER_API_KEY=<from Infisical or enterprise secrets>
ANTHROPIC_API_KEY=<from Infisical or enterprise secrets>
GOOGLE_AI_API_KEY=<from Infisical or enterprise secrets>
OLLAMA_URL=<Ollama LXC or host IP:11434 or blank>
```

---

## Step 4 — Apply and Restart

```bash
# On n8n LXC as root
chmod 600 /opt/n8n.env
systemctl daemon-reload
systemctl restart n8n

# Monitor startup
journalctl -u n8n -f
# Look for: "n8n ready on 0.0.0.0, port 5678"
# If postgres connection fails, you will see DB connection error here
```

---

## Step 5 — Run DB Migrations on infra-postgres

From **dockge-cti LXC** (where infra-postgres runs):

```bash
# Clone or copy migration files to dockge-cti LXC
git clone https://github.com/JazenaYLA/n8n-ecosystem-unified.git /tmp/n8n-unified

# Run migrations against the n8n database
for sql in 000_extensions.sql 001_schema.sql 002_seed.sql; do
  echo "Applying: $sql"
  docker exec -i infra-postgres psql -U n8n -d n8n \
    < /tmp/n8n-unified/migrations/$sql
done
```

Or from the **n8n LXC** directly (if psql client is installed):

```bash
apt-get install -y postgresql-client

for sql in 000_extensions.sql 001_schema.sql 002_seed.sql; do
  psql -h <DOCKGE_CTI_LXC_IP> -U n8n -d n8n \
    -f /path/to/n8n-ecosystem-unified/migrations/$sql
done
```

> **Note:** `001_schema.sql` installs the `vector` extension and creates
> all application tables. This requires pgvector to be available in
> infra-postgres. The `postgres:17-alpine` image does NOT include pgvector
> by default — see Step 5a below.

### Step 5a — pgvector in infra-postgres

The current `infra/docker-compose.yml` uses `postgres:17-alpine` which
**does not include pgvector**. Two options:

**Option A — Switch image (recommended):**
Change `infra/docker-compose.yml`:
```yaml
# FROM:
image: postgres:17-alpine
# TO:
image: pgvector/pgvector:pg17
```
Then: `docker compose up -d postgres` on dockge-cti LXC.
Existing data is preserved (volume mount unchanged).

**Option B — Install pgvector at runtime:**
```bash
docker exec infra-postgres sh -c "
  apk add --no-cache git build-base clang llvm &&
  git clone https://github.com/pgvector/pgvector.git /tmp/pgvector &&
  cd /tmp/pgvector && make && make install"
docker exec infra-postgres psql -U postgres -d n8n -c 'CREATE EXTENSION IF NOT EXISTS vector;'
```
Option B is lost on container recreation. Option A is permanent.

---

## Step 6 — Verify Migration

```bash
# Check n8n is using Postgres (not SQLite)
curl -s http://localhost:5678/healthz
# Should return: {"status":"ok"}

# Check DB connection in n8n logs
journalctl -u n8n --since "5 minutes ago" | grep -i 'database\|postgres\|error'

# Verify tables were created
docker exec infra-postgres psql -U n8n -d n8n -c '\dt public.*'
# Should list: agents, soul, tools_config, conversations, memory_long, etc.
```

---

## Step 7 — Post-Migration n8n UI Configuration

After n8n boots on Postgres, configure via the UI:

1. **Create owner account** (first boot on fresh Postgres)
2. **Settings → API** → Create API key → save securely
3. **Settings → Variables** → Add all vars from Step 3
   (MISP_URL, FLOWISE_URL, SEARXNG_URL, TELEGRAM_CHAT_ID, etc.)
4. **Settings → Credentials** → Create all credentials
   (See `docs/N8N_CONFIGURATION.md` Step 3 for full credential list)
5. **Import workflows** from `workflows/unified/`

---

## Antigravity Task Summary

When asked to reconfigure the n8n LXC, Antigravity should:

1. SSH to dockge-cti LXC → read `N8N_DB_PASSWORD` from `infra/.env`
2. SSH to n8n LXC → verify postgres reachability (`nc -zv <DOCKGE_IP> 5432`)
3. Backup `/.n8n/database.sqlite`
4. Write the complete target `/opt/n8n.env` (Step 3 above) with real values
5. Run `systemctl daemon-reload && systemctl restart n8n`
6. Verify `journalctl -u n8n` shows successful Postgres connection
7. Run DB migrations from dockge-cti or n8n LXC (Step 5)
8. Report back: n8n URL, any errors, tables created

**Do NOT:**
- Install Docker on the n8n LXC (it uses native systemd)
- Modify `/etc/systemd/system/n8n.service` (only `/opt/n8n.env` changes)
- Run `npm install` or reinstall n8n (use `systemctl restart n8n` only)
- Commit real IPs, passwords, or API keys to this public repo

---

## infra-postgres Change Required

Before running migrations, the infra stack needs one change:

**File:** `threatlabs-cti-stack/infra/docker-compose.yml`  
**Change:** `image: postgres:17-alpine` → `image: pgvector/pgvector:pg17`

This is a **zero-downtime change** — existing volume data is preserved.
See `threatlabs-cti-stack` repo for the PR.
