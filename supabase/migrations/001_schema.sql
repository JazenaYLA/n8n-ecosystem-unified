--
-- n8n-ecosystem-unified schema
-- Based on JazenaYLA/n8n-claw with unified additions:
--   - email_log table (autonomous email manager)
--   - channel_sessions table (multi-channel router session tracking)
--   - cti_events table (CTI skills)
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA public;
CREATE EXTENSION IF NOT EXISTS vector SCHEMA public;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'supabase_admin') THEN
    CREATE ROLE supabase_admin WITH LOGIN SUPERUSER PASSWORD 'supabase_admin';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS public;
ALTER SCHEMA public OWNER TO pg_database_owner;
COMMENT ON SCHEMA public IS 'standard public schema';

-- ── Vector search RPC ────────────────────────────────────────
CREATE FUNCTION public.search_memory(query_embedding public.vector, match_threshold double precision DEFAULT 0.7, match_count integer DEFAULT 5, filter_category text DEFAULT NULL::text)
RETURNS TABLE(id integer, content text, category text, importance integer, similarity double precision, metadata jsonb, created_at timestamp with time zone)
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY
  SELECT ml.id, ml.content, ml.category, ml.importance,
    1 - (ml.embedding <=> query_embedding) as similarity,
    ml.metadata, ml.created_at
  FROM memory_long ml
  WHERE (filter_category IS NULL OR ml.category = filter_category)
    AND 1 - (ml.embedding <=> query_embedding) > match_threshold
    AND (ml.expires_at IS NULL OR ml.expires_at > now())
  ORDER BY ml.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;
ALTER FUNCTION public.search_memory(query_embedding public.vector, match_threshold double precision, match_count integer, filter_category text) OWNER TO postgres;

CREATE FUNCTION public.search_memory_keyword(search_query text, match_count integer DEFAULT 5)
RETURNS TABLE(id integer, content text, category text, importance integer, metadata jsonb, created_at timestamp with time zone)
LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY
  SELECT ml.id, ml.content, ml.category, ml.importance, ml.metadata, ml.created_at
  FROM memory_long ml
  WHERE ml.content ILIKE '%' || search_query || '%'
    AND (ml.expires_at IS NULL OR ml.expires_at > now())
  ORDER BY ml.importance DESC, ml.created_at DESC
  LIMIT match_count;
END;
$$;
ALTER FUNCTION public.search_memory_keyword(search_query text, match_count integer) OWNER TO postgres;

SET default_tablespace = '';
SET default_table_access_method = heap;

-- ── Core tables (from n8n-claw) ──────────────────────────────

