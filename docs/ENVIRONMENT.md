# Environment & configuration reference

This document is the authoritative reference for every environment variable used by the workflows. Values shown are the defaults baked into the workflows (via n8n expressions like `$env.AI_CONFIDENCE_THRESHOLD || 0.6`); n8n merges process environment variables and the `.env` file inside its user folder (`N8N_USER_FOLDER`).

## Global

| Variable | Default | Used by | Purpose |
|----------|---------|---------|---------|
| `N8N_HOST` | `localhost` | n8n | Host n8n binds to |
| `N8N_PORT` | `5678` | n8n | Port n8n listens on |
| `N8N_PROTOCOL` | `http` | n8n | Protocol for webhook URLs |
| `N8N_ENCRYPTION_KEY` | — (must be set) | n8n | Encrypts credential data in the DB. Generate with `openssl rand -hex 24`. |
| `SUBWORKFLOW_BASE_PATH` | — (must be set) | Main workflow | Absolute path to `workflows/subflows` on the n8n host. All `Execute Workflow` nodes resolve `{{ $env.SUBWORKFLOW_BASE_PATH }}/<file>.json`. |
| `WEBHOOK_PATH` | `customer-support` | Main workflow | URL suffix: `POST /webhook/<value>` |

## AI / model

| Variable | Default | Purpose |
|----------|---------|---------|
| `CHAT_MODEL` | `gpt-4o-mini` | Chat model used by classification, sentiment and generation chain/agent nodes |
| `EMBEDDING_MODEL` | `text-embedding-3-small` | Embeddings model (1536 dims). **Must match `VECTOR(1536)` in `schema.sql`.** |
| `OPENAI_API_KEY` | — | Only needed if you do not bind the OpenAI credential explicitly in n8n |

## Thresholds — classification & policy

| Variable | Default | Purpose |
|----------|---------|---------|
| `AI_CONFIDENCE_THRESHOLD` | `0.6` | Intent/sentiment confidence below this → escalate |
| `REFUND_APPROVAL_THRESHOLD` | `100` | Refunds ≥ this USD amount require manual approval (escalate) |
| `ESCALATION_RETRY_NEEDED` | `1` | Reserved; number of validation failures that force escalation |

## Thresholds — RAG

| Variable | Default | Purpose |
|----------|---------|---------|
| `RAG_TOP_K` | `4` | Number of chunks retrieved per query |
| `RAG_STRONG_THRESHOLD` | `0.5` | Top score ≥ this → `strong` (automated answer) |
| `RAG_SIMILARITY_THRESHOLD` | `0.3` | Top score ≥ this → `weak` (clarify/escalate); below → `miss` (escalate) |

## Context & memory

| Variable | Default | Purpose |
|----------|---------|---------|
| `CONTEXT_MESSAGE_LIMIT` | `10` | Recent messages injected into the LLM window |
| `CONTEXT_SUMMARIZE_THRESHOLD` | `8` | Auto-summarize when the loaded window reaches this size |
| `RESPONSE_MIN_LENGTH` | `5` | Min validated response length (chars) |
| `RESPONSE_MAX_LENGTH` | `500` | Max validated response length (chars) |
| `RETRY_LIMIT` | `1` | Regeneration attempts before escalating |

## Knowledge base ingestion

| Variable | Default | Purpose |
|----------|---------|---------|
| `KB_SOURCE_URL` | — | JSON/plain source fetched when the webhook body carries no documents |
| `KB_CHUNK_SIZE` | `800` | Chunk size (characters) |
| `KB_CHUNK_OVERLAP` | `100` | Chunk overlap (characters) |

## Database (documentation values)

| Variable | Default | Purpose |
|----------|---------|---------|
| `POSTGRES_HOST` | `localhost` | PostgreSQL host |
| `POSTGRES_PORT` | `5432` | PostgreSQL port |
| `POSTGRES_DB` | `ai_customer_support` | Database name |
| `POSTGRES_USER` | `n8n` | Database user |
| `POSTGRES_PASSWORD` | `change-me` | Database password |

> The Postgres **credential** in n8n holds the real connection details and password; the variables above are documentation/`docker-compose` values. **Never put a real password in `.env` tracked by git.**

## Credentials to create in n8n

| Credential | Name (suggestion) | Notes |
|-----------|-------------------|-------|
| **OpenAI API** | `OpenAI API` | Used by `lmChatOpenAi`, `chainLlm`, `agent` (via its `ai_languageModel` sub-node) and `embeddingsOpenAi`. Model names come from `CHAT_MODEL`/`EMBEDDING_MODEL`. |
| **Postgres** | `Postgres` | Used by every Postgres node and both Vector Store nodes. Host/port/db/user/password, database `ai_customer_support`, schema `public`. |

On import, credential references appear as placeholders (`REPLACE_WITH_..._CREDENTIAL_ID`). Select the right credential on each flagged node; n8n stores its own credential UUIDs in its database, so the placeholders are never persisted.

## `.env.example` quick reference

```bash
cp .env.example .env
```

Only values that differ from defaults need to be set. In a containerized deployment the same names can be injected as process environment variables instead of a `.env` file.
