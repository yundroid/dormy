-- =====================================================================
-- Dormy · DEMO VERİLERİ
-- Supabase → SQL Editor'e yapıştırıp bir kez çalıştırın.
-- Kaldırmak için: supabase/seed/demo_temizle.sql
--
-- Oluşturulan hesaplar (şifre hepsinde: Demo1234!)
--   demo.yonetici@example.com    Yönetici
--   demo.ogretmen1@example.com   Öğretmen · 9. Sınıf Etüdü + Dahili Ders A
--   demo.ogretmen2@example.com   Öğretmen · 10. Sınıf Etüdü + Dahili Ders B
--   demo.ogretmen3@example.com   Öğretmen · 11. Sınıf Etüdü
-- example.com adresleri gerçek değildir; bu hesaplara e-posta gitmez.
-- =====================================================================

create or replace function pg_temp.demo_user(p_email text, p_meta jsonb) returns uuid
language plpgsql as $f$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token)
  values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', p_email,
    extensions.crypt('Demo1234!', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, p_meta, now(), now(),
    '', '', '', '');
  insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id::text, v_id,
    jsonb_build_object('sub', v_id::text, 'email', p_email, 'email_verified', true),
    'email', now(), now(), now());
  return v_id;
end;
$f$;

do $$
declare
  v_today date := (now() at time zone 'Europe/Istanbul')::date;
  v_tenant uuid;
  v_admin uuid;
  v_t uuid[] := array[]::uuid[];
  v_g_study uuid[] := array[]::uuid[];
  v_g_int uuid[] := array[]::uuid[];
  v_first text[] := array['Ahmet','Mehmet','Mustafa','Ali','Hüseyin','Hasan','İbrahim','İsmail','Yusuf','Ömer',
    'Emre','Burak','Enes','Furkan','Kerem','Eren','Berat','Yiğit','Muhammed','Abdullah','Emir','Mert','Kaan',
    'Arda','Taha','Hamza','Selim','Bilal','Talha','Oğuz','Cem','Batuhan','Umut','Serkan','Halil','Yasin'];
  v_last text[] := array['Yılmaz','Kaya','Demir','Şahin','Çelik','Yıldız','Yıldırım','Öztürk','Aydın','Özdemir',
    'Arslan','Doğan','Kılıç','Aslan','Çetin','Kara','Koç','Kurt','Özkan','Şimşek','Polat','Erdoğan','Güneş',
    'Aksoy','Taş','Akın','Uçar','Bulut','Keskin','Ateş','Bozkurt','Karaca','Tekin','Turan','Ünal','Yavuz'];
  v_fathers text[] := array['Osman','Recep','Kemal','Murat','Ramazan','Halit','Yaşar','Nihat','Orhan','Sami','Tuncay','Zafer'];
  m_att uuid; m_bed uuid; m_study uuid; m_int uuid; m_def uuid;
  s_mat uuid; s_fiz uuid; s_kim uuid; s_tur uuid;
  r record;
  v_exam uuid;
  v_as uuid;
  i int;
