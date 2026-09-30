-- =====================================================================
-- AMS v1 — نظام إدارة أكاديمية آفاق
-- 0001: الجداول والقيود الأساسية
-- كل الشهور بتتخزن كـ date = أول يوم في الشهر (مثال: 2026-10-01)
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------
create type course_type        as enum ('normal', 'maintenance', 'advanced');
create type service_area       as enum ('الصف', 'العياط', 'أطفيح', 'أخرى');
create type lead_source_type   as enum ('paid_ad', 'influencer', 'promo_code', 'direct');
create type enrollment_status  as enum ('pending', 'active', 'suspended', 'completed', 'cancelled');
create type attendance_status  as enum ('present', 'absent', 'excused');
create type payment_method     as enum ('cash', 'vodafone_cash', 'instapay', 'bank_transfer');
create type staff_role         as enum ('manager', 'secretary', 'instructor', 'accountant');
create type bonus_type         as enum ('enrollment_activation', 'manual');
create type commission_status  as enum ('pending', 'paid', 'cancelled');
create type item_category      as enum ('tool', 'consumable');
create type inventory_tx_type  as enum ('purchase', 'consume', 'adjust', 'dispose');
create type fund_direction     as enum ('in', 'out');
create type expense_category   as enum ('electricity', 'internet', 'rent', 'fixed_salaries', 'other');
create type payroll_status     as enum ('draft', 'approved', 'paid');

-- تاريخ النهارده بتوقيت القاهرة (سيرفر Supabase شغال UTC)
create or replace function today_eg() returns date
language sql stable as $$ select (now() at time zone 'Africa/Cairo')::date $$;

create or replace function month_of(d date) returns date
language sql immutable as $$ select date_trunc('month', d)::date $$;

-- دالة مساعدة: التأكد إن التاريخ أول يوم في الشهر
create or replace function is_month_start(d date) returns boolean
language sql immutable as $$ select extract(day from d) = 1 $$;

-- ---------------------------------------------------------------------
-- الإعدادات العامة (صف واحد فقط) — كل الأرقام الثابتة في المواصفات هنا
-- ---------------------------------------------------------------------
create table app_settings (
  id                               boolean primary key default true check (id),
  maintenance_fund_deduction       numeric(12,2) not null default 1000,  -- استقطاع صندوق التجديد
  maintenance_engineer_pct         numeric(5,2)  not null default 50,    -- حصة م. معتز من صافي الصيانة
  advanced_supervision_pct         numeric(5,2)  not null default 7,     -- نسبة الإشراف على الكورسات المتقدمة
  default_referral_commission      numeric(12,2) not null default 100,   -- عمولة صاحب الكود
  secretary_bonus_on_promo_leads   boolean       not null default false, -- منع العمولة المزدوجة (سكرتارية + كود)
  maintenance_engineer_staff_id    uuid,                                 -- مين بياخد حصة الصيانة (م. معتز)
  advanced_supervisor_staff_id     uuid,                                 -- مين بياخد 7% (م. معتز)
  updated_at                       timestamptz   not null default now()
);
insert into app_settings default values;

-- ---------------------------------------------------------------------
-- 01 الطلاب والمناهج
-- ---------------------------------------------------------------------
create table tracks (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  min_age     int  not null check (min_age between 4 and 99),
  max_age     int  check (max_age is null or max_age >= min_age),  -- null = مفتوح (18+)
  description text,
  sort_order  int  not null default 0
);

create table external_instructors (
  id                   uuid primary key default gen_random_uuid(),
  name                 text not null,
  phone                text,
  specialty            text,
  payout_terms         text,                                            -- نص العقد
  instructor_share_pct numeric(5,2) not null default 50
                       check (instructor_share_pct between 0 and 100), -- نسبته من الباقي بعد الـ 7%
  active               boolean not null default true,
  created_at           timestamptz not null default now()
);

create table staff (
  id                      uuid primary key default gen_random_uuid(),
  auth_user_id            uuid unique,                 -- ربط بحساب Supabase Auth
  full_name               text not null,
  phone                   text,
  role                    staff_role not null,
  base_salary             numeric(12,2) not null default 0 check (base_salary >= 0),
  equity_partner          boolean not null default false,
  equity_share_pct        numeric(5,2) not null default 0 check (equity_share_pct between 0 and 100),
  enrollment_bonus_amount numeric(12,2) not null default 0 check (enrollment_bonus_amount >= 0),
  hire_date               date not null default today_eg(),
  active                  boolean not null default true,
  created_at              timestamptz not null default now(),
  -- الحصة الرأسمالية مربوطة بـ equity_partner مش بالدور أو المرتب
  constraint equity_pct_requires_partner check (equity_partner or equity_share_pct = 0)
);

