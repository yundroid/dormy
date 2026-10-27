-- =====================================================================
-- Dormy · Faz 1 şeması
-- Çok kiracılı (multi-tenant) yurt takip sistemi.
-- Her yurt = tenant. Kiracılar arası izolasyon Row Level Security ile
-- veritabanı seviyesinde sağlanır.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tipler
-- ---------------------------------------------------------------------
create type public.user_role as enum ('superadmin', 'admin', 'teacher');
create type public.tenant_status as enum ('pending', 'active', 'suspended');
create type public.account_status as enum ('active', 'disabled');
create type public.student_status as enum ('active', 'left', 'graduated');
-- study = etüt grubu, internal = dahili ders grubu
create type public.group_kind as enum ('study', 'internal');
-- general = yurt geneli (tüm öğretmenler), diğerleri ilgili grubun öğretmenleri
create type public.module_scope as enum ('general', 'study_group', 'internal_group');
create type public.module_value_type as enum ('attendance', 'score', 'yes_no');

-- ---------------------------------------------------------------------
-- Tablolar
-- ---------------------------------------------------------------------
create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  city text,
  address text,
  phone text,
  email text,
  timezone text not null default 'Europe/Istanbul',
  status public.tenant_status not null default 'pending',
  -- null = sınırsız
  max_teachers int default 3 check (max_teachers is null or max_teachers >= 0),
  max_students int default 3 check (max_students is null or max_students >= 0),
  subscription_ends_on date,
  created_at timestamptz not null default now(),
  activated_at timestamptz
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  tenant_id uuid references public.tenants (id) on delete cascade,
  role public.user_role not null,
  full_name text not null,
  email text not null,
  phone text,
  status public.account_status not null default 'active',
  -- davetle gelen kullanıcı ilk girişte şifre belirleyene kadar false
  password_set boolean not null default true,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  unique (tenant_id, id),
  check ((role = 'superadmin') = (tenant_id is null))
);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  email text not null,
  full_name text not null,
  phone text,
  role public.user_role not null check (role in ('admin', 'teacher')),
  invited_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  accepted_at timestamptz
);
create unique index invitations_pending_email_idx
  on public.invitations (lower(email)) where accepted_at is null;

create table public.students (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  first_name text not null check (length(trim(first_name)) > 0),
  last_name text not null check (length(trim(last_name)) > 0),
  school_grade text,
  room_no text,
  phone text,
  guardian_name text,
  guardian_phone text,
  notes text,
  status public.student_status not null default 'active',
  created_at timestamptz not null default now(),
  unique (tenant_id, id)
);
create index students_tenant_idx on public.students (tenant_id, status);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  kind public.group_kind not null,
  name text not null check (length(trim(name)) > 0),
  description text,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, id, kind),
  unique (tenant_id, kind, name)
);

create table public.group_teachers (
  tenant_id uuid not null,
  group_id uuid not null,
  teacher_id uuid not null,
  primary key (group_id, teacher_id),
  foreign key (tenant_id, group_id) references public.groups (tenant_id, id) on delete cascade,
  foreign key (tenant_id, teacher_id) references public.profiles (tenant_id, id) on delete cascade
);
create index group_teachers_teacher_idx on public.group_teachers (teacher_id);

-- Üyelik geçmişi tutulur: grup değişince eski kayıt end_date ile kapanır.
create table public.group_students (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  group_id uuid not null,
  student_id uuid not null,
  kind public.group_kind not null,
  start_date date not null default current_date,
  end_date date,
  check (end_date is null or end_date >= start_date),
  foreign key (tenant_id, group_id, kind) references public.groups (tenant_id, id, kind) on delete cascade,
  foreign key (tenant_id, student_id) references public.students (tenant_id, id) on delete cascade
);
-- Bir öğrenci her türden en fazla bir aktif gruba üye olabilir.
create unique index group_students_one_active_idx
  on public.group_students (student_id, kind) where end_date is null;
create index group_students_group_idx on public.group_students (group_id) where end_date is null;

create table public.subjects (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  sort_order int not null default 0,
  unique (tenant_id, id),
  unique (tenant_id, name)
);

