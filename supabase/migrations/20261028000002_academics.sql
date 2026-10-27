-- =====================================================================
-- Dormy · Faz 2: yazılılar, testler, deneme sınavları, kitap takibi
-- Hepsi etüt grubuna özeldir: grubun öğretmeni (veya admin) yönetir,
-- yurdun tüm personeli okuyabilir.
-- =====================================================================

create type public.assessment_kind as enum ('test', 'trial');
create type public.book_status as enum ('assigned', 'reading', 'finished', 'dropped');

-- Konunun dersine ait olduğunu bileşik FK ile garanti etmek için
alter table public.topics add constraint topics_subject_id_id_key unique (subject_id, id);

-- ---------------------------------------------------------------------
-- Varsayılan modül listesine özel modüller
-- ---------------------------------------------------------------------
create or replace function public.seed_default_modules(t uuid) returns void
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
       array['Günlük'], true, 40),
    (t, 'exams', 'Yazılılar', 'Etüt grubunun yazılı sonuçları (0-100)', 'edit_note', 'study_group', 'exam', null, null,
       array['Günlük'], true, 50),
    (t, 'tests', 'Testler', 'Doğru / yanlış girişi; 3 yanlış 1 doğruyu götürür', 'quiz', 'study_group', 'test', null, null,
       array['Günlük'], true, 60),
    (t, 'trial_exams', 'Deneme Sınavları', 'Çok dersli deneme sınavları', 'assignment', 'study_group', 'trial_exam', null, null,
       array['Günlük'], true, 70),
    (t, 'books', 'Kitap Takibi', 'Öğrencilere kitap ata, okumayı takip et', 'library', 'study_group', 'book', null, null,
       array['Günlük'], true, 80)
  on conflict (tenant_id, code) do nothing;
$$;

select public.seed_default_modules(id) from public.tenants;

-- Özel modül tipleri sadece sistem modülü olabilir ve günlük giriş almaz.
create or replace function public.modules_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and (new.is_system or new.value_type not in ('attendance', 'score', 'yes_no')) then
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

create or replace function public.entries_before_write() returns trigger
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
  else
    raise exception 'Bu modüle günlük giriş yapılamaz' using errcode = '22023';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- Yetki yardımcıları
-- ---------------------------------------------------------------------

-- Yurdun ilgili özel modülü açık mı?
create function public.feature_enabled(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from modules where tenant_id = app_tenant() and code = p_code and is_active)
$$;

-- Etüt grubunu yönetebilir mi? (admin: tüm etüt grupları, öğretmen: kendi grupları)
create function public.can_manage_group(p_group uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_role user_role := app_role();
begin
  if v_role is null or v_role = 'superadmin' then
    return false;
  end if;
  if not exists (select 1 from groups where id = p_group and tenant_id = app_tenant() and kind = 'study') then
    return false;
  end if;
  if v_role = 'admin' then
    return true;
  end if;
  return exists (select 1 from group_teachers where group_id = p_group and teacher_id = auth.uid());
end;
$$;

-- Öğrencinin kitaplarını yönetebilir mi? (admin veya öğrencinin şu anki etüt öğretmeni)
create function public.can_manage_student_books(p_student uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_role user_role := app_role();
begin
  if v_role is null or v_role = 'superadmin' then
    return false;
  end if;
  if not exists (select 1 from students where id = p_student and tenant_id = app_tenant()) then
    return false;
  end if;
  if v_role = 'admin' then
    return true;
  end if;
  return exists (
    select 1
    from group_students gs
    join group_teachers gt on gt.group_id = gs.group_id
    where gs.student_id = p_student and gs.kind = 'study' and gs.end_date is null and gt.teacher_id = auth.uid()
  );
end;
$$;

-- ---------------------------------------------------------------------
-- Yazılılar
-- ---------------------------------------------------------------------
create table public.exams (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  group_id uuid not null,
  group_kind public.group_kind not null default 'study' check (group_kind = 'study'),
  subject_id uuid not null,
  topic_id uuid,
  title text,
  held_on date not null,
  created_by uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, group_id, group_kind) references public.groups (tenant_id, id, kind),
  foreign key (tenant_id, subject_id) references public.subjects (tenant_id, id),
  foreign key (subject_id, topic_id) references public.topics (subject_id, id) on delete set null (topic_id)
);
create index exams_group_idx on public.exams (group_id, held_on desc);

create table public.exam_results (
  tenant_id uuid not null,
  exam_id uuid not null,
  student_id uuid not null,
  score numeric(5, 2) not null check (score between 0 and 100),
  updated_by uuid default auth.uid() references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (exam_id, student_id),
  foreign key (tenant_id, exam_id) references public.exams (tenant_id, id) on delete cascade,
  foreign key (tenant_id, student_id) references public.students (tenant_id, id) on delete cascade
);
create index exam_results_student_idx on public.exam_results (student_id);

-- ---------------------------------------------------------------------
-- Testler ve deneme sınavları (test = tek bölümlü ölçme)
-- ---------------------------------------------------------------------
create table public.assessments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  kind public.assessment_kind not null,
  group_id uuid not null,
  group_kind public.group_kind not null default 'study' check (group_kind = 'study'),
  title text,
  -- testler için ders / konu; denemelerde bölüm bazında
  subject_id uuid,
  topic_id uuid,
  held_on date not null,
  created_by uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  check (kind = 'trial' or subject_id is not null),
  foreign key (tenant_id, group_id, group_kind) references public.groups (tenant_id, id, kind),
  foreign key (tenant_id, subject_id) references public.subjects (tenant_id, id),
  foreign key (subject_id, topic_id) references public.topics (subject_id, id) on delete set null (topic_id)
);
create index assessments_group_idx on public.assessments (group_id, kind, held_on desc);

