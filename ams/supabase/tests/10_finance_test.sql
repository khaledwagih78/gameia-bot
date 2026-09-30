-- =====================================================================
-- اختبار شامل للمنطق المالي — بيتشغل على Postgres محلي بعد الـ migrations والـ seed
--   psql -v ON_ERROR_STOP=1 -f 10_finance_test.sql
-- الشهر المختبر = الشهر اللي فات (عشان ينفع يتقفل)
-- =====================================================================
\set QUIET on
\o /dev/null
begin;

-- ---------- تجهيز الموظفين (كـ admin) ----------
insert into staff (id, auth_user_id, full_name, role, base_salary, equity_partner, equity_share_pct, hire_date) values
  ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-00000000000a', 'م. معتز', 'manager', 5000, true, 5, '2026-01-01');
insert into staff (id, auth_user_id, full_name, role, base_salary, enrollment_bonus_amount, hire_date) values
  ('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-00000000000b', 'السكرتارية', 'secretary', 4000, 50, '2026-01-01'),
  ('00000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-00000000000c', 'المحاسب', 'accountant', 1500, 0, '2026-01-01');
update app_settings set maintenance_engineer_staff_id = '00000000-0000-0000-0000-00000000000a',
                        advanced_supervisor_staff_id  = '00000000-0000-0000-0000-00000000000a';
insert into external_instructors (id, name, instructor_share_pct)
values ('00000000-0000-0000-0000-0000000000e1', 'مدرب AI خارجي', 60);
update courses set external_instructor_id = '00000000-0000-0000-0000-0000000000e1' where name = 'الذكاء الاصطناعي';
insert into promo_codes (id, code, owner_name, discount_value, commission_amount)
values ('00000000-0000-0000-0000-0000000000c1', 'AFAQ10', 'أحمد', 50, 100);

select set_config('t.prev', month_of((month_of(today_eg()) - 1))::text, false);
-- يوم في الشهر اللي فات بيوافق weekday = 1 (الاتنين)
select set_config('t.day', (select d::date::text from generate_series(current_setting('t.prev')::date,
        current_setting('t.prev')::date + 27, '1 day') d where extract(dow from d) = 1 limit 1), false);

-- ---------- المدير يعمل المجموعات (RLS insert) ----------
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-00000000000a', false);
set role authenticated;

insert into groups (id, course_id, period_id, weekday, capacity, room, start_date)
select v.id::uuid, c.id, p.id, 1, v.cap, v.room, current_setting('t.prev')::date
  from (values ('00000000-0000-0000-0000-0000000000a1', 'سكراتش للمبتدئين', 1, 12, 'المعمل'),
               ('00000000-0000-0000-0000-0000000000a2', 'صيانة الموبايل واللابتوب', 2, 15, 'المعمل'),
               ('00000000-0000-0000-0000-0000000000a3', 'الذكاء الاصطناعي', 3, 15, 'المعمل'),
               ('00000000-0000-0000-0000-0000000000a4', 'بايثون وأردوينو', 4, 2, 'المعمل')) v(id, course, slot, cap, room)
  join courses c on c.name = v.course join periods p on p.slot_no = v.slot;

-- تعارض: نفس الغرفة/الفترة/اليوم لازم يترفض
do $$ begin
  insert into groups (course_id, period_id, weekday, room)
  select c.id, p.id, 1, 'المعمل' from courses c, periods p where c.name = 'تطوير الويب' and p.slot_no = 1;
  raise exception 'FAIL: clash allowed';
exception when unique_violation then raise notice 'OK  منع تعارض الفترات';
end $$;

-- ---------- السكرتارية تسجّل ----------
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-00000000000b', false);
set role authenticated;

