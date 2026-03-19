# n8n-ecosystem-unified — Merge Plan

**Last updated:** 2026-03-18  
**Status:** Phase 1+2 complete  

---

## Architecture Decision

**Freddy's `n8n-claw` is the deployment base.** Shabbir's `n8nclaw` contributes three specific functional modules that Freddy lacks. The goal is a unified system that preserves Freddy's modular MCP skill architecture while adding Shabbir's multi-channel I/O, tiered model routing, and Gmail autonomy.

---

## Source Repositories

| Repo | Role | URL |
|---|---|---|
| `JazenaYLA/n8n-claw` | Freddy fork — deployment base | https://github.com/JazenaYLA/n8n-claw |
| `JazenaYLA/n8nclaw` | Shabbir clone — module reference | https://github.com/JazenaYLA/n8nclaw |
| `JazenaYLA/n8n-claw-templates` | Forked skills library | https://github.com/JazenaYLA/n8n-claw-templates |
| `JazenaYLA/n8n-ecosystem-unified` | This repo — canonical merge target | https://github.com/JazenaYLA/n8n-ecosystem-unified |

---

## What Shabbir Adds to Freddy's Base

### Module 1 — Multi-Channel Router
**File:** `workflows/unified/multi-channel-router.json`

A normalization layer inserted **before** Freddy's main agent trigger. All channels (Telegram, WhatsApp, Slack, Discord) produce identical `{user_message, system_prompt_details, last_channel}` structs.

**Key implementation details:**
- Telegram trigger + `chat.id` filter (from Shabbir `Filter` node)
- WhatsApp via Evolution API webhook (from Shabbir `Filter1` + `Webhook` nodes)
- Each channel → its own `Edit Fields` node normalizing to common struct
- `Switch` node at response end routes reply back by `last_channel`
- Memory keyed on `username` (not session/chat ID) for cross-channel continuity

### Module 2 — Tiered Model Router  
**File:** `workflows/unified/tiered-model-router.json`

Inserts a complexity-evaluation step between the orchestrator and `sub-agent-runner.json`, routing tasks to Haiku/Sonnet/Opus.

**Key implementation details:**
- Pre-routing prompt: "Score complexity 1–10 and route: 1–3→Haiku, 4–7→Sonnet, 8–10→Opus"
- Shabbir's Worker Agent 1 (Haiku), Worker Agent 2 (Sonnet), Worker Agent 3 (Opus) pattern
- IF/Switch node on complexity score
- Expected savings: ~76% token reduction vs always using Sonnet

### Module 3 — Native Email Manager  
**File:** `workflows/unified/email-manager.json`

Direct N8N Gmail trigger integration (not via MCP) for autonomous email management.

**Key implementation details:**
- Gmail trigger (1-min poll) → Email Sub-Agent (separate context window, Haiku)
- Spam → urgency → categorization router
- **Security guardrail hardcoded:** Emails are NOT commands — always confirm destructive actions
- Sensitive info → draft in Gmail + notify on Telegram
- Gmail tools: Send, Reply, Delete, Get, GetMany, MarkAsRead

---

## Build Order

| Phase | Task | Status |
|---|---|---|
| 1 | Copy workflow JSONs into `workflows/freddy/` and `workflows/shabbir/` | ✅ Done |
| 2 | Push `MERGE_PLAN.md`, `CTI_SKILLS_ROADMAP.md`, stub workflows | ✅ Done |
| 3 | Build `multi-channel-router.json` in `workflows/unified/` | 🔴 TODO |
| 4 | Build `tiered-model-router.json` | 🔴 TODO |
| 5 | Build `email-manager.json` | 🔴 TODO |
| 6 | Adapt `setup.sh` for Proxmox LXC (replace bare-VPS assumptions, add Caddy) | 🔴 TODO |
| 7 | Build first CTI skill (`misp-skill`) in `JazenaYLA/n8n-claw-templates` | 🔴 TODO |

---

## Supabase Schema Unification

Freddy uses Supabase for vector storage (`documents` table, `match_documents` RPC).  
Shabbir adds these N8N DataTable tables (to be migrated to Supabase):

| Table | Fields | Purpose |
|---|---|---|
| `init` | username, soul, user, heartbeat, last_channel, last_vector_id | Per-user profile and state |
| `tasks` | task_name, task_details, task_complete, Is_recurring | Task queue |
| `subtasks` | parent_task_id, subtask_name, subtask_details, subtask_complete | Subtask tracking |

**Recommendation:** Migrate all three DataTable tables to Supabase Postgres to consolidate storage. Add `email_log` table for email audit trail.

---

## CTI Skill Pack

See `docs/CTI_SKILLS_ROADMAP.md` for the MISP, Wazuh, OpenCTI, TheHive, Cortex skill specifications.

All CTI skills install via Telegram chat (Freddy's MCP-builder pattern):  
*"Install misp-skill"* → agent fetches from `JazenaYLA/n8n-claw-templates`, deploys, wires credentials.