CREATE TABLE public.agents (
    id SERIAL PRIMARY KEY,
    key text NOT NULL UNIQUE,
    content text NOT NULL,
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE public.soul (
    id SERIAL PRIMARY KEY,
    key text NOT NULL UNIQUE,
    content text NOT NULL,
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE public.tools_config (
    id SERIAL PRIMARY KEY,
    tool_name text NOT NULL UNIQUE,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    enabled boolean DEFAULT true,
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE public.user_profiles (
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

CREATE TABLE public.conversations (
    id SERIAL PRIMARY KEY,
    session_id text NOT NULL,
    user_id text,
    role text NOT NULL,
    content text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now(),
    CONSTRAINT conversations_role_check CHECK (role = ANY (ARRAY['user','assistant','system']))
);

CREATE TABLE public.memory_long (
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

CREATE TABLE public.memory_daily (
    id SERIAL PRIMARY KEY,
    date date DEFAULT CURRENT_DATE,
    content text NOT NULL,
    role text DEFAULT 'assistant',
    user_id text,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE public.tasks (
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

CREATE TABLE public.reminders (
    id SERIAL PRIMARY KEY,
    user_id text NOT NULL,
    chat_id text NOT NULL,
    message text NOT NULL,
    remind_at timestamptz NOT NULL,
    reminded_at timestamptz,
    type text NOT NULL DEFAULT 'reminder',
    created_at timestamptz DEFAULT now()
);

CREATE TABLE public.projects (
    id SERIAL PRIMARY KEY,
    name text NOT NULL UNIQUE,
    status text DEFAULT 'active' NOT NULL,
    content text DEFAULT '' NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT projects_status_check CHECK (status = ANY (ARRAY['active','paused','completed']))
);

CREATE TABLE public.heartbeat_config (
    id SERIAL PRIMARY KEY,
    check_name text NOT NULL UNIQUE,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_run timestamptz,
    interval_minutes integer DEFAULT 30,
    enabled boolean DEFAULT true
);

CREATE TABLE public.mcp_registry (
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

CREATE TABLE IF NOT EXISTS public.template_credentials (
    id SERIAL PRIMARY KEY,
    template_id text NOT NULL,
    cred_key text NOT NULL,
    cred_value text NOT NULL,
    created_at timestamptz DEFAULT NOW(),
    updated_at timestamptz DEFAULT NOW(),
    UNIQUE(template_id, cred_key)
);

-- ── Unified additions ────────────────────────────────────────

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

-- Channel sessions (multi-channel router — tracks chatId per source)
CREATE TABLE IF NOT EXISTS public.channel_sessions (
    id SERIAL PRIMARY KEY,
    session_id text NOT NULL UNIQUE,
    user_id text NOT NULL,
    chat_id text NOT NULL,
    source text NOT NULL,  -- 'telegram' | 'whatsapp'
    last_seen timestamptz DEFAULT NOW(),
    created_at timestamptz DEFAULT NOW()
);

-- CTI events (CTI skill workflows — MISP, Wazuh, OpenCTI ingestion)
CREATE TABLE IF NOT EXISTS public.cti_events (
    id BIGSERIAL PRIMARY KEY,
    source text NOT NULL,          -- 'misp' | 'wazuh' | 'opencti' | 'thehive' | 'cortex'
    event_id text,                 -- source-system event ID
    severity text,
    title text,
    description text,
    raw_data jsonb DEFAULT '{}',
    tags text[] DEFAULT '{}',
    processed boolean DEFAULT false,
    notified_at timestamptz,
    created_at timestamptz DEFAULT NOW()
);

-- ── Indexes ──────────────────────────────────────────────────
CREATE INDEX idx_conversations_session ON public.conversations USING btree (session_id, created_at DESC);
CREATE INDEX idx_conversations_user ON public.conversations USING btree (user_id, created_at DESC);
CREATE INDEX idx_memory_long_category ON public.memory_long USING btree (category);
CREATE INDEX IF NOT EXISTS idx_memory_long_embedding ON public.memory_long USING hnsw (embedding public.vector_cosine_ops);
CREATE INDEX idx_memory_long_importance ON public.memory_long USING btree (importance DESC);
CREATE INDEX idx_memory_daily_date ON public.memory_daily USING btree (date DESC);
CREATE INDEX idx_tasks_user_status ON public.tasks USING btree (user_id, status);
CREATE INDEX idx_tasks_due_date ON public.tasks USING btree (due_date) WHERE (due_date IS NOT NULL);
CREATE INDEX idx_tasks_parent ON public.tasks USING btree (parent_id) WHERE (parent_id IS NOT NULL);
CREATE INDEX idx_reminders_pending ON public.reminders USING btree (remind_at) WHERE (reminded_at IS NULL);
CREATE INDEX idx_mcp_registry_active ON public.mcp_registry USING btree (active);
CREATE INDEX idx_mcp_registry_path ON public.mcp_registry USING btree (path);
CREATE INDEX idx_projects_status ON public.projects USING btree (status);
CREATE INDEX idx_projects_updated ON public.projects USING btree (updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_credential_tokens_expires ON public.credential_tokens (expires_at) WHERE used = false;
CREATE INDEX IF NOT EXISTS idx_template_credentials_template ON public.template_credentials (template_id);
CREATE INDEX IF NOT EXISTS idx_email_log_processed_at ON public.email_log (processed_at DESC);
CREATE INDEX IF NOT EXISTS idx_channel_sessions_user ON public.channel_sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_cti_events_source ON public.cti_events (source, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cti_events_unprocessed ON public.cti_events (processed) WHERE processed = false;

-- ── Grants ───────────────────────────────────────────────────
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role, supabase_admin;
GRANT ALL ON SCHEMA public TO supabase_admin;

GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role, supabase_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role, supabase_admin;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role, supabase_admin;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