do $$
declare v_direct uuid; v_promo uuid; s_a uuid; s_b uuid; e uuid; i int; v_age_fail boolean := false;
begin
  select id into v_direct from lead_sources where type = 'direct' limit 1;
  select id into v_promo  from lead_sources where type = 'promo_code' limit 1;

  -- مصدر كود بدون كود → رفض
  begin perform register_student('x', '2015-01-01', '010', 'الصف', v_promo);
        raise exception 'FAIL';
  exception when others then if sqlerrm = 'FAIL' then raise; end if; end;
  -- كود مع مصدر مباشر → رفض (مصدر واحد)
  begin perform register_student('x', '2015-01-01', '010', 'الصف', v_direct, 'AFAQ10');
        raise exception 'FAIL';
  exception when others then if sqlerrm = 'FAIL' then raise; end if; end;
  raise notice 'OK  مصدر العميل الإلزامي والمصدر الواحد';

  s_a := register_student('طالب مباشر', (today_eg() - interval '9 years')::date, '0100', 'الصف', v_direct);
  s_b := register_student('طالب بكود',  (today_eg() - interval '9 years')::date, '0101', 'العياط', v_promo, 'afaq10');

  -- سن 9 في مسار الصيانة (12+) → رفض
  begin perform create_enrollment(s_a, '00000000-0000-0000-0000-0000000000a2');
  exception when others then v_age_fail := true; end;
  assert v_age_fail, 'FAIL age check';
  raise notice 'OK  فحص الفئة العمرية';

  perform set_config('t.enr_a', create_enrollment(s_a, '00000000-0000-0000-0000-0000000000a1')::text, false);
  perform set_config('t.enr_b', create_enrollment(s_b, '00000000-0000-0000-0000-0000000000a1')::text, false);

  -- 3 طلاب صيانة + 2 متقدم
  for i in 1..3 loop
    e := create_enrollment(register_student('صيانة ' || i, (today_eg() - interval '14 years')::date, '011', 'أطفيح', v_direct),
                           '00000000-0000-0000-0000-0000000000a2');
    perform set_config('t.m' || i, e::text, false);
  end loop;
  for i in 1..2 loop
    e := create_enrollment(register_student('متقدم ' || i, (today_eg() - interval '17 years')::date, '012', 'الصف', v_direct),
                           '00000000-0000-0000-0000-0000000000a3');
    perform set_config('t.x' || i, e::text, false);
  end loop;

  -- سعة المجموعة (2)
  perform create_enrollment(register_student('س1', (today_eg() - interval '13 years')::date, '0', 'الصف', v_direct), '00000000-0000-0000-0000-0000000000a4', null, false);
  perform create_enrollment(register_student('س2', (today_eg() - interval '13 years')::date, '0', 'الصف', v_direct), '00000000-0000-0000-0000-0000000000a4', null, false);
  begin
    perform create_enrollment(register_student('س3', (today_eg() - interval '13 years')::date, '0', 'الصف', v_direct), '00000000-0000-0000-0000-0000000000a4', null, false);
    raise exception 'FAIL';
  exception when others then if sqlerrm = 'FAIL' then raise exception 'FAIL capacity'; end if; end;
  raise notice 'OK  سعة المجموعة';
end $$;

-- بونص + عمولة + خصم الكود
do $$
declare v_bonus numeric; v_cnt int; v_disc numeric;
begin
  select count(*), sum(amount) into v_cnt, v_bonus from staff_bonus_transactions;
  -- 1 مباشر + 3 صيانة + 2 متقدم = 6 (طالب الكود مايتحسبش) — التسجيلات pending مالهاش بونص
  assert v_cnt = 6 and v_bonus = 300, format('FAIL bonus %s %s', v_cnt, v_bonus);
  select count(*) into v_cnt from referral_commissions where status = 'pending' and amount = 100;
  assert v_cnt = 1, 'FAIL referral';
  select promo_discount into v_disc from enrollments where id = current_setting('t.enr_b')::uuid;
  assert v_disc = 50, 'FAIL discount';
  raise notice 'OK  بونص السكرتارية (6×50) وعمولة الكود بدون ازدواج';
end $$;

-- العمولة متتصرفش قبل الدفع (السكرتارية أصلاً مش مسموح لها)
do $$ begin
  perform pay_referral_commission((select id from referral_commissions limit 1));
  raise exception 'FAIL';
exception when insufficient_privilege then raise notice 'OK  السكرتارية متقدرش تصرف عمولات';
end $$;

