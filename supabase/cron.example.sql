-- Run only after deploying automation-worker and setting its WORKER_SECRET.
-- Replace the placeholders. Vault prevents secrets from appearing in cron.job.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

select vault.create_secret('https://YOUR_PROJECT_REF.supabase.co', 'dpa_project_url');
select vault.create_secret('YOUR_WORKER_SECRET', 'dpa_worker_secret');
select vault.create_secret('YOUR_LEGACY_ANON_JWT', 'dpa_anon_jwt');

select cron.schedule(
  'digital-product-automation-worker',
  '* * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'dpa_project_url')
      || '/functions/v1/automation-worker',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'dpa_anon_jwt'),
      'x-worker-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'dpa_worker_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);
