--
-- 001_schema.sql
-- n8n-ecosystem-unified application schema
-- Run against: infra-postgres on CTI LXC (database: n8n, user: n8n)
-- Tables: core agent tables + email_log + channel_sessions + cti_events + mcp_skills
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET client_min_messages = warning;

-- ── Vector search RPC ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.search_memory(
  query_embedding public.vector,
  match_threshold double precision DEFAULT 0.7,
  match_count integer DEFAULT 5,
  filter_category text DEFAULT NULL::text
)
RETURNS TABLE(
  id integer, content text, category text, importance integer,
  similarity double precision, metadata jsonb, created_at timestamptz
)
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY
  SELECT ml.id, ml.content, ml.category, ml.importance,
    1 - (ml.embedding <=> query_embedding) as similarity,
    ml.metadata, ml.created_at
  FROM public.memory_long ml
  WHERE (filter_category IS NULL OR ml.category = filter_category)
    AND 1 - (ml.embedding <=> query_embedding) > match_threshold
    AND (ml.expires_at IS NULL OR ml.expires_at > now())
  ORDER BY ml.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.search_memory_keyword(
  search_query text,
  match_count integer DEFAULT 5
)
RETURNS TABLE(
  id integer, content text, category text, importance integer,
  metadata jsonb, created_at timestamptz
)
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY
  SELECT ml.id, ml.content, ml.category, ml.importance, ml.metadata, ml.created_at
  FROM public.memory_long ml
  WHERE ml.content ILIKE '%' || search_query || '%'
    AND (ml.expires_at IS NULL OR ml.expires_at > now())
  ORDER BY ml.importance DESC, ml.created_at DESC
  LIMIT match_count;
END;
$$;

