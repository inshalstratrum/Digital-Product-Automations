-- Digital Product Automations: secure, Supabase-native business pipelines.
-- Generated for PostgreSQL 17 / Supabase CLI 2.109.1.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pgmq;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- New objects are private by default. API access is granted deliberately below.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 100),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  owner_id uuid not null references auth.users(id),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  timezone text not null default 'Asia/Karachi',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'operator', 'viewer')),
  created_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table public.sales_channels (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  provider text not null check (provider in ('lemon_squeezy', 'etsy', 'gumroad', 'stripe', 'manual')),
  external_store_id text not null,
  display_name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, external_store_id)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  sku text not null unique check (sku ~ '^[A-Z0-9][A-Z0-9_-]{2,63}$'),
  name text not null,
  description text,
  tier text not null default 'core' check (tier in ('lead_magnet', 'core', 'expansion', 'subscription', 'studio', 'service_lite')),
  status text not null default 'draft' check (status in ('draft', 'review', 'active', 'retired')),
  price_minor integer not null default 0 check (price_minor >= 0),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.product_versions (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  version text not null check (version ~ '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$'),
  release_notes text,
  compatibility jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft', 'review', 'active', 'superseded')),
  released_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, version)
);

create unique index product_versions_one_active_idx
  on public.product_versions(product_id) where status = 'active';

create table public.product_assets (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  product_version_id uuid not null references public.product_versions(id) on delete cascade,
  bucket_id text not null default 'product-assets',
  object_path text not null,
  label text not null,
  asset_type text not null check (asset_type in ('download', 'guide', 'preview', 'license', 'changelog')),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (bucket_id, object_path)
);

create table public.product_external_ids (
  product_id uuid not null references public.products(id) on delete cascade,
  provider text not null,
  external_product_id text not null,
  created_at timestamptz not null default now(),
  primary key (provider, external_product_id)
);

create table public.leads (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  email text not null,
  source text not null,
  niche text not null,
  consent_status text not null default 'pending' check (consent_status in ('pending', 'opted_in', 'opted_out')),
  status text not null default 'new' check (status in ('new', 'nurturing', 'qualified', 'converted', 'archived')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index leads_workspace_email_idx on public.leads(workspace_id, lower(email));

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  email text not null,
  name text,
  external_refs jsonb not null default '{}'::jsonb,
  marketing_consent boolean not null default false,
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index customers_workspace_email_idx on public.customers(workspace_id, lower(email));

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  provider text not null,
  external_order_id text not null,
  external_customer_id text,
  status text not null check (status in ('pending', 'paid', 'refunded', 'disputed', 'cancelled')),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  gross_minor integer not null check (gross_minor >= 0),
  net_minor integer check (net_minor is null or net_minor >= 0),
  feedback_token uuid not null default gen_random_uuid() unique,
  provider_payload jsonb not null default '{}'::jsonb,
  purchased_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, external_order_id)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id),
  product_version_id uuid references public.product_versions(id),
  quantity integer not null default 1 check (quantity > 0),
  unit_price_minor integer not null check (unit_price_minor >= 0),
  created_at timestamptz not null default now(),
  unique (order_id, product_id)
);

