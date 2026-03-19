-- =============================================================
-- 002_seed.sql
-- Initial seed data for n8n-ecosystem-unified
-- Run against: infra-postgres on CTI LXC (database: n8n, user: n8n)
-- Safe to re-run: all inserts use ON CONFLICT DO NOTHING
-- =============================================================

-- Default agent persona
INSERT INTO public.agents (key, content) VALUES
  ('system_prompt', 'You are a helpful CTI automation assistant. You have access to MISP, OpenCTI, TheHive, Cortex, and Wazuh. You can search threat intelligence, create cases, and analyze observables.')
ON CONFLICT (key) DO NOTHING;

-- Default soul/personality config
INSERT INTO public.soul (key, content) VALUES
  ('name', 'ThreatBot'),
  ('role', 'CTI Automation Assistant'),
  ('language', 'en')
ON CONFLICT (key) DO NOTHING;

-- Default tools config (all disabled until credentials set in n8n)
INSERT INTO public.tools_config (tool_name, config, enabled) VALUES
  ('misp',     '{"url_var": "MISP_URL",    "key_var": "MISP_API_KEY"}',    false),
  ('opencti',  '{"url_var": "OPENCTI_URL", "key_var": "OPENCTI_API_KEY"}', false),
  ('thehive',  '{"url_var": "THEHIVE_URL", "key_var": "THEHIVE_API_KEY"}', false),
  ('cortex',   '{"url_var": "CORTEX_URL",  "key_var": "CORTEX_API_KEY"}',  false),
  ('wazuh',    '{"url_var": "WAZUH_URL",   "user_var": "WAZUH_USER"}',     false),
  ('flowise',  '{"url_var": "FLOWISE_URL", "key_var": "FLOWISE_API_KEY"}', false),
  ('searxng',  '{"url_var": "SEARXNG_URL"}',                               true),
  ('crawl4ai', '{"url": "http://crawl4ai:11235"}',                         true)
ON CONFLICT (tool_name) DO NOTHING;

-- Default heartbeat monitors
INSERT INTO public.heartbeat_config (check_name, config, interval_minutes, enabled) VALUES
  ('n8n_health',      '{"url": "http://n8n:5678/healthz"}',          5,  true),
  ('misp_health',     '{"url_var": "MISP_URL", "path": "/"}',        15, false),
  ('opencti_health',  '{"url_var": "OPENCTI_URL", "path": "/"}',     15, false),
  ('thehive_health',  '{"url_var": "THEHIVE_URL", "path": "/api/status"}', 15, false)
ON CONFLICT (check_name) DO NOTHING;
