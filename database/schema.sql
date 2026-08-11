-- =====================================================================
-- n8n AI Customer Support Automation - PostgreSQL schema
-- ---------------------------------------------------------------------
-- Requires PostgreSQL 13+ with the pgvector extension (>= 0.5.0).
--
-- The vector dimension (1536) matches OpenAI text-embedding-3-small.
-- If you change the embedding model, adjust VECTOR(n) accordingly.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";          -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "vector";            -- pgvector

-- ---------------------------------------------------------------------
-- Sequences
-- ---------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS ticket_number_seq START 1000;
CREATE SEQUENCE IF NOT EXISTS analytics_seq START 1;

-- ---------------------------------------------------------------------
-- Customers
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_id           VARCHAR(255) NOT NULL,      -- channel-specific customer id
    name                  VARCHAR(255),
    email                 VARCHAR(320),
    channel               VARCHAR(50) NOT NULL,       -- website|whatsapp|telegram|email|slack|instagram|facebook
    first_interaction_at  TIMESTAMPTZ DEFAULT now(),
    last_interaction_at   TIMESTAMPTZ DEFAULT now(),
    metadata              JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT customers_external_channel_unique UNIQUE (external_id, channel)
);

CREATE INDEX IF NOT EXISTS idx_customers_external_id ON customers (external_id);
CREATE INDEX IF NOT EXISTS idx_customers_email         ON customers (lower(email));
CREATE INDEX IF NOT EXISTS idx_customers_channel       ON customers (channel);
CREATE INDEX IF NOT EXISTS idx_customers_metadata      ON customers USING gin (metadata);

-- ---------------------------------------------------------------------
-- Conversations
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversations (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_conversation_id  VARCHAR(255) NOT NULL,
    customer_id               UUID REFERENCES customers (id) ON DELETE CASCADE,
    channel                   VARCHAR(50) NOT NULL,
    status                    VARCHAR(30) NOT NULL DEFAULT 'open', -- open|pending|resolved|closed
    summary                   TEXT,                                -- rolling LLM summary
    message_count             INT NOT NULL DEFAULT 0,
    first_message_at          TIMESTAMPTZ,
    last_message_at           TIMESTAMPTZ DEFAULT now(),
    metadata                  JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT conversations_external_channel_unique UNIQUE (external_conversation_id, channel)
);

CREATE INDEX IF NOT EXISTS idx_conversations_customer_id ON conversations (customer_id);
CREATE INDEX IF NOT EXISTS idx_conversations_channel     ON conversations (channel);
CREATE INDEX IF NOT EXISTS idx_conversations_status      ON conversations (status);
CREATE INDEX IF NOT EXISTS idx_conversations_updated     ON conversations (updated_at);