create table public.topics (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  subject_id uuid not null,
  name text not null check (length(trim(name)) > 0),
  sort_order int not null default 0,
  unique (subject_id, name),
  foreign key (tenant_id, subject_id) references public.subjects (tenant_id, id) on delete cascade
);

-- Kontrol modülleri. Varsayılan modüller (is_system) her yurda kopyalanır,
-- admin bunları açıp kapatabilir; yurda özel yeni modüller de buraya eklenir.
create table public.modules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  code text,
  name text not null check (length(trim(name)) > 0),
  description text,
  icon text not null default 'checklist',
  scope public.module_scope not null,
  value_type public.module_value_type not null,
  min_value int,
  max_value int,
  sessions text[] not null default array['Günlük'],
  is_system boolean not null default false,
  is_active boolean not null default true,
  include_in_reports boolean not null default true,
  weight numeric not null default 1 check (weight >= 0),
  sort_order int not null default 100,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, code),
  check (cardinality(sessions) between 1 and 10),
  check (value_type <> 'score' or (min_value is not null and max_value is not null and min_value < max_value))
);

-- Yoklama, puanlama ve özel modüllerin tüm günlük girişleri.
create table public.entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  module_id uuid not null,
  student_id uuid not null,
  entry_date date not null,
  session smallint not null default 0 check (session >= 0),
  -- score / yes_no için sayı
  value numeric,
  -- attendance için: present | absent | excused
  choice text,
  note text,
  recorded_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (module_id, student_id, entry_date, session),
  foreign key (tenant_id, module_id) references public.modules (tenant_id, id) on delete cascade,
  foreign key (tenant_id, student_id) references public.students (tenant_id, id) on delete cascade
);
create index entries_module_date_idx on public.entries (module_id, entry_date);
create index entries_student_date_idx on public.entries (student_id, entry_date);
create index entries_tenant_date_idx on public.entries (tenant_id, entry_date);

-- ---------------------------------------------------------------------
-- Yetki yardımcıları (RLS'i atlayarak profili okur, özyinelemeyi önler)
-- ---------------------------------------------------------------------
create function public.app_role() returns public.user_role
language sql stable security definer set search_path = public as $$
  select p.role
  from profiles p
  left join tenants t on t.id = p.tenant_id
  where p.id = auth.uid()
    and p.status = 'active'
    and (p.role = 'superadmin' or t.status <> 'suspended')
$$;

create function public.app_tenant() returns uuid
language sql stable security definer set search_path = public as $$
  select p.tenant_id
  from profiles p
  join tenants t on t.id = p.tenant_id
  where p.id = auth.uid()
    and p.status = 'active'
    and t.status <> 'suspended'
$$;

create function public.is_superadmin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.app_role() = 'superadmin', false)
$$;

create function public.is_admin_of(t uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.app_role() = 'admin' and public.app_tenant() = t, false)
$$;

-- Yurdun yerel tarihi (sunucu UTC'dir; Türkiye'de gece 00-03 arası kaymayı önler)
create function public.tenant_today(t uuid) returns date
language sql stable security definer set search_path = public as $$
  select (now() at time zone coalesce((select timezone from tenants where id = t), 'Europe/Istanbul'))::date
$$;

-- Öğretmenler en fazla bu kadar gün geriye veri girebilir.
create function public.teacher_backfill_days() returns int
language sql immutable as $$ select 7 $$;

create function public.can_write_entry(p_module uuid, p_student uuid, p_date date)
returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_role user_role := app_role();
  v_tenant uuid := app_tenant();
  v_today date;
  m modules;
