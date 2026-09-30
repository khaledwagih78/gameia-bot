# AMS v1 — نظام إدارة أكاديمية آفاق للبرمجة والذكاء الاصطناعي

تطبيق مبني بـ **Supabase (Postgres)** للقاعدة والمنطق المالي، و**React + Vite** للواجهة.

```
ams/
├── supabase/
│   ├── migrations/
│   │   ├── 0001_schema.sql     ← الجداول والقيود (26 جدول)
│   │   ├── 0002_logic.sql      ← الدوال المالية (الـ API) + التريجرز + الـ views
│   │   └── 0003_security.sql   ← الصلاحيات (RLS) لكل دور
│   ├── seed.sql                ← المسارات الأربعة + 7 فترات + مصادر العملاء + كورسات مبدئية
│   └── tests/                  ← اختبارات المعادلات المالية (18 اختبار)
└── web/                        ← الواجهة: الاستقبال / المدير / المحاسب / الإعدادات
```

---

## التشغيل خطوة بخطوة

### 1) مشروع Supabase
1. افتح [supabase.com](https://supabase.com) ← **New project**.
2. من **SQL Editor** شغّل الملفات دي **بالترتيب**، كل ملف لوحده (انسخ المحتوى كله ← Run):
   1. `supabase/migrations/0001_schema.sql`
   2. `supabase/migrations/0002_logic.sql`
   3. `supabase/migrations/0003_security.sql`
   4. `supabase/seed.sql`

### 2) الحسابات (أول مدير)
1. **Authentication → Users → Add user**: اعمل يوزر بإيميل وباسورد لكل موظف (معتز، السكرتارية، المحاسب).
2. انسخ الـ **User UID** بتاع م. معتز، وشغّل في SQL Editor (غيّر الـ UID):

```sql
insert into staff (auth_user_id, full_name, role, base_salary, equity_partner, equity_share_pct, hire_date)
values ('ضع-UID-معتز-هنا', 'م. معتز', 'manager', 5000, true, 5, '2026-01-01')
returning id;

-- معتز هو اللي بياخد 50% الصيانة و7% المتقدم
update app_settings set
  maintenance_engineer_staff_id = (select id from staff where full_name = 'م. معتز'),
  advanced_supervisor_staff_id  = (select id from staff where full_name = 'م. معتز');
```

3. باقي الموظفين تقدر تضيفهم من شاشة **الإعدادات** بعد ما تدخل بحساب معتز (حط الـ UID في خانة "User UID"):
   - السكرتارية: راتب 4000، بونص كل تفعيل 50–75.
   - المحاسب: دور `محاسب`.

> الإضافة الأولى بس هي اللي من SQL، لأن الصلاحيات بتمنع أي حد مش مدير يضيف موظفين.

### 3) الواجهة
```bash
cd ams/web
cp .env.example .env.local      # وحط فيه URL و anon key من Supabase → Project Settings → API
npm install
npm run dev                     # http://localhost:5173
```

للنشر: ارفع فولدر `ams/web` على **Vercel** أو **Netlify** (Build: `npm run build`، Output: `dist`) وحط نفس متغيرين الـ env هناك.

### 4) تشغيل الاختبارات (اختياري، على Postgres محلي)
```bash
PGHOST=localhost PGUSER=postgres ./ams/supabase/tests/run.sh
```

---

## ترتيب الشغل الشهري

| مين | إمتى | إيه |
|---|---|---|
| السكرتارية | يومياً | تسجيل طلاب ← تفعيل ← حضور ← تحصيل |
| المحاسب | كل أسبوع | **إقفال الأسبوع** (نقدية داخلة − خارجة) + تصدير Excel |
| المحاسب | أول الشهر | إدخال مصروفات الشهر اللي فات ← **إقفال الشهر** ← **حساب الرواتب** ← اعتماد ← صرف |
| المدير/المحاسب | بعد أول دفعة | صرف عمولات الأكواد المستحقة |

**إقفال الشهر** بيعمل تلقائياً: إقفال كل كورسات الصيانة (استقطاع 1000 للصندوق ثم 50/50) والمتقدمة (7% إشراف)، حساب صافي الربح، وقفل الشهر ضد أي تعديل في التحصيل أو المصروفات.

---

## مطابقة الـ API في المواصفات ← دوال Supabase

كل عملية مالية = دالة (RPC) بتتنادى بـ `supabase.rpc('اسم_الدالة', {...})`، ومفيش أي حساب مالي ضمني عند القراءة.

| المواصفات | الدالة |
|---|---|
| `POST /api/students` | `register_student` (مصدر العميل إلزامي + مصدر واحد بس) |
| `POST /api/enrollments` | `create_enrollment` ← `activate_enrollment` (بونص السكرتارية + عمولة الكود) |
| `POST /api/sessions/:id/attendance` | `open_session` + `mark_attendance` |
| `GET /api/groups?period=&day=` | view `v_group_occupancy` |
| `POST /api/payments` | `record_payment` |
| `POST /api/maintenance-courses/:id/close-month` | `close_maintenance_month` |
| `POST /api/advanced-courses/:id/close-month` | `close_advanced_month` |
| `GET /api/maintenance-fund/ledger` | جدول `maintenance_fund_ledger` + view `v_maintenance_fund_balance` + `spend_maintenance_fund` |
| `POST /api/payroll/run?month=` | `close_profit_month` ثم `run_payroll` |
| `GET /api/staff/:id/equity-share` | `staff_equity_share` |
| `POST /api/referral-commissions/:id/pay` | `pay_referral_commission` |
| `POST /api/weekly-closures` | `preview_weekly_closure` + `close_week` |
| `GET /api/weekly-closures/:id/export.xlsx` | `weekly_closure_details` + التصدير في المتصفح |
| `PATCH /api/expenses/:id` | تعديل مباشر على `expenses` (محمي بالـ RLS + قفل الشهر) |
| CRUD: tracks, courses, staff, inventory_items, promo_codes | جداول مباشرة، الكتابة للمدير بس |

---

## قرارات اتاخدت في التنفيذ (فيها اختلاف عن المواصفات)

1. **الـ 5% شهرية مش أسبوعية.** المواصفات حاطة `manager_profit_share_5pct` في الإقفال الأسبوعي، بس الرواتب والمصروفات الثابتة (إيجار، مرتبات) شهرية — لو اتحسبت أسبوعياً هتطلع أرقام غلط. الإقفال الأسبوعي بقى مراجعة نقدية (داخل − خارج)، والـ 5% بتتحسب في `profit_ledger` الشهري.

2. **معادلة صافي الربح اتعدّلت.** المعادلة في المواصفات بتطرح المصاريف من *إجمالي* الدخل، يعني الـ 5% كانت هتتحسب على فلوس مش بتاعة المركز. المعادلة المنفذة:
   ```
   إيراد المركز = إجمالي التحصيل − استقطاع الصندوق − 50% الصيانة − 7% الإشراف − حصة المدرب الخارجي
   صافي الربح  = إيراد المركز − (مصروفات تشغيل + الرواتب الأساسية + بونص السكرتارية + عمولات الأكواد)
   الحصة       = 5% × max(صافي الربح، 0)
   ```

3. **رواتب الموظفين بتتحسب تلقائي** من جدول `staff`. بند "رواتب خارج النظام" في المصروفات لأي حد مش متسجل كموظف (زي عامل نظافة) — عشان المرتب مايتحسبش مرتين.

4. **الصيانة لو دخلها أقل من 1000**: الدخل كله بيروح للصندوق وماحدش بياخد حاجة الشهر ده.

5. **الكورس المتقدم**: الـ 7% بتتحسب بس لو فيه مدرب خارجي (زي المواصفات). "الباقي حسب العقد" بقى رقم: `instructor_share_pct` على المدرب الخارجي (نسبته من الباقي بعد الـ 7%).

6. **العمولة المزدوجة**: الطالب اللي جاي بكود، السكرتارية مابتاخدش عليه بونص (افتراضياً). لو عايز الاتنين، فعّل الخيار في الإعدادات.

7. **العمولة بتتصرف بعد أول دفعة** للطالب، مش بمجرد التسجيل.

8. **الحصة الرأسمالية مستقلة**: لو معتز بطّل يبقى موظف نشط (أو مرتبه بقى صفر)، `run_payroll` بتفضل تحسب له الـ 5% طول ما `equity_partner = true`.

9. **كل الأرقام الثابتة قابلة للتعديل** من شاشة الإعدادات (1000، 50%، 7%، 100ج) من غير تعديل كود.
