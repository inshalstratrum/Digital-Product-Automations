# Deployment status

## Live project

- Supabase project: `Digi-Product-ecom`
- Project reference: `kjalldzwxedziwoqipsq`
- Region: Seoul (`ap-northeast-2`)
- PostgreSQL: 17

## Deployed database

- 20 public business tables
- RLS enabled on all 20 tables
- private `product-assets` Storage bucket
- four durable queues: `sales_fulfillment`, `idea_scoring`, `feedback_classification`, `outbound_email`
- two recorded migrations: core schema and policy/index hardening
- paid-order ingestion and queue RPCs callable by `service_role` only

## Deployed Edge Functions

| Function | Status | Gateway JWT |
|---|---|---|
| `health` | active | not required; returns only availability |
| `payment-webhook` | active | custom Lemon Squeezy HMAC verification |
| `submit-idea` | active | required |
| `submit-feedback` | active | order feedback token required in body |
| `automation-worker` | active | required, plus `x-worker-secret` |

## Verification completed

- Health returned HTTP 200 with database available.
- Invalid feedback token returned HTTP 404.
- Missing JWT returned HTTP 401 for idea submission and worker.
- Anonymous and authenticated database roles cannot call paid-order ingestion.
- Service role can call paid-order ingestion.
- Supabase security advisor returned no findings.
- Performance advisor has only expected “unused index” information because every business table is currently empty.

## Configuration still required

These cannot be safely guessed or created without the owner's provider accounts:

1. Set a strong `LEMON_SQUEEZY_WEBHOOK_SECRET` in Supabase Edge Function secrets and the identical value in Lemon Squeezy.
2. Set a random `WORKER_SECRET` of at least 32 characters in Edge Function secrets.
3. Create the first Supabase Auth owner and workspace.
4. Create the first product/version and upload its actual files.
5. Choose the exact email provider. The current release keeps delivery records inside Supabase and does not export customer data.
6. After the legacy anon JWT and worker secret are available, install the schedule from `supabase/cron.example.sql`.

## Commercial activation gate

Keep checkout fulfilment in test mode until the research validation condition is reached: 10 genuine preorders or 100 waitlist signups. The first cohort should still be checked manually before enabling unattended delivery.
