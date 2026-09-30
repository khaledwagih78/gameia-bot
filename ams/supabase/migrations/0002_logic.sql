-- =====================================================================
-- AMS v1 — 0002: الصلاحيات، التريجرز، والدوال (الـ API)
-- كل منطق مالي بيتنفذ عن طريق RPC صريح (supabase.rpc) مش حساب ضمني
-- =====================================================================

-- ---------------------------------------------------------------------
-- هوية المستخدم الحالي
-- ---------------------------------------------------------------------
create or replace function current_staff_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from staff where auth_user_id = auth.uid() and active
$$;

create or replace function current_staff_role() returns staff_role
language sql stable security definer set search_path = public as $$
  select role from staff where auth_user_id = auth.uid() and active
$$;

create or replace function has_role(variadic roles staff_role[]) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(current_staff_role() = any(roles), false)
$$;

create or replace function require_role(variadic roles staff_role[]) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v_id uuid;
begin
  if not has_role(variadic roles) then
    raise exception 'غير مصرح: الصلاحية المطلوبة %', roles using errcode = '42501';
  end if;
  v_id := current_staff_id();
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- تريجرز الحماية
-- ---------------------------------------------------------------------

-- 1) سعة المجموعة (12–15) — مع قفل صف المجموعة لمنع الحجز المزدوج
create or replace function trg_enrollment_capacity() returns trigger
language plpgsql as $$
declare v_capacity int; v_count int;
begin
  if new.status not in ('pending', 'active') then return new; end if;
  if tg_op = 'UPDATE' and old.status in ('pending', 'active') and old.group_id = new.group_id then
    return new;
  end if;
  select capacity into v_capacity from groups where id = new.group_id for update;
  select count(*) into v_count from enrollments
   where group_id = new.group_id and status in ('pending', 'active') and id <> new.id;
  if v_count >= v_capacity then
    raise exception 'المجموعة مكتملة (% من %)', v_count, v_capacity;
  end if;
  return new;
end $$;
create trigger enrollment_capacity before insert or update on enrollments
  for each row execute function trg_enrollment_capacity();

-- 2) منع تعديل تحصيل شهر مقفول (إقفال عام أو إقفال كورس صيانة/متقدم)
create or replace function assert_payment_month_open(p_enrollment_id uuid, p_month date) returns void
language plpgsql as $$
declare v_course uuid;
begin
  if exists (select 1 from closed_months where month = p_month) then
    raise exception 'شهر % مقفول — مينفعش تعديل التحصيل', to_char(p_month, 'YYYY-MM');
  end if;
  select g.course_id into v_course from enrollments e join groups g on g.id = e.group_id
   where e.id = p_enrollment_id;
  if exists (select 1 from maintenance_course_ledger where course_id = v_course and month = p_month)
     or exists (select 1 from advanced_course_ledger where course_id = v_course and month = p_month) then
    raise exception 'الكورس ده اتقفل لشهر % — مينفعش تعديل التحصيل', to_char(p_month, 'YYYY-MM');
  end if;
end $$;

create or replace function trg_payment_lock() returns trigger
language plpgsql as $$
begin
  if tg_op <> 'INSERT' then perform assert_payment_month_open(old.enrollment_id, old.month_covered); end if;
  if tg_op <> 'DELETE' then perform assert_payment_month_open(new.enrollment_id, new.month_covered); end if;
  return coalesce(new, old);
end $$;
create trigger payment_lock before insert or update or delete on payments
  for each row execute function trg_payment_lock();

-- 3) منع تعديل مصروفات شهر مقفول
create or replace function trg_expense_lock() returns trigger
language plpgsql as $$
begin
  if (tg_op <> 'INSERT' and exists (select 1 from closed_months where month = old.month))
     or (tg_op <> 'DELETE' and exists (select 1 from closed_months where month = new.month)) then
    raise exception 'الشهر مقفول — مينفعش تعديل المصروفات';
  end if;
  return coalesce(new, old);
end $$;
create trigger expense_lock before insert or update or delete on expenses
  for each row execute function trg_expense_lock();

-- 4) الرصيد التراكمي لصندوق التجديد — ومنع السحب على المكشوف
create or replace function trg_fund_balance() returns trigger
language plpgsql as $$
declare v_last numeric;
begin
  perform pg_advisory_xact_lock(hashtext('maintenance_fund_ledger'));
  select running_balance into v_last from maintenance_fund_ledger
   order by created_at desc, id desc limit 1;
  v_last := coalesce(v_last, 0);
  new.running_balance := v_last + case when new.direction = 'in' then new.amount else -new.amount end;
  if new.running_balance < 0 then
    raise exception 'رصيد صندوق التجديد مش كفاية (المتاح %)', v_last;
  end if;
  new.created_at := clock_timestamp();
  return new;
