# YAOC2 Gateway Workflows

All 7 n8n workflows running on the **gateway LXC** (`n8n.lab.threatresearcher.net:5678`).

## Architecture

```
[Telegram Trigger] ──┐
                     ├──► [Receptionist] ──► X-Gateway-Secret ──► Brain :5678/webhook/yaoc2-intelligence-v1
[WhatsApp Trigger] ──┘

[Brain ProposedAction] ──► /webhook/proposed-action ──► [Policy Gateway]
                                                              ├── allow ──► Sandbox Workflow
                                                              ├── deny  ──► Audit + 403
                                                              └── needs-approval ──► Telegram + 202
```

## Required env vars on gateway LXC (`/opt/n8n.env`)

```env
# Shared
GATEWAY_WEBHOOK_SECRET=<secret shared with brain>
APPROVAL_CHAT_ID=<telegram chat id for analyst approvals>

# Telegram
TELEGRAM_BOT_TOKEN=<rotated — never hardcode>

# Evolution / WhatsApp
EVOLUTION_API_KEY=<rotated — never hardcode>
EVOLUTION_INSTANCE_NAME=n8n claw

# TheHive
THEHIVE_URL=http://thehive:9000
THEHIVE_API_KEY=<key>

# OpenCTI
OPENCTI_URL=http://opencti:4000
OPENCTI_API_KEY=<key>

# MISP
MISP_URL=https://misp.lab.threatresearcher.net
MISP_API_KEY=<key>

# Cortex
CORTEX_URL=http://cortex:9001
CORTEX_API_KEY=<key>
```

## Workflows

| File | n8n ID | Role |
|---|---|---|
| `wa-receptionist.json` | vWApAS9WDfPD40q6 | WhatsApp → Brain |
| `tg-receptionist.json` | vT0pAS9WDfPD40q5 | Telegram → Brain |
| `heartbeat.json` | vGhbAS9WDfPD40q7 | ngrok URL refresh |
| `policy-gateway.json` | ap66ZptIy180B0w8 | ProposedAction enforcement |
| `sandbox-thehive.json` | wKPBXbyhvYMJ8qEH | TheHive case + observables |
| `sandbox-opencti.json` | FFdEjxvVkqRIZQ7W | OpenCTI STIX bundle/object |
| `sandbox-misp-enrich.json` | HbuaYADHUZWsIFW0 | MISP → Cortex → OpenCTI |
