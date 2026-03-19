# Cleanup Guide — Removed Files

This document records files that existed in this repo prior to the
March 2026 refactor and explains why they were removed or moved.

**Last updated:** 2026-03-19

---

## Removed Files

### `supabase/kong.yml`
**Removed.** This was the Kong API gateway config used to route
`/rest/v1` to PostgREST in the old self-hosted Supabase stack.
Kong is no longer part of this project. PostgREST now runs as
`infra-postgrest` in the CTI LXC `infra` stack and is accessed
directly at `http://postgrest.lab.local`.

### `supabase/` folder (as a Supabase-specific path)
**Removed.** The `supabase/` folder name implied Supabase dependency.
SQL migrations have been moved to `migrations/` with Supabase-specific
roles (`supabase_admin`) stripped out. The target database is now
`infra-postgres` (pgvector image) on the CTI LXC, not the Supabase
Postgres image.

### Old `docker-compose.yml` services removed
| Service | Image | Reason |
|---|---|---|
| `db` | `supabase/postgres:15.8.1.085` | Replaced by `infra-postgres` on CTI LXC |
| `rest` | `postgrest/postgrest:v14.5` | Replaced by `infra-postgrest` on CTI LXC |
| `kong` | `kong:2.8.1` | API gateway no longer needed |
| `studio` | `supabase/studio` | Replaced by `infra-pgadmin` on CTI LXC |
| `meta` | `supabase/postgres-meta` | Only needed by Studio |
| `searxng` | `searxng/searxng` | Moved to separate Dockge stack on SearXNG LXC |

### `setup.sh` (old)
**Rewritten.** The old `setup.sh` generated Supabase JWT keys, deployed
Kong, and wrote Supabase-specific variables. The new version generates
only n8n secrets, writes the correct `.env` for `infra-postgres`,
and points users to the separate Flowise and SearXNG setup docs.

---

## Moved Files

### `supabase/migrations/*.sql` → `migrations/*.sql`
- `supabase/migrations/000_extensions.sql` → `migrations/000_extensions.sql`
  - Removed `supabase_admin` role creation
  - Simplified to only uuid-ossp, vector, and PostgREST anon roles
- `supabase/migrations/001_schema.sql` → `migrations/001_schema.sql`
  - Removed `supabase_admin` role creation and all `supabase_admin` grants
  - All grants now target `n8n` user (actual DB owner in infra-postgres)
  - All `CREATE TABLE` statements converted to `CREATE TABLE IF NOT EXISTS`
- `supabase/migrations/002_seed.sql` → `migrations/002_seed.sql`
  - Rewritten with CTI-appropriate defaults
  - All inserts use `ON CONFLICT DO NOTHING` for idempotency

---

## Files That Remain But Were NOT Removed by Mistake

### `searxng/` folder
This folder remains in the repo. It contains `settings.yml` which
`setup.sh` updates with the generated secret key. When deploying
SearXNG as a standalone Dockge stack, copy this folder's content
into the SearXNG LXC stack directory.

### `email-bridge/` folder
Remains — this is the IMAP/SMTP REST microservice still used by n8n.

### `workflows/` folder
Remains — all n8n workflow JSON files live here.
