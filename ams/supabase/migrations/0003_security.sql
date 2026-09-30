-- =====================================================================
-- AMS v1 — 0003: الصلاحيات (Row Level Security)
-- ثلاث لوحات بحجم الصلاحية: الاستقبال ينفّذ، المدير يراقب، المحاسب يُقفل
-- الكتابة على الجداول المالية ممنوعة مباشرة — بتتم بس عن طريق الدوال
-- =====================================================================

do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- ------------------------------ قراءة ------------------------------
-- جداول مرجعية: أي موظف نشط يقرأها
do $$
declare t text;
begin
  foreach t in array array['tracks','courses','periods','groups','lead_sources','app_settings',
                           'closed_months','inventory_items','promo_codes'] loop
    execute format('create policy %I on %I for select to authenticated using (current_staff_id() is not null)',
                   t || '_read_staff', t);
  end loop;
end $$;

-- بيانات الطلاب والحضور: الاستقبال + المدير + المدرب + المحاسب
do $$
declare t text;
begin
  foreach t in array array['students','enrollments','sessions','attendance'] loop
    execute format($f$create policy %I on %I for select to authenticated
                     using (has_role('secretary','manager','instructor','accountant'))$f$, t || '_read', t);
  end loop;
end $$;

create policy payments_read on payments for select to authenticated
  using (has_role('secretary', 'manager', 'accountant'));

create policy referral_read on referral_commissions for select to authenticated
  using (has_role('secretary', 'manager', 'accountant'));

-- المالية والإقفال: المدير + المحاسب
do $$
declare t text;
begin
  foreach t in array array['maintenance_course_ledger','advanced_course_ledger','external_instructors',
                           'maintenance_fund_ledger','expenses','weekly_closures','profit_ledger',
                           'inventory_transactions'] loop
    execute format($f$create policy %I on %I for select to authenticated
                     using (has_role('manager','accountant'))$f$, t || '_read', t);
  end loop;
end $$;

-- الموظف يشوف بياناته وبونصه ومرتبه، والمدير/المحاسب يشوفوا الكل
create policy staff_read on staff for select to authenticated
  using (auth_user_id = auth.uid() or has_role('manager', 'accountant'));
create policy bonus_read on staff_bonus_transactions for select to authenticated
  using (staff_id = current_staff_id() or has_role('manager', 'accountant'));
create policy payroll_read on payroll_runs for select to authenticated
  using (staff_id = current_staff_id() or has_role('manager', 'accountant'));

-- ------------------------------ كتابة ------------------------------
-- الإعدادات والكيانات المرجعية (CRUD قياسي): المدير
do $$
declare t text;
begin
  foreach t in array array['tracks','courses','periods','groups','lead_sources','promo_codes',
                           'external_instructors','staff','inventory_items','app_settings'] loop
    execute format($f$create policy %I on %I for insert to authenticated with check (has_role('manager'))$f$,
                   t || '_ins_mgr', t);
    execute format($f$create policy %I on %I for update to authenticated
                     using (has_role('manager')) with check (has_role('manager'))$f$, t || '_upd_mgr', t);
  end loop;
end $$;

-- تعديل بيانات تواصل الطالب: الاستقبال والمدير
create policy students_update on students for update to authenticated
  using (has_role('secretary', 'manager')) with check (has_role('secretary', 'manager'));

-- المصروفات (PATCH /api/expenses/:id): المحاسب والمدير — والشهر المقفول محمي بتريجر
create policy expenses_ins on expenses for insert to authenticated
  with check (has_role('accountant', 'manager'));
create policy expenses_upd on expenses for update to authenticated
  using (has_role('accountant', 'manager')) with check (has_role('accountant', 'manager'));
create policy expenses_del on expenses for delete to authenticated
  using (has_role('accountant', 'manager'));

-- ------------------------------ الدوال ------------------------------
-- محدش من برّه (anon) يشغّل أي دالة
revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated;

-- دوال الحساب الداخلية بترجع أرقام مالية من غير فحص صلاحية — ممنوعة على الواجهة
revoke execute on function course_month_revenue(uuid, date)   from authenticated;
revoke execute on function calc_maintenance_split(uuid, date) from authenticated;
revoke execute on function calc_advanced_split(uuid, date)    from authenticated;
revoke execute on function assert_payment_month_open(uuid, date) from authenticated;

-- الـ views بتحترم RLS الجداول (security_invoker)
-- الـ grants مفتوحة والـ RLS policies هي اللي بتحدد مين يعمل إيه
grant select, insert, update, delete on all tables in schema public to authenticated;
revoke all on all tables in schema public from anon;
