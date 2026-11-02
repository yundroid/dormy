-- =====================================================================
-- Düzeltme: yurt veya kullanıcı silinirken "kaydı giren" alanlarının
-- (recorded_by / updated_by / assigned_by) ON DELETE SET NULL ile
-- boşaltılması doğrulama tetikleyicilerini çalıştırıyordu. Aynı silme
-- işleminde modül/sınav/kitap da silindiği için tetikleyici hata verip
-- silmeyi durduruyordu (ör. superadmin yurt silemiyordu).
-- Artık güncellemede sadece bu alanlar değişiyorsa doğrulama atlanır.
-- =====================================================================

drop trigger entries_before_write on public.entries;
create trigger entries_before_insert before insert on public.entries
  for each row execute function public.entries_before_write();
create trigger entries_before_update before update on public.entries
  for each row
  when ((to_jsonb(new) - 'recorded_by' - 'updated_at') is distinct from (to_jsonb(old) - 'recorded_by' - 'updated_at'))
  execute function public.entries_before_write();

drop trigger exam_results_before_write on public.exam_results;
create trigger exam_results_before_insert before insert on public.exam_results
  for each row execute function public.exam_results_before_write();
create trigger exam_results_before_update before update on public.exam_results
  for each row
  when ((to_jsonb(new) - 'updated_by' - 'updated_at') is distinct from (to_jsonb(old) - 'updated_by' - 'updated_at'))
  execute function public.exam_results_before_write();

drop trigger assessment_results_before_write on public.assessment_results;
create trigger assessment_results_before_insert before insert on public.assessment_results
  for each row execute function public.assessment_results_before_write();
create trigger assessment_results_before_update before update on public.assessment_results
  for each row
  -- net hesaplanan sütun olduğu için tüm satır yerine sütunlar tek tek karşılaştırılır
  when ((new.tenant_id, new.assessment_id, new.section_id, new.student_id, new.correct, new.wrong)
        is distinct from (old.tenant_id, old.assessment_id, old.section_id, old.student_id, old.correct, old.wrong))
  execute function public.assessment_results_before_write();

drop trigger book_assignments_before_write on public.book_assignments;
create trigger book_assignments_before_insert before insert on public.book_assignments
  for each row execute function public.book_assignments_before_write();
create trigger book_assignments_before_update before update on public.book_assignments
  for each row
  when ((to_jsonb(new) - 'assigned_by' - 'updated_at') is distinct from (to_jsonb(old) - 'assigned_by' - 'updated_at'))
  execute function public.book_assignments_before_write();

-- ---------------------------------------------------------------------
-- Düzeltme: yurt silinirken silme zincirinin sırası yüzünden "ders /
-- grup / kitap hâlâ kullanılıyor" kontrolü, ilgili sınav ve bölümler
-- silinmeden önce çalışıp silmeyi durduruyordu. Kontroller işlem sonuna
-- ertelenir; tek başına ders/grup/kitap silinmeye çalışılırsa koruma aynen
-- devam eder (işlem sonunda yine hata verir).
-- ---------------------------------------------------------------------
alter table public.exams alter constraint exams_tenant_id_group_id_group_kind_fkey deferrable initially deferred;
alter table public.exams alter constraint exams_tenant_id_subject_id_fkey deferrable initially deferred;
alter table public.assessments alter constraint assessments_tenant_id_group_id_group_kind_fkey deferrable initially deferred;
alter table public.assessments alter constraint assessments_tenant_id_subject_id_fkey deferrable initially deferred;
alter table public.assessment_sections alter constraint assessment_sections_tenant_id_subject_id_fkey deferrable initially deferred;
alter table public.book_assignments alter constraint book_assignments_tenant_id_book_id_fkey deferrable initially deferred;