end $$;
create trigger fund_balance before insert on maintenance_fund_ledger
  for each row execute function trg_fund_balance();

create or replace function trg_fund_immutable() returns trigger
language plpgsql as $$
begin
  raise exception 'دفتر الصندوق للإضافة فقط — اعمل حركة عكسية بدل التعديل';
end $$;
create trigger fund_immutable before update or delete on maintenance_fund_ledger
  for each row execute function trg_fund_immutable();

-- 5) تحديث كمية الصنف مع كل حركة مخزون
create or replace function trg_inventory_apply() returns trigger
language plpgsql as $$
begin
  update inventory_items
     set quantity  = quantity + new.quantity,
         unit_cost = case when new.tx_type = 'purchase' and new.unit_cost is not null
                          then new.unit_cost else unit_cost end,
         purchase_date = case when new.tx_type = 'purchase' then today_eg() else purchase_date end
   where id = new.item_id;
  return new;
exception when check_violation then
  raise exception 'الكمية في المخزن مش كفاية';
end $$;
create trigger inventory_apply after insert on inventory_transactions
  for each row execute function trg_inventory_apply();

-- ---------------------------------------------------------------------
-- Views (security_invoker = بتحترم RLS الخاصة بالمستخدم)
-- ---------------------------------------------------------------------
create view v_enrollment_roster with (security_invoker = true) as
select e.id as enrollment_id, e.status, e.group_id, e.student_id,
       s.full_name, s.guardian_phone, s.area,
       date_part('year', age(today_eg(), s.birth_date))::int as age,
       c.id as course_id, c.name as course_name, c.type as course_type,
       coalesce(e.monthly_fee_override, c.monthly_fee) as effective_fee,
       e.promo_discount, e.activated_at
  from enrollments e
  join students s on s.id = e.student_id
  join groups g   on g.id = e.group_id
  join courses c  on c.id = g.course_id;

create view v_group_occupancy with (security_invoker = true) as
select g.id as group_id, g.label, g.room, g.weekday, g.capacity, g.active,
       p.id as period_id, p.slot_no, p.label as period_label, p.start_time, p.end_time,
       c.id as course_id, c.name as course_name, c.type as course_type,
       t.name as track_name,
       count(e.id) filter (where e.status = 'active')  as active_count,
       count(e.id) filter (where e.status = 'pending') as pending_count,
       g.capacity - count(e.id) filter (where e.status in ('active', 'pending')) as free_seats
  from groups g
  join periods p on p.id = g.period_id
  join courses c on c.id = g.course_id
  join tracks t  on t.id = c.track_id
  left join enrollments e on e.group_id = g.id
 group by g.id, p.id, c.id, t.id;

create view v_revenue_by_track with (security_invoker = true) as
select pay.month_covered as month, t.id as track_id, t.name as track_name,
       c.type as course_type, sum(pay.amount) as revenue, count(*) as payments_count
  from payments pay
  join enrollments e on e.id = pay.enrollment_id
  join groups g      on g.id = e.group_id
  join courses c     on c.id = g.course_id
  join tracks t      on t.id = c.track_id
 group by pay.month_covered, t.id, c.type;

create view v_promo_performance with (security_invoker = true) as
select pc.id, pc.code, pc.owner_name, pc.active,
       count(distinct s.id) as students_registered,
       count(distinct rc.student_id) as students_activated,
       coalesce(sum(rc.amount) filter (where rc.status = 'pending'), 0) as commission_pending,
       coalesce(sum(rc.amount) filter (where rc.status = 'paid'), 0)    as commission_paid
  from promo_codes pc
  left join students s on s.promo_code_id = pc.id
  left join referral_commissions rc on rc.promo_code_id = pc.id and rc.student_id = s.id
 group by pc.id;

create view v_maintenance_fund_balance with (security_invoker = true) as
select coalesce((select running_balance from maintenance_fund_ledger
                  order by created_at desc, id desc limit 1), 0) as balance;

create view v_unpaid_enrollments with (security_invoker = true) as
select r.*, m.month,
       coalesce((select sum(amount) from payments p
                  where p.enrollment_id = r.enrollment_id and p.month_covered = m.month), 0) as paid
  from v_enrollment_roster r
 cross join (select month_of(today_eg()) as month) m
 where r.status = 'active';