-- ── Core tables ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.agents (
    id SERIAL PRIMARY KEY,
    key text NOT NULL UNIQUE,
    content text NOT NULL,
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.soul (
    id SERIAL PRIMARY KEY,
    key text NOT NULL UNIQUE,
    content text NOT NULL,
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.tools_config (
    id SERIAL PRIMARY KEY,
    tool_name text NOT NULL UNIQUE,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    enabled boolean DEFAULT true,
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_profiles (
    id SERIAL PRIMARY KEY,
    user_id text NOT NULL UNIQUE,
    name text,
    display_name text,
    timezone text DEFAULT 'America/Chicago'::text,
    preferences jsonb DEFAULT '{}'::jsonb,
    context text,
    setup_done boolean DEFAULT false,
    setup_step integer DEFAULT 0,
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id SERIAL PRIMARY KEY,
    session_id text NOT NULL,
    user_id text,
    role text NOT NULL,
    content text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now(),
    CONSTRAINT conversations_role_check CHECK (role = ANY (ARRAY['user','assistant','system']))
);

CREATE TABLE IF NOT EXISTS public.memory_long (
    id SERIAL PRIMARY KEY,
    content text NOT NULL,
    category text DEFAULT 'general',
    importance integer DEFAULT 5,
    embedding public.vector(1536),
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    expires_at timestamptz,
    CONSTRAINT memory_long_importance_check CHECK (importance >= 1 AND importance <= 10)
);

CREATE TABLE IF NOT EXISTS public.memory_daily (
    id SERIAL PRIMARY KEY,
    date date DEFAULT CURRENT_DATE,
    content text NOT NULL,
    role text DEFAULT 'assistant',
    user_id text,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.tasks (
    id SERIAL PRIMARY KEY,
    user_id text NOT NULL,
    title text NOT NULL,
    description text,
    status text DEFAULT 'pending' NOT NULL,
    priority text DEFAULT 'medium' NOT NULL,
    due_date timestamptz,
    parent_id integer,
    tags text[] DEFAULT '{}'::text[],
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    completed_at timestamptz,
    CONSTRAINT tasks_status_check CHECK (status = ANY (ARRAY['pending','in_progress','done','cancelled'])),
    CONSTRAINT tasks_priority_check CHECK (priority = ANY (ARRAY['low','medium','high','urgent'])),
    CONSTRAINT tasks_parent_fk FOREIGN KEY (parent_id) REFERENCES public.tasks(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.reminders (
    id SERIAL PRIMARY KEY,
    user_id text NOT NULL,
    chat_id text NOT NULL,
    message text NOT NULL,
    remind_at timestamptz NOT NULL,
    reminded_at timestamptz,
    type text NOT NULL DEFAULT 'reminder',
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.projects (
    id SERIAL PRIMARY KEY,
    name text NOT NULL UNIQUE,
    status text DEFAULT 'active' NOT NULL,
    content text DEFAULT '' NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT projects_status_check CHECK (status = ANY (ARRAY['active','paused','completed']))
);

CREATE TABLE IF NOT EXISTS public.heartbeat_config (
    id SERIAL PRIMARY KEY,
    check_name text NOT NULL UNIQUE,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_run timestamptz,
    interval_minutes integer DEFAULT 30,
    enabled boolean DEFAULT true
);

-- MCP skill registry
CREATE TABLE IF NOT EXISTS public.mcp_registry (
    id SERIAL PRIMARY KEY,
    server_name text NOT NULL,
    path text NOT NULL UNIQUE,
    mcp_url text NOT NULL,
    description text,
    tools text[],
    workflow_id text,
    active boolean DEFAULT true,
    template_id text,
    template_type text DEFAULT 'custom',
    sub_workflow_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Credential form tokens (one-time install tokens)
CREATE TABLE IF NOT EXISTS public.credential_tokens (
    token UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id text NOT NULL,
    cred_key text NOT NULL,
    cred_label text,
    cred_hint text,
    expires_at timestamptz NOT NULL DEFAULT NOW() + INTERVAL '10 minutes',
    used boolean DEFAULT false,
    created_at timestamptz DEFAULT NOW()
);

-- Stored template credentials
CREATE TABLE IF NOT EXISTS public.template_credentials (
    id SERIAL PRIMARY KEY,
    template_id text NOT NULL,
    cred_key text NOT NULL,
    cred_value text NOT NULL,
    created_at timestamptz DEFAULT NOW(),
    updated_at timestamptz DEFAULT NOW(),
    UNIQUE(template_id, cred_key)
);

-- ── Unified additions ─────────────────────────────────────────

-- Email log (autonomous email manager workflow)
CREATE TABLE IF NOT EXISTS public.email_log (
    id BIGSERIAL PRIMARY KEY,
    from_address text,
    subject text,
    message_id text,
    action_taken text,
    notes text,
    processed_at timestamptz DEFAULT NOW()
);

-- Multi-channel session tracking (Telegram + WhatsApp)
CREATE TABLE IF NOT EXISTS public.channel_sessions (
    id SERIAL PRIMARY KEY,
    session_id text NOT NULL UNIQUE,
    user_id text NOT NULL,
    chat_id text NOT NULL,
    source text NOT NULL,
    last_seen timestamptz DEFAULT NOW(),
    created_at timestamptz DEFAULT NOW()
);

-- CTI events (MISP, Wazuh, OpenCTI, TheHive, Cortex ingestion)
CREATE TABLE IF NOT EXISTS public.cti_events (
    id BIGSERIAL PRIMARY KEY,
    source text NOT NULL,
    event_id text,
    severity text,
    title text,
    description text,
    raw_data jsonb DEFAULT '{}',
    tags text[] DEFAULT '{}',
    processed boolean DEFAULT false,
    notified_at timestamptz,
    created_at timestamptz DEFAULT NOW()
);

-- ── Indexes ───────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_conversations_session   ON public.conversations (session_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_user      ON public.conversations (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_memory_long_category    ON public.memory_long (category);
CREATE INDEX IF NOT EXISTS idx_memory_long_embedding   ON public.memory_long USING hnsw (embedding public.vector_cosine_ops);
CREATE INDEX IF NOT EXISTS idx_memory_long_importance  ON public.memory_long (importance DESC);
CREATE INDEX IF NOT EXISTS idx_memory_daily_date       ON public.memory_daily (date DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_user_status       ON public.tasks (user_id, status);
CREATE INDEX IF NOT EXISTS idx_tasks_due_date          ON public.tasks (due_date) WHERE (due_date IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_reminders_pending       ON public.reminders (remind_at) WHERE (reminded_at IS NULL);
CREATE INDEX IF NOT EXISTS idx_mcp_registry_active     ON public.mcp_registry (active);
CREATE INDEX IF NOT EXISTS idx_mcp_registry_path       ON public.mcp_registry (path);
CREATE INDEX IF NOT EXISTS idx_projects_status         ON public.projects (status);
CREATE INDEX IF NOT EXISTS idx_cred_tokens_expires     ON public.credential_tokens (expires_at) WHERE used = false;
CREATE INDEX IF NOT EXISTS idx_template_creds_template ON public.template_credentials (template_id);
CREATE INDEX IF NOT EXISTS idx_email_log_processed     ON public.email_log (processed_at DESC);
CREATE INDEX IF NOT EXISTS idx_channel_sessions_user   ON public.channel_sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_cti_events_source       ON public.cti_events (source, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cti_events_unprocessed  ON public.cti_events (processed) WHERE processed = false;

-- ── Grants ────────────────────────────────────────────────────
GRANT ALL ON ALL TABLES IN SCHEMA public TO n8n, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO n8n, anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO n8n, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE n8n IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE n8n IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE n8n IN SCHEMA public
  GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
