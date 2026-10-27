-- Faz 3: student_report hesaplama ve izolasyon testleri.
\set ON_ERROR_STOP 1
set client_min_messages = warning;

insert into auth.users (email, raw_user_meta_data) values
  ('a1@a.com', '{"signup_type":"tenant","tenant_name":"A Yurdu","full_name":"Ali Admin"}'),
  ('b1@b.com', '{"signup_type":"tenant","tenant_name":"B Yurdu","full_name":"Berk Admin"}');

select tests.login('a1@a.com');
insert into students (tenant_id, first_name, last_name) select id, 'Ahmet', 'Y' from tenants;
insert into students (tenant_id, first_name, last_name) select id, 'Mehmet', 'K' from tenants;
insert into groups (tenant_id, kind, name) select id, 'study', 'Etüt-1' from tenants;
select assign_student_group(s.id, 'study', (select id from groups)) from students s;
insert into subjects (tenant_id, name) select id, 'Matematik' from tenants;
select tests.logout();

select id as ta from tenants where name = 'A Yurdu' \gset
select id as s1 from students where first_name = 'Ahmet' \gset
select id as s2 from students where first_name = 'Mehmet' \gset
select id as g1 from groups \gset
select id as mat from subjects \gset
select id as att from modules where code = 'attendance' and tenant_id = :'ta' \gset
select id as bed from modules where code = 'bed_locker' and tenant_id = :'ta' \gset
select id as ex from modules where code = 'exams' and tenant_id = :'ta' \gset
select id as ts from modules where code = 'tests' and tenant_id = :'ta' \gset
select id as tr from modules where code = 'trial_exams' and tenant_id = :'ta' \gset
select id as bk from modules where code = 'books' and tenant_id = :'ta' \gset

select tests.login('a1@a.com');
-- Ahmet yoklama: 3 var, 1 yok, 1 izinli (aralık içinde) + aralık dışında 1 yok
insert into entries (module_id, student_id, entry_date, session, choice) values
  (:'att', :'s1', current_date, 0, 'present'),
  (:'att', :'s1', current_date, 1, 'present'),
  (:'att', :'s1', current_date - 1, 0, 'present'),
  (:'att', :'s1', current_date - 1, 1, 'absent'),
  (:'att', :'s1', current_date - 2, 0, 'excused'),
  (:'att', :'s1', current_date - 20, 0, 'absent');
-- yatak-dolap: 4 ve 5 -> ort 4,5 -> %90
insert into entries (module_id, student_id, entry_date, value) values
  (:'bed', :'s1', current_date, 4), (:'bed', :'s1', current_date - 1, 5), (:'bed', :'s2', current_date, 2);
-- yazılı: 80 ve 90
insert into exams (tenant_id, group_id, subject_id, held_on) values (:'ta', :'g1', :'mat', current_date), (:'ta', :'g1', :'mat', current_date - 3);
insert into exam_results (exam_id, student_id, score) select id, :'s1', case when held_on = current_date then 80 else 90 end from exams;
-- test: 20 soru, 12 D 6 Y -> net 10 -> %50
insert into assessments (tenant_id, kind, group_id, subject_id, held_on) values (:'ta', 'test', :'g1', :'mat', current_date);
insert into assessment_sections (assessment_id, name, question_count) select id, 'Mat', 20 from assessments where kind = 'test';
insert into assessment_results (section_id, student_id, correct, wrong) select id, :'s1', 12, 6 from assessment_sections;
-- Mehmet çok kötü test: 0 D 9 Y -> net -3 -> %0
insert into assessment_results (section_id, student_id, correct, wrong) select id, :'s2', 0, 9 from assessment_sections;
-- deneme: 2 bölüm (40 + 20 soru), net 30 + 10 = 40 -> %66,67
insert into assessments (tenant_id, kind, group_id, held_on) values (:'ta', 'trial', :'g1', current_date - 2);
insert into assessment_sections (assessment_id, name, question_count, sort_order)
  select id, 'Mat', 40, 0 from assessments where kind = 'trial'
  union all select id, 'Fen', 20, 1 from assessments where kind = 'trial';