create table public.assessment_sections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  assessment_id uuid not null,
  name text not null check (length(trim(name)) > 0),
  subject_id uuid,
  question_count int not null check (question_count between 1 and 500),
  sort_order int not null default 0,
  unique (assessment_id, id),
  foreign key (tenant_id, assessment_id) references public.assessments (tenant_id, id) on delete cascade,
  foreign key (tenant_id, subject_id) references public.subjects (tenant_id, id)
);

create table public.assessment_results (
  tenant_id uuid not null,
  assessment_id uuid not null,
  section_id uuid not null,
  student_id uuid not null,
  correct int not null check (correct >= 0),
  wrong int not null check (wrong >= 0),
  -- 3 yanlış 1 doğruyu götürür
  net numeric generated always as (correct - wrong / 3.0) stored,
  updated_by uuid default auth.uid() references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (section_id, student_id),
  foreign key (assessment_id, section_id) references public.assessment_sections (assessment_id, id) on delete cascade,
  foreign key (tenant_id, assessment_id) references public.assessments (tenant_id, id) on delete cascade,
  foreign key (tenant_id, student_id) references public.students (tenant_id, id) on delete cascade
);
create index assessment_results_student_idx on public.assessment_results (student_id);
create index assessment_results_assessment_idx on public.assessment_results (assessment_id);

-- ---------------------------------------------------------------------
-- Kitap takibi
-- ---------------------------------------------------------------------
create table public.books (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  author text,
  page_count int check (page_count is null or page_count > 0),
  created_by uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id, id)
);

create table public.book_assignments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  book_id uuid not null,
  student_id uuid not null,
  status public.book_status not null default 'assigned',
  pages_read int not null default 0 check (pages_read >= 0),
  assigned_on date not null,
  started_on date,
  finished_on date,
  note text,
  assigned_by uuid default auth.uid() references public.profiles (id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (book_id, student_id),
  foreign key (tenant_id, book_id) references public.books (tenant_id, id),
  foreign key (tenant_id, student_id) references public.students (tenant_id, id) on delete cascade
);
create index book_assignments_student_idx on public.book_assignments (student_id);

-- ---------------------------------------------------------------------
-- Tetikleyiciler
-- ---------------------------------------------------------------------
create function public.exam_results_before_write() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select tenant_id into new.tenant_id from exams where id = new.exam_id;
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  new.updated_at := now();
  return new;
end;
$$;
create trigger exam_results_before_write before insert or update on public.exam_results
  for each row execute function public.exam_results_before_write();

create function public.assessment_sections_before_write() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_max int;
begin
  select tenant_id into new.tenant_id from assessments where id = new.assessment_id;
  if tg_op = 'UPDATE' and new.question_count < old.question_count then
    select max(correct + wrong) into v_max from assessment_results where section_id = new.id;
    if v_max is not null and v_max > new.question_count then
      raise exception 'Girilmiş sonuçlarda % cevap var; soru sayısı bundan az olamaz', v_max
        using errcode = 'P0001', hint = 'question_count_too_low';
    end if;
  end if;
  return new;
end;
$$;
create trigger assessment_sections_before_write before insert or update on public.assessment_sections
  for each row execute function public.assessment_sections_before_write();