alter table app_settings
  add constraint app_settings_engineer_fk   foreign key (maintenance_engineer_staff_id) references staff(id),
  add constraint app_settings_supervisor_fk foreign key (advanced_supervisor_staff_id)  references staff(id);

create table courses (
  id                     uuid primary key default gen_random_uuid(),
  track_id               uuid not null references tracks(id),
  name                   text not null,
  type                   course_type not null default 'normal',
  monthly_fee            numeric(12,2) not null check (monthly_fee >= 0),
  sessions_per_month     int not null default 8 check (sessions_per_month > 0),
  instructor_staff_id    uuid references staff(id),
  external_instructor_id uuid references external_instructors(id),
  active                 boolean not null default true,
  created_at             timestamptz not null default now(),
  unique (track_id, name),
  -- المدرب الخارجي مسموح بس في الكورسات المتقدمة
  constraint external_only_advanced check (external_instructor_id is null or type = 'advanced')
);

-- الفترات اليومية الثابتة (حد أقصى 7) — كل فترة ساعة ونص شاملة البريك
create table periods (
  id         uuid primary key default gen_random_uuid(),
  slot_no    int  not null unique check (slot_no between 1 and 7),
  label      text not null,
  start_time time not null,
  end_time   time not null,
  constraint period_is_90_minutes check (end_time - start_time = interval '90 minutes')
);