-- التحصيل للشهر اللي فات
do $$
declare p date := current_setting('t.prev')::date; d date := current_setting('t.day')::date;
begin
  perform record_payment(current_setting('t.enr_a')::uuid, 600,  p, 'cash', d);
  perform record_payment(current_setting('t.enr_a')::uuid, 20000, p, 'cash', d, 'مبلغ اختبار كبير');
  perform record_payment(current_setting('t.enr_b')::uuid, 550,  p, 'vodafone_cash', d);
  perform record_payment(current_setting('t.m1')::uuid, 800, p, 'cash', d);
  perform record_payment(current_setting('t.m2')::uuid, 800, p, 'cash', d);
  perform record_payment(current_setting('t.m3')::uuid, 800, p, 'cash', d);
  perform record_payment(current_setting('t.x1')::uuid, 900, p, 'instapay', d);
  perform record_payment(current_setting('t.x2')::uuid, 900, p, 'instapay', d);
end $$;

-- الحضور
do $$
declare s uuid; n int;
begin
  s := open_session('00000000-0000-0000-0000-0000000000a1', current_setting('t.day')::date);
  n := mark_attendance(s, jsonb_build_array(
         jsonb_build_object('enrollment_id', current_setting('t.enr_a'), 'status', 'present'),
         jsonb_build_object('enrollment_id', current_setting('t.enr_b'), 'status', 'absent')));
  assert n = 2;
  -- طالب من مجموعة تانية → رفض
  begin
    perform mark_attendance(s, jsonb_build_array(jsonb_build_object('enrollment_id', current_setting('t.m1'), 'status', 'present')));
    raise exception 'FAIL';
  exception when others then if sqlerrm = 'FAIL' then raise exception 'FAIL attendance scope'; end if; end;
  raise notice 'OK  كشف الحضور';
end $$;

-- السكرتارية مش شايفة المصروفات
do $$ declare n int; begin
  select count(*) into n from expenses; assert n = 0;
  begin perform close_profit_month(current_setting('t.prev')::date); raise exception 'FAIL';
  exception when insufficient_privilege then null; end;
  raise notice 'OK  صلاحيات السكرتارية';
end $$;

-- ---------- المحاسب يقفل ----------
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-00000000000c', false);
set role authenticated;

insert into expenses (category, amount, month, expense_date) values
  ('rent', 3000, current_setting('t.prev')::date, current_setting('t.day')::date),
  ('electricity', 500, current_setting('t.prev')::date, current_setting('t.day')::date);

do $$
declare r profit_ledger; m maintenance_course_ledger; a advanced_course_ledger; bal numeric;
begin
  r := close_profit_month(current_setting('t.prev')::date);

  select * into m from maintenance_course_ledger;
  assert m.total_revenue = 2400 and m.consumables_deduction = 1000 and m.engineer_share = 700
     and m.center_share = 700, format('FAIL maintenance %s', m);
  raise notice 'OK  صيانة: 2400 → صندوق 1000 → معتز 700 / مركز 700';

  select * into a from advanced_course_ledger;
  assert a.total_revenue = 1800 and a.supervision_fee_7pct = 126 and a.instructor_share = 1004.40
     and a.center_share = 669.60, format('FAIL advanced %s', a);
  raise notice 'OK  متقدم: 1800 → 7%% = 126 → مدرب 1004.40 / مركز 669.60';

  select balance into bal from v_maintenance_fund_balance;
  assert bal = 1000, 'FAIL fund';

  -- gross 25350 − 1000 − 700 − 126 − 1004.40 = 22519.60
  -- مصروفات: 3500 + رواتب 10500 + بونص (الشهر ده مش اللي فات) 0 + عمولات 0 = 14000
  assert r.gross_revenue = 25350 and r.center_revenue = 22519.60, format('FAIL revenue %s', r);
  assert r.total_expenses = 14000 and r.net_profit = 8519.60, format('FAIL net %s', r);
  assert r.equity_share_total = 425.98, format('FAIL equity %s', r.equity_share_total);
  raise notice 'OK  صافي الربح 8519.60 وحصة 5%% = 425.98';
end $$;

-- الشهر اتقفل: تحصيل/مصروف جديد عليه مرفوض
do $$ begin
  insert into expenses (category, amount, month) values ('other', 1, current_setting('t.prev')::date);
  raise exception 'FAIL';
