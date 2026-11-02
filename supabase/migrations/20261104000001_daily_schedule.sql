-- =====================================================================
-- Günlük program: yönetimin oluşturduğu "başlangıç - bitiş - program"
-- tablosu. Her satır haftanın hangi günlerinde geçerli olduğunu taşır
-- (hafta içi / hafta sonu farklı programlar için).
-- Yönetici yazar, yurdun tüm personeli okur.
-- =====================================================================

create table public.schedule_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  starts_at time not null,
  ends_at time not null,
  title text not null check (length(trim(title)) > 0),
  note text,
  -- 1 = Pazartesi ... 7 = Pazar (ISO)
  days smallint[] not null default array[1, 2, 3, 4, 5, 6, 7]::smallint[],
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (cardinality(days) between 1 and 7 and days <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[])
);
create index schedule_items_tenant_idx on public.schedule_items (tenant_id, starts_at);

alter table public.schedule_items enable row level security;

create policy schedule_items_select on public.schedule_items for select to authenticated
  using (tenant_id = (select public.app_tenant()));
create policy schedule_items_insert on public.schedule_items for insert to authenticated
  with check (public.is_admin_of(tenant_id));
create policy schedule_items_update on public.schedule_items for update to authenticated
  using (public.is_admin_of(tenant_id)) with check (public.is_admin_of(tenant_id));
create policy schedule_items_delete on public.schedule_items for delete to authenticated
  using (public.is_admin_of(tenant_id));
