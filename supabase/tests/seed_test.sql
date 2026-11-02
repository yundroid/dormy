-- Demo veri betiğinin doğruluğu: hesaplar, ilişkiler, RLS altında görünürlük, temizleme.
\set ON_ERROR_STOP 1
set client_min_messages = warning;

\i seed/demo_data.sql

select id as ta from tenants where name = 'Demo Erkek Öğrenci Yurdu' \gset
select tests.eq((select status from tenants where id = :'ta'), 'active'::tenant_status, 'demo yurt aktif');
select tests.eq((select count(*) from profiles where tenant_id = :'ta' and role = 'teacher' and password_set), 3::bigint, '3 öğretmen, şifresi hazır');
select tests.eq((select count(*) from auth.identities i join auth.users u on u.id = i.user_id where u.email like 'demo.%'), 4::bigint, 'kimlikler');
select tests.eq((select count(*) from auth.users where email like 'demo.%' and encrypted_password like '$2%'), 4::bigint, 'bcrypt şifre');
select tests.eq((select count(*) from students where tenant_id = :'ta'), 36::bigint, '36 öğrenci');
select tests.eq((select count(*) from group_students where tenant_id = :'ta' and end_date is null), 72::bigint, 'her öğrenci 2 grupta');
select tests.eq((select count(*) from modules where tenant_id = :'ta'), 9::bigint, '8 varsayılan + 1 özel modül');
select tests.eq((select count(*) from exams where tenant_id = :'ta'), 9::bigint, '9 yazılı');
select tests.eq((select count(*) from assessments where tenant_id = :'ta' and kind = 'test'), 12::bigint, '12 test');
select tests.eq((select count(*) from assessments where tenant_id = :'ta' and kind = 'trial'), 4::bigint, '4 deneme');
select tests.eq((select count(*) from book_assignments where tenant_id = :'ta' and status = 'reading'), 36::bigint, 'herkes bir kitap okuyor');
select tests.eq((select count(*) from schedule_items where tenant_id = :'ta' and 1 = any(days)), 11::bigint, 'pazartesi programı');

-- Öğretmen gözünden
select tests.login('demo.ogretmen1@example.com');
select tests.eq((select count(*) from module_students((select id from modules where code = 'study_score'))), 12::bigint, 'öğretmen 1: kendi etüdü 12 kişi');
select tests.eq((select count(*) from module_students((select id from modules where code = 'internal_score'))), 18::bigint, 'öğretmen 1: dahili 18 kişi');
select tests.eq((select filled from today_progress() p join modules m on m.id = p.module_id where m.code = 'attendance' and p.session = 0), 36::bigint, 'bugün sabah yoklaması tam');
select tests.eq((select filled from today_progress() p join modules m on m.id = p.module_id where m.code = 'attendance' and p.session = 2), 0::bigint, 'ikindi alınmamış');
select tests.eq((select filled from today_progress() p join modules m on m.id = p.module_id where m.code = 'study_score'), 12::bigint, 'bugün etüt girilmiş');
select tests.logout();

-- Yönetici gözünden: rapor ve uyarılar dolu
select tests.login('demo.yonetici@example.com');
select tests.eq((select count(distinct student_id) from student_report(current_date - 30, current_date)), 36::bigint, 'raporda herkes var');
select tests.eq((select count(*) > 0 from attendance_alerts()), true, 'devamsızlık uyarısı var');
select tests.eq((select bool_and(percent between 0 and 100) from student_report(current_date - 30, current_date) where percent is not null), true, 'yüzdeler 0-100');
select tests.logout();

-- Temizleme
\i seed/demo_temizle.sql
select tests.eq((select count(*) from tenants where id = :'ta'), 0::bigint, 'demo yurt silindi');
select tests.eq((select count(*) from students), 0::bigint, 'öğrenciler silindi');
select tests.eq((select count(*) from auth.users where email like 'demo.%'), 0::bigint, 'demo hesaplar silindi');

-- Temizlikten sonra tekrar yüklenebilir
\i seed/demo_data.sql
select tests.eq((select count(*) from students), 36::bigint, 'yeniden yüklendi');

\echo 'DEMO VERİ TESTLERİ BAŞARILI'
