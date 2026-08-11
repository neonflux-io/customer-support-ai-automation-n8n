# Security

This document describes the security model of the system and the hardening checklist to apply before production use.

## Design principles

1. **No secrets in the repository.** Only `.env.example` is tracked. API keys and database passwords live in n8n Credentials (encrypted at rest with `N8N_ENCRYPTION_KEY`) or the runtime environment.
2. **All SQL is parameterized.** Postgres nodes use `executeQuery` with `$1..$n` bind parameters. No string-concatenated user input ever reaches a query.
3. **Unified trust boundary for customer content.** Customer messages, channel metadata and retrieved documents are all treated as **untrusted data** and pass through the same sanitization and injection-defense layers.
4. **Deterministic gates for safety-critical paths.** Escalations, refund approvals and validation never depend on the LLM alone.

## Threat model

| Threat | Mitigation |
|--------|-----------|
| Prompt injection via customer message | `Validate & Normalize` flags injection keywords (`ignore`, `system prompt`, `disregard`, `jailbreak`, `developer`, …). Generation prompt hard-forbids executing embedded instructions and reveals no system prompt/keys/internal reasoning. |
| Prompt injection via knowledge document | The same grounding/injection rules apply to retrieved context. `KB_SOURCE_URL` should point to a trusted, vetted source. |
| Response prompt leakage | `response-validation.json` scans for system-prompt excerpts, `OPENAI_`, `sk-`, private-key patterns and rejects such responses (then escalates). |
| Secret exposure via webhook responses | Responses contain only the envelope fields listed in the API reference — never credentials, tokens or SQL. |
| Credential files | `.gitignore` excludes `.env`, `*.pem`, `*.key`, n8n data dirs, and the validation output dir. |
| Duplicate/amplified requests | Idempotency key on `message_id + source`; concurrent `processing` keys block re-entry; analytics and message writes are idempotent. |
| Denial of service on ingestion | Ingestion limits document count/size in the extraction code node and requires a trusted webhook (`kb/ingest`). |
| LLM hallucination / ungrounded answers | Grounding instructions + deterministic validation + one regeneration + escalation fallback. |
| Error information leakage | The Error Handler logs to `analytics_events`; webhook responses return generic success/validation errors, not stack traces. |

## Hardening checklist (before production)

- [ ] Set a strong random `N8N_ENCRYPTION_KEY` (`openssl rand -hex 24`) and keep it in the host environment, not in git.
- [ ] Store the OpenAI API key and Postgres password **only** in n8n Credentials; verify no `.env` is committed.
- [ ] Protect webhook endpoints: consider a shared secret header (`x-webhook-secret`) checked in the Validate node, or run the webhooks behind a reverse proxy with IP allow-listing.
- [ ] Restrict `KB_SOURCE_URL` to an internal, vetted content source; validate content before ingest.
- [ ] Use TLS: set `N8N_PROTOCOL=https` behind a reverse proxy with a valid certificate.
- [ ] Enforce PostgreSQL network isolation (dedicated user, least-privilege grants, no public access).
- [ ] Prune `n8n_chat_histories`, `analytics_events` and `messages` on a retention schedule.
- [ ] Review the injection-keyword list in `Validate & Normalize` and extend it for your domain.
- [ ] Rotate the OpenAI key if it ever appears in a response-validation issue log.

## Related

- `ENVIRONMENT.md` — credential setup.
- `TESTING.md` — scenario matrix includes prompt-injection and secret-leak tests.