exception when others then if sqlerrm = 'FAIL' then raise exception 'FAIL expense lock'; end if;
  raise notice 'OK  قفل مصروفات الشهر المقفول';
end $$;

do $$
declare p payroll_runs;
begin
  perform run_payroll(current_setting('t.prev')::date);
  select * into p from payroll_runs where staff_id = '00000000-0000-0000-0000-00000000000a';
  -- 5000 + (700 صيانة + 126 إشراف) + 425.98
  assert p.base_salary = 5000 and p.commission_total = 826 and p.profit_share_total = 425.98
     and p.net_pay = 6251.98, format('FAIL payroll %s', p);
  select * into p from payroll_runs where staff_id = '00000000-0000-0000-0000-00000000000b';
  assert p.net_pay = 4000, format('FAIL secretary payroll %s', p);
  raise notice 'OK  مرتب م. معتز 6251.98 = 5000 + 826 + 425.98';
end $$;

-- الحصة الرأسمالية مستمرة لو المرتب التشغيلي وقف
reset role;
update staff set active = false, base_salary = 0 where id = '00000000-0000-0000-0000-00000000000a';
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-00000000000c', false);
set role authenticated;
do $$
declare p payroll_runs; s record;
begin
  perform run_payroll(current_setting('t.prev')::date);
  select * into p from payroll_runs where staff_id = '00000000-0000-0000-0000-00000000000a';
  assert p.base_salary = 0 and p.profit_share_total = 425.98, format('FAIL equity continuity %s', p);
  select * into s from staff_equity_share('00000000-0000-0000-0000-00000000000a');
  assert s.share = 425.98;
  raise notice 'OK  الحصة الرأسمالية مستقلة عن المرتب والدور';

  perform pay_referral_commission((select id from referral_commissions limit 1));
  assert (select status from referral_commissions limit 1) = 'paid';
  raise notice 'OK  صرف عمولة الكود بعد الدفع';
end $$;

-- الإقفال الأسبوعي
do $$
declare w weekly_closures; ws date;
begin
  ws := current_setting('t.day')::date;
  w := close_week(ws, 'اختبار');
  assert w.total_revenue = 25350 and w.total_expenses = 3500 and w.net_cash = 21850, format('FAIL weekly %s', w);
  assert (select count(*) from weekly_closure_details(ws)) = 10;
  raise notice 'OK  الإقفال الأسبوعي والتصدير';
end $$;

-- صندوق التجديد: صرف + شراء مستهلكات، ومنع السحب على المكشوف
reset role;
insert into inventory_items (id, name, category, unit) values
  ('00000000-0000-0000-0000-0000000000f1', 'قصدير لحام', 'consumable', 'بكرة');
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-00000000000c', false);
set role authenticated;
do $$ begin
  perform spend_maintenance_fund(400, 'شراء قصدير', '00000000-0000-0000-0000-0000000000f1', 4);
  assert (select balance from v_maintenance_fund_balance) = 600;
  begin perform spend_maintenance_fund(601, 'زيادة'); raise exception 'FAIL';
  exception when others then if sqlerrm = 'FAIL' then raise exception 'FAIL overdraft'; end if; end;
  raise notice 'OK  صندوق التجديد (1000 − 400 = 600) ومنع السحب على المكشوف';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-00000000000a', false);
update staff set active = true where id = '00000000-0000-0000-0000-00000000000a';
set role authenticated;
do $$ begin
  perform record_inventory_tx('00000000-0000-0000-0000-0000000000f1', 'consume', 3);
  assert (select quantity from inventory_items where id = '00000000-0000-0000-0000-0000000000f1') = 1;
  begin perform record_inventory_tx('00000000-0000-0000-0000-0000000000f1', 'consume', 5); raise exception 'FAIL';
  exception when others then if sqlerrm = 'FAIL' then raise exception 'FAIL stock'; end if; end;
  raise notice 'OK  حركة المخزون ومنع الرصيد السالب';
end $$;

reset role;
\echo '=== كل الاختبارات نجحت ==='
rollback;