-- ---------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS messages (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_message_id   VARCHAR(255) NOT NULL,
    conversation_id       UUID REFERENCES conversations (id) ON DELETE CASCADE,
    customer_id           UUID REFERENCES customers (id),
    channel               VARCHAR(50) NOT NULL,
    role                  VARCHAR(20) NOT NULL,          -- user|assistant|system
    content               TEXT NOT NULL,
    intent                VARCHAR(50),
    confidence            NUMERIC(4,3),
    sentiment             VARCHAR(20),
    priority              VARCHAR(20),
    requires_human        BOOLEAN NOT NULL DEFAULT FALSE,
    resolution            VARCHAR(30),                   -- automated|clarified|escalated
    escalated             BOOLEAN NOT NULL DEFAULT FALSE,
    rag_hit               BOOLEAN NOT NULL DEFAULT FALSE,
    response_validated    BOOLEAN NOT NULL DEFAULT FALSE,
    is_summary            BOOLEAN NOT NULL DEFAULT FALSE,
    metadata              JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_external_channel_unique
    ON messages (external_message_id, channel);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages (conversation_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_customer_id     ON messages (customer_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_intent          ON messages (intent);
CREATE INDEX IF NOT EXISTS idx_messages_created_at      ON messages (created_at);

-- ---------------------------------------------------------------------
-- Knowledge documents
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS documents (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title        VARCHAR(512) NOT NULL,
    source       VARCHAR(255),
    category     VARCHAR(100),
    content      TEXT NOT NULL,
    metadata     JSONB NOT NULL DEFAULT '{}'::jsonb,
    ingested_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_documents_title_source ON documents (title, source);
CREATE INDEX IF NOT EXISTS idx_documents_category ON documents (category);
CREATE INDEX IF NOT EXISTS idx_documents_source    ON documents (source);
CREATE INDEX IF NOT EXISTS idx_documents_metadata  ON documents USING gin (metadata);

-- ---------------------------------------------------------------------
-- n8n Postgres Chat Memory table
-- Created and managed by the @n8n/n8n-nodes-langchain.memoryPostgresChat
-- node. Declared here for documentation completeness; the node auto-creates
-- it when the "Create table" option is enabled.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS n8n_chat_histories (
    "sessionId" VARCHAR(255) NOT NULL,
    "message"   TEXT NOT NULL,
    "role"      VARCHAR(30) NOT NULL,
    "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_n8n_chat_histories_session ON n8n_chat_histories ("sessionId");

-- ---------------------------------------------------------------------
-- Document chunks (pgvector)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS document_chunks (
    id           UUID PRIMARY KEY,
    document_id  UUID REFERENCES documents (id) ON DELETE CASCADE,
    chunk_index  INT NOT NULL DEFAULT 0,
    chunk_text   TEXT NOT NULL,
    metadata     JSONB NOT NULL DEFAULT '{}'::jsonb,
    embedding    VECTOR(1536),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- HNSW index is more robust than IVFFlat for small and changing datasets.
CREATE INDEX IF NOT EXISTS idx_document_chunks_embedding
    ON document_chunks USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS idx_document_chunks_document_id ON document_chunks (document_id);
CREATE INDEX IF NOT EXISTS idx_document_chunks_metadata     ON document_chunks USING gin (metadata);

-- ---------------------------------------------------------------------
-- Tickets
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tickets (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_number     VARCHAR(20) NOT NULL DEFAULT ('TKT-' || lpad(nextval('ticket_number_seq')::text, 8, '0')),
    customer_id       UUID REFERENCES customers (id) ON DELETE SET NULL,
    conversation_id   UUID REFERENCES conversations (id) ON DELETE SET NULL,
    subject           TEXT,
    status            VARCHAR(30) NOT NULL DEFAULT 'open',
    priority          VARCHAR(20),
    intent            VARCHAR(50),
    confidence        NUMERIC(4,3),
    sentiment         VARCHAR(20),
    ai_summary        TEXT,
    escalation_reason TEXT,
    assigned_to       VARCHAR(255),
    resolution        TEXT,
    last_message      TEXT,
    resolved_at       TIMESTAMPTZ,
    closed_at         TIMESTAMPTZ,
    metadata          JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tickets_number   ON tickets (ticket_number);
CREATE INDEX IF NOT EXISTS idx_tickets_status          ON tickets (status);
CREATE INDEX IF NOT EXISTS idx_tickets_priority        ON tickets (priority);
CREATE INDEX IF NOT EXISTS idx_tickets_customer_id     ON tickets (customer_id);
CREATE INDEX IF NOT EXISTS idx_tickets_conversation_id ON tickets (conversation_id);
CREATE INDEX IF NOT EXISTS idx_tickets_created_at      ON tickets (created_at);

-- ---------------------------------------------------------------------
-- Analytics events
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS analytics_events (
    id                 BIGINT PRIMARY KEY DEFAULT nextval('analytics_seq'),
    event_type         VARCHAR(50) NOT NULL,
    channel            VARCHAR(50),
    conversation_id    UUID,
    customer_id        UUID,
    message_id         UUID,
    ticket_id          UUID,
    intent             VARCHAR(50),
    sentiment          VARCHAR(20),
    priority           VARCHAR(20),
    requires_human     BOOLEAN,
    rag_hit            BOOLEAN,
    response_validated BOOLEAN,
    escalation_reason  TEXT,
    duration_ms        INT,
    status             VARCHAR(30),
    error_message      TEXT,
    metadata           JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_analytics_event_type ON analytics_events (event_type);
CREATE INDEX IF NOT EXISTS idx_analytics_created_at ON analytics_events (created_at);
CREATE INDEX IF NOT EXISTS idx_analytics_channel    ON analytics_events (channel);
CREATE INDEX IF NOT EXISTS idx_analytics_intent     ON analytics_events (intent);

-- ---------------------------------------------------------------------
-- Idempotency keys
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS idempotency_keys (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key           VARCHAR(255) NOT NULL,
    channel       VARCHAR(50),
    message_id    VARCHAR(255),
    status        VARCHAR(20) NOT NULL DEFAULT 'processing', -- processing|completed|failed
    hash          VARCHAR(64),
    payload       JSONB,                                     -- cached response payload
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ NOT NULL DEFAULT now() + interval '24 hours'
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_idempotency_keys_key ON idempotency_keys (key);
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_message    ON idempotency_keys (message_id);

COMMIT;
