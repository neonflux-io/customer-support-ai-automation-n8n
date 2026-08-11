# Troubleshooting

Common issues, causes and fixes for the n8n AI Customer Support Automation project.

## Workflow import

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| "Could not import: node type not found" | n8n version predates a node type or `typeVersion` used in the JSON | Upgrade n8n to a recent 1.x. The LangChain nodes (`@n8n/n8n-nodes-langchain.*`) require n8n ≥ 1.0. |
| "Error: node could not be found" during import | The file references a node type that is disabled/not installed | Re-check the node type allow-list; all used types ship with n8n 1.x. |
| Sub-workflow not found at runtime | `SUBWORKFLOW_BASE_PATH` not set or wrong | Set it to the **absolute path** of `workflows/subflows` on the n8n host and restart n8n. |

## Credentials

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Node shows "credentials are not set" | Placeholder credential ID left unbound | Open each flagged node → **Credential** → select the real OpenAI/Postgres credential. |
| OpenAI 401 / 403 | API key missing or invalid | Bind the OpenAI credential (or set `OPENAI_API_KEY` in the n8n environment). |
| Postgres connection refused | Wrong host/port or DB not created | Verify `POSTGRES_HOST/PORT/DB`; run `schema.sql` first. |
| `permission denied` on tables | DB user lacks grants | Grant privileges on the `public` schema to the n8n user. |

## RAG / embeddings

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| RAG always returns `miss` | `document_chunks` holds zero/placeholder vectors | Re-ingest the KB via `/webhook/kb/ingest` or the Manual Trigger so real embeddings replace the seed placeholders. |
| "column dimension does not match vector" | Embedding dimension ≠ `VECTOR(1536)` | Match `EMBEDDING_MODEL` to the schema dimension, or rebuild `document_chunks` with a matching dimension. |
| Vector store table not found (name mismatch) | `tableName` on the node differs from `document_chunks` | Keep the node's `tableName` set to `document_chunks` to match the schema. |
| Empty result for a known FAQ | Chunking overlap too small / threshold too strict | Lower `RAG_STRONG_THRESHOLD`; increase `KB_CHUNK_OVERLAP`. |

## Behaviour

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Everything escalates | `AI_CONFIDENCE_THRESHOLD` too high, or classification output malformed | Lower the threshold; check `ai-classification` output in the editor; check the OpenAI model is reachable. |
| Everything responds (no escalation) | RAG threshold too permissive, or policy rules bypassed | Raise `RAG_STRONG_THRESHOLD`; verify the policy Code node isn't erroring (check execution logs). |
| Duplicate messages still processed | `message_id` not unique per logical message | Ensure the client sends a stable unique `message_id` per message per channel. |
| Response always regenerated once | `response-validation` is conservative | Read the returned `issues[]`; tune length/relevance checks in the validation Code node. |
| Reply never returns to the webhook | A sub-workflow errored and no Error Workflow caught it | Confirm `error-handler` is active and set as the Error Workflow; check execution history. |

## Execution / performance

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Webhook timeout on first call | Cold start (model + embeddings) | Call the webhook once to warm; n8n caches connections. |
| Slow classification | Large context | Reduce `CONTEXT_MESSAGE_LIMIT`; rely on summarization. |
| Many `n8n_chat_histories` rows | Memory node appends every turn | Prune on a schedule; not business-critical. |

## Error workflow

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| No error events in `analytics_events` | Error Workflow not assigned/active | Set **Error Workflow** on every workflow to `AI Support - Error Handler` and activate it. |

## Still stuck?

Check the execution history of the failing run, enable the **Debug** pane, and post the failing node's error. For environment questions see `docs/ENVIRONMENT.md`; for testing, `docs/TESTING.md`.
