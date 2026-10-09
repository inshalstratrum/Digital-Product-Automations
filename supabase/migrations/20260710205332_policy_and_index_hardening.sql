-- Cover foreign keys used by RLS, joins, deletes, and operational dashboards.
create index approval_requests_workspace_id_idx on public.approval_requests(workspace_id);
create index approval_requests_requested_by_idx on public.approval_requests(requested_by) where requested_by is not null;
create index approval_requests_decided_by_idx on public.approval_requests(decided_by) where decided_by is not null;
create index automation_runs_workspace_id_idx on public.automation_runs(workspace_id) where workspace_id is not null;
create index change_requests_workspace_id_idx on public.change_requests(workspace_id);
create index change_requests_product_id_idx on public.change_requests(product_id) where product_id is not null;
create index content_ideas_workspace_id_idx on public.content_ideas(workspace_id);
create index content_ideas_submitted_by_idx on public.content_ideas(submitted_by) where submitted_by is not null;
create index customer_feedback_workspace_id_idx on public.customer_feedback(workspace_id);
create index customer_feedback_order_id_idx on public.customer_feedback(order_id) where order_id is not null;
create index customer_feedback_customer_id_idx on public.customer_feedback(customer_id) where customer_id is not null;
create index customer_feedback_product_id_idx on public.customer_feedback(product_id) where product_id is not null;
create index entitlements_workspace_id_idx on public.entitlements(workspace_id);
create index entitlements_customer_id_idx on public.entitlements(customer_id);
create index entitlements_product_id_idx on public.entitlements(product_id);
create index order_items_product_id_idx on public.order_items(product_id);
create index order_items_product_version_id_idx on public.order_items(product_version_id) where product_version_id is not null;
create index orders_workspace_id_idx on public.orders(workspace_id);
create index orders_customer_id_idx on public.orders(customer_id);
create index outbound_messages_workspace_id_idx on public.outbound_messages(workspace_id);
create index outbound_messages_customer_id_idx on public.outbound_messages(customer_id) where customer_id is not null;
create index product_assets_workspace_id_idx on public.product_assets(workspace_id);
create index product_assets_product_version_id_idx on public.product_assets(product_version_id);
create index product_external_ids_product_id_idx on public.product_external_ids(product_id);
create index products_workspace_id_idx on public.products(workspace_id);
create index sales_channels_workspace_id_idx on public.sales_channels(workspace_id);
create index workspace_members_user_id_idx on public.workspace_members(user_id);
create index workspaces_owner_id_idx on public.workspaces(owner_id);

-- Make the service-only intent explicit to the database advisor.
create policy webhook_events_service_role on public.webhook_events
  for all to service_role using (true) with check (true);

-- Split FOR ALL policies so SELECT has one permissive policy per role/table.
drop policy versions_write_operator on public.product_versions;
create policy versions_insert_operator on public.product_versions for insert to authenticated with check (
  exists (select 1 from public.products p where p.id = product_id and private.has_workspace_role(p.workspace_id, array['owner','admin','operator']))
);
create policy versions_update_operator on public.product_versions for update to authenticated using (
  exists (select 1 from public.products p where p.id = product_id and private.has_workspace_role(p.workspace_id, array['owner','admin','operator']))
) with check (
  exists (select 1 from public.products p where p.id = product_id and private.has_workspace_role(p.workspace_id, array['owner','admin','operator']))
);
create policy versions_delete_admin on public.product_versions for delete to authenticated using (
  exists (select 1 from public.products p where p.id = product_id and private.has_workspace_role(p.workspace_id, array['owner','admin']))
);

drop policy external_ids_write_admin on public.product_external_ids;
create policy external_ids_insert_admin on public.product_external_ids for insert to authenticated with check (
  exists (select 1 from public.products p where p.id = product_id and private.has_workspace_role(p.workspace_id, array['owner','admin']))
);
create policy external_ids_update_admin on public.product_external_ids for update to authenticated using (
  exists (select 1 from public.products p where p.id = product_id and private.has_workspace_role(p.workspace_id, array['owner','admin']))
) with check (
  exists (select 1 from public.products p where p.id = product_id and private.has_workspace_role(p.workspace_id, array['owner','admin']))
);
create policy external_ids_delete_admin on public.product_external_ids for delete to authenticated using (
  exists (select 1 from public.products p where p.id = product_id and private.has_workspace_role(p.workspace_id, array['owner','admin']))
);

drop policy order_items_write_operator on public.order_items;
create policy order_items_insert_operator on public.order_items for insert to authenticated with check (
  exists (select 1 from public.orders o where o.id = order_id and private.has_workspace_role(o.workspace_id, array['owner','admin','operator']))
);
create policy order_items_update_operator on public.order_items for update to authenticated using (
  exists (select 1 from public.orders o where o.id = order_id and private.has_workspace_role(o.workspace_id, array['owner','admin','operator']))
) with check (
  exists (select 1 from public.orders o where o.id = order_id and private.has_workspace_role(o.workspace_id, array['owner','admin','operator']))
);
create policy order_items_delete_admin on public.order_items for delete to authenticated using (
  exists (select 1 from public.orders o where o.id = order_id and private.has_workspace_role(o.workspace_id, array['owner','admin']))
);
