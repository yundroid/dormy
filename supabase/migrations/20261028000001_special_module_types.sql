-- Faz 2: özel (günlük giriş dışındaki) modül tipleri.
-- Enum değerleri ayrı migration'da eklenir; aynı işlemde kullanılamazlar.
alter type public.module_value_type add value if not exists 'exam';
alter type public.module_value_type add value if not exists 'test';
alter type public.module_value_type add value if not exists 'trial_exam';
alter type public.module_value_type add value if not exists 'book';
