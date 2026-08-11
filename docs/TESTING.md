# Testing

This project ships two kinds of testing:

1. **Static validation** — automated, runs with plain Node.js, no n8n/DB required.
2. **Behavioural / end-to-end scenarios** — documented manual tests that require a live n8n + PostgreSQL + pgvector + an OpenAI key.

## 1. Static validation

```bash
cd tests
./run_tests.sh
```

What `tests/validate_workflows.mjs` checks:

- **JSON** — every workflow file parses and is an object with `nodes` and `connections`.
- **Node IDs** — unique; `id` is non-empty.
- **Node types** — every `type` is on the n8n allow-list for the importable node set (Postgres, Webhook, IF, Switch, Code, HTTP Request, Execute Workflow, Respond, Error Trigger, Manual Trigger, Chat Model, Chain LLM, AI Agent, Chat Memory (Postgres), Code Tool, Embeddings, Vector Store (Postgres), and the LangChain sub-node container types used in AI Agent connections).
- **Connections** — each connection references an existing node, has valid types, and connections belong to declared source nodes. Orphaned/`_` placeholder connections are allowed (n8n uses them internally on import), but no dangling *non-placeholder* references to missing nodes.
- **Environment references** — every `$env.X` referenced in the workflows exists in `.env.example`.
- **Sub-workflow references** — every `Execute Workflow` node using `source: localFile` points at a file that exists under `workflows/subflows/`.
- **Credential placeholders** — flags any `REPLACE_WITH_` strings that survive in node credentials, so you remember to bind them.

## 2. Behavioural test scenarios

`tests/scenarios.md` describes 15 executable scenarios. For each scenario there is a payload fixture in `tests/fixtures/` you can POST with curl:

```bash
curl -X POST http://localhost:5678/webhook/customer-support \
  -H 'Content-Type: application/json' \
  -d @tests/fixtures/scenario-01-faq.json
```

And the expected outcome for each (intent, confidence band, routing decision, RAG status, validation, reply expectations, ticket creation).

### Minimal smoke test

1. Import all workflows.
2. Set `SUBWORKFLOW_BASE_PATH`, bind the Postgres + OpenAI credentials.
3. Activate `customer-support` and `error-handler`.
4. `curl -X POST http://localhost:5678/webhook/customer-support -H 'Content-Type: application/json' -d '{"channel":"website","customer_id":"smoke_1","conversation_id":"conv_smoke_1","message_id":"m_smoke_1","message":"Hi"}'`
5. Expect a `200` with `success: true` and a reply (or an escalation envelope).

### Idempotency smoke test

POST the same `message_id` twice. The second call must return the cached reply without reprocessing (check `idempotency_keys.status` in the database).

### RAG smoke test

1. Ingest the seed knowledge documents (run the ingestion workflow manually or POST to `/webhook/kb/ingest`).
2. Ask "What is your shipping policy?" — expect `rag_status: strong` and a grounded answer.

## 3. Database validation

After a run, verify the side effects:

```sql
SELECT * FROM messages ORDER BY created_at DESC LIMIT 5;
SELECT * FROM analytics_events ORDER BY created_at DESC LIMIT 5;
SELECT * FROM idempotency_keys ORDER BY created_at DESC LIMIT 5;
SELECT * FROM tickets WHERE status <> 'closed' ORDER BY created_at DESC LIMIT 5;
```

## What is NOT covered by automated tests

The LLM-dependent quality dimensions (classification accuracy, response groundedness, sentiment judgement) cannot be asserted without a live model and are therefore verified through the manual scenario matrix. The static validator guarantees structural validity of every workflow JSON, which is the primary import-blocker risk.