begin
  if v_role is null or v_role = 'superadmin' or p_date is null then
    return false;
  end if;

  select * into m from modules where id = p_module and tenant_id = v_tenant and is_active;
  if not found then
    return false;
  end if;

  if not exists (select 1 from students where id = p_student and tenant_id = v_tenant and status = 'active') then
    return false;
  end if;

  v_today := tenant_today(v_tenant);
  if p_date > v_today then
    return false;
  end if;

  -- Admin geçmişe sınırsız düzeltme yapabilir ve tüm gruplara yazabilir.
  if v_role = 'admin' then
    return true;
  end if;

  if p_date < v_today - teacher_backfill_days() then
    return false;
  end if;

  if m.scope = 'general' then
    return true;
  end if;

  return exists (
    select 1
    from group_students gs
    join group_teachers gt on gt.group_id = gs.group_id
    where gs.student_id = p_student
      and gs.end_date is null
      and gt.teacher_id = auth.uid()
      and gs.kind = case m.scope when 'study_group' then 'study'::group_kind else 'internal'::group_kind end
  );
end;
$$;

-- ---------------------------------------------------------------------
-- Tetikleyiciler
-- ---------------------------------------------------------------------

-- Kiracı durum / kota alanlarını sadece superadmin (veya SQL konsolu) değiştirebilir.
create function public.tenants_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if auth.uid() is not null and not is_superadmin() then
    if new.status is distinct from old.status
       or new.max_teachers is distinct from old.max_teachers
       or new.max_students is distinct from old.max_students
       or new.subscription_ends_on is distinct from old.subscription_ends_on
       or new.activated_at is distinct from old.activated_at then
      raise exception 'Bu alanları sadece sistem yöneticisi değiştirebilir' using errcode = '42501';
    end if;
  end if;
  if new.status = 'active' and old.status is distinct from 'active' and new.activated_at is null then
    new.activated_at := now();
  end if;
  return new;
end;
$$;
create trigger tenants_guard before update on public.tenants
  for each row execute function public.tenants_guard();

create function public.profiles_guard() returns trigger
language plpgsql set search_path = public as $$
declare
  v_max int;
  v_count int;
begin
  if auth.uid() is null or is_superadmin() then
    null;
  else
    if new.role is distinct from old.role
       or new.tenant_id is distinct from old.tenant_id
       or new.email is distinct from old.email
       or new.created_at is distinct from old.created_at then
      raise exception 'Bu alan değiştirilemez' using errcode = '42501';
    end if;
    if new.status is distinct from old.status then
      if old.id = auth.uid() then
        raise exception 'Kendi hesabınızın durumunu değiştiremezsiniz' using errcode = '42501';
      end if;
      if old.role <> 'teacher' then
        raise exception 'Yönetici hesaplarını sadece sistem yöneticisi değiştirebilir' using errcode = '42501';
      end if;
    end if;
    if new.password_set is distinct from old.password_set and old.id <> auth.uid() then
      raise exception 'Bu alan değiştirilemez' using errcode = '42501';
    end if;
  end if;

  -- Pasif öğretmen tekrar aktif edilirken kota kontrolü
  if new.role = 'teacher' and new.status = 'active' and old.status = 'disabled' then
    select max_teachers into v_max from tenants where id = new.tenant_id;
    select count(*) into v_count from profiles
      where tenant_id = new.tenant_id and role = 'teacher' and status = 'active' and id <> new.id;
    if v_max is not null and v_count >= v_max then
      raise exception 'Öğretmen kotası dolu (%)', v_max using errcode = 'P0001', hint = 'quota_teachers';
    end if;
  end if;
  return new;
end;
$$;
create trigger profiles_guard before update on public.profiles
  for each row execute function public.profiles_guard();

create function public.invitations_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  t tenants;
  v_count int;
begin
  new.email := lower(trim(new.email));
  new.invited_by := auth.uid();
  select * into t from tenants where id = new.tenant_id;
  if t.status = 'suspended' then
    raise exception 'Yurt hesabı askıya alınmış' using errcode = 'P0001', hint = 'tenant_suspended';
  end if;
  if exists (select 1 from profiles where lower(email) = new.email) then
    raise exception 'Bu e-posta ile kayıtlı bir kullanıcı zaten var' using errcode = 'P0001', hint = 'email_exists';
  end if;
  if new.role = 'teacher' and t.max_teachers is not null then
    select
      (select count(*) from profiles where tenant_id = t.id and role = 'teacher' and status = 'active')
      + (select count(*) from invitations where tenant_id = t.id and role = 'teacher' and accepted_at is null)
    into v_count;
    if v_count >= t.max_teachers then
      raise exception 'Öğretmen kotası dolu (%)', t.max_teachers using errcode = 'P0001', hint = 'quota_teachers';
    end if;
  end if;
  return new;