create table groups (
  id         uuid primary key default gen_random_uuid(),
  course_id  uuid not null references courses(id),
  period_id  uuid not null references periods(id),
  weekday    int  not null check (weekday between 0 and 6),   -- 0 = الأحد ... 6 = السبت
  capacity   int  not null default 15 check (capacity between 1 and 15),
  room       text not null default 'المعمل',
  label      text,
  start_date date not null default today_eg(),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
-- منع التعارض: مجموعة نشطة واحدة بس في نفس الغرفة/الفترة/اليوم
create unique index groups_no_clash on groups (room, period_id, weekday) where active;

create table lead_sources (
  id     uuid primary key default gen_random_uuid(),
  type   lead_source_type not null,
  label  text not null,
  active boolean not null default true,
  unique (type, label)
);

create table promo_codes (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique check (code = upper(code) and length(code) between 3 and 30),
  owner_name        text not null,
  owner_phone       text,
  discount_value    numeric(12,2) not null default 0 check (discount_value >= 0),
  commission_amount numeric(12,2) not null default 100 check (commission_amount >= 0),
  active            boolean not null default true,
  created_at        timestamptz not null default now()
);

create table students (
  id             uuid primary key default gen_random_uuid(),
  full_name      text not null,
  birth_date     date not null,
  phone          text,
  guardian_name  text,
  guardian_phone text not null,
  area           service_area not null,
  lead_source_id uuid not null references lead_sources(id),   -- إلزامي
  promo_code_id  uuid references promo_codes(id),
  notes          text,
  created_by     uuid references staff(id),
  created_at     timestamptz not null default now()
);
create index students_name_idx on students using gin (to_tsvector('simple', full_name));
create index students_phone_idx on students (guardian_phone);

create table enrollments (
  id                   uuid primary key default gen_random_uuid(),
  student_id           uuid not null references students(id),
  group_id             uuid not null references groups(id),
  status               enrollment_status not null default 'pending',
  monthly_fee_override numeric(12,2) check (monthly_fee_override is null or monthly_fee_override >= 0),
  promo_discount       numeric(12,2) not null default 0 check (promo_discount >= 0),
  activated_at         timestamptz,
  activated_by         uuid references staff(id),
  created_at           timestamptz not null default now(),
  unique (student_id, group_id)
);
create index enrollments_group_idx on enrollments (group_id) where status = 'active';

create table sessions (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references groups(id),
  session_date date not null,
  topic        text,
  created_at   timestamptz not null default now(),
  unique (group_id, session_date)
);

create table attendance (
  id                uuid primary key default gen_random_uuid(),
  session_id        uuid not null references sessions(id) on delete cascade,
  enrollment_id     uuid not null references enrollments(id),
  attendance_status attendance_status not null,
  marked_by         uuid references staff(id),
  marked_at         timestamptz not null default now(),
  unique (session_id, enrollment_id)
);

-- ---------------------------------------------------------------------
-- 02 المالية
-- ---------------------------------------------------------------------
create table payments (
  id            uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references enrollments(id),
  amount        numeric(12,2) not null check (amount > 0),
  payment_date  date not null default today_eg(),
  month_covered date not null check (is_month_start(month_covered)),
  method        payment_method not null default 'cash',
  received_by   uuid references staff(id),
  notes         text,
  created_at    timestamptz not null default now()
);
create index payments_month_idx on payments (month_covered);
create index payments_date_idx  on payments (payment_date);

-- قفل الشهور: بعد إقفال شهر مايتعدّلش إيراده
create table closed_months (
  month     date primary key check (is_month_start(month)),
  closed_at timestamptz not null default now(),
  closed_by uuid references staff(id)
);

create table maintenance_course_ledger (
  id                    uuid primary key default gen_random_uuid(),
  course_id             uuid not null references courses(id),
  month                 date not null check (is_month_start(month)),
  total_revenue         numeric(12,2) not null,
  consumables_deduction numeric(12,2) not null,
  distributable         numeric(12,2) not null,
  engineer_staff_id     uuid references staff(id),
  engineer_share        numeric(12,2) not null,
  center_share          numeric(12,2) not null,
  closed_by             uuid references staff(id),
  closed_at             timestamptz not null default now(),
  unique (course_id, month),
  check (total_revenue = consumables_deduction + engineer_share + center_share)
);

create table advanced_course_ledger (
  id                     uuid primary key default gen_random_uuid(),
  course_id              uuid not null references courses(id),
  month                  date not null check (is_month_start(month)),
  external_instructor_id uuid references external_instructors(id),
  total_revenue          numeric(12,2) not null,
  supervision_fee_7pct   numeric(12,2) not null,
  supervisor_staff_id    uuid references staff(id),
  instructor_share       numeric(12,2) not null,
  center_share           numeric(12,2) not null,
  closed_by              uuid references staff(id),
  closed_at              timestamptz not null default now(),
  unique (course_id, month),
  check (total_revenue = supervision_fee_7pct + instructor_share + center_share)
);

-- ---------------------------------------------------------------------
-- 03 الموارد البشرية والرواتب
-- ---------------------------------------------------------------------
create table staff_bonus_transactions (
  id             uuid primary key default gen_random_uuid(),
  staff_id       uuid not null references staff(id),
  enrollment_id  uuid references enrollments(id),
  type           bonus_type not null,
  amount         numeric(12,2) not null check (amount >= 0),
  month          date not null check (is_month_start(month)),
  note           text,
  created_by     uuid references staff(id),
  created_at     timestamptz not null default now()
);
-- بونص تفعيل واحد بس لكل تسجيل
create unique index bonus_one_per_enrollment on staff_bonus_transactions (enrollment_id)
  where type = 'enrollment_activation';

create table payroll_runs (
  id                 uuid primary key default gen_random_uuid(),
  staff_id           uuid not null references staff(id),
  month              date not null check (is_month_start(month)),
  base_salary        numeric(12,2) not null default 0,
  bonus_total        numeric(12,2) not null default 0,
  commission_total   numeric(12,2) not null default 0,  -- حصة الصيانة + 7% إشراف
  profit_share_total numeric(12,2) not null default 0,  -- الحصة الرأسمالية
  deductions         numeric(12,2) not null default 0,
  net_pay            numeric(12,2) not null,
  status             payroll_status not null default 'draft',
  created_at         timestamptz not null default now(),
  unique (staff_id, month),
  check (net_pay = base_salary + bonus_total + commission_total + profit_share_total - deductions)
);

-- ---------------------------------------------------------------------
-- 04 التسويق والإحالة
-- ---------------------------------------------------------------------
create table referral_commissions (
  id            uuid primary key default gen_random_uuid(),
  promo_code_id uuid not null references promo_codes(id),
  student_id    uuid not null unique references students(id),   -- عمولة واحدة لكل طالب
  enrollment_id uuid not null references enrollments(id),
  amount        numeric(12,2) not null check (amount >= 0),
  month         date not null check (is_month_start(month)),
  status        commission_status not null default 'pending',
  paid_at       timestamptz,
  paid_by       uuid references staff(id),
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 05 المخزون وورشة الصيانة
-- ---------------------------------------------------------------------
create table inventory_items (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null unique,
  category           item_category not null,
  unit               text not null default 'قطعة',
  quantity           numeric(12,2) not null default 0 check (quantity >= 0),
  unit_cost          numeric(12,2) not null default 0 check (unit_cost >= 0),
  purchase_date      date,
  useful_life_months int check (useful_life_months is null or useful_life_months > 0), -- للأدوات فقط
  reorder_level      numeric(12,2) not null default 0,
  notes              text,
  created_at         timestamptz not null default now()
);

create table maintenance_fund_ledger (
  id                    uuid primary key default gen_random_uuid(),
  transaction_date      date not null default today_eg(),
  amount                numeric(12,2) not null check (amount > 0),
  direction             fund_direction not null,
  source_course_id      uuid references courses(id),
  maintenance_ledger_id uuid references maintenance_course_ledger(id),
  description           text,
  running_balance       numeric(12,2) not null default 0,
  created_by            uuid references staff(id),
  created_at            timestamptz not null default now()
);

create table inventory_transactions (
  id             uuid primary key default gen_random_uuid(),
  item_id        uuid not null references inventory_items(id),
  tx_type        inventory_tx_type not null,
  quantity       numeric(12,2) not null check (quantity <> 0),  -- موجب = دخول، سالب = خروج
  unit_cost      numeric(12,2),
  course_id      uuid references courses(id),
  fund_ledger_id uuid references maintenance_fund_ledger(id),
  note           text,
  created_by     uuid references staff(id),
  created_at     timestamptz not null default now(),
  check ((tx_type in ('consume', 'dispose') and quantity < 0)
      or (tx_type = 'purchase' and quantity > 0)
      or tx_type = 'adjust')
);

-- ---------------------------------------------------------------------
-- 06 المحاسبة والإقفال
-- ---------------------------------------------------------------------
create table expenses (
  id           uuid primary key default gen_random_uuid(),
  category     expense_category not null,
  amount       numeric(12,2) not null check (amount > 0),
  month        date not null check (is_month_start(month)),
  expense_date date not null default today_eg(),
  recurring    boolean not null default false,
  description  text,
  created_by   uuid references staff(id),
  created_at   timestamptz not null default now()
);
create index expenses_month_idx on expenses (month);

-- إقفال أسبوعي (نقدي): مقبوضات الأسبوع − مصروفات الأسبوع
create table weekly_closures (
  id                       uuid primary key default gen_random_uuid(),
  week_start               date not null unique,
  week_end                 date not null,
  total_revenue            numeric(12,2) not null,
  total_expenses           numeric(12,2) not null,
  net_cash                 numeric(12,2) not null,
  payments_count           int not null,
  notes                    text,
  closed_by                uuid references staff(id),
  closed_at                timestamptz not null default now(),
  check (week_end = week_start + 6)
);

-- دفتر الربح الشهري الرسمي — عليه بتتحسب الـ 5%
create table profit_ledger (
  id                        uuid primary key default gen_random_uuid(),
  month                     date not null unique check (is_month_start(month)),
  gross_revenue             numeric(12,2) not null,  -- كل التحصيل
  maintenance_fund_reserve  numeric(12,2) not null,  -- استقطاعات الصندوق
  maintenance_engineer_share numeric(12,2) not null, -- 50% م. معتز
  advanced_supervision_fees numeric(12,2) not null,  -- 7% م. معتز
  external_instructor_share numeric(12,2) not null,  -- المدربين الخارجيين
  center_revenue            numeric(12,2) not null,  -- اللي فاضل للمركز
  operating_expenses        numeric(12,2) not null,  -- كهرباء/نت/إيجار/أخرى/رواتب خارج النظام
  staff_base_salaries       numeric(12,2) not null,
  staff_bonuses             numeric(12,2) not null,
  referral_commissions      numeric(12,2) not null,
  total_expenses            numeric(12,2) not null,
  net_profit                numeric(12,2) not null,
  equity_share_total        numeric(12,2) not null,
  closed_by                 uuid references staff(id),
  closed_at                 timestamptz not null default now()
);
