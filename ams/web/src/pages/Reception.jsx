import { useEffect, useState } from 'react'
import { rpc, select, supabase } from '../lib/supabase'
import {
  AREAS, ENROLLMENT_STATUS, LEAD_TYPES, PAYMENT_METHODS, WEEKDAYS,
  money, monthStart, searchTerm, thisMonth, today, weekdayOf,
} from '../lib/format'
import { Card, Field, Msg, Table, useAction, useLoad } from '../components/ui'

const groupLabel = (g) =>
  `${g.track_name} — ${g.course_name} · ${WEEKDAYS[g.weekday]} ${g.period_label} (${g.start_time.slice(0, 5)}) · فاضي ${g.free_seats}`

// ------------------------------------------------------------------
// تسجيل طالب جديد + تفعيل الاشتراك
// ------------------------------------------------------------------
const EMPTY_STUDENT = {
  full_name: '', birth_date: '', guardian_name: '', guardian_phone: '', phone: '',
  area: 'الصف', lead_source_id: '', promo_code: '', group_id: '', fee_override: '',
}

function RegisterStudent({ onDone }) {
  const [f, setF] = useState(EMPTY_STUDENT)
  const [promo, setPromo] = useState(null)
  const { busy, msg, setMsg, run } = useAction()
  const set = (k) => (e) => setF({ ...f, [k]: e.target.value })

  const sources = useLoad(() => select(supabase.from('lead_sources').select('*').eq('active', true).order('type')), [])
  const groups = useLoad(
    () => select(supabase.from('v_group_occupancy').select('*').eq('active', true).gt('free_seats', 0)
      .order('weekday').order('slot_no')),
    [],
  )
  const source = sources.data?.find((s) => s.id === f.lead_source_id)
  const isPromo = source?.type === 'promo_code'

  const checkPromo = () =>
    run(async () => {
      const rows = await rpc('check_promo_code', { p_code: f.promo_code })
      if (!rows.length) throw new Error('الكود مش موجود أو متوقف')
      setPromo(rows[0])
    })

  const submit = (e) => {
    e.preventDefault()
    run(async () => {
      const studentId = await rpc('register_student', {
        p_full_name: f.full_name,
        p_birth_date: f.birth_date,
        p_guardian_phone: f.guardian_phone,
        p_area: f.area,
        p_lead_source_id: f.lead_source_id,
        p_promo_code: isPromo ? f.promo_code : null,
        p_phone: f.phone || null,
        p_guardian_name: f.guardian_name || null,
      })
      if (f.group_id) {
        await rpc('create_enrollment', {
          p_student_id: studentId,
          p_group_id: f.group_id,
          p_monthly_fee_override: f.fee_override ? Number(f.fee_override) : null,
          p_activate: true,
        })
      }
      setF(EMPTY_STUDENT)
      setPromo(null)
      groups.reload()
      onDone?.()
    }, f.group_id ? 'تم التسجيل وتفعيل الاشتراك ✔' : 'تم تسجيل الطالب ✔ (من غير مجموعة)')
  }

  return (
    <Card title="تسجيل طالب جديد" subtitle="مصدر العميل إلزامي — مصدر واحد بس لكل طالب">
      <form className="grid" onSubmit={submit}>
        <Field label="اسم الطالب"><input value={f.full_name} onChange={set('full_name')} required /></Field>
        <Field label="تاريخ الميلاد"><input type="date" value={f.birth_date} onChange={set('birth_date')} required /></Field>
        <Field label="اسم ولي الأمر"><input value={f.guardian_name} onChange={set('guardian_name')} /></Field>
        <Field label="موبايل ولي الأمر"><input value={f.guardian_phone} onChange={set('guardian_phone')} required inputMode="tel" /></Field>
        <Field label="موبايل الطالب"><input value={f.phone} onChange={set('phone')} inputMode="tel" /></Field>
        <Field label="المنطقة">
          <select value={f.area} onChange={set('area')}>
            {AREAS.map((a) => <option key={a}>{a}</option>)}
          </select>
        </Field>
        <Field label="مصدر العميل">
          <select value={f.lead_source_id} onChange={(e) => { set('lead_source_id')(e); setPromo(null) }} required>
            <option value="">— اختار —</option>
            {sources.data?.map((s) => (
              <option key={s.id} value={s.id}>{LEAD_TYPES[s.type]} · {s.label}</option>
            ))}
          </select>
        </Field>
        {isPromo && (
          <Field label="الكود الترويجي" hint={promo && `✔ ${promo.owner_name} — خصم ${money(promo.discount_value)}`}>
            <div className="row">
              <input value={f.promo_code} onChange={(e) => { set('promo_code')(e); setPromo(null) }} required />
              <button type="button" onClick={checkPromo} disabled={busy}>تحقق</button>
            </div>
          </Field>
        )}
        <Field label="المجموعة (اختياري)">
          <select value={f.group_id} onChange={set('group_id')}>
            <option value="">— من غير مجموعة دلوقتي —</option>
            {groups.data?.map((g) => <option key={g.group_id} value={g.group_id}>{groupLabel(g)}</option>)}
          </select>
        </Field>
        <Field label="رسوم مخصوصة (اختياري)" hint="سيبها فاضية للسعر العادي">
          <input type="number" min="0" value={f.fee_override} onChange={set('fee_override')} />
        </Field>
        <div className="full">
          <button className="primary" disabled={busy}>حفظ وتفعيل الاشتراك</button>
          <Msg msg={msg} />
        </div>
      </form>
    </Card>
  )
}

