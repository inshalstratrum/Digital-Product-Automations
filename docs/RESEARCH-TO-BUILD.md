# Research-to-build decisions

Five supplied reports were reviewed. Two were byte-identical; the remaining reports converged on a staged digital-product business with three initial workflows.

| Research conclusion | Build decision |
|---|---|
| Begin with a narrow, premium creator system | Default commercial target is Documentary Shorts Factory OS for faceless educational/documentary creators |
| Validate before automating | Human approval gates and a documented 10-preorder/100-waitlist activation threshold |
| First workflow protects revenue | Signed webhook, idempotent order ingestion, entitlements, private signed downloads, retryable email outbox |
| Second workflow captures/scored ideas | Evidence rubric with transparent weights and optional AI enrichment |
| Third workflow closes the customer loop | Tokenized feedback, classification, severity routing, change request, approval |
| Use durable queues and explicit retry paths | Supabase Queues, visibility timeouts, run ledger, five-attempt dead-letter policy |
| Do not violate marketplace terms | No marketplace scraping is implemented |
| Keep secrets and customer data controlled | Private Storage, service-role-only ingestion RPCs, RLS, HMAC verification, no payment-card storage |
| Preserve product/version compatibility | Semantic product versions, active-version constraint, asset metadata, compatibility JSON |
| Allow n8n later without locking core data into it | Email and intelligence webhooks are adapters; Postgres remains the source of truth |

## Why Supabase replaces SurrealDB in this implementation

Some reports proposed SurrealDB, while the strongest report later simplified the first 90 days to PostgreSQL. The user explicitly selected Supabase. Supabase Postgres provides the relational integrity needed for orders and entitlements, Auth/RLS for the operator dashboard, private Storage for assets, Edge Functions for verified intake, and Postgres-native Queues/Cron for background work. This removes an unnecessary database from the MVP.

## Product data already supported

The schema supports the recommended offer ladder:

- lead magnet
- core OS
- expansion pack
- subscription
- studio licence
- services-lite

It also supports the report's first product specification through product versions, multiple downloadable assets, compatibility metadata, guides, licences, release notes, and update history.
