# YAOC2 Communications Guard — Boundary with n8n-unified

This document explains the division of responsibility between `n8n-ecosystem-unified`
and `YAOC2` for communications channel readiness checking.

**Last updated:** 2026-03-24

---

## TL;DR

> For direct chat workflows in `n8n-unified`, keep env checks minimal — a missing
> credential will surface as a node error, which is acceptable for interactive use.
>
> For agentic/gateway workflows in `YAOC2`, all channel readiness checks are
> **delegated to the YAOC2 capability guard**. Do not duplicate that logic here.

---

## What Each System Owns

| System | Communications role | Guard pattern |
|---|---|---|
| `n8n-ecosystem-unified` | Direct chat: Telegram bot replies, WhatsApp replies via Evolution, multi-channel router | Minimal — n8n node errors surface misconfiguration |
| `YAOC2 gateway` | Agentic outbound: approval requests, capability-missing alerts, LLM calls, tool results | Full capability guard — structured `{status:ok/missing}`, audit log, operator Telegram alert |

---

## Why n8n-unified Doesn’t Need the Full Guard

In `n8n-unified`, the multi-channel router and direct reply workflows are:
- **Operator-triggered** or **user-triggered** in real time
- If Telegram is misconfigured, the workflow errors immediately and the operator sees it
- Recovery is manual and immediate (fix the credential, rerun)

In `YAOC2`, the gateway runs **autonomously**:
- An AI agent submits a ProposedAction; no human is watching
- A silent failure on Telegram send means the operator never sees the approval request
- The guard converts that into an explicit, logged, alerted failure state

---

## When to Apply the Guard to n8n-unified

Consider adding the YAOC2 guard pattern to `n8n-unified` workflows if:

1. You add **unattended/scheduled** workflows that send to Telegram or WhatsApp autonomously.
2. You integrate `n8n-unified` as a sub-system called by YAOC2 (it then inherits YAOC2's guard context).
3. An enterprise deployment requires **audit trail** for all outbound comms, even direct chat.

The guard workflows are fully reusable: import `yaoc2-capability-guard-comms.json`
and `yaoc2-onboarding-capability.json` into the `n8n-unified` instance and wire them
before any outbound node. The CHECKS registry, audit logging, and Telegram alerting
are identical — no changes to the guard itself needed.

---

## Enterprise Deployment Note

For the **enterprise Threat Intel branch**, channel readiness checks for all
agentic actions MUST go through the YAOC2 capability guard. The `n8n-unified`
multi-channel router handles direct user-facing comms and is out of scope for
the guard unless the branch explicitly extends it.

See:
- [YAOC2/docs/ANTIGRAVITY_COMMUNICATIONS_GUARD.md](https://github.com/JazenaYLA/YAOC2/blob/main/docs/ANTIGRAVITY_COMMUNICATIONS_GUARD.md) — enterprise integration rules
- [YAOC2/docs/CAPABILITY_ONBOARDING.md](https://github.com/JazenaYLA/YAOC2/blob/main/docs/CAPABILITY_ONBOARDING.md) — full CHECKS registry and onboarding pattern
- [YAOC2/docs/ANTIGRAVITY_RECONFIGURE.md](https://github.com/JazenaYLA/YAOC2/blob/main/docs/ANTIGRAVITY_RECONFIGURE.md) — Step 6b: import order for guard workflows