create table public.entitlements (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  order_item_id uuid not null unique references public.order_items(id) on delete cascade,
  product_id uuid not null references public.products(id),
  license_type text not null default 'individual' check (license_type in ('individual', 'commercial', 'studio', 'subscription')),
  access_status text not null default 'active' check (access_status in ('active', 'suspended', 'expired', 'revoked')),
  version_delivered text,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.content_ideas (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  submitted_by uuid references auth.users(id) on delete set null,
  niche text not null,
  angle text not null,
  audience text,
  evidence_note text,
  source_url text,
  metrics jsonb not null default '{}'::jsonb,
  score numeric(5,2) check (score between 0 and 100),
  score_breakdown jsonb not null default '{}'::jsonb,
  status text not null default 'pending_score' check (status in ('pending_score', 'low_priority', 'review', 'approved', 'in_production', 'published', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customer_feedback (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  order_id uuid references public.orders(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  product_id uuid references public.products(id) on delete set null,
  rating smallint check (rating between 1 and 5),
  note text not null check (char_length(note) between 2 and 5000),
  issue_type text,
  severity text check (severity is null or severity in ('low', 'medium', 'high', 'critical')),
  sentiment numeric(4,3) check (sentiment is null or sentiment between -1 and 1),
  tags text[] not null default '{}',
  classification jsonb not null default '{}'::jsonb,
  status text not null default 'pending_classification' check (status in ('pending_classification', 'acknowledged', 'needs_action', 'resolved', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.change_requests (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  product_id uuid references public.products(id) on delete cascade,
  title text not null,
  description text not null,
  source text not null check (source in ('feedback', 'research', 'support', 'internal')),
  priority text not null check (priority in ('low', 'medium', 'high', 'critical')),
  status text not null default 'proposed' check (status in ('proposed', 'approved', 'planned', 'in_progress', 'released', 'rejected')),
  evidence_count integer not null default 1 check (evidence_count > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.approval_requests (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  request_type text not null check (request_type in ('idea', 'product_release', 'customer_issue', 'change_request', 'outbound_campaign')),
  entity_id uuid not null,
  summary text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  requested_by uuid references auth.users(id) on delete set null,
  decided_by uuid references auth.users(id) on delete set null,
  decision_note text,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (request_type, entity_id, status)
);

create table public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text not null,
  event_type text not null,
  signature_valid boolean not null,
  payload jsonb not null,
  status text not null default 'received' check (status in ('received', 'processed', 'ignored', 'failed')),
  error_message text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (provider, provider_event_id)
);

create table public.automation_runs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid references public.workspaces(id) on delete cascade,
  pipeline text not null check (pipeline in ('sales_delivery', 'idea_scoring', 'feedback_loop', 'outbound_email')),
  entity_type text not null,
  entity_id uuid,
  status text not null default 'queued' check (status in ('queued', 'running', 'waiting_approval', 'succeeded', 'failed', 'dead_letter')),
  attempt integer not null default 0 check (attempt >= 0),
  input jsonb not null default '{}'::jsonb,
  output jsonb not null default '{}'::jsonb,
  error_message text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index automation_runs_pipeline_status_idx
  on public.automation_runs(pipeline, status, created_at desc);

create table public.outbound_messages (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  channel text not null default 'email' check (channel in ('email', 'webhook')),
  recipient text not null,
  template_key text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued', 'sending', 'sent', 'failed', 'cancelled')),
  provider_message_id text,
  attempts integer not null default 0,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Internal authorization helpers. Authorization is database-backed, never user_metadata-backed.
create or replace function private.is_workspace_member(p_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.workspace_members wm
    where wm.workspace_id = p_workspace_id and wm.user_id = (select auth.uid())
  );
$$;

create or replace function private.has_workspace_role(p_workspace_id uuid, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.workspace_members wm
    where wm.workspace_id = p_workspace_id
      and wm.user_id = (select auth.uid())
      and wm.role = any(p_roles)
  );
$$;

revoke all on function private.is_workspace_member(uuid) from public, anon, authenticated;
revoke all on function private.has_workspace_role(uuid, text[]) from public, anon, authenticated;
grant usage on schema private to authenticated;
grant execute on function private.is_workspace_member(uuid) to authenticated;
grant execute on function private.has_workspace_role(uuid, text[]) to authenticated;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles(id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

create or replace function private.add_workspace_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.workspace_members(workspace_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict (workspace_id, user_id) do update set role = 'owner';
  return new;
end;
$$;

create trigger on_workspace_created
  after insert on public.workspaces
  for each row execute function private.add_workspace_owner();

do $$
declare t text;
begin
  foreach t in array array[
    'profiles','workspaces','sales_channels','products','product_versions','leads','customers',
    'orders','entitlements','content_ideas','customer_feedback','change_requests',
    'approval_requests','automation_runs','outbound_messages'
  ] loop
    execute format('create trigger set_%I_updated_at before update on public.%I for each row execute function private.set_updated_at()', t, t);
  end loop;
end;
$$;

-- Durable queues. They remain outside the Data API; only service-role wrappers below can consume them.
select pgmq.create('sales_fulfillment');
select pgmq.create('idea_scoring');
select pgmq.create('feedback_classification');
select pgmq.create('outbound_email');

create or replace function private.queue_content_idea()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_run_id uuid;
begin
  insert into public.automation_runs(workspace_id, pipeline, entity_type, entity_id, input)
  values (new.workspace_id, 'idea_scoring', 'content_idea', new.id, jsonb_build_object('idea_id', new.id))
  returning id into v_run_id;
  perform pgmq.send('idea_scoring', jsonb_build_object('idea_id', new.id, 'run_id', v_run_id));
  return new;
end;
$$;

create trigger queue_content_idea_after_insert
  after insert on public.content_ideas
  for each row when (new.status = 'pending_score')
  execute function private.queue_content_idea();

create or replace function private.queue_feedback()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_run_id uuid;
begin
  insert into public.automation_runs(workspace_id, pipeline, entity_type, entity_id, input)
  values (new.workspace_id, 'feedback_loop', 'customer_feedback', new.id, jsonb_build_object('feedback_id', new.id))
  returning id into v_run_id;
  perform pgmq.send('feedback_classification', jsonb_build_object('feedback_id', new.id, 'run_id', v_run_id));
  return new;
end;
$$;

create trigger queue_feedback_after_insert
  after insert on public.customer_feedback
  for each row when (new.status = 'pending_classification')
  execute function private.queue_feedback();

create or replace function private.queue_outbound_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_run_id uuid;
begin
  insert into public.automation_runs(workspace_id, pipeline, entity_type, entity_id, input)
  values (new.workspace_id, 'outbound_email', 'outbound_message', new.id, jsonb_build_object('message_id', new.id))
  returning id into v_run_id;
  perform pgmq.send('outbound_email', jsonb_build_object('message_id', new.id, 'run_id', v_run_id));
  return new;
end;
$$;

create trigger queue_outbound_email_after_insert
  after insert on public.outbound_messages
  for each row when (new.status = 'queued' and new.channel = 'email')
  execute function private.queue_outbound_email();

-- Idempotent paid-order ingestion. Only trusted Edge Functions using service_role can call it.
create or replace function public.ingest_paid_order(
  p_provider text,
  p_external_order_id text,
  p_external_customer_id text,
  p_customer_email text,
  p_customer_name text,
  p_product_sku text,
  p_external_product_id text,
  p_currency text,
  p_gross_minor integer,
  p_net_minor integer,
  p_license_type text,
  p_provider_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_product public.products%rowtype;
  v_customer_id uuid;
  v_order_id uuid;
  v_order_item_id uuid;
  v_version_id uuid;
  v_version text;
  v_run_id uuid;
  v_existing boolean := false;
begin
  if p_customer_email is null or position('@' in p_customer_email) < 2 then
    raise exception 'A valid customer email is required';
  end if;
  if p_gross_minor < 0 then raise exception 'gross amount cannot be negative'; end if;

  select p.* into v_product
  from public.products p
  left join public.product_external_ids pei on pei.product_id = p.id
  where p.status = 'active'
    and ((p_product_sku is not null and p.sku = upper(p_product_sku))
      or (p_external_product_id is not null and pei.provider = p_provider and pei.external_product_id = p_external_product_id))
  order by case when p.sku = upper(coalesce(p_product_sku, '')) then 0 else 1 end
  limit 1;

  if v_product.id is null then raise exception 'No active product mapping found'; end if;

  select o.id into v_order_id from public.orders o
  where o.provider = p_provider and o.external_order_id = p_external_order_id;
  if v_order_id is not null then
    return jsonb_build_object('order_id', v_order_id, 'idempotent_replay', true);
  end if;

  insert into public.customers(workspace_id, email, name, external_refs)
  values (
    v_product.workspace_id,
    lower(trim(p_customer_email)),
    nullif(trim(coalesce(p_customer_name, '')), ''),
    case when p_external_customer_id is null then '{}'::jsonb else jsonb_build_object(p_provider, p_external_customer_id) end
  )
  on conflict (workspace_id, (lower(email))) do update
    set name = coalesce(excluded.name, public.customers.name),
        external_refs = public.customers.external_refs || excluded.external_refs,
        updated_at = now()
  returning id into v_customer_id;

  select pv.id, pv.version into v_version_id, v_version
  from public.product_versions pv
  where pv.product_id = v_product.id and pv.status = 'active'
  limit 1;

  insert into public.orders(
    workspace_id, customer_id, provider, external_order_id, external_customer_id,
    status, currency, gross_minor, net_minor, provider_payload
  ) values (
    v_product.workspace_id, v_customer_id, p_provider, p_external_order_id, p_external_customer_id,
    'paid', upper(p_currency), p_gross_minor, p_net_minor, coalesce(p_provider_payload, '{}'::jsonb)
  ) returning id into v_order_id;

  insert into public.order_items(order_id, product_id, product_version_id, unit_price_minor)
  values (v_order_id, v_product.id, v_version_id, p_gross_minor)
  returning id into v_order_item_id;

  insert into public.entitlements(workspace_id, customer_id, order_item_id, product_id, license_type, version_delivered)
  values (
    v_product.workspace_id, v_customer_id, v_order_item_id, v_product.id,
    case when p_license_type in ('individual','commercial','studio','subscription') then p_license_type else 'individual' end,
    v_version
  );

  insert into public.automation_runs(workspace_id, pipeline, entity_type, entity_id, input)
  values (v_product.workspace_id, 'sales_delivery', 'order', v_order_id, jsonb_build_object('order_id', v_order_id))
  returning id into v_run_id;

  perform pgmq.send('sales_fulfillment', jsonb_build_object('order_id', v_order_id, 'run_id', v_run_id));
  return jsonb_build_object('order_id', v_order_id, 'run_id', v_run_id, 'idempotent_replay', v_existing);
end;
$$;

create or replace function public.claim_automation_jobs(
  p_queue text,
  p_visibility_seconds integer default 120,
  p_batch_size integer default 5
)
returns table(msg_id bigint, read_ct integer, enqueued_at timestamptz, vt timestamptz, message jsonb)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_queue <> all(array['sales_fulfillment','idea_scoring','feedback_classification','outbound_email']) then
    raise exception 'Queue is not allowed';
  end if;
  return query select r.msg_id, r.read_ct, r.enqueued_at, r.vt, r.message
    from pgmq.read(p_queue, greatest(30, least(p_visibility_seconds, 900)), greatest(1, least(p_batch_size, 20))) r;
end;
$$;

create or replace function public.complete_automation_job(p_queue text, p_msg_id bigint, p_archive boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_queue <> all(array['sales_fulfillment','idea_scoring','feedback_classification','outbound_email']) then
    raise exception 'Queue is not allowed';
  end if;
  if p_archive then
    return pgmq.archive(p_queue, p_msg_id);
  end if;
  return pgmq.delete(p_queue, p_msg_id);
end;
$$;

revoke all on function public.ingest_paid_order(text,text,text,text,text,text,text,text,integer,integer,text,jsonb) from public, anon, authenticated;
revoke all on function public.claim_automation_jobs(text,integer,integer) from public, anon, authenticated;
revoke all on function public.complete_automation_job(text,bigint,boolean) from public, anon, authenticated;
grant execute on function public.ingest_paid_order(text,text,text,text,text,text,text,text,integer,integer,text,jsonb) to service_role;
grant execute on function public.claim_automation_jobs(text,integer,integer) to service_role;
grant execute on function public.complete_automation_job(text,bigint,boolean) to service_role;

-- RLS: exposed public tables are private to authenticated workspace members.
alter table public.profiles enable row level security;
alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.sales_channels enable row level security;
alter table public.products enable row level security;
alter table public.product_versions enable row level security;
alter table public.product_assets enable row level security;
alter table public.product_external_ids enable row level security;
alter table public.leads enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.entitlements enable row level security;
alter table public.content_ideas enable row level security;
alter table public.customer_feedback enable row level security;
alter table public.change_requests enable row level security;
alter table public.approval_requests enable row level security;
alter table public.webhook_events enable row level security;
alter table public.automation_runs enable row level security;
alter table public.outbound_messages enable row level security;

create policy profiles_select_self on public.profiles for select to authenticated
  using ((select auth.uid()) = id);
create policy profiles_update_self on public.profiles for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy workspaces_select_member on public.workspaces for select to authenticated
  using (private.is_workspace_member(id));
create policy workspaces_insert_owner on public.workspaces for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy workspaces_update_admin on public.workspaces for update to authenticated
  using (private.has_workspace_role(id, array['owner','admin']))
  with check (private.has_workspace_role(id, array['owner','admin']));

create policy members_select_member on public.workspace_members for select to authenticated
  using (private.is_workspace_member(workspace_id));
create policy members_insert_admin on public.workspace_members for insert to authenticated
  with check (private.has_workspace_role(workspace_id, array['owner','admin']));
create policy members_update_owner on public.workspace_members for update to authenticated
  using (private.has_workspace_role(workspace_id, array['owner']))
  with check (private.has_workspace_role(workspace_id, array['owner']));
create policy members_delete_owner on public.workspace_members for delete to authenticated
  using (private.has_workspace_role(workspace_id, array['owner']) and role <> 'owner');

-- Workspace-direct tables.
do $$
declare t text;
begin
  foreach t in array array[
    'sales_channels','products','product_assets','leads','customers','orders','entitlements',
    'content_ideas','customer_feedback','change_requests','approval_requests','automation_runs','outbound_messages'
  ] loop
    execute format('create policy %I_select_member on public.%I for select to authenticated using (private.is_workspace_member(workspace_id))', t, t);
    execute format('create policy %I_insert_operator on public.%I for insert to authenticated with check (private.has_workspace_role(workspace_id, array[''owner'',''admin'',''operator'']))', t, t);
    execute format('create policy %I_update_operator on public.%I for update to authenticated using (private.has_workspace_role(workspace_id, array[''owner'',''admin'',''operator''])) with check (private.has_workspace_role(workspace_id, array[''owner'',''admin'',''operator'']))', t, t);
    execute format('create policy %I_delete_admin on public.%I for delete to authenticated using (private.has_workspace_role(workspace_id, array[''owner'',''admin'']))', t, t);
  end loop;
end;
$$;

-- Tables whose workspace is reached through a parent.
create policy versions_select_member on public.product_versions for select to authenticated using (
  exists (select 1 from public.products p where p.id = product_id and private.is_workspace_member(p.workspace_id))
);
create policy versions_write_operator on public.product_versions for all to authenticated using (
  exists (select 1 from public.products p where p.id = product_id and private.has_workspace_role(p.workspace_id, array['owner','admin','operator']))
) with check (
  exists (select 1 from public.products p where p.id = product_id and private.has_workspace_role(p.workspace_id, array['owner','admin','operator']))
);

create policy external_ids_select_member on public.product_external_ids for select to authenticated using (
  exists (select 1 from public.products p where p.id = product_id and private.is_workspace_member(p.workspace_id))
);
create policy external_ids_write_admin on public.product_external_ids for all to authenticated using (
  exists (select 1 from public.products p where p.id = product_id and private.has_workspace_role(p.workspace_id, array['owner','admin']))
) with check (
  exists (select 1 from public.products p where p.id = product_id and private.has_workspace_role(p.workspace_id, array['owner','admin']))
);

create policy order_items_select_member on public.order_items for select to authenticated using (
  exists (select 1 from public.orders o where o.id = order_id and private.is_workspace_member(o.workspace_id))
);
create policy order_items_write_operator on public.order_items for all to authenticated using (
  exists (select 1 from public.orders o where o.id = order_id and private.has_workspace_role(o.workspace_id, array['owner','admin','operator']))
) with check (
  exists (select 1 from public.orders o where o.id = order_id and private.has_workspace_role(o.workspace_id, array['owner','admin','operator']))
);

-- Raw webhook payloads are deliberately service-role only.
revoke all on public.webhook_events from anon, authenticated;

-- Explicit Data API grants. RLS still determines which rows are accessible.
grant usage on schema public to authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;
revoke all on public.webhook_events from anon, authenticated;

-- Private product asset bucket. Paths must begin with the workspace UUID.
insert into storage.buckets(id, name, public, file_size_limit)
values ('product-assets', 'product-assets', false, 104857600)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

create policy product_assets_read_member on storage.objects for select to authenticated using (
  bucket_id = 'product-assets'
  and split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and private.is_workspace_member(split_part(name, '/', 1)::uuid)
);
create policy product_assets_insert_operator on storage.objects for insert to authenticated with check (
  bucket_id = 'product-assets'
  and split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and private.has_workspace_role(split_part(name, '/', 1)::uuid, array['owner','admin','operator'])
);
create policy product_assets_update_operator on storage.objects for update to authenticated using (
  bucket_id = 'product-assets'
  and split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and private.has_workspace_role(split_part(name, '/', 1)::uuid, array['owner','admin','operator'])
) with check (
  bucket_id = 'product-assets'
  and split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and private.has_workspace_role(split_part(name, '/', 1)::uuid, array['owner','admin','operator'])
);
create policy product_assets_delete_admin on storage.objects for delete to authenticated using (
  bucket_id = 'product-assets'
  and split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and private.has_workspace_role(split_part(name, '/', 1)::uuid, array['owner','admin'])
);
