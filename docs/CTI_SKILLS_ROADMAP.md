# CTI Skills Roadmap

**Repository:** `JazenaYLA/n8n-claw-templates` (forked from `freddy-schuetz/n8n-claw-templates`)  
**Last updated:** 2026-03-18  

All CTI skills follow Freddy's MCP skill pattern: installable on demand via Telegram command to the main agent, which fetches the skill JSON from `n8n-claw-templates`, deploys it, and wires credentials automatically via the `credential-form` workflow.

---

## Skill Priority Matrix

| Skill | Source API | Priority | Auth Method | Key Operations |
|---|---|---|---|---|
| `misp-skill` | MISP REST API | 🔴 High | API Key (header) | search_events, add_event, add_attribute, create_tag, correlate_ioc |
| `wazuh-skill` | Wazuh API (JWT) | 🔴 High | JWT Bearer | get_alerts, query_agents, run_active_response, get_vulnerabilities |
| `opencti-skill` | OpenCTI GraphQL | 🔴 High | API Token | search_indicators, create_report, add_relationship, get_ttps |
| `theHive-skill` | TheHive REST | 🟡 Medium | API Key | create_case, add_observable, get_alerts, add_task, close_case |
| `cortex-skill` | Cortex REST | 🟡 Medium | API Key | run_analyzer, get_job_report, list_analyzers |
| `headscale-skill` | Headscale Admin API | 🟢 Low | API Key | list_nodes, expire_node, create_preauth_key, get_routes |

---

## misp-skill Specification

**Trigger:** `"Install misp-skill"` via Telegram  
**Base URL:** Your MISP instance (self-hosted, e.g. `https://misp.yourdomain.com`)  
**Auth:** `Authorization: YOUR_API_KEY` header  

### Tools to expose:
```
search_events(query, tags, date_range)
add_event(info, threat_level, distribution, attributes[])
add_attribute(event_id, type, value, category, to_ids)
create_tag(name, colour)
correlate_ioc(value)  → returns matching events
get_event(event_id)
export_event(event_id, format)  → STIX2 / CSV
```

### Credential form fields:
- `MISP_URL` — Base URL of MISP instance
- `MISP_API_KEY` — API key from MISP user profile
- `MISP_VERIFY_SSL` — true/false (set false for self-signed certs)

---

## wazuh-skill Specification

**Trigger:** `"Install wazuh-skill"` via Telegram  
**Base URL:** Wazuh API (default port 55000)  
**Auth:** JWT — POST `/security/user/authenticate` → Bearer token  

### Tools to expose:
```
get_alerts(agent_id, level, limit, date_range)
query_agents(status, os, group)
run_active_response(agent_id, command)
get_vulnerabilities(agent_id, severity)
get_sca_results(agent_id, policy_id)
get_agent_info(agent_id)
```

### Credential form fields:
- `WAZUH_API_URL` — Base URL (e.g. `https://wazuh.yourdomain.com:55000`)
- `WAZUH_USER` — API user (default: `wazuh`)
- `WAZUH_PASSWORD` — API password

---

## opencti-skill Specification

**Trigger:** `"Install opencti-skill"` via Telegram  
**Base URL:** OpenCTI GraphQL endpoint (`/graphql`)  
**Auth:** `Authorization: Bearer YOUR_TOKEN` header  

### Tools to expose:
```
search_indicators(value, type, confidence_min)
create_report(name, description, published, objects[])
add_relationship(from_id, to_id, relationship_type, confidence)
get_ttps(attack_pattern_id)
list_threats(threat_actor_type, country)
get_indicator(id)
create_indicator(name, pattern, pattern_type, valid_from)
```

### Credential form fields:
- `OPENCTI_URL` — Base URL (e.g. `https://opencti.yourdomain.com`)
- `OPENCTI_TOKEN` — API token from user profile

---

## theHive-skill Specification

**Trigger:** `"Install thehive-skill"` via Telegram  
**Base URL:** TheHive REST API  
**Auth:** `Authorization: Bearer YOUR_API_KEY`  

### Tools to expose:
```
create_case(title, description, severity, tlp, pap, tags[])
add_observable(case_id, data, data_type, tlp, tags[])
get_alerts(status, severity, date_range)
add_task(case_id, title, description, assignee)
close_case(case_id, resolution_status, impact_status)
run_responder(object_type, object_id, responder_name)
```

### Credential form fields:
- `THEHIVE_URL` — Base URL
- `THEHIVE_API_KEY` — API key
- `THEHIVE_ORG` — Organisation name

---

## cortex-skill Specification

**Trigger:** `"Install cortex-skill"` via Telegram  
**Base URL:** Cortex REST API  
**Auth:** `Authorization: Bearer YOUR_API_KEY`  

### Tools to expose:
```
list_analyzers(data_type)
run_analyzer(analyzer_id, data, data_type, tlp)
get_job_report(job_id)
list_jobs(analyzer_id, limit)
```

### Credential form fields:
- `CORTEX_URL` — Base URL
- `CORTEX_API_KEY` — API key

---

## headscale-skill Specification

**Trigger:** `"Install headscale-skill"` via Telegram  
**Base URL:** Headscale Admin API  
**Auth:** `Authorization: Bearer YOUR_API_KEY`  

### Tools to expose:
```
list_nodes(user)
expire_node(node_id)
create_preauth_key(user, reusable, ephemeral, expiry)
get_routes(node_id)
enable_route(route_id)
disable_route(route_id)
delete_node(node_id)
```

### Credential form fields:
- `HEADSCALE_URL` — Admin API URL
- `HEADSCALE_API_KEY` — API key from Headscale config

---

## Installation Pattern

All skills install via Freddy's `mcp-builder.json` workflow:

1. User sends: `"Install misp-skill"` in Telegram
2. Main agent calls `mcp-builder` tool
3. `mcp-builder` fetches skill JSON from `JazenaYLA/n8n-claw-templates`
4. `credential-form` workflow prompts user for required credentials
5. Skill sub-workflow deployed and linked to main agent as MCP tool
6. Skill registered in `mcp-library-manager` table

---

## MISP ↔ OpenCTI Bidirectional Sync Note

Both MISP and OpenCTI are running in the homelab. Consider a dedicated sync workflow (separate from the MCP skills) that:
- Exports MISP events → OpenCTI reports on schedule
- Pushes OpenCTI indicators → MISP attributes
- Uses Wazuh alerts as triggers for case creation in TheHive
- Routes TheHive observables to Cortex analyzers automatically

This forms a full SOC automation loop: **Wazuh → TheHive → Cortex → MISP → OpenCTI**