// ------------------------------------------------------------------
// ربط طالب موجود بمجموعة + التسجيلات المعلّقة
// ------------------------------------------------------------------
function EnrollExisting() {
  const [q, setQ] = useState('')
  const [studentId, setStudentId] = useState('')
  const [groupId, setGroupId] = useState('')
  const { busy, msg, run } = useAction()
  const students = useLoad(
    () => (searchTerm(q).length < 2 ? Promise.resolve([])
      : select(supabase.from('students').select('id, full_name, guardian_phone')
          .or(`full_name.ilike.%${searchTerm(q)}%,guardian_phone.ilike.%${searchTerm(q)}%`).limit(10))),
    [q],
  )
  const groups = useLoad(
    () => select(supabase.from('v_group_occupancy').select('*').eq('active', true).gt('free_seats', 0)
      .order('weekday').order('slot_no')),
    [],
  )
  const pending = useLoad(
    () => select(supabase.from('v_enrollment_roster').select('*').in('status', ['pending', 'suspended']).order('full_name')),
    [],
  )

  const enroll = () =>
    run(async () => {
      await rpc('create_enrollment', { p_student_id: studentId, p_group_id: groupId, p_activate: true })
      setGroupId('')
      groups.reload()
    }, 'تم التسجيل في المجموعة ✔')

  const activate = (id) =>
    run(async () => {
      await rpc('set_enrollment_status', { p_enrollment_id: id, p_status: 'active' })
      pending.reload()
    }, 'تم التفعيل ✔')

  return (
    <Card title="تسجيل طالب قديم في مجموعة">
      <div className="grid">
        <Field label="بحث بالاسم أو موبايل ولي الأمر">
          <input value={q} onChange={(e) => setQ(e.target.value)} />
        </Field>
        <Field label="الطالب">
          <select value={studentId} onChange={(e) => setStudentId(e.target.value)}>
            <option value="">— اختار —</option>
            {students.data?.map((s) => <option key={s.id} value={s.id}>{s.full_name} · {s.guardian_phone}</option>)}
          </select>
        </Field>
        <Field label="المجموعة">
          <select value={groupId} onChange={(e) => setGroupId(e.target.value)}>
            <option value="">— اختار —</option>
            {groups.data?.map((g) => <option key={g.group_id} value={g.group_id}>{groupLabel(g)}</option>)}
          </select>
        </Field>
        <div className="full">
          <button className="primary" disabled={busy || !studentId || !groupId} onClick={enroll}>تسجيل وتفعيل</button>
          <Msg msg={msg} />
        </div>
      </div>
      <h4>تسجيلات معلّقة / موقوفة</h4>
      <Table
        rows={pending.data}
        empty="مفيش تسجيلات معلّقة"
        columns={[
          { key: 'full_name', label: 'الطالب' },
          { key: 'course_name', label: 'الكورس' },
          { key: 'status', label: 'الحالة', render: (r) => ENROLLMENT_STATUS[r.status] },
          { key: 'a', label: '', render: (r) => <button onClick={() => activate(r.enrollment_id)} disabled={busy}>تفعيل</button> },
        ]}
      />
    </Card>
  )
}