end;
$$;
create trigger invitations_before_insert before insert on public.invitations
  for each row execute function public.invitations_before_insert();

create function public.students_quota() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_max int;
  v_count int;
begin
  if new.status <> 'active' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'active' then
    return new;
  end if;
  select max_students into v_max from tenants where id = new.tenant_id;
  if v_max is null then
    return new;
  end if;
  select count(*) into v_count from students
    where tenant_id = new.tenant_id and status = 'active' and id <> new.id;
  if v_count >= v_max then
    raise exception 'Öğrenci kotası dolu (%)', v_max using errcode = 'P0001', hint = 'quota_students';
  end if;
  return new;
end;
$$;
create trigger students_quota before insert or update of status on public.students
  for each row execute function public.students_quota();

-- Öğrenci ayrılınca/mezun olunca grup üyelikleri kapanır.
create function public.students_close_memberships() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status <> 'active' and old.status = 'active' then
    update group_students
      set end_date = greatest(start_date, tenant_today(new.tenant_id))
      where student_id = new.id and end_date is null;
  end if;
  return new;
end;
$$;
create trigger students_close_memberships after update of status on public.students
  for each row execute function public.students_close_memberships();

create function public.group_students_set_kind() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select kind into new.kind from groups where id = new.group_id;
  return new;
end;
$$;
create trigger group_students_set_kind before insert or update of group_id on public.group_students
  for each row execute function public.group_students_set_kind();

create function public.modules_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and new.is_system then
      raise exception 'Sistem modülü eklenemez' using errcode = '42501';
    end if;
    return new;
  end if;
  if old.is_system and auth.uid() is not null then
    if new.code is distinct from old.code
       or new.scope is distinct from old.scope
       or new.value_type is distinct from old.value_type
       or new.min_value is distinct from old.min_value
       or new.max_value is distinct from old.max_value
       or new.is_system is distinct from old.is_system then
      raise exception 'Varsayılan modülün yapısı değiştirilemez' using errcode = '42501';
    end if;
  end if;
  -- Veri girilmiş bir modülün ölçeği değiştirilemez (raporlar bozulmasın)
  if exists (select 1 from entries where module_id = old.id) and (
       new.value_type is distinct from old.value_type
       or new.min_value is distinct from old.min_value
       or new.max_value is distinct from old.max_value
       or cardinality(new.sessions) < cardinality(old.sessions)) then
    raise exception 'Veri girilmiş modülün ölçeği değiştirilemez' using errcode = 'P0001', hint = 'module_has_entries';
  end if;
  return new;
end;
$$;
create trigger modules_guard before insert or update on public.modules
  for each row execute function public.modules_guard();

create function public.entries_before_write() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  m modules;
begin
  select * into m from modules where id = new.module_id;
  if not found then
    raise exception 'Modül bulunamadı';
  end if;
  new.tenant_id := m.tenant_id;
  new.recorded_by := coalesce(auth.uid(), new.recorded_by);
  new.updated_at := now();

  if new.session >= cardinality(m.sessions) then
    raise exception 'Geçersiz oturum' using errcode = '22023';
  end if;

  if m.value_type = 'attendance' then
    if new.choice is null or new.choice not in ('present', 'absent', 'excused') then
      raise exception 'Geçersiz yoklama değeri' using errcode = '22023';
    end if;
    new.value := null;
  elsif m.value_type = 'score' then
    if new.value is null or new.value < m.min_value or new.value > m.max_value then
      raise exception 'Puan % ile % arasında olmalı', m.min_value, m.max_value using errcode = '22023';
    end if;
    new.choice := null;
  elsif m.value_type = 'yes_no' then
    if new.value is null or new.value not in (0, 1) then
      raise exception 'Geçersiz değer' using errcode = '22023';
    end if;
    new.choice := null;
  end if;
  return new;
