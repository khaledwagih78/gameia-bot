import { useState } from 'react'
import { rpc, select, supabase } from '../lib/supabase'
import { COURSE_TYPES, LEAD_TYPES, ROLES, WEEKDAYS, money } from '../lib/format'
import { Card, Field, Msg, Table, useAction, useLoad } from '../components/ui'

// ------------------------------------------------------------------
// جدول CRUD عام: إضافة + تعديل لأي كيان مرجعي
// fields: [{ name, label, type: text|number|date|time|select|bool, options, required, show }]
// ------------------------------------------------------------------
function CrudTable({ title, subtitle, table, fields, columns, order = 'created_at', lookups = {} }) {
  const blank = Object.fromEntries(fields.map((f) => [f.name, f.default ?? (f.type === 'bool' ? false : '')]))
  const [form, setForm] = useState(blank)
  const [editId, setEditId] = useState(null)
  const { busy, msg, run } = useAction()
  const rows = useLoad(() => select(supabase.from(table).select('*').order(order)), [table])

  const clean = (f) =>
    Object.fromEntries(
      fields.map((d) => {
        const v = f[d.name]
        if (d.type === 'number') return [d.name, v === '' || v === null ? null : Number(v)]
        if (d.type === 'bool') return [d.name, !!v]
        return [d.name, v === '' ? null : v]
      }),
    )

  const submit = (e) => {
    e.preventDefault()
    run(async () => {
      const payload = clean(form)
      // في الإضافة: الحقول الفاضية بتتشال عشان القيم الافتراضية في القاعدة تشتغل
      if (!editId) for (const k of Object.keys(payload)) if (payload[k] === null) delete payload[k]
      if (editId) await select(supabase.from(table).update(payload).eq('id', editId))
      else await select(supabase.from(table).insert(payload))
      setForm(blank)
      setEditId(null)
      rows.reload()
    }, editId ? 'تم التعديل ✔' : 'تمت الإضافة ✔')
  }

  const edit = (r) => {
    setEditId(r.id)
    setForm(Object.fromEntries(fields.map((f) => [f.name, r[f.name] ?? (f.type === 'bool' ? false : '')])))
  }

  const input = (f) => {
    const v = form[f.name]
    const on = (e) => setForm({ ...form, [f.name]: f.type === 'bool' ? e.target.checked : e.target.value })
    if (f.type === 'bool') return <input type="checkbox" checked={!!v} onChange={on} />
    if (f.type === 'select') {
      const opts = typeof f.options === 'string' ? lookups[f.options] || [] : f.options
      return (
        <select value={v ?? ''} onChange={on} required={f.required}>
          <option value="">—</option>
          {opts.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
        </select>
      )
    }
    return <input type={f.type || 'text'} step={f.type === 'number' ? 'any' : undefined} value={v ?? ''} onChange={on} required={f.required} />
  }

  return (
    <Card title={title} subtitle={subtitle} wide>
      <form className="grid" onSubmit={submit}>
        {fields.filter((f) => !f.show || f.show(form)).map((f) => (
          <Field key={f.name} label={f.label} hint={f.hint}>{input(f)}</Field>
        ))}
        <div className="full row">
          <button className="primary" disabled={busy}>{editId ? 'حفظ التعديل' : 'إضافة'}</button>
          {editId && <button type="button" onClick={() => { setEditId(null); setForm(blank) }}>إلغاء</button>}
        </div>
      </form>
      <Msg msg={msg} />
      <Table rows={rows.data} columns={[...columns, { key: '_e', label: '', render: (r) => <button onClick={() => edit(r)}>تعديل</button> }]} />
    </Card>
  )
}

const yesNo = (v) => (v ? '✔' : '—')
const entries = (obj) => Object.entries(obj)

function AppSettings({ staffOptions }) {
  const { busy, msg, run } = useAction()
  const s = useLoad(() => select(supabase.from('app_settings').select('*').single()), [])
  const [f, setF] = useState(null)
  const cur = f || s.data
  if (!cur) return null
  const set = (k, num) => (e) => setF({ ...cur, [k]: e.target.type === 'checkbox' ? e.target.checked : num ? Number(e.target.value) : e.target.value || null })
  const save = () =>
    run(async () => {
      const { id, updated_at, ...rest } = cur
      await select(supabase.from('app_settings').update({ ...rest, updated_at: new Date().toISOString() }).eq('id', true))
      s.reload()
    }, 'تم حفظ الإعدادات ✔')
  return (
    <Card title="الإعدادات المالية" subtitle="كل النسب والمبالغ الثابتة في المواصفات" wide>
      <div className="grid">
        <Field label="استقطاع صندوق التجديد (ج)"><input type="number" value={cur.maintenance_fund_deduction} onChange={set('maintenance_fund_deduction', true)} /></Field>
        <Field label="حصة المهندس من الصيانة %"><input type="number" value={cur.maintenance_engineer_pct} onChange={set('maintenance_engineer_pct', true)} /></Field>
        <Field label="نسبة الإشراف على المتقدم %"><input type="number" value={cur.advanced_supervision_pct} onChange={set('advanced_supervision_pct', true)} /></Field>
        <Field label="عمولة الكود الافتراضية"><input type="number" value={cur.default_referral_commission} onChange={set('default_referral_commission', true)} /></Field>
        <Field label="مهندس الصيانة (بياخد 50%)">
          <select value={cur.maintenance_engineer_staff_id || ''} onChange={set('maintenance_engineer_staff_id')}>
            <option value="">—</option>
            {staffOptions.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
        </Field>
        <Field label="المشرف على المتقدم (بياخد 7%)">
          <select value={cur.advanced_supervisor_staff_id || ''} onChange={set('advanced_supervisor_staff_id')}>
            <option value="">—</option>
            {staffOptions.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
        </Field>
        <label className="check">
          <input type="checkbox" checked={cur.secretary_bonus_on_promo_leads} onChange={set('secretary_bonus_on_promo_leads')} />
          السكرتارية تاخد بونص على طلاب الأكواد كمان (عمولة مزدوجة)
        </label>
        <div className="full"><button className="primary" onClick={save} disabled={busy}>حفظ</button><Msg msg={msg} /></div>
      </div>
    </Card>
  )
}

function InventoryMovement({ items, courses }) {
  const [f, setF] = useState({ item_id: '', tx_type: 'consume', quantity: '', course_id: '', note: '' })
  const { busy, msg, run } = useAction()
  const submit = (e) => {
    e.preventDefault()
    run(async () => {
      await rpc('record_inventory_tx', {
        p_item_id: f.item_id, p_tx_type: f.tx_type, p_quantity: Number(f.quantity),
        p_course_id: f.course_id || null, p_note: f.note || null,
      })
      setF({ ...f, quantity: '', note: '' })
    }, 'تم تسجيل الحركة ✔ (اعمل تحديث للصفحة عشان تشوف الكمية الجديدة)')
  }
  return (
    <Card title="حركة مخزون" subtitle="صرف مستهلكات لدورة صيانة، أو شراء، أو تسوية جرد">
      <form className="grid" onSubmit={submit}>
        <Field label="الصنف">
          <select value={f.item_id} onChange={(e) => setF({ ...f, item_id: e.target.value })} required>
            <option value="">—</option>
            {items.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
        </Field>
        <Field label="نوع الحركة">
          <select value={f.tx_type} onChange={(e) => setF({ ...f, tx_type: e.target.value })}>
            <option value="consume">صرف / استهلاك</option>
            <option value="purchase">شراء (من خارج الصندوق)</option>
            <option value="adjust">تسوية جرد (+/−)</option>
            <option value="dispose">إهلاك / تالف</option>
          </select>
        </Field>
        <Field label="الكمية"><input type="number" step="any" value={f.quantity} onChange={(e) => setF({ ...f, quantity: e.target.value })} required /></Field>
        <Field label="دورة صيانة (اختياري)">
          <select value={f.course_id} onChange={(e) => setF({ ...f, course_id: e.target.value })}>
            <option value="">—</option>
            {courses.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
        </Field>
        <Field label="ملاحظة"><input value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} /></Field>
        <div className="full"><button className="primary" disabled={busy}>تسجيل</button><Msg msg={msg} /></div>
      </form>
    </Card>
  )
}

export default function Setup() {
  const lk = useLoad(async () => {
    const [tracks, courses, periods, staff, ext, items] = await Promise.all([
      select(supabase.from('tracks').select('id, name').order('sort_order')),
      select(supabase.from('courses').select('id, name, type').order('name')),
      select(supabase.from('periods').select('id, label, start_time').order('slot_no')),
      select(supabase.from('staff').select('id, full_name, role').order('full_name')),
      select(supabase.from('external_instructors').select('id, name').order('name')),
      select(supabase.from('inventory_items').select('id, name').order('name')),
    ])
    return {
      tracks: tracks.map((r) => [r.id, r.name]),
      courses: courses.map((r) => [r.id, r.name]),
      maintenanceCourses: courses.filter((r) => r.type === 'maintenance').map((r) => [r.id, r.name]),
      periods: periods.map((r) => [r.id, `${r.label} (${r.start_time.slice(0, 5)})`]),
      staff: staff.map((r) => [r.id, `${r.full_name} · ${ROLES[r.role]}`]),
      external: ext.map((r) => [r.id, r.name]),
      items: items.map((r) => [r.id, r.name]),
    }
  }, [])
  const L = lk.data
  if (!L) return <p className="muted">جاري التحميل…</p>
  const name = (list, id) => list.find(([k]) => k === id)?.[1] || '—'

  return (
    <div className="cards">
      <AppSettings staffOptions={L.staff} />

      <CrudTable title="الموظفون" table="staff" order="full_name" lookups={L}
        subtitle="auth_user_id = الـ User UID من Supabase → Authentication → Users"
        fields={[
          { name: 'full_name', label: 'الاسم', required: true },
          { name: 'phone', label: 'الموبايل' },
          { name: 'role', label: 'الدور', type: 'select', options: entries(ROLES), required: true },
          { name: 'base_salary', label: 'الراتب الأساسي', type: 'number', default: 0 },
          { name: 'enrollment_bonus_amount', label: 'بونص كل تفعيل (50–75)', type: 'number', default: 0 },
          { name: 'equity_partner', label: 'شريك (حصة رأسمالية)', type: 'bool' },
          { name: 'equity_share_pct', label: 'نسبة الحصة %', type: 'number', default: 0, show: (f) => f.equity_partner },
          { name: 'hire_date', label: 'تاريخ التعيين', type: 'date' },
          { name: 'auth_user_id', label: 'User UID (للدخول)' },
          { name: 'active', label: 'نشط', type: 'bool', default: true },
        ]}
        columns={[
          { key: 'full_name', label: 'الاسم' },
          { key: 'role', label: 'الدور', render: (r) => ROLES[r.role] },
          { key: 'base_salary', label: 'الأساسي', render: (r) => money(r.base_salary) },
          { key: 'enrollment_bonus_amount', label: 'بونص', render: (r) => money(r.enrollment_bonus_amount) },
          { key: 'equity_share_pct', label: 'حصة', render: (r) => (r.equity_partner ? `${r.equity_share_pct}%` : '—') },
          { key: 'auth_user_id', label: 'دخول', render: (r) => yesNo(r.auth_user_id) },
          { key: 'active', label: 'نشط', render: (r) => yesNo(r.active) },
        ]} />

      <CrudTable title="المسارات" table="tracks" order="sort_order"
        fields={[
          { name: 'name', label: 'الاسم', required: true },
          { name: 'min_age', label: 'من سن', type: 'number', required: true },
          { name: 'max_age', label: 'لسن (فاضي = مفتوح)', type: 'number' },
          { name: 'description', label: 'المحتوى' },
          { name: 'sort_order', label: 'الترتيب', type: 'number', default: 0 },
        ]}
        columns={[
          { key: 'name', label: 'المسار' },
          { key: 'age', label: 'السن', render: (r) => `${r.min_age}–${r.max_age ?? '+'}` },
          { key: 'description', label: 'المحتوى' },
        ]} />

      <CrudTable title="الكورسات" table="courses" order="name" lookups={L}
        fields={[
          { name: 'track_id', label: 'المسار', type: 'select', options: 'tracks', required: true },
          { name: 'name', label: 'الاسم', required: true },
          { name: 'type', label: 'النوع', type: 'select', options: entries(COURSE_TYPES), required: true, default: 'normal' },
          { name: 'monthly_fee', label: 'الرسوم الشهرية', type: 'number', required: true },
          { name: 'sessions_per_month', label: 'حصص في الشهر', type: 'number', default: 8 },
          { name: 'instructor_staff_id', label: 'المدرب', type: 'select', options: 'staff' },
          { name: 'external_instructor_id', label: 'مدرب خارجي', type: 'select', options: 'external', show: (f) => f.type === 'advanced' },
          { name: 'active', label: 'نشط', type: 'bool', default: true },
        ]}
        columns={[
          { key: 'name', label: 'الكورس' },
          { key: 'track', label: 'المسار', render: (r) => name(L.tracks, r.track_id) },
          { key: 'type', label: 'النوع', render: (r) => COURSE_TYPES[r.type] },
          { key: 'monthly_fee', label: 'الرسوم', render: (r) => money(r.monthly_fee) },
          { key: 'ext', label: 'خارجي', render: (r) => (r.external_instructor_id ? name(L.external, r.external_instructor_id) : '—') },
          { key: 'active', label: 'نشط', render: (r) => yesNo(r.active) },
        ]} />

      <CrudTable title="المجموعات" table="groups" lookups={L}
        subtitle="كل مجموعة = فترة ثابتة + يوم في الأسبوع — النظام بيمنع التعارض في نفس الغرفة"
        fields={[
          { name: 'course_id', label: 'الكورس', type: 'select', options: 'courses', required: true },
          { name: 'period_id', label: 'الفترة', type: 'select', options: 'periods', required: true },
          { name: 'weekday', label: 'اليوم', type: 'select', options: WEEKDAYS.map((d, i) => [i, d]), required: true },
          { name: 'capacity', label: 'السعة (حد أقصى 15)', type: 'number', default: 15 },
          { name: 'room', label: 'الغرفة', default: 'المعمل' },
          { name: 'label', label: 'اسم مميز (اختياري)' },
          { name: 'start_date', label: 'تاريخ البداية', type: 'date' },
          { name: 'active', label: 'نشطة', type: 'bool', default: true },
        ]}
        columns={[
          { key: 'c', label: 'الكورس', render: (r) => name(L.courses, r.course_id) },
          { key: 'd', label: 'اليوم', render: (r) => WEEKDAYS[r.weekday] },
          { key: 'p', label: 'الفترة', render: (r) => name(L.periods, r.period_id) },
          { key: 'room', label: 'الغرفة' },
          { key: 'capacity', label: 'السعة' },
          { key: 'active', label: 'نشطة', render: (r) => yesNo(r.active) },
        ]} />

      <CrudTable title="الفترات اليومية" table="periods" order="slot_no"
        subtitle="حد أقصى 7 فترات — كل فترة ساعة ونص بالظبط"
        fields={[
          { name: 'slot_no', label: 'رقم (1–7)', type: 'number', required: true },
          { name: 'label', label: 'الاسم', required: true },
          { name: 'start_time', label: 'من', type: 'time', required: true },
          { name: 'end_time', label: 'إلى', type: 'time', required: true },
        ]}
        columns={[
          { key: 'slot_no', label: '#' },
          { key: 'label', label: 'الفترة' },
          { key: 't', label: 'الوقت', render: (r) => `${r.start_time.slice(0, 5)} – ${r.end_time.slice(0, 5)}` },
        ]} />

      <CrudTable title="الأكواد الترويجية" table="promo_codes" order="code"
        fields={[
          { name: 'code', label: 'الكود (حروف كابيتال)', required: true },
          { name: 'owner_name', label: 'صاحب الكود', required: true },
          { name: 'owner_phone', label: 'موبايله' },
          { name: 'discount_value', label: 'خصم للطالب (ج)', type: 'number', default: 0 },
          { name: 'commission_amount', label: 'عمولة صاحب الكود', type: 'number', default: 100 },
          { name: 'active', label: 'نشط', type: 'bool', default: true },
        ]}
        columns={[
          { key: 'code', label: 'الكود' },
          { key: 'owner_name', label: 'صاحبه' },
          { key: 'discount_value', label: 'خصم', render: (r) => money(r.discount_value) },
          { key: 'commission_amount', label: 'عمولة', render: (r) => money(r.commission_amount) },
          { key: 'active', label: 'نشط', render: (r) => yesNo(r.active) },
        ]} />

      <CrudTable title="مصادر العملاء" table="lead_sources" order="type"
        fields={[
          { name: 'type', label: 'النوع', type: 'select', options: entries(LEAD_TYPES), required: true },
          { name: 'label', label: 'الوصف', required: true },
          { name: 'active', label: 'نشط', type: 'bool', default: true },
        ]}
        columns={[
          { key: 'type', label: 'النوع', render: (r) => LEAD_TYPES[r.type] },
          { key: 'label', label: 'الوصف' },
          { key: 'active', label: 'نشط', render: (r) => yesNo(r.active) },
        ]} />

      <CrudTable title="المدربين الخارجيين" table="external_instructors" order="name"
        fields={[
          { name: 'name', label: 'الاسم', required: true },
          { name: 'phone', label: 'الموبايل' },
          { name: 'specialty', label: 'التخصص' },
          { name: 'instructor_share_pct', label: 'نسبته من الباقي بعد 7% (%)', type: 'number', default: 50 },
          { name: 'payout_terms', label: 'شروط العقد' },
          { name: 'active', label: 'نشط', type: 'bool', default: true },
        ]}
        columns={[
          { key: 'name', label: 'الاسم' },
          { key: 'specialty', label: 'التخصص' },
          { key: 'instructor_share_pct', label: 'نسبته', render: (r) => `${r.instructor_share_pct}%` },
          { key: 'active', label: 'نشط', render: (r) => yesNo(r.active) },
        ]} />

      <CrudTable title="أصناف المخزن" table="inventory_items" order="name"
        subtitle="الكمية بتتغير من حركات المخزون بس، مش من هنا"
        fields={[
          { name: 'name', label: 'الصنف', required: true },
          { name: 'category', label: 'النوع', type: 'select', options: [['tool', 'أداة (رأسمالية)'], ['consumable', 'مستهلك']], required: true },
          { name: 'unit', label: 'الوحدة', default: 'قطعة' },
          { name: 'unit_cost', label: 'تكلفة الوحدة', type: 'number', default: 0 },
          { name: 'purchase_date', label: 'تاريخ الشراء', type: 'date' },
          { name: 'useful_life_months', label: 'العمر الافتراضي (شهور)', type: 'number', show: (f) => f.category === 'tool' },
          { name: 'reorder_level', label: 'حد إعادة الطلب', type: 'number', default: 0 },
          { name: 'notes', label: 'ملاحظات' },
        ]}
        columns={[
          { key: 'name', label: 'الصنف' },
          { key: 'category', label: 'النوع', render: (r) => (r.category === 'tool' ? 'أداة' : 'مستهلك') },
          { key: 'quantity', label: 'الكمية', render: (r) => <span className={Number(r.quantity) <= Number(r.reorder_level) ? 'bad' : ''}>{r.quantity} {r.unit}</span> },
          { key: 'unit_cost', label: 'التكلفة', render: (r) => money(r.unit_cost) },
          { key: 'v', label: 'القيمة', render: (r) => money(r.quantity * r.unit_cost) },
        ]} />

      <InventoryMovement items={L.items} courses={L.maintenanceCourses} />
    </div>
  )
}
