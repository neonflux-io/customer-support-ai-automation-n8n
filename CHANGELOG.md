# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-09

### Added

#### Architecture
- Multi-channel webhook intake (Website, WhatsApp, Telegram, Email, Slack, Instagram, Facebook Messenger) normalized into a single internal envelope.
- One reusable core engine shared by all channels; no AI logic duplicated per channel.
- Modular sub-workflow design: customer lookup, conversation memory, intent classification, sentiment & priority, RAG retrieval, response generation, response validation, escalation & tickets, finalize & respond.
- Deterministic policy engine that combines rule-based decisions with AI classification (critical decisions never rely on the LLM alone).

#### Ingestion, validation and security
- Input validation and normalization (JSON schema, message length, customer/conversation/message IDs, timestamp, channel).
- Structured error responses for invalid webhook payloads.
- Input sanitization: control-character stripping, HTML entity encoding, credential/secret redaction, injection keyword flagging.
- Prompt injection defense: retrieved documents and customer messages are treated as untrusted data.
- No hard-coded secrets; all credentials via n8n Credentials and environment variables.

#### Persistence and idempotency
- PostgreSQL schema for customers, conversations, messages, knowledge documents, document chunks, pgvector embeddings, tickets, analytics events and idempotency keys.
- Idempotency guarantee based on message ID or deterministic SHA-256 hash; duplicate requests return the cached response.
- Idempotent ticket and message creation.

#### AI, memory and RAG
- AI Agent / LLM with structured classification across 15 intents (greeting, faq, product_question, pricing, order_status, order_issue, payment_issue, refund_request, cancellation, technical_support, complaint, account_issue, shipping, human_agent_request, unknown).
- Sentiment detection (positive, neutral, negative, angry, frustrated, urgent) and priority detection (low, normal, high, critical).
- Conversation memory with recent-message window plus automatic summarization of long conversations.
- Real RAG with PostgreSQL + pgvector: document ingestion workflow, chunking, embeddings, vector similarity search, metadata filtering and configurable similarity threshold.
- Grounded response generation that only answers from retrieved knowledge; asks for clarification or escalates when knowledge is insufficient.
- Response validation (relevance, factual grounding, unsupported claims, prompt leakage, secrets, length, business-rule compliance) with one regeneration attempt before escalation.

#### Human escalation and tickets
- Escalation rules: low confidence, critical issues, human requests, unsupported questions, repeated AI failures, angry customers, sensitive account issues, manual refund approval, failed response validation.
- Ticket lifecycle supporting open, pending, assigned, waiting_customer, resolved, closed.
- Ticket operations: create, update, assign, resolve, reopen via a dedicated ticket-management workflow.

#### Observability and error handling
- Analytics event logging for every processed message.
- Dedicated error-handler workflow (Error Trigger) that logs structured errors to analytics.
- Safe retries and structured error logging for LLM, database/vector, malformed AI output and webhook failures.

#### Configuration and testing
- Central configuration through environment variables (thresholds for confidence, RAG similarity, context length, response length, retries, escalation, refund approval).
- Seed data for customers, conversations, messages, knowledge documents and placeholder vectors.
- Test scenarios and fixtures covering FAQ, product questions, order status, refunds, angry customers, human requests, unknown questions, low confidence, RAG miss, duplicates, invalid requests, LLM failure, database failure, prompt injection and critical issues.
- JSON validation script (`tests/validate_workflows.mjs`) to check workflow structure, connections, expressions, environment variable references and sub-workflow references.

### Documentation
- Comprehensive `README.md` with Mermaid architecture diagram, installation, configuration, import, RAG ingestion, testing, troubleshooting, security and limitations.
- `docs/` folder with architecture, environment, testing, security and troubleshooting guides.
- `examples/` with sample webhook payloads for every channel and scenario.

### Fixed
- `chainLLM` → `chainLlm` (compiled node name) in intent classification, sentiment analysis and conversation summarization; typeVersion 1.2 uses the `prompt` property (no `promptType`/`text`/`options.systemMessage`).
- `vectorStorePostgres` → `vectorStorePGVector`; RAG retrieval uses `mode: "load"` with `prompt`/`topK`; ingestion uses `mode: "insert"`.
- RAG retrieval score handling: the PGVector load operation returns `{ document, score }` where `score` is a cosine distance (lower is better); converted to a `[0,1]` similarity for threshold checks.
- Ingestion now wires a `documentDefaultDataLoader` (`ai_document`) into the vector store insert operation, preserving `document_id`/`chunk_index` in chunk metadata for the Link Chunks backfill.
- Agent V2 sub-node connections use the verified types `ai_languageModel`, `ai_memory`, `ai_tool` and `ai_embedding`.