begin
  if exists (select 1 from auth.users where email = 'demo.yonetici@example.com') then
    raise exception 'Demo veriler zaten yüklü. Yeniden yüklemek için önce supabase/seed/demo_temizle.sql dosyasını çalıştırın.';
  end if;
  perform setseed(0.42);

  -- ---- Yurt ve yönetici ("Hesap oluştur" akışıyla aynı tetikleyici)
  v_admin := pg_temp.demo_user('demo.yonetici@example.com', jsonb_build_object(
    'signup_type', 'tenant', 'tenant_name', 'Demo Erkek Öğrenci Yurdu', 'city', 'Ankara',
    'phone', '0312 555 00 00', 'full_name', 'Demo Yönetici'));
  select tenant_id into v_tenant from profiles where id = v_admin;
  update tenants set status = 'active', max_teachers = 20, max_students = 200, address = 'Örnek Mah. Demo Sok. No:1 Çankaya'
    where id = v_tenant;

  -- ---- Öğretmenler (davet akışıyla aynı tetikleyici)
  for i in 1..3 loop
    insert into invitations (tenant_id, email, full_name, phone, role)
      values (v_tenant, format('demo.ogretmen%s@example.com', i),
              (array['Ahmet Hoca','Mehmet Hoca','Yusuf Hoca'])[i], format('0532 555 00 0%s', i), 'teacher');
    v_t := v_t || pg_temp.demo_user(format('demo.ogretmen%s@example.com', i), '{}'::jsonb);
  end loop;
  update profiles set password_set = true, last_seen_at = now() - (random() * interval '2 days') where tenant_id = v_tenant;

  -- ---- Gruplar
  for i in 1..3 loop
    insert into groups (tenant_id, kind, name, description)
      values (v_tenant, 'study', format('%s. Sınıf Etüdü', i + 8), format('%s. sınıf öğrencileri akşam etüdü', i + 8))
      returning id into r;
    v_g_study := v_g_study || r.id;
    insert into group_teachers (tenant_id, group_id, teacher_id) values (v_tenant, r.id, v_t[i]);
  end loop;
  for i in 1..2 loop
    insert into groups (tenant_id, kind, name)
      values (v_tenant, 'internal', format('Dahili Ders %s', chr(64 + i))) returning id into r;
    v_g_int := v_g_int || r.id;
    insert into group_teachers (tenant_id, group_id, teacher_id) values (v_tenant, r.id, v_t[i]);
  end loop;

  -- ---- Dersler ve konular
  insert into subjects (tenant_id, name, sort_order) values
    (v_tenant, 'Matematik', 0), (v_tenant, 'Fizik', 1), (v_tenant, 'Kimya', 2), (v_tenant, 'Biyoloji', 3),
    (v_tenant, 'Türkçe', 4), (v_tenant, 'Tarih', 5), (v_tenant, 'Coğrafya', 6), (v_tenant, 'İngilizce', 7);
  select id into s_mat from subjects where tenant_id = v_tenant and name = 'Matematik';
  select id into s_fiz from subjects where tenant_id = v_tenant and name = 'Fizik';
  select id into s_kim from subjects where tenant_id = v_tenant and name = 'Kimya';
  select id into s_tur from subjects where tenant_id = v_tenant and name = 'Türkçe';
  insert into topics (tenant_id, subject_id, name, sort_order) values
    (v_tenant, s_mat, 'Fonksiyonlar', 0), (v_tenant, s_mat, 'Türev', 1), (v_tenant, s_mat, 'İntegral', 2),
    (v_tenant, s_fiz, 'Hareket', 0), (v_tenant, s_fiz, 'Kuvvet', 1),
    (v_tenant, s_kim, 'Mol Kavramı', 0),
    (v_tenant, s_tur, 'Paragraf', 0), (v_tenant, s_tur, 'Dil Bilgisi', 1);

  -- ---- Yurda özel modül örneği
  insert into modules (tenant_id, name, description, icon, scope, value_type, sessions, sort_order)
    values (v_tenant, 'Defter Kontrolü', 'Etüt defteri düzenli tutuluyor mu?', 'edit_note', 'study_group', 'yes_no',
            array['Günlük'], 90)
    returning id into m_def;
  select id into m_att from modules where tenant_id = v_tenant and code = 'attendance';
  select id into m_bed from modules where tenant_id = v_tenant and code = 'bed_locker';
  select id into m_study from modules where tenant_id = v_tenant and code = 'study_score';
  select id into m_int from modules where tenant_id = v_tenant and code = 'internal_score';

  -- ---- Öğrenciler: 36 kişi, her etütte 12, her dahili grupta 18
  create temp table demo_s (id uuid, idx int, skill numeric, sg uuid, ig uuid, st uuid, it uuid) on commit drop;
  for i in 1..36 loop
    insert into students (tenant_id, first_name, last_name, school_grade, room_no, phone, guardian_name, guardian_phone, created_at)
      values (v_tenant, v_first[i], v_last[i],
              format('%s-%s', 9 + (i - 1) / 12, (array['A','B'])[1 + i % 2]),
              (101 + (i - 1) / 3)::text,
              format('0555 %s %s %s', 100 + i, 10 + i, 20 + i),
              v_fathers[1 + (i % 12)] || ' ' || v_last[i],
              format('0532 %s %s %s', 200 + i, 30 + i, 40 + i),
              now() - interval '45 days')
      returning id into r;
    insert into demo_s values (r.id, i,
      -- 1. ve 13. öğrenci zayıf, 2. ve 14. çok başarılı; diğerleri 0,55-0,95 arası
      case when i in (1, 13) then 0.45 when i in (2, 14) then 0.97 else round((0.55 + random() * 0.4)::numeric, 2) end,
      v_g_study[1 + (i - 1) / 12], v_g_int[1 + (i - 1) / 18], v_t[1 + (i - 1) / 12], v_t[1 + (i - 1) / 18]);
  end loop;
  insert into group_students (tenant_id, group_id, student_id, kind, start_date)
    select v_tenant, sg, id, 'study'::group_kind, v_today - 40 from demo_s
    union all
    select v_tenant, ig, id, 'internal'::group_kind, v_today - 40 from demo_s;

  -- ---- Son 4 hafta yoklama (5 vakit). Bugün sadece sabah ve öğle alınmış.
  -- 1. ve 13. öğrenci son 7 günde sık devamsız (kontrol panelinde uyarı çıkar).
  insert into entries (module_id, student_id, entry_date, session, choice, recorded_by, created_at, updated_at)
  select m_att, s.id, d::date, v.ses,
    case
      when random() < 0.025 then 'excused'
      when random() < (case when s.idx in (1, 13) and d > v_today - 7 then 0.35 else (1 - s.skill) * 0.12 end) then 'absent'
      else 'present'
    end,
    v_t[1 + floor(random() * 3)::int], d + interval '8 hours', d + interval '8 hours'
  from demo_s s
  cross join generate_series(v_today - 27, v_today, interval '1 day') d
  cross join generate_series(0, 4) v(ses)
  where d::date < v_today or v.ses <= 1;

  -- Yatak-dolap (her gün, bugün dahil)
  insert into entries (module_id, student_id, entry_date, value, recorded_by)
  select m_bed, s.id, d::date, greatest(1, least(5, round(s.skill * 5 + (random() - 0.6) * 2))),
         v_t[1 + floor(random() * 3)::int]
  from demo_s s cross join generate_series(v_today - 27, v_today, interval '1 day') d;

  -- Etüt ve dahili ders puanları (pazar hariç; bugün sadece 9. sınıf etüdü girilmiş)
  insert into entries (module_id, student_id, entry_date, value, recorded_by)
  select m_study, s.id, d::date, greatest(1, least(5, round(s.skill * 5 + (random() - 0.5) * 1.6))), s.st
  from demo_s s cross join generate_series(v_today - 27, v_today, interval '1 day') d
  where extract(dow from d) <> 0 and (d::date < v_today or s.idx <= 12);

  insert into entries (module_id, student_id, entry_date, value, recorded_by)
  select m_int, s.id, d::date, greatest(1, least(5, round(s.skill * 5 + (random() - 0.4) * 1.6))), s.it
  from demo_s s cross join generate_series(v_today - 27, v_today - 1, interval '1 day') d
  where extract(dow from d) <> 0;

  -- Defter kontrolü (iki günde bir)
  insert into entries (module_id, student_id, entry_date, value, recorded_by)
  select m_def, s.id, d::date, case when random() < s.skill then 1 else 0 end, s.st
  from demo_s s cross join generate_series(v_today - 26, v_today - 1, interval '2 days') d;

  -- ---- Yazılılar: her etütte 3 yazılı
  for r in
    select g.id as gid, g.ord, x.subject, x.title, x.days_ago
    from unnest(v_g_study) with ordinality g(id, ord)
    cross join (values (s_mat, '1. Dönem 1. Matematik Yazılısı', 18),
                       (s_fiz, '1. Dönem 1. Fizik Yazılısı', 11),
                       (s_tur, '1. Dönem 1. Türkçe Yazılısı', 4)) x(subject, title, days_ago)
  loop
    insert into exams (tenant_id, group_id, subject_id, title, held_on, created_by)
      values (v_tenant, r.gid, r.subject, r.title, v_today - r.days_ago, v_t[r.ord]) returning id into v_exam;
    insert into exam_results (exam_id, student_id, score, updated_by)
      select v_exam, s.id, greatest(15, least(100, round(s.skill * 100 + (random() - 0.5) * 28))), v_t[r.ord]
      from demo_s s where s.sg = r.gid and random() > 0.05;
  end loop;

  -- ---- Testler: her etütte 4 test
  for r in
    select g.id as gid, g.ord, x.subject, x.topic_name, x.q, x.days_ago
    from unnest(v_g_study) with ordinality g(id, ord)
    cross join (values (s_mat, 'Türev', 20, 20), (s_fiz, 'Kuvvet', 15, 13),
                       (s_kim, 'Mol Kavramı', 20, 6), (s_tur, 'Paragraf', 25, 2)) x(subject, topic_name, q, days_ago)
  loop
    insert into assessments (tenant_id, kind, group_id, subject_id, topic_id, title, held_on, created_by)
      values (v_tenant, 'test', r.gid, r.subject,
              (select id from topics where subject_id = r.subject and name = r.topic_name),
              r.topic_name || ' Tarama Testi', v_today - r.days_ago, v_t[r.ord])
      returning id into v_as;
    insert into assessment_sections (tenant_id, assessment_id, name, subject_id, question_count)
      values (v_tenant, v_as, (select name from subjects where id = r.subject), r.subject, r.q);
    insert into assessment_results (section_id, student_id, correct, wrong, updated_by)
      select sec.id, x.id, x.c, least(r.q - x.c, round((r.q - x.c) * random() * 0.7)::int), v_t[r.ord]
      from (select s.id, least(r.q, greatest(0, round(r.q * s.skill * (0.75 + random() * 0.3))::int)) as c
            from demo_s s where s.sg = r.gid and random() > 0.05) x
      cross join (select id from assessment_sections where assessment_id = v_as) sec;
  end loop;

  -- ---- Deneme sınavları: her etütte 1 TYT, 11. sınıfta 1 tane daha
  for r in
    select g.id as gid, g.ord, x.title, x.days_ago
    from unnest(v_g_study) with ordinality g(id, ord)
    cross join (values ('TYT Deneme 1', 8)) x(title, days_ago)
    union all
    select v_g_study[3], 3, 'TYT Deneme 0', 22
  loop
    insert into assessments (tenant_id, kind, group_id, title, held_on, created_by)
      values (v_tenant, 'trial', r.gid, r.title, v_today - r.days_ago, v_t[r.ord]) returning id into v_as;
    insert into assessment_sections (tenant_id, assessment_id, name, subject_id, question_count, sort_order) values
      (v_tenant, v_as, 'Türkçe', s_tur, 40, 0), (v_tenant, v_as, 'Sosyal Bilimler', null, 20, 1),
      (v_tenant, v_as, 'Temel Matematik', s_mat, 40, 2), (v_tenant, v_as, 'Fen Bilimleri', null, 20, 3);
    insert into assessment_results (section_id, student_id, correct, wrong, updated_by)
      select sec.id, x.id, x.c, least(sec.question_count - x.c, round((sec.question_count - x.c) * random() * 0.6)::int), v_t[r.ord]
      from assessment_sections sec
      cross join lateral (
        select s.id, least(sec.question_count, greatest(0, round(sec.question_count * s.skill * (0.6 + random() * 0.35))::int)) as c
        from demo_s s where s.sg = r.gid) x
      where sec.assessment_id = v_as;
  end loop;

  -- ---- Kitaplar
  insert into books (tenant_id, title, author, page_count, created_by) values
    (v_tenant, 'Sefiller', 'Victor Hugo', 420, v_admin),
    (v_tenant, 'Suç ve Ceza', 'Fyodor Dostoyevski', 560, v_admin),
    (v_tenant, 'Simyacı', 'Paulo Coelho', 184, v_t[1]),
    (v_tenant, 'Kürk Mantolu Madonna', 'Sabahattin Ali', 160, v_t[1]),
    (v_tenant, 'Çalıkuşu', 'Reşat Nuri Güntekin', 544, v_t[2]),
    (v_tenant, 'İnce Memed', 'Yaşar Kemal', 436, v_t[2]),
    (v_tenant, 'Hayvan Çiftliği', 'George Orwell', 152, v_t[3]),
    (v_tenant, 'Küçük Prens', 'Antoine de Saint-Exupéry', 112, v_t[3]),
    (v_tenant, 'Saatleri Ayarlama Enstitüsü', 'Ahmet Hamdi Tanpınar', 392, v_admin),
    (v_tenant, 'Nutuk', 'Mustafa Kemal Atatürk', 600, v_admin);
  -- her öğrenciye biri bitmiş, biri okunan iki kitap; başarılılar bir tane daha bitirmiş
  insert into book_assignments (tenant_id, book_id, student_id, status, pages_read, assigned_on, started_on, finished_on, assigned_by)
  select v_tenant, b.id, s.id, 'finished', b.page_count, v_today - 30, v_today - 28,
         v_today - (2 + floor(random() * 24))::int, s.st
  from demo_s s
  join lateral (select id, page_count from books where tenant_id = v_tenant order by md5(s.id::text || title) limit 1) b on true;
  insert into book_assignments (tenant_id, book_id, student_id, status, pages_read, assigned_on, started_on, finished_on, assigned_by)
  select v_tenant, b.id, s.id, 'finished', b.page_count, v_today - 20, v_today - 18,
         v_today - (1 + floor(random() * 15))::int, s.st
  from demo_s s
  join lateral (select id, page_count from books where tenant_id = v_tenant
                and id not in (select book_id from book_assignments where student_id = s.id)
                order by md5(title || s.id::text) limit 1) b on true
  where s.skill > 0.8;
  insert into book_assignments (tenant_id, book_id, student_id, status, pages_read, assigned_on, started_on, assigned_by)
  select v_tenant, b.id, s.id, 'reading', (b.page_count * (0.1 + random() * 0.8))::int, v_today - 10, v_today - 9, s.st
  from demo_s s
  join lateral (select id, page_count from books where tenant_id = v_tenant
                and id not in (select book_id from book_assignments where student_id = s.id)
                order by md5(s.id::text || author) limit 1) b on true;

  raise notice 'Demo yurt oluşturuldu: % öğrenci, % kayıt.',
    (select count(*) from students where tenant_id = v_tenant),
    (select count(*) from entries where tenant_id = v_tenant);
end;
$$;