end;
$$;
create trigger entries_before_write before insert or update on public.entries
  for each row execute function public.entries_before_write();

-- Her yeni yurda varsayılan modüller kopyalanır.
create function public.seed_default_modules(t uuid) returns void
language sql security definer set search_path = public as $$
  insert into modules (tenant_id, code, name, description, icon, scope, value_type, min_value, max_value, sessions, is_system, sort_order)
  values
    (t, 'attendance', 'Yoklama', 'Günlük 5 vakit yoklama', 'fact_check', 'general', 'attendance', null, null,
       array['Sabah', 'Öğle', 'İkindi', 'Akşam', 'Yatsı'], true, 10),
    (t, 'bed_locker', 'Yatak-Dolap Düzeni', 'Günlük yatak ve dolap kontrolü (1-5)', 'bed', 'general', 'score', 1, 5,
       array['Günlük'], true, 20),
    (t, 'study_score', 'Etüt Puanlama', 'Etüt grubuna günlük puan (1-5)', 'menu_book', 'study_group', 'score', 1, 5,
       array['Günlük'], true, 30),
    (t, 'internal_score', 'Dahili Ders Puanlama', 'Dahili ders grubuna günlük puan (1-5)', 'school', 'internal_group', 'score', 1, 5,
       array['Günlük'], true, 40)
  on conflict (tenant_id, code) do nothing;
$$;

create function public.tenants_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform seed_default_modules(new.id);
  return new;
end;
$$;
create trigger tenants_after_insert after insert on public.tenants
  for each row execute function public.tenants_after_insert();

-- Yeni auth kullanıcısı: davet varsa davetteki yurda/rolle, yoksa
-- "hesap oluştur" akışıyla gelen yeni yurt kaydı olarak profil oluşturulur.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  inv invitations;
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_tenant uuid;
begin
  select * into inv from invitations
    where lower(email) = lower(new.email) and accepted_at is null
    order by created_at desc limit 1;

  if found then
    insert into profiles (id, tenant_id, role, full_name, email, phone, password_set)
      values (new.id, inv.tenant_id, inv.role, inv.full_name, lower(new.email), inv.phone, false);
    update invitations set accepted_at = now() where id = inv.id;
  elsif meta ->> 'signup_type' = 'tenant' then
    insert into tenants (name, city, phone, email)
      values (
        coalesce(nullif(trim(meta ->> 'tenant_name'), ''), 'Yeni Yurt'),
        nullif(trim(meta ->> 'city'), ''),
        nullif(trim(meta ->> 'phone'), ''),
        lower(new.email))
      returning id into v_tenant;
    insert into profiles (id, tenant_id, role, full_name, email, phone)
      values (
        new.id, v_tenant, 'admin',
        coalesce(nullif(trim(meta ->> 'full_name'), ''), split_part(new.email, '@', 1)),
        lower(new.email),
        nullif(trim(meta ->> 'phone'), ''));
  end if;
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- RPC fonksiyonları
-- ---------------------------------------------------------------------

-- Uygulama açılışında oturum bağlamı (askıya alınmış/pasif durumunu da döner).
create function public.get_my_context() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p profiles;
  t tenants;
begin
  select * into p from profiles where id = auth.uid();
  if not found then
    return null;
  end if;
  update profiles set last_seen_at = now() where id = p.id;
  if p.tenant_id is not null then
    select * into t from tenants where id = p.tenant_id;
  end if;
  return jsonb_build_object(
    'profile', to_jsonb(p),
    'tenant', case when t.id is null then null else to_jsonb(t) end,
    'today', case when t.id is null then (now() at time zone 'Europe/Istanbul')::date else tenant_today(t.id) end,
    'backfill_days', teacher_backfill_days()
  );
end;
$$;

