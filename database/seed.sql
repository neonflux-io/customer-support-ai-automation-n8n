-- =====================================================================
-- n8n AI Customer Support Automation - Seed data
-- ---------------------------------------------------------------------
-- Idempotent seed script: safe to run repeatedly.
--
-- NOTE: embedding vectors are zero-vectors (placeholders) so that the
-- seed can run without an OpenAI key. Run the knowledge-base-ingestion
-- workflow afterwards to embed real chunks, or delete the placeholder
-- rows first:
--
--   TRUNCATE document_chunks, documents RESTART IDENTITY CASCADE;
--
-- The seed knowledge is realistic (coffee roastery) and is used by the
-- automated tests in tests/scenarios.md.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- Customers
-- ---------------------------------------------------------------------
INSERT INTO customers (id, external_id, name, email, channel, first_interaction_at, last_interaction_at, metadata)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'cus_website_001', 'Alex Morgan',  'alex.morgan@example.com', 'website',  now() - interval '30 days', now() - interval '2 hours',  '{"plan":"pro","tags":["vip"]}'::jsonb),
    ('22222222-2222-2222-2222-222222222222', 'cus_whatsapp_001','Maria Garcia', 'maria.garcia@example.com','whatsapp', now() - interval '12 days', now() - interval '1 day',    '{"plan":"free"}'::jsonb),
    ('33333333-3333-3333-3333-333333333333', 'cus_telegram_001','Liam Chen',    'liam.chen@example.com',   'telegram', now() - interval '2 days',  now() - interval '30 minutes','{"plan":"pro"}'::jsonb)
ON CONFLICT (external_id, channel) DO NOTHING;

-- ---------------------------------------------------------------------
-- Conversations
-- ---------------------------------------------------------------------
INSERT INTO conversations (id, external_conversation_id, customer_id, channel, status, message_count, first_message_at, last_message_at, metadata)
VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'conv_website_001', '11111111-1111-1111-1111-111111111111', 'website',  'open',      4, now() - interval '30 days', now() - interval '2 hours', '{"topic":"order"}'::jsonb),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'conv_whatsapp_001','22222222-2222-2222-2222-222222222222', 'whatsapp', 'resolved',  2, now() - interval '12 days', now() - interval '1 day',  '{"topic":"faq"}'::jsonb),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'conv_telegram_001','33333333-3333-3333-3333-333333333333', 'telegram', 'open',      3, now() - interval '2 days',  now() - interval '30 minutes', '{"topic":"refund"}'::jsonb)
ON CONFLICT (external_conversation_id, channel) DO NOTHING;

-- ---------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------
INSERT INTO messages (external_message_id, conversation_id, customer_id, channel, role, content, intent, confidence, sentiment, priority, requires_human, created_at)
VALUES
    ('seed_msg_001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'website',  'user',      'Where is my order? It has been 5 days.',        'order_status', 0.920, 'neutral',   'normal',  false, now() - interval '2 hours'),
    ('seed_msg_002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'website',  'assistant', 'Your order is out for delivery and arrives today.', 'order_status', 0.910, 'positive',  'normal',  false, now() - interval '2 hours' - interval '1 minute'),
    ('seed_msg_003', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', 'whatsapp', 'user',      'Do you ship internationally?',                    'faq',          0.870, 'neutral',   'normal',  false, now() - interval '1 day'),
    ('seed_msg_004', 'cccccccc-cccc-cccc-cccc-cccccccccccc', '33333333-3333-3333-3333-333333333333', 'telegram', 'user',      'I want a refund, this coffee never arrived.',      'refund_request', 0.850, 'angry',   'high',    true,  now() - interval '30 minutes')
ON CONFLICT (external_message_id, channel) DO NOTHING;

-- ---------------------------------------------------------------------
-- Knowledge documents (RAG source)
-- ---------------------------------------------------------------------
INSERT INTO documents (id, title, source, category, content, metadata)
VALUES
    ('dddddddd-0000-0000-0000-000000000001', 'Shipping Policy',        'seed', 'shipping', 'We ship worldwide. Standard shipping takes 3-5 business days and is free for orders over $40. Express shipping takes 1-2 business days and costs $12. Orders are dispatched within 24 hours from our roastery in Portland, Oregon.', '{"author":"ops"}'::jsonb),
    ('dddddddd-0000-0000-0000-000000000002', 'Refund Policy',          'seed', 'refund',   'Refunds are available within 30 days of purchase. To request a refund, contact support with your order number. Refunds over $100 require manual approval by a team member and are issued to the original payment method within 5-7 business days.', '{"author":"finance"}'::jsonb),
    ('dddddddd-0000-0000-0000-000000000003', 'Roast Profiles & Prices','seed', 'pricing',  'Our single-origin beans cost $18 per 12oz bag. Decaf is $19 per 12oz bag. Subscriptions save 15%. We currently roast Light, Medium and Dark profiles across 6 origins including Ethiopia, Colombia and Sumatra.', '{"author":"product"}'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------
-- Document chunks with placeholder zero vectors (1536 dims).
-- Replace with real embeddings by running the ingestion workflow:
--   POST /kb/ingest  (see workflows/knowledge-base-ingestion.json)
-- ---------------------------------------------------------------------
INSERT INTO document_chunks (id, document_id, chunk_index, chunk_text, metadata, embedding)
SELECT
    gen_random_uuid(),
    d.id,
    c.ci,
    d.content,
    jsonb_build_object('document_id', d.id, 'title', d.title, 'source', d.source, 'category', d.category, 'chunk_index', c.ci),
    (('[' || repeat('0,', 1535) || '0]')::vector)
FROM documents d
CROSS JOIN LATERAL (SELECT generate_series(0, 0) AS ci) c;

-- ---------------------------------------------------------------------
-- Tickets (sample)
-- ---------------------------------------------------------------------
INSERT INTO tickets (id, ticket_number, customer_id, conversation_id, subject, status, priority, intent, confidence, sentiment, ai_summary, escalation_reason, last_message)
VALUES
    ('eeeeeeee-0000-0000-0000-000000000001', 'TKT-00001001', '33333333-3333-3333-3333-333333333333', 'cccccccc-cccc-cccc-cccc-cccccccccccc',
     'Refund request - order never arrived', 'open', 'high', 'refund_request', 0.850, 'angry',
     'Customer requested a refund because their coffee order never arrived. Amount likely below manual-approval threshold.',
     'angry_customer|refund_request', 'I want a refund, this coffee never arrived.')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------
-- Sample analytics event
-- ---------------------------------------------------------------------
INSERT INTO analytics_events (event_type, channel, conversation_id, customer_id, intent, sentiment, priority, requires_human, rag_hit, response_validated, status)
VALUES
    ('message_processed', 'website', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
     'order_status', 'neutral', 'normal', false, true, true, 'success')
ON CONFLICT DO NOTHING;

COMMIT;
