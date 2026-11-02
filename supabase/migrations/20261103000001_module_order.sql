-- =====================================================================
-- Modül sıralaması
-- Varsayılan sıra: Yoklama, Yatak-Dolap, Etüt, Dahili Ders, Yazılılar,
-- Testler, Kitap Takibi, Deneme Sınavları; yurda özel modüller altta.
-- Yönetici sırayı Kontrol Modülleri ekranından sürükleyerek değiştirebilir.
-- =====================================================================

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
    (t, 'books', 'Kitap Takibi', 'Öğrencilere kitap ata, okumayı takip et', 'library', 'study_group', 'book', null, null,
       array['Günlük'], true, 70),
    (t, 'trial_exams', 'Deneme Sınavları', 'Çok dersli deneme sınavları', 'assignment', 'study_group', 'trial_exam', null, null,
       array['Günlük'], true, 80)
  on conflict (tenant_id, code) do nothing;
$$;

-- Mevcut yurtlarda (sırası elle değiştirilmemişse) Kitap Takibi denemelerin önüne
update public.modules set sort_order = 70 where code = 'books' and sort_order = 80;
update public.modules set sort_order = 80 where code = 'trial_exams' and sort_order = 70;

-- Verilen sırayla 10, 20, 30... atar. RLS: sadece yönetici güncelleyebilir.
create function public.reorder_modules(p_ids uuid[]) returns void
language sql security invoker set search_path = public as $$
  update modules m
  set sort_order = x.ord * 10
  from unnest(p_ids) with ordinality as x(id, ord)
  where m.id = x.id;
$$;