insert into assessment_results (section_id, student_id, correct, wrong)
  select s.id, :'s1', case s.name when 'Mat' then 30 else 10 end, 0
  from assessment_sections s join assessments a on a.id = s.assessment_id where a.kind = 'trial';
-- kitap: 1 bitti (300 sayfa), 1 okunuyor
insert into books (tenant_id, title, page_count) values (:'ta', 'Sefiller', 300), (:'ta', 'Nutuk', 500);
insert into book_assignments (book_id, student_id, status) select id, :'s1', 'finished' from books where title = 'Sefiller';
insert into book_assignments (book_id, student_id, pages_read) select id, :'s1', 100 from books where title = 'Nutuk';

create temp table r as select * from student_report(current_date - 7, current_date);
select tests.eq((select percent from r where student_id = :'s1' and module_id = :'att'), 75.00, 'yoklama yüzdesi (izinli hariç)');
select tests.eq((select data_count from r where student_id = :'s1' and module_id = :'att'), 4::bigint, 'yoklama kayıt sayısı');
select tests.eq((select raw_value from r where student_id = :'s1' and module_id = :'att'), 1::numeric, 'yok sayısı');
select tests.eq((select extra from r where student_id = :'s1' and module_id = :'att'), 1::numeric, 'izinli sayısı');
select tests.eq((select percent from r where student_id = :'s1' and module_id = :'bed'), 90.00, 'puan yüzdesi');
select tests.eq((select raw_value from r where student_id = :'s1' and module_id = :'bed'), 4.50, 'ortalama puan');
select tests.eq((select percent from r where student_id = :'s2' and module_id = :'bed'), 40.00, 'düşük puan yüzdesi');
select tests.eq((select percent from r where student_id = :'s1' and module_id = :'ex'), 85.00, 'yazılı ortalaması');
select tests.eq((select percent from r where student_id = :'s1' and module_id = :'ts'), 50.00, 'test yüzdesi');
select tests.eq((select raw_value from r where student_id = :'s1' and module_id = :'ts'), 10.00, 'test ort. net');
select tests.eq((select percent from r where student_id = :'s2' and module_id = :'ts'), 0.00, 'negatif net %0');
select tests.eq((select percent from r where student_id = :'s1' and module_id = :'tr'), 66.67, 'deneme yüzdesi');
select tests.eq((select raw_value from r where student_id = :'s1' and module_id = :'tr'), 40.00, 'deneme toplam net');
select tests.eq((select raw_value from r where student_id = :'s1' and module_id = :'bk'), 1::numeric, 'bitirilen kitap');
select tests.eq((select extra from r where student_id = :'s1' and module_id = :'bk'), 300::numeric, 'okunan sayfa');
drop table r;

-- tarih aralığı daraltılınca eski kayıtlar düşer
select tests.eq((select percent from student_report(current_date, current_date) where student_id = :'s1' and module_id = :'att'), 100.00, 'sadece bugün');
select tests.eq((select percent from student_report(current_date - 30, current_date) where student_id = :'s1' and module_id = :'att'), 60.00, '30 gün');

-- kapalı modül rapora girmez
update modules set is_active = false where id = :'bed';
select tests.eq((select count(*) from student_report(current_date - 7, current_date) where module_id = :'bed'), 0::bigint, 'kapalı modül');
select tests.logout();

-- izolasyon
select tests.login('b1@b.com');
select tests.eq((select count(*) from student_report(current_date - 365, current_date)), 0::bigint, 'B, A raporunu görmez');
select tests.logout();
select tests.eq((select count(*) from student_report(current_date - 365, current_date)), 0::bigint, 'oturumsuz rapor boş');

\echo 'FAZ 3 TESTLERİ BAŞARILI'