// ------------------------------------------------------------------
// كشف حضور المجموعة الحالية
// ------------------------------------------------------------------
function Attendance() {
  const [date, setDate] = useState(today())
  const [groupId, setGroupId] = useState('')
  const [sessionId, setSessionId] = useState(null)
  const [marks, setMarks] = useState({})
  const { busy, msg, setMsg, run } = useAction()

  const groups = useLoad(
    () => select(supabase.from('v_group_occupancy').select('*').eq('active', true)
      .eq('weekday', weekdayOf(date)).order('slot_no')),
    [date],
  )
  const roster = useLoad(
    () => (!groupId ? Promise.resolve(null)
      : select(supabase.from('v_enrollment_roster').select('enrollment_id, full_name, guardian_phone')
          .eq('group_id', groupId).eq('status', 'active').order('full_name'))),
    [groupId],
  )

  // فتح الحصة وتحميل الحضور المسجل قبل كده
  useEffect(() => {
    setSessionId(null)
    setMarks({})
    setMsg(null)
    if (!groupId) return
    run(async () => {
      const sid = await rpc('open_session', { p_group_id: groupId, p_date: date })
      setSessionId(sid)
      const rows = await select(supabase.from('attendance').select('enrollment_id, attendance_status').eq('session_id', sid))
      setMarks(Object.fromEntries(rows.map((r) => [r.enrollment_id, r.attendance_status])))
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [groupId, date])

  const allPresent = () => setMarks(Object.fromEntries((roster.data || []).map((r) => [r.enrollment_id, 'present'])))

  const save = () =>
    run(async () => {
      const records = Object.entries(marks).map(([enrollment_id, status]) => ({ enrollment_id, status }))
      if (!records.length) throw new Error('مفيش حضور متسجل')
      await rpc('mark_attendance', { p_session_id: sessionId, p_records: records })
    }, 'تم حفظ الحضور ✔')

  return (
    <Card title="كشف حضور المجموعة" subtitle="ضغطة واحدة لكل طالب">
      <div className="grid">
        <Field label="التاريخ">
          <input type="date" value={date} onChange={(e) => { setDate(e.target.value); setGroupId('') }} />
        </Field>
        <Field label={`مجموعات يوم ${WEEKDAYS[weekdayOf(date)]}`}>
          <select value={groupId} onChange={(e) => setGroupId(e.target.value)}>
            <option value="">— اختار —</option>
            {groups.data?.map((g) => (
              <option key={g.group_id} value={g.group_id}>
                {g.period_label} ({g.start_time.slice(0, 5)}) — {g.course_name} · {g.room}
              </option>
            ))}
          </select>
        </Field>
      </div>
      {sessionId && roster.data && (
        <>
          <div className="attendance">
            {roster.data.map((r) => (
              <div key={r.enrollment_id} className="att-row">
                <span>{r.full_name}</span>
                <div className="seg">
                  {[['present', 'حاضر'], ['absent', 'غايب'], ['excused', 'بعذر']].map(([k, l]) => (
                    <button key={k} className={marks[r.enrollment_id] === k ? `on ${k}` : ''}
                      onClick={() => setMarks({ ...marks, [r.enrollment_id]: k })}>{l}</button>
                  ))}
                </div>
              </div>
            ))}
            {!roster.data.length && <p className="muted">مفيش طلاب نشطين في المجموعة</p>}
          </div>
          <div className="row">
            <button onClick={allPresent}>الكل حاضر</button>
            <button className="primary" onClick={save} disabled={busy}>حفظ الحضور</button>
          </div>
        </>
      )}
      <Msg msg={msg} />
    </Card>
  )
}

// ------------------------------------------------------------------
// تحصيل سريع
// ------------------------------------------------------------------
function QuickPayment() {
  const [q, setQ] = useState('')
  const [enr, setEnr] = useState(null)
  const [amount, setAmount] = useState('')
  const [month, setMonth] = useState(thisMonth())
  const [method, setMethod] = useState('cash')
  const { busy, msg, run } = useAction()

  const results = useLoad(
    () => (searchTerm(q).length < 2 ? Promise.resolve([])
      : select(supabase.from('v_enrollment_roster').select('*').in('status', ['active', 'suspended'])
          .or(`full_name.ilike.%${searchTerm(q)}%,guardian_phone.ilike.%${searchTerm(q)}%`).limit(10))),
    [q],
  )
  const history = useLoad(
    () => (!enr ? Promise.resolve(null)
      : select(supabase.from('payments').select('*').eq('enrollment_id', enr.enrollment_id)
          .order('payment_date', { ascending: false }).limit(6))),
    [enr?.enrollment_id],
  )

  const pick = (r) => {
    setEnr(r)
    const firstMonth = !r.activated_at || r.activated_at.slice(0, 7) === thisMonth()
    setAmount(String(r.effective_fee - (firstMonth ? r.promo_discount : 0)))
  }

  const pay = () =>
    run(async () => {
      await rpc('record_payment', {
        p_enrollment_id: enr.enrollment_id,
        p_amount: Number(amount),
        p_month: monthStart(month),
        p_method: method,
      })
      history.reload()
    }, 'تم التحصيل ✔')

  return (
    <Card title="تحصيل سريع" subtitle="الدفعة بتتربط بالشهر وطريقة الدفع">
      <Field label="بحث بالاسم أو موبايل ولي الأمر">
        <input value={q} onChange={(e) => { setQ(e.target.value); setEnr(null) }} />
      </Field>
      {!enr && results.data?.length > 0 && (
        <ul className="pick">
          {results.data.map((r) => (
            <li key={r.enrollment_id}>
              <button onClick={() => pick(r)}>
                {r.full_name} — {r.course_name} · {money(r.effective_fee)}
              </button>
            </li>
          ))}
        </ul>
      )}
      {enr && (
        <>
          <p><strong>{enr.full_name}</strong> — {enr.course_name}</p>
          <div className="grid">
            <Field label="المبلغ"><input type="number" min="1" value={amount} onChange={(e) => setAmount(e.target.value)} /></Field>
            <Field label="عن شهر"><input type="month" value={month} onChange={(e) => setMonth(e.target.value)} /></Field>
            <Field label="طريقة الدفع">
              <select value={method} onChange={(e) => setMethod(e.target.value)}>
                {Object.entries(PAYMENT_METHODS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </Field>
          </div>
          <button className="primary" onClick={pay} disabled={busy || !(Number(amount) > 0)}>تسجيل الدفعة</button>
          <Table
            rows={history.data}
            empty="مفيش دفعات سابقة"
            columns={[
              { key: 'payment_date', label: 'التاريخ' },
              { key: 'month_covered', label: 'عن شهر', render: (r) => r.month_covered.slice(0, 7) },
              { key: 'amount', label: 'المبلغ', render: (r) => money(r.amount) },
              { key: 'method', label: 'الطريقة', render: (r) => PAYMENT_METHODS[r.method] },
            ]}
          />
        </>
      )}
      <Msg msg={msg} />
    </Card>
  )
}

export default function Reception({ staff }) {
  if (staff.role === 'instructor') return <div className="cards"><Attendance /></div>
  return (
    <div className="cards">
      <RegisterStudent />
      <Attendance />
      <QuickPayment />
      <EnrollExisting />
    </div>
  )
}