-- Bir modül için mevcut kullanıcının veri girebileceği öğrenciler.
create function public.module_students(p_module uuid)
returns table (
  student_id uuid,
  first_name text,
  last_name text,
  room_no text,
  school_grade text,
  group_id uuid,
  group_name text
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_role user_role := app_role();
  v_tenant uuid := app_tenant();
  m modules;
  v_kind group_kind;
begin
  select * into m from modules where id = p_module and tenant_id = v_tenant;
  if not found or v_role is null then
    return;
  end if;

  if m.scope = 'general' then
    return query
      select s.id, s.first_name, s.last_name, s.room_no, s.school_grade, null::uuid, null::text
      from students s
      where s.tenant_id = v_tenant and s.status = 'active'
      order by s.first_name, s.last_name;
    return;
  end if;

  v_kind := case m.scope when 'study_group' then 'study'::group_kind else 'internal'::group_kind end;
  return query
    select s.id, s.first_name, s.last_name, s.room_no, s.school_grade, g.id, g.name
    from group_students gs
    join groups g on g.id = gs.group_id
    join students s on s.id = gs.student_id
    where gs.tenant_id = v_tenant
      and gs.kind = v_kind
      and gs.end_date is null
      and s.status = 'active'
      and (
        v_role = 'admin'
        or exists (select 1 from group_teachers gt where gt.group_id = g.id and gt.teacher_id = auth.uid())
      )
    order by g.name, s.first_name, s.last_name;
end;
$$;

-- Öğrenciyi bir türdeki gruba ata (null = gruptan çıkar). Geçmiş korunur.
create function public.assign_student_group(p_student uuid, p_kind public.group_kind, p_group uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_tenant uuid;
  v_today date;
  cur group_students;
begin
  select tenant_id into v_tenant from students where id = p_student;
  if v_tenant is null or not is_admin_of(v_tenant) then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_group is not null and not exists (
    select 1 from groups where id = p_group and tenant_id = v_tenant and kind = p_kind and not is_archived) then
    raise exception 'Grup bulunamadı';
  end if;

  v_today := tenant_today(v_tenant);
  select * into cur from group_students where student_id = p_student and kind = p_kind and end_date is null;
  if found then
    if cur.group_id = p_group then
      return;
    end if;
    if cur.start_date >= v_today then
      delete from group_students where id = cur.id;
    else
      update group_students set end_date = v_today - 1 where id = cur.id;
    end if;
  end if;

  if p_group is not null then
    insert into group_students (tenant_id, group_id, student_id, kind, start_date)
      values (v_tenant, p_group, p_student, p_kind, v_today);
  end if;
end;
$$;

-- Superadmin: yurtların özet listesi
create function public.tenant_overview()
returns table (
  id uuid,
  name text,
  city text,
  phone text,
  email text,
  status public.tenant_status,
  max_teachers int,
  max_students int,
  subscription_ends_on date,
  created_at timestamptz,
  activated_at timestamptz,
  admin_count bigint,
  teacher_count bigint,
  student_count bigint,
  pending_invites bigint,
  entries_last_30d bigint,
  last_entry_at timestamptz,
  last_seen_at timestamptz
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_superadmin() then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  return query
    select
      t.id, t.name, t.city, t.phone, t.email, t.status, t.max_teachers, t.max_students,
      t.subscription_ends_on, t.created_at, t.activated_at,
      (select count(*) from profiles p where p.tenant_id = t.id and p.role = 'admin' and p.status = 'active'),
      (select count(*) from profiles p where p.tenant_id = t.id and p.role = 'teacher' and p.status = 'active'),
      (select count(*) from students s where s.tenant_id = t.id and s.status = 'active'),
      (select count(*) from invitations i where i.tenant_id = t.id and i.accepted_at is null),
      (select count(*) from entries e where e.tenant_id = t.id and e.entry_date >= current_date - 30),
      (select max(e.updated_at) from entries e where e.tenant_id = t.id),
      (select max(p.last_seen_at) from profiles p where p.tenant_id = t.id)
    from tenants t
    order by (t.status = 'pending') desc, t.created_at desc;
end;
$$;

-- Davet edilen kullanıcı şifresini belirledikten sonra çağırır.
create function public.mark_password_set() returns void
language sql security definer set search_path = public as $$
  update profiles set password_set = true where id = auth.uid();
$$;

-- Sadece SQL konsolundan çalıştırılır: mevcut bir auth kullanıcısını superadmin yapar.
create function public.promote_superadmin(p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare
  u auth.users;
begin
  select * into u from auth.users where lower(email) = lower(p_email);
  if not found then
    raise exception 'Kullanıcı bulunamadı: %', p_email;
  end if;
  insert into profiles (id, tenant_id, role, full_name, email)
    values (u.id, null, 'superadmin', coalesce(u.raw_user_meta_data ->> 'full_name', 'Sistem Yöneticisi'), lower(u.email))
  on conflict (id) do update set tenant_id = null, role = 'superadmin', status = 'active';
end;
$$;
revoke execute on function public.promote_superadmin(text) from public, anon, authenticated;
revoke execute on function public.seed_default_modules(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------
alter table public.tenants enable row level security;
alter table public.profiles enable row level security;
alter table public.invitations enable row level security;
alter table public.students enable row level security;
alter table public.groups enable row level security;
alter table public.group_teachers enable row level security;
alter table public.group_students enable row level security;
alter table public.subjects enable row level security;
alter table public.topics enable row level security;
alter table public.modules enable row level security;
alter table public.entries enable row level security;

-- tenants
create policy tenants_select on public.tenants for select to authenticated
  using ((select public.is_superadmin()) or id = (select public.app_tenant()));
create policy tenants_update on public.tenants for update to authenticated
  using ((select public.is_superadmin()) or public.is_admin_of(id))
  with check ((select public.is_superadmin()) or public.is_admin_of(id));
create policy tenants_delete on public.tenants for delete to authenticated
  using ((select public.is_superadmin()));

-- profiles
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or (select public.is_superadmin()) or tenant_id = (select public.app_tenant()));
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() or (select public.is_superadmin()) or public.is_admin_of(tenant_id))
  with check (id = auth.uid() or (select public.is_superadmin()) or public.is_admin_of(tenant_id));

-- invitations: admin sadece öğretmen, superadmin admin/öğretmen davet eder
create policy invitations_select on public.invitations for select to authenticated
  using ((select public.is_superadmin()) or public.is_admin_of(tenant_id));
create policy invitations_insert on public.invitations for insert to authenticated
  with check ((select public.is_superadmin()) or (public.is_admin_of(tenant_id) and role = 'teacher'));
create policy invitations_delete on public.invitations for delete to authenticated
  using (accepted_at is null and ((select public.is_superadmin()) or (public.is_admin_of(tenant_id) and role = 'teacher')));

-- Yurt verisi: üyeler okur, adminler yazar
do $$
declare
  tbl text;
begin
  foreach tbl in array array['students', 'groups', 'group_teachers', 'group_students', 'subjects', 'topics', 'modules']
  loop
    execute format(
      'create policy %1$s_select on public.%1$s for select to authenticated using (tenant_id = (select public.app_tenant()))',
      tbl);
    execute format(
      'create policy %1$s_insert on public.%1$s for insert to authenticated with check (public.is_admin_of(tenant_id))',
      tbl);
    execute format(
      'create policy %1$s_update on public.%1$s for update to authenticated using (public.is_admin_of(tenant_id)) with check (public.is_admin_of(tenant_id))',
      tbl);
    execute format(
      'create policy %1$s_delete on public.%1$s for delete to authenticated using (public.is_admin_of(tenant_id))',
      tbl);
  end loop;
end;
$$;

-- Varsayılan modüller silinemez (sadece pasifleştirilir)
drop policy modules_delete on public.modules;
create policy modules_delete on public.modules for delete to authenticated
  using (public.is_admin_of(tenant_id) and not is_system);

-- entries
create policy entries_select on public.entries for select to authenticated
  using (tenant_id = (select public.app_tenant()));
create policy entries_insert on public.entries for insert to authenticated
  with check (public.can_write_entry(module_id, student_id, entry_date));
create policy entries_update on public.entries for update to authenticated
  using (public.can_write_entry(module_id, student_id, entry_date))
  with check (public.can_write_entry(module_id, student_id, entry_date));
create policy entries_delete on public.entries for delete to authenticated
  using (public.can_write_entry(module_id, student_id, entry_date));