create function public.assessment_results_before_write() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  s assessment_sections;
begin
  select * into s from assessment_sections where id = new.section_id;
  if not found then
    raise exception 'Bölüm bulunamadı';
  end if;
  new.tenant_id := s.tenant_id;
  new.assessment_id := s.assessment_id;
  if new.correct + new.wrong > s.question_count then
    raise exception 'Doğru + yanlış (%) soru sayısını (%) geçemez', new.correct + new.wrong, s.question_count
      using errcode = 'P0001', hint = 'answers_exceed_questions';
  end if;
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  new.updated_at := now();
  return new;
end;
$$;
create trigger assessment_results_before_write before insert or update on public.assessment_results
  for each row execute function public.assessment_results_before_write();

create function public.book_assignments_before_write() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  b books;
  v_today date;
begin
  select * into b from books where id = new.book_id;
  new.tenant_id := b.tenant_id;
  v_today := tenant_today(b.tenant_id);
  new.assigned_on := coalesce(new.assigned_on, v_today);

  if b.page_count is not null and new.pages_read > b.page_count then
    new.pages_read := b.page_count;
  end if;
  if new.status = 'assigned' and new.pages_read > 0 then
    new.status := 'reading';
  end if;
  if new.status = 'finished' then
    new.finished_on := coalesce(new.finished_on, v_today);
    new.pages_read := coalesce(b.page_count, new.pages_read);
  else
    new.finished_on := null;
  end if;
  if new.status in ('reading', 'finished') then
    new.started_on := coalesce(new.started_on, least(v_today, coalesce(new.finished_on, v_today)));
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger book_assignments_before_write before insert or update on public.book_assignments
  for each row execute function public.book_assignments_before_write();

-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------
alter table public.exams enable row level security;
alter table public.exam_results enable row level security;
alter table public.assessments enable row level security;
alter table public.assessment_sections enable row level security;
alter table public.assessment_results enable row level security;
alter table public.books enable row level security;
alter table public.book_assignments enable row level security;

do $$
declare
  tbl text;
begin
  foreach tbl in array array['exams', 'exam_results', 'assessments', 'assessment_sections', 'assessment_results', 'books', 'book_assignments']
  loop
    execute format(
      'create policy %1$s_select on public.%1$s for select to authenticated using (tenant_id = (select public.app_tenant()))',
      tbl);
  end loop;
end;
$$;

-- yazılılar
create policy exams_write on public.exams for all to authenticated
  using (public.can_manage_group(group_id))
  with check (public.can_manage_group(group_id) and public.feature_enabled('exams'));

create policy exam_results_write on public.exam_results for all to authenticated
  using (public.can_manage_group((select e.group_id from public.exams e where e.id = exam_id)))
  with check (
    public.can_manage_group((select e.group_id from public.exams e where e.id = exam_id))
    and public.feature_enabled('exams'));

-- testler / denemeler
create function public.can_manage_assessment(p_assessment uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select can_manage_group(a.group_id)
       and feature_enabled(case a.kind when 'test' then 'tests' else 'trial_exams' end)
    from assessments a where a.id = p_assessment), false)
$$;

create policy assessments_write on public.assessments for all to authenticated
  using (public.can_manage_group(group_id))
  with check (
    public.can_manage_group(group_id)
    and public.feature_enabled(case kind when 'test' then 'tests' else 'trial_exams' end));

create policy assessment_sections_write on public.assessment_sections for all to authenticated
  using (public.can_manage_assessment(assessment_id))
  with check (public.can_manage_assessment(assessment_id));

create policy assessment_results_write on public.assessment_results for all to authenticated
  using (public.can_manage_assessment(assessment_id))
  with check (public.can_manage_assessment(
    (select s.assessment_id from public.assessment_sections s where s.id = section_id)));

-- kitaplar: personel kataloğa kitap ekleyebilir, ekleyen ya da admin düzenler
create policy books_insert on public.books for insert to authenticated
  with check (
    tenant_id = (select public.app_tenant())
    and (select public.app_role()) in ('admin', 'teacher')
    and public.feature_enabled('books'));
create policy books_update on public.books for update to authenticated
  using (public.is_admin_of(tenant_id) or (created_by = auth.uid() and tenant_id = (select public.app_tenant())))
  with check (tenant_id = (select public.app_tenant()));
create policy books_delete on public.books for delete to authenticated
  using (public.is_admin_of(tenant_id) or (created_by = auth.uid() and tenant_id = (select public.app_tenant())));

create policy book_assignments_write on public.book_assignments for all to authenticated
  using (public.can_manage_student_books(student_id))
  with check (public.can_manage_student_books(student_id) and public.feature_enabled('books'));
