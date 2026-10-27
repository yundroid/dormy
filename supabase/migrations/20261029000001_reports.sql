-- =====================================================================
-- Dormy · Faz 3: raporlar
-- Seçilen tarih aralığında her öğrenci ve her aktif modül için
-- yüzdeye çevrilmiş başarı değeri.
--
-- Yüzde kuralları:
--   yoklama     : var / (var + yok)          (izinli sayılmaz)
--   puan        : ortalama / en yüksek puan  (5 üzerinden 4 = %80)
--   evet/hayır  : evet oranı
--   yazılı      : not ortalaması
--   test/deneme : toplam net / toplam soru   (negatif net %0 sayılır)
--   kitap       : yüzde yok; bitirilen kitap ve sayfa sayısı
-- RLS geçerlidir (security invoker): sadece kullanıcının yurdunun verisi.
-- =====================================================================

create function public.student_report(p_from date, p_to date)
returns table (
  student_id uuid,
  module_id uuid,
  -- yüzdeye giren kayıt sayısı (gün/oturum, sınav sayısı, kitap sayısı)
  data_count bigint,
  percent numeric,
  -- modüle göre: yok sayısı / ortalama puan / ortalama not / ortalama net / kitap sayısı
  raw_value numeric,
  -- modüle göre: izinli sayısı / - / - / - / okunan sayfa
  extra numeric
)
language sql stable set search_path = public as $$
  with mods as (
    select * from modules where tenant_id = app_tenant() and is_active
  )
  -- günlük giriş modülleri
  select
    e.student_id,
    m.id,
    case when m.value_type = 'attendance' then count(*) filter (where e.choice in ('present', 'absent')) else count(*) end,
    round(case m.value_type
      when 'attendance' then 100.0 * count(*) filter (where e.choice = 'present')
                             / nullif(count(*) filter (where e.choice in ('present', 'absent')), 0)
      when 'score' then 100.0 * avg(e.value) / m.max_value
      when 'yes_no' then 100.0 * avg(e.value)
    end, 2),
    case when m.value_type = 'attendance' then count(*) filter (where e.choice = 'absent') else round(avg(e.value), 2) end,
    case when m.value_type = 'attendance' then count(*) filter (where e.choice = 'excused') end
  from entries e
  join mods m on m.id = e.module_id
  where e.entry_date between p_from and p_to
    and m.value_type in ('attendance', 'score', 'yes_no')
  group by e.student_id, m.id, m.value_type, m.max_value

  union all

  -- yazılılar
  select r.student_id, m.id, count(*), round(avg(r.score), 2), round(avg(r.score), 2), null
  from exam_results r
  join exams x on x.id = r.exam_id
  join mods m on m.code = 'exams'
  where x.held_on between p_from and p_to
  group by r.student_id, m.id

  union all

  -- testler ve denemeler
  select
    r.student_id,
    m.id,
    count(distinct a.id),
    round(greatest(0, 100.0 * sum(r.net) / nullif(sum(s.question_count), 0)), 2),
    round(sum(r.net) / count(distinct a.id), 2),
    null
  from assessment_results r
  join assessment_sections s on s.id = r.section_id
  join assessments a on a.id = r.assessment_id
  join mods m on m.code = case a.kind when 'test' then 'tests' else 'trial_exams' end
  where a.held_on between p_from and p_to
  group by r.student_id, m.id

  union all

  -- kitaplar
  select ba.student_id, m.id, count(*), null, count(*), sum(coalesce(b.page_count, ba.pages_read))
  from book_assignments ba
  join books b on b.id = ba.book_id
  join mods m on m.code = 'books'
  where ba.status = 'finished' and ba.finished_on between p_from and p_to
  group by ba.student_id, m.id
$$;
