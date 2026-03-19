# CTI Skills Roadmap

**MCP Template Library:** [`JazenaYLA/n8n-claw-templates`](https://github.com/JazenaYLA/n8n-claw-templates)  
**Last updated:** 2026-03-19

All CTI skills follow the n8n MCP skill pattern: installable on demand
via Telegram/WhatsApp command to the main agent, which fetches the
skill JSON from `n8n-claw-templates`, deploys it, and wires credentials
automatically via the `credential-form` workflow.

---

## Priority Matrix

| Skill | Source API | Priority | Auth | Status |
|---|---|---|---|---|
| `misp-skill` | MISP REST API | 🔴 High | API Key | Spec complete |
| `wazuh-skill` | Wazuh API (JWT) | 🔴 High | JWT Bearer | Spec complete |
| `opencti-skill` | OpenCTI GraphQL | 🔴 High | API Token | Spec complete |
| `thehive-skill` | TheHive REST | 🟡 Medium | API Key | Spec complete |
| `cortex-skill` | Cortex REST | 🟡 Medium | API Key | Spec complete |
| `flowise-skill` | Flowise API | 🟡 Medium | API Key | Planned |
| `ail-darkweb-skill` | AIL Framework API | 🟡 Medium | API Key | Planned |
| `headscale-skill` | Headscale Admin API | 🟢 Low | API Key | Spec complete |
| `threat-brief-skill` | OpenCTI + MISP | 🟡 Medium | Multiple | Planned |
| `wazuh-thehive-skill` | Wazuh → TheHive | 🔴 High | Multiple | Planned |

---

## misp-skill

**Trigger:** `"Install misp-skill"` via Telegram  
**Auth:** `Authorization: <API_KEY>` header  

**Tools:**
```
search_events(query, tags, date_range)
add_event(info, threat_level, distribution, attributes[])
add_attribute(event_id, type, value, category, to_ids)
create_tag(name, colour)
correlate_ioc(value)
get_event(event_id)
export_event(event_id, format)  → STIX2 / CSV
```

**Credentials:** `MISP_URL`, `MISP_API_KEY`, `MISP_VERIFY_SSL`

---

## wazuh-skill

**Trigger:** `"Install wazuh-skill"` via Telegram  
**Auth:** JWT — POST `/security/user/authenticate` → Bearer token  

**Tools:**
```
get_alerts(agent_id, level, limit, date_range)
query_agents(status, os, group)
run_active_response(agent_id, command)
get_vulnerabilities(agent_id, severity)
get_sca_results(agent_id, policy_id)
get_agent_info(agent_id)
```

**Credentials:** `WAZUH_API_URL`, `WAZUH_USER`, `WAZUH_PASSWORD`

---

## opencti-skill

**Trigger:** `"Install opencti-skill"` via Telegram  
**Auth:** `Authorization: Bearer <TOKEN>` header  

**Tools:**
```
search_indicators(value, type, confidence_min)
create_report(name, description, published, objects[])
add_relationship(from_id, to_id, relationship_type, confidence)
get_ttps(attack_pattern_id)
list_threats(threat_actor_type, country)
create_indicator(name, pattern, pattern_type, valid_from)
```

**Credentials:** `OPENCTI_URL`, `OPENCTI_TOKEN`

---

## thehive-skill

**Trigger:** `"Install thehive-skill"` via Telegram  
**Auth:** `Authorization: Bearer <API_KEY>`  

**Tools:**
```
create_case(title, description, severity, tlp, pap, tags[])
add_observable(case_id, data, data_type, tlp, tags[])
get_alerts(status, severity, date_range)
add_task(case_id, title, description, assignee)
close_case(case_id, resolution_status, impact_status)
run_responder(object_type, object_id, responder_name)
```

**Credentials:** `THEHIVE_URL`, `THEHIVE_API_KEY`, `THEHIVE_ORG`

---

## cortex-skill

**Trigger:** `"Install cortex-skill"` via Telegram  
**Auth:** `Authorization: Bearer <API_KEY>`  

**Tools:**
```
list_analyzers(data_type)
run_analyzer(analyzer_id, data, data_type, tlp)
get_job_report(job_id)
list_jobs(analyzer_id, limit)
```

**Credentials:** `CORTEX_URL`, `CORTEX_API_KEY`

---

## flowise-skill (Planned)

**Trigger:** `"Install flowise-skill"` via Telegram  
**Auth:** `Authorization: Bearer <API_KEY>`  

**Tools:**
```
chat_with_chatflow(chatflow_id, question, session_id)
list_chatflows()
get_chatflow(chatflow_id)
trigger_tool(chatflow_id, tool_name, params)
```

**Credentials:** `FLOWISE_URL`, `FLOWISE_API_KEY`

---

## ail-darkweb-skill (Planned)

**Trigger:** `"Install ail-darkweb-skill"` via Telegram  
**Auth:** API Key  

**Tools:**
```
search_items(query, date_range, tags)
get_item(item_id)
get_pastes_by_keyword(keyword, limit)
create_misp_event_from_item(item_id)
list_crawler_queues()
```

**Credentials:** `AIL_URL`, `AIL_API_KEY`

---

## headscale-skill

**Trigger:** `"Install headscale-skill"` via Telegram  
**Auth:** `Authorization: Bearer <API_KEY>`  

**Tools:**
```
list_nodes(user)
expire_node(node_id)
create_preauth_key(user, reusable, ephemeral, expiry)
get_routes(node_id)
enable_route(route_id)
disable_route(route_id)
```

**Credentials:** `HEADSCALE_URL`, `HEADSCALE_API_KEY`

---

## SOC Automation Loop

The full automation pipeline connects all CTI tools:

```
Wazuh alert
  → TheHive case auto-created (wazuh-thehive-skill)
    → Cortex analyzer runs on observables
      → Enriched results pushed to MISP as attributes
        → MISP event exported to OpenCTI as indicator
          → Flowise RAG updated with new threat data
            → Telegram/WhatsApp brief sent to operator
```

---

## Installation Pattern

All skills install via the `mcp-builder` workflow:

1. Send: `"Install misp-skill"` in Telegram/WhatsApp
2. Agent calls `mcp-builder` tool
3. `mcp-builder` fetches skill JSON from `JazenaYLA/n8n-claw-templates`
4. `credential-form` prompts for required credentials
5. Skill deployed and linked to main agent as MCP tool
6. Skill registered in `mcp_skills` table in Postgres