-- ---------------------------------------------------------------------
-- الطلاب والتسجيل  (POST /api/students, /api/enrollments)
-- ---------------------------------------------------------------------
create or replace function check_promo_code(p_code text)
returns table (id uuid, code text, owner_name text, discount_value numeric, commission_amount numeric)
language sql stable security definer set search_path = public as $$
  select id, code, owner_name, discount_value, commission_amount
    from promo_codes where code = upper(trim(p_code)) and active
$$;

create or replace function register_student(
  p_full_name text, p_birth_date date, p_guardian_phone text, p_area service_area,
  p_lead_source_id uuid, p_promo_code text default null, p_phone text default null,
  p_guardian_name text default null, p_notes text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_staff uuid; v_type lead_source_type; v_promo uuid; v_id uuid;
begin
  v_staff := require_role('secretary', 'manager');
  select type into v_type from lead_sources where id = p_lead_source_id and active;
  if v_type is null then raise exception 'لازم تختار مصدر العميل'; end if;

  -- مصدر واحد بس لكل طالب: الكود مسموح فقط لو المصدر = كود ترويجي
  if v_type = 'promo_code' then
    if nullif(trim(p_promo_code), '') is null then
      raise exception 'المصدر كود ترويجي — لازم تكتب الكود';
    end if;
    select id into v_promo from check_promo_code(p_promo_code);
    if v_promo is null then raise exception 'الكود % مش موجود أو متوقف', upper(p_promo_code); end if;
  elsif nullif(trim(p_promo_code), '') is not null then
    raise exception 'فيه كود مكتوب لكن المصدر مش "كود ترويجي" — اختار مصدر واحد بس';
  end if;

  insert into students (full_name, birth_date, phone, guardian_name, guardian_phone, area,
                        lead_source_id, promo_code_id, notes, created_by)
  values (trim(p_full_name), p_birth_date, p_phone, p_guardian_name, p_guardian_phone, p_area,
          p_lead_source_id, v_promo, p_notes, v_staff)
  returning id into v_id;
  return v_id;
end $$;

create or replace function activate_enrollment(p_enrollment_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_staff uuid; e enrollments; s students; v_src lead_source_type;
  v_settings app_settings; v_bonus numeric; v_month date := month_of(today_eg());
begin
  v_staff := require_role('secretary', 'manager');
  select * into e from enrollments where id = p_enrollment_id for update;
  if e.id is null then raise exception 'التسجيل مش موجود'; end if;
  if e.status = 'active' then return; end if;
  if e.status not in ('pending', 'suspended') then
    raise exception 'مينفعش تفعيل تسجيل حالته %', e.status;
  end if;

  update enrollments set status = 'active', activated_at = now(), activated_by = v_staff
   where id = p_enrollment_id;

  select * into s from students where id = e.student_id;
  select type into v_src from lead_sources where id = s.lead_source_id;
  select * into v_settings from app_settings;

  -- عمولة الكود: مرة واحدة للطالب (unique على student_id)
  if v_src = 'promo_code' and s.promo_code_id is not null then
    insert into referral_commissions (promo_code_id, student_id, enrollment_id, amount, month)
    select s.promo_code_id, s.id, e.id, pc.commission_amount, v_month
      from promo_codes pc where pc.id = s.promo_code_id
    on conflict (student_id) do nothing;
  end if;

  -- بونص السكرتارية على التفعيل (مرة واحدة لكل تسجيل)
  -- ممنوع لو الطالب جاي بكود، إلا لو الإعداد secretary_bonus_on_promo_leads مفعّل
  if v_src <> 'promo_code' or v_settings.secretary_bonus_on_promo_leads then
    select enrollment_bonus_amount into v_bonus from staff where id = v_staff and role = 'secretary';
    if coalesce(v_bonus, 0) > 0 then
      insert into staff_bonus_transactions (staff_id, enrollment_id, type, amount, month, created_by)
      values (v_staff, e.id, 'enrollment_activation', v_bonus, v_month, v_staff)
      on conflict do nothing;
    end if;
  end if;
end $$;

create or replace function create_enrollment(
  p_student_id uuid, p_group_id uuid, p_monthly_fee_override numeric default null,
  p_activate boolean default true, p_skip_age_check boolean default false
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_staff uuid; v_age int; t tracks; v_discount numeric := 0; v_id uuid;
begin
  v_staff := require_role('secretary', 'manager');
  if not exists (select 1 from groups where id = p_group_id and active) then
    raise exception 'المجموعة مش موجودة أو متوقفة';
  end if;

  select date_part('year', age(today_eg(), birth_date))::int into v_age from students where id = p_student_id;
  if v_age is null then raise exception 'الطالب مش موجود'; end if;
  select t2.* into t from groups g join courses c on c.id = g.course_id join tracks t2 on t2.id = c.track_id
   where g.id = p_group_id;
  if not p_skip_age_check and (v_age < t.min_age or (t.max_age is not null and v_age > t.max_age)) then
    raise exception 'سن الطالب % خارج فئة مسار % (% – %)', v_age, t.name, t.min_age, coalesce(t.max_age::text, '+');
  end if;

  -- خصم الكود على أول تسجيل للطالب بس
  if not exists (select 1 from enrollments where student_id = p_student_id) then
    select coalesce(pc.discount_value, 0) into v_discount
      from students s join promo_codes pc on pc.id = s.promo_code_id where s.id = p_student_id;
  end if;

  insert into enrollments (student_id, group_id, monthly_fee_override, promo_discount)
  values (p_student_id, p_group_id, p_monthly_fee_override, coalesce(v_discount, 0))
  returning id into v_id;

  if p_activate then perform activate_enrollment(v_id); end if;
  return v_id;
end $$;

create or replace function set_enrollment_status(p_enrollment_id uuid, p_status enrollment_status)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform require_role('secretary', 'manager');
  if p_status = 'active' then
    perform activate_enrollment(p_enrollment_id);
  else
    update enrollments set status = p_status where id = p_enrollment_id;
    -- إلغاء عمولة الكود لو اتلغى قبل ما تتصرف
    if p_status = 'cancelled' then
      update referral_commissions set status = 'cancelled'
       where enrollment_id = p_enrollment_id and status = 'pending';
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- الحضور  (POST /api/sessions/:id/attendance)
-- ---------------------------------------------------------------------
create or replace function open_session(p_group_id uuid, p_date date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_date date := coalesce(p_date, today_eg()); v_weekday int;
begin
  perform require_role('secretary', 'manager', 'instructor');
  select weekday into v_weekday from groups where id = p_group_id;
  if v_weekday is null then raise exception 'المجموعة مش موجودة'; end if;
  if extract(dow from v_date)::int <> v_weekday then
    raise exception 'المجموعة دي مش ميعادها يوم %', to_char(v_date, 'YYYY-MM-DD');
  end if;
  insert into sessions (group_id, session_date) values (p_group_id, v_date)
  on conflict (group_id, session_date) do update set group_id = excluded.group_id
  returning id into v_id;
  return v_id;
end $$;

-- p_records = [{"enrollment_id": "...", "status": "present"}, ...]
create or replace function mark_attendance(p_session_id uuid, p_records jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_staff uuid; v_group uuid; v_count int;
begin
  v_staff := require_role('secretary', 'manager', 'instructor');
  select group_id into v_group from sessions where id = p_session_id;
  if v_group is null then raise exception 'الحصة مش موجودة'; end if;

  if exists (select 1 from jsonb_array_elements(p_records) r
              left join enrollments e on e.id = (r->>'enrollment_id')::uuid and e.group_id = v_group
             where e.id is null) then
    raise exception 'فيه طالب مش مسجل في المجموعة دي';
  end if;

  insert into attendance (session_id, enrollment_id, attendance_status, marked_by)
  select p_session_id, (r->>'enrollment_id')::uuid, (r->>'status')::attendance_status, v_staff
    from jsonb_array_elements(p_records) r
  on conflict (session_id, enrollment_id)
  do update set attendance_status = excluded.attendance_status,
                marked_by = excluded.marked_by, marked_at = now();
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- ---------------------------------------------------------------------
-- التحصيل  (POST /api/payments)
-- ---------------------------------------------------------------------
create or replace function record_payment(
  p_enrollment_id uuid, p_amount numeric, p_month date default null,
  p_method payment_method default 'cash', p_payment_date date default null, p_notes text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_staff uuid; v_id uuid;
begin
  v_staff := require_role('secretary', 'manager');
  if not exists (select 1 from enrollments where id = p_enrollment_id and status in ('active', 'suspended', 'completed')) then
    raise exception 'التسجيل مش مفعّل — فعّله الأول';
  end if;
  insert into payments (enrollment_id, amount, month_covered, method, payment_date, received_by, notes)
  values (p_enrollment_id, p_amount, month_of(coalesce(p_month, today_eg())), p_method,
          coalesce(p_payment_date, today_eg()), v_staff, p_notes)
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- محركات القسمة (حساب بدون حفظ) — مستخدمة في الإقفال والمعاينة
-- ---------------------------------------------------------------------
create or replace function course_month_revenue(p_course_id uuid, p_month date)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(p.amount), 0)
    from payments p join enrollments e on e.id = p.enrollment_id join groups g on g.id = e.group_id
   where g.course_id = p_course_id and p.month_covered = p_month
$$;

-- الصيانة: استقطاع 1000 للصندوق أولاً، ثم 50/50
create or replace function calc_maintenance_split(p_course_id uuid, p_month date,
  out total_revenue numeric, out consumables_deduction numeric, out distributable numeric,
  out engineer_share numeric, out center_share numeric)
language plpgsql stable security definer set search_path = public as $$
declare st app_settings;
begin
  select * into st from app_settings;
  total_revenue         := course_month_revenue(p_course_id, p_month);
  consumables_deduction := least(total_revenue, st.maintenance_fund_deduction);
  distributable         := total_revenue - consumables_deduction;
  engineer_share        := round(distributable * st.maintenance_engineer_pct / 100, 2);
  center_share          := distributable - engineer_share;
end $$;

-- المتقدم: 7% إشراف (فقط لو فيه مدرب خارجي)، والباقي مركز + مدرب حسب العقد
create or replace function calc_advanced_split(p_course_id uuid, p_month date,
  out total_revenue numeric, out supervision_fee numeric,
  out instructor_share numeric, out center_share numeric, out external_instructor_id uuid)
language plpgsql stable security definer set search_path = public as $$
declare st app_settings; v_pct numeric; v_rest numeric;
begin
  select * into st from app_settings;
  select c.external_instructor_id, ei.instructor_share_pct into external_instructor_id, v_pct
    from courses c left join external_instructors ei on ei.id = c.external_instructor_id
   where c.id = p_course_id;
  total_revenue := course_month_revenue(p_course_id, p_month);
  if external_instructor_id is null then
    supervision_fee := 0; instructor_share := 0; center_share := total_revenue;
  else
    supervision_fee  := round(total_revenue * st.advanced_supervision_pct / 100, 2);
    v_rest           := total_revenue - supervision_fee;
    instructor_share := round(v_rest * v_pct / 100, 2);
    center_share     := v_rest - instructor_share;
  end if;
end $$;

-- POST /api/maintenance-courses/:id/close-month
create or replace function close_maintenance_month(p_course_id uuid, p_month date)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_staff uuid; r record; v_id uuid; v_engineer uuid; v_month date := month_of(p_month);
begin
  v_staff := require_role('accountant', 'manager');
  if not exists (select 1 from courses where id = p_course_id and type = 'maintenance') then
    raise exception 'الكورس ده مش كورس صيانة';
  end if;
  if exists (select 1 from maintenance_course_ledger where course_id = p_course_id and month = v_month) then
    raise exception 'الكورس ده اتقفل قبل كده لشهر %', to_char(v_month, 'YYYY-MM');
  end if;
  select maintenance_engineer_staff_id into v_engineer from app_settings;
  if v_engineer is null then raise exception 'حدد مهندس الصيانة في الإعدادات الأول'; end if;

  select * into r from calc_maintenance_split(p_course_id, v_month);
  insert into maintenance_course_ledger (course_id, month, total_revenue, consumables_deduction,
       distributable, engineer_staff_id, engineer_share, center_share, closed_by)
  values (p_course_id, v_month, r.total_revenue, r.consumables_deduction, r.distributable,
          v_engineer, r.engineer_share, r.center_share, v_staff)
  returning id into v_id;

  if r.consumables_deduction > 0 then
    insert into maintenance_fund_ledger (transaction_date, amount, direction, source_course_id,
                                         maintenance_ledger_id, description, created_by)
    values (today_eg(), r.consumables_deduction, 'in', p_course_id, v_id,
            'استقطاع صيانة شهر ' || to_char(v_month, 'YYYY-MM'), v_staff);
  end if;
  return v_id;
end $$;

-- POST /api/advanced-courses/:id/close-month
create or replace function close_advanced_month(p_course_id uuid, p_month date)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_staff uuid; r record; v_id uuid; v_supervisor uuid; v_month date := month_of(p_month);
begin
  v_staff := require_role('accountant', 'manager');
  if not exists (select 1 from courses where id = p_course_id and type = 'advanced') then
    raise exception 'الكورس ده مش كورس متقدم';
  end if;
  if exists (select 1 from advanced_course_ledger where course_id = p_course_id and month = v_month) then
    raise exception 'الكورس ده اتقفل قبل كده لشهر %', to_char(v_month, 'YYYY-MM');
  end if;
  select * into r from calc_advanced_split(p_course_id, v_month);
  if r.supervision_fee > 0 then
    select advanced_supervisor_staff_id into v_supervisor from app_settings;
    if v_supervisor is null then raise exception 'حدد المشرف (م. معتز) في الإعدادات الأول'; end if;
  end if;
  insert into advanced_course_ledger (course_id, month, external_instructor_id, total_revenue,
       supervision_fee_7pct, supervisor_staff_id, instructor_share, center_share, closed_by)
  values (p_course_id, v_month, r.external_instructor_id, r.total_revenue, r.supervision_fee,
          v_supervisor, r.instructor_share, r.center_share, v_staff)
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- صندوق التجديد والمخزون
-- ---------------------------------------------------------------------
-- صرف من الصندوق (ولو فيه صنف، بيتسجل شراء في المخزن تلقائياً)
create or replace function spend_maintenance_fund(
  p_amount numeric, p_description text, p_item_id uuid default null, p_quantity numeric default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_staff uuid; v_id uuid;
begin
  v_staff := require_role('manager', 'accountant');
  insert into maintenance_fund_ledger (amount, direction, description, created_by)
  values (p_amount, 'out', p_description, v_staff) returning id into v_id;
  if p_item_id is not null then
    if coalesce(p_quantity, 0) <= 0 then raise exception 'لازم تحدد الكمية المشتراة'; end if;
    insert into inventory_transactions (item_id, tx_type, quantity, unit_cost, fund_ledger_id, note, created_by)
    values (p_item_id, 'purchase', p_quantity, round(p_amount / p_quantity, 2), v_id, p_description, v_staff);
  end if;
  return v_id;
end $$;

create or replace function record_inventory_tx(
  p_item_id uuid, p_tx_type inventory_tx_type, p_quantity numeric,
  p_course_id uuid default null, p_unit_cost numeric default null, p_note text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_staff uuid; v_id uuid; v_qty numeric;
begin
  v_staff := require_role('manager', 'instructor', 'secretary');
  -- الصرف والإهلاك بيتسجلوا بالسالب تلقائياً
  v_qty := case when p_tx_type in ('consume', 'dispose') then -abs(p_quantity)
                when p_tx_type = 'purchase' then abs(p_quantity) else p_quantity end;
  insert into inventory_transactions (item_id, tx_type, quantity, unit_cost, course_id, note, created_by)
  values (p_item_id, p_tx_type, v_qty, p_unit_cost, p_course_id, p_note, v_staff)
  returning id into v_id;
  return v_id;
end $$;

-- إهلاك الأدوات (قسط ثابت) لحد تاريخ معين
create or replace view v_tool_depreciation with (security_invoker = true) as
select id, name, quantity, unit_cost, purchase_date, useful_life_months,
       quantity * unit_cost as original_value,
       least(quantity * unit_cost,
             round(quantity * unit_cost / useful_life_months
                   * ((date_part('year', age(today_eg(), purchase_date)) * 12
                      + date_part('month', age(today_eg(), purchase_date)))::numeric), 2)) as accumulated_depreciation
  from inventory_items
 where category = 'tool' and useful_life_months is not null and purchase_date is not null;

-- ---------------------------------------------------------------------
-- الربح الشهري والرواتب
-- ---------------------------------------------------------------------
-- معاينة ربح الشهر (بدون حفظ) — نفس الحساب اللي بيتحفظ عند الإقفال
create or replace function compute_month_profit(p_month date)
returns profit_ledger language plpgsql stable security definer set search_path = public as $$
declare r profit_ledger; v_month date := month_of(p_month); c record; m record; a record;
begin
  if not has_role('manager', 'accountant') then raise exception 'غير مصرح' using errcode = '42501'; end if;
  r.month := v_month;
  select coalesce(sum(amount), 0) into r.gross_revenue from payments where month_covered = v_month;
  r.maintenance_fund_reserve := 0; r.maintenance_engineer_share := 0;
  r.advanced_supervision_fees := 0; r.external_instructor_share := 0;

  -- الصيانة: من الدفتر لو اتقفل، وإلا حساب تقديري
  for c in select id, type from courses where type in ('maintenance', 'advanced') loop
    if c.type = 'maintenance' then
      select consumables_deduction, engineer_share into m from maintenance_course_ledger
       where course_id = c.id and month = v_month;
      if not found then
        select consumables_deduction, engineer_share into m from calc_maintenance_split(c.id, v_month);
      end if;
      r.maintenance_fund_reserve  := r.maintenance_fund_reserve + m.consumables_deduction;
      r.maintenance_engineer_share := r.maintenance_engineer_share + m.engineer_share;
    else
      select supervision_fee_7pct as supervision_fee, instructor_share into a from advanced_course_ledger
       where course_id = c.id and month = v_month;
      if not found then
        select supervision_fee, instructor_share into a from calc_advanced_split(c.id, v_month);
      end if;
      r.advanced_supervision_fees := r.advanced_supervision_fees + a.supervision_fee;
      r.external_instructor_share := r.external_instructor_share + a.instructor_share;
    end if;
  end loop;

  r.center_revenue := r.gross_revenue - r.maintenance_fund_reserve - r.maintenance_engineer_share
                    - r.advanced_supervision_fees - r.external_instructor_share;

  select coalesce(sum(amount), 0) into r.operating_expenses from expenses where month = v_month;
  select coalesce(sum(base_salary), 0) into r.staff_base_salaries
    from staff where active and hire_date <= (v_month + interval '1 month - 1 day')::date;
  select coalesce(sum(amount), 0) into r.staff_bonuses from staff_bonus_transactions where month = v_month;
  select coalesce(sum(amount), 0) into r.referral_commissions
    from referral_commissions where month = v_month and status <> 'cancelled';

  r.total_expenses := r.operating_expenses + r.staff_base_salaries + r.staff_bonuses + r.referral_commissions;
  r.net_profit     := r.center_revenue - r.total_expenses;
  select coalesce(sum(round(greatest(r.net_profit, 0) * equity_share_pct / 100, 2)), 0)
    into r.equity_share_total from staff where equity_partner;
  return r;
end $$;

-- إقفال الشهر: بيقفل أي كورس صيانة/متقدم لسه مفتوح، وبيحفظ الربح، وبيقفل الشهر
create or replace function close_profit_month(p_month date)
returns profit_ledger language plpgsql security definer set search_path = public as $$
declare v_staff uuid; v_month date := month_of(p_month); c record; r profit_ledger;
begin
  v_staff := require_role('accountant', 'manager');
  if v_month >= month_of(today_eg()) then raise exception 'مينفعش تقفل شهر لسه ماخلصش'; end if;
  if exists (select 1 from closed_months where month = v_month) then
    raise exception 'شهر % مقفول قبل كده', to_char(v_month, 'YYYY-MM');
  end if;

  for c in select id from courses where type = 'maintenance'
            and id not in (select course_id from maintenance_course_ledger where month = v_month)
            and course_month_revenue(id, v_month) > 0 loop
    perform close_maintenance_month(c.id, v_month);
  end loop;
  for c in select id from courses where type = 'advanced'
            and id not in (select course_id from advanced_course_ledger where month = v_month)
            and course_month_revenue(id, v_month) > 0 loop
    perform close_advanced_month(c.id, v_month);
  end loop;

  r := compute_month_profit(v_month);
  r.id := gen_random_uuid(); r.closed_by := v_staff; r.closed_at := now();
  insert into profit_ledger select r.*;
  insert into closed_months (month, closed_by) values (v_month, v_staff);
  return r;
end $$;

-- POST /api/payroll/run?month=
create or replace function run_payroll(p_month date)
returns setof payroll_runs language plpgsql security definer set search_path = public as $$
declare v_month date := month_of(p_month); v_net numeric; s record;
        v_base numeric; v_bonus numeric; v_comm numeric; v_share numeric;
begin
  perform require_role('accountant', 'manager');
  select net_profit into v_net from profit_ledger where month = v_month;
  if v_net is null then raise exception 'اقفل ربح الشهر الأول (close_profit_month)'; end if;
  if exists (select 1 from payroll_runs where month = v_month and status <> 'draft') then
    raise exception 'رواتب الشهر ده اتعمدت — مينفعش إعادة الحساب';
  end if;
  delete from payroll_runs where month = v_month and status = 'draft';

  -- الموظفين النشطين + الشركاء حتى لو المرتب التشغيلي وقف
  for s in select * from staff
            where (active and hire_date <= (v_month + interval '1 month - 1 day')::date)
               or (equity_partner and equity_share_pct > 0) loop
    v_base  := case when s.active then s.base_salary else 0 end;
    select coalesce(sum(amount), 0) into v_bonus from staff_bonus_transactions
     where staff_id = s.id and month = v_month;
    select coalesce((select sum(engineer_share) from maintenance_course_ledger
                      where engineer_staff_id = s.id and month = v_month), 0)
         + coalesce((select sum(supervision_fee_7pct) from advanced_course_ledger
                      where supervisor_staff_id = s.id and month = v_month), 0)
      into v_comm;
    v_share := case when s.equity_partner then round(greatest(v_net, 0) * s.equity_share_pct / 100, 2) else 0 end;

    if v_base + v_bonus + v_comm + v_share > 0 then
      insert into payroll_runs (staff_id, month, base_salary, bonus_total, commission_total,
                                profit_share_total, net_pay)
      values (s.id, v_month, v_base, v_bonus, v_comm, v_share, v_base + v_bonus + v_comm + v_share);
    end if;
  end loop;
  return query select * from payroll_runs where month = v_month;
end $$;

create or replace function set_payroll_status(p_month date, p_status payroll_status)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform require_role('accountant', 'manager');
  update payroll_runs set status = p_status where month = month_of(p_month);
end $$;

-- GET /api/staff/:id/equity-share — مستقلة عن الدور والمرتب
create or replace function staff_equity_share(p_staff_id uuid)
returns table (month date, net_profit numeric, share_pct numeric, share numeric)
language sql stable security definer set search_path = public as $$
  select pl.month, pl.net_profit, s.equity_share_pct,
         round(greatest(pl.net_profit, 0) * s.equity_share_pct / 100, 2)
    from profit_ledger pl cross join staff s
   where s.id = p_staff_id and s.equity_partner
     and (has_role('manager', 'accountant') or s.id = current_staff_id())
   order by pl.month desc
$$;

-- POST /api/referral-commissions/:id/pay
create or replace function pay_referral_commission(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_staff uuid; rc referral_commissions;
begin
  v_staff := require_role('manager', 'accountant');
  select * into rc from referral_commissions where id = p_id for update;
  if rc.id is null then raise exception 'العمولة مش موجودة'; end if;
  if rc.status <> 'pending' then raise exception 'العمولة حالتها % بالفعل', rc.status; end if;
  -- التسجيل الفعلي = تسجيل مفعّل + أول دفعة
  if not exists (select 1 from payments where enrollment_id = rc.enrollment_id) then
    raise exception 'الطالب لسه مادفعش — العمولة بتتصرف بعد التسجيل الفعلي';
  end if;
  update referral_commissions set status = 'paid', paid_at = now(), paid_by = v_staff where id = p_id;
end $$;

-- ---------------------------------------------------------------------
-- الإقفال الأسبوعي  (POST /api/weekly-closures)
-- ---------------------------------------------------------------------
create or replace function preview_weekly_closure(p_week_start date)
returns weekly_closures language plpgsql stable security definer set search_path = public as $$
declare r weekly_closures;
begin
  if not has_role('manager', 'accountant') then raise exception 'غير مصرح' using errcode = '42501'; end if;
  r.week_start := p_week_start; r.week_end := p_week_start + 6;
  select coalesce(sum(amount), 0), count(*) into r.total_revenue, r.payments_count
    from payments where payment_date between r.week_start and r.week_end;
  select coalesce(sum(amount), 0) into r.total_expenses
    from expenses where expense_date between r.week_start and r.week_end;
  r.net_cash := r.total_revenue - r.total_expenses;
  return r;
end $$;

create or replace function close_week(p_week_start date, p_notes text default null)
returns weekly_closures language plpgsql security definer set search_path = public as $$
declare v_staff uuid; r weekly_closures;
begin
  v_staff := require_role('accountant', 'manager');
  if p_week_start + 6 >= today_eg() then raise exception 'الأسبوع لسه ماخلصش'; end if;
  r := preview_weekly_closure(p_week_start);
  r.id := gen_random_uuid(); r.notes := p_notes; r.closed_by := v_staff; r.closed_at := now();
  insert into weekly_closures select r.*;
  return r;
end $$;

-- تفاصيل الأسبوع للتصدير لإكسل (GET /api/weekly-closures/:id/export.xlsx)
create or replace function weekly_closure_details(p_week_start date)
returns table (kind text, entry_date date, description text, category text, amount numeric)
language sql stable security definer set search_path = public as $$
  select 'إيراد', p.payment_date, s.full_name || ' — ' || c.name, p.method::text, p.amount
    from payments p join enrollments e on e.id = p.enrollment_id join students s on s.id = e.student_id
    join groups g on g.id = e.group_id join courses c on c.id = g.course_id
   where has_role('manager', 'accountant') and p.payment_date between p_week_start and p_week_start + 6
  union all
  select 'مصروف', x.expense_date, coalesce(x.description, ''), x.category::text, -x.amount
    from expenses x
   where has_role('manager', 'accountant') and x.expense_date between p_week_start and p_week_start + 6
  order by 2, 1
$$;
