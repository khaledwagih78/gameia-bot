import { useState } from 'react'
import { rpc, select, supabase } from '../lib/supabase'
import {
  EXPENSE_CATEGORIES, ROLES, addDays, lastFullWeekStart, money, monthStart, prevMonth, thisMonth, today,
} from '../lib/format'
import { Card, Field, Msg, Stat, Table, useAction, useLoad } from '../components/ui'
import { ProfitBreakdown, ReferralPayouts } from './Manager'

const bold = (value) => ({ value, fontWeight: 'bold' })

// مكتبة الإكسل بتتحمل بس لما حد يضغط تصدير
const xlsx = (...args) => import('write-excel-file/browser').then((m) => m.default(...args))

// ------------------------------------------------------------------
// الإقفال الأسبوعي + التصدير لإكسل
// ------------------------------------------------------------------
function WeeklyClosure() {
  const [weekStart, setWeekStart] = useState(lastFullWeekStart())
  const { busy, msg, run } = useAction()
  const preview = useLoad(() => rpc('preview_weekly_closure', { p_week_start: weekStart }), [weekStart])
  const history = useLoad(
    () => select(supabase.from('weekly_closures').select('*').order('week_start', { ascending: false }).limit(8)),
    [],
  )
  const isClosed = history.data?.some((w) => w.week_start === weekStart)

  const close = () =>
    run(async () => {
      await rpc('close_week', { p_week_start: weekStart })
      history.reload()
    }, 'تم إقفال الأسبوع ✔')

  const exportXlsx = (ws) =>
    run(async () => {
      const [summary, details] = await Promise.all([
        rpc('preview_weekly_closure', { p_week_start: ws }),
        rpc('weekly_closure_details', { p_week_start: ws }),
      ])
      await (await xlsx(
        [
          {
            sheet: 'الملخص',
            rightToLeft: true,
            columns: [{ width: 28 }, { width: 18 }],
            data: [
              [bold('إقفال أسبوع'), `${ws} ← ${addDays(ws, 6)}`],
              ['إجمالي الإيراد', Number(summary.total_revenue)],
              ['إجمالي المصروفات', Number(summary.total_expenses)],
              [bold('صافي النقدية'), bold(Number(summary.net_cash))],
              ['عدد الدفعات', summary.payments_count],
            ],
          },
          {
            sheet: 'التفاصيل',
            rightToLeft: true,
            columns: [{ width: 10 }, { width: 14 }, { width: 40 }, { width: 18 }, { width: 14 }],
            data: [
              ['النوع', 'التاريخ', 'البيان', 'التصنيف', 'المبلغ'].map(bold),
              ...details.map((d) => [d.kind, d.entry_date, d.description, d.category, Number(d.amount)]),
            ],
          },
        ],
      )).toFile(`afaq-week-${ws}.xlsx`)
    })

  const p = preview.data
  return (
    <Card title="إقفال الأسبوع" subtitle="مقبوضات الأسبوع − مصروفات الأسبوع (الأسبوع من السبت للجمعة)">
      <div className="toolbar">
        <Field label="بداية الأسبوع">
          <input type="date" value={weekStart} onChange={(e) => setWeekStart(e.target.value)} />
        </Field>
        <span className="muted">لحد {addDays(weekStart, 6)}</span>
      </div>
      {p && (
        <div className="stats">
          <Stat label="الإيراد" value={money(p.total_revenue)} />
          <Stat label="المصروفات" value={money(p.total_expenses)} />
          <Stat label="الصافي" value={money(p.net_cash)} tone={p.net_cash < 0 ? 'bad' : 'good'} />
          <Stat label="عدد الدفعات" value={p.payments_count} />
        </div>
      )}
      <div className="row">
        <button className="primary" onClick={close} disabled={busy || isClosed || addDays(weekStart, 6) >= today()}>
          {isClosed ? 'الأسبوع مقفول' : 'إقفال الأسبوع'}
        </button>
        <button onClick={() => exportXlsx(weekStart)} disabled={busy}>تصدير Excel</button>
      </div>
      <Msg msg={msg} />
      <h4>آخر الإقفالات</h4>
      <Table
        rows={history.data}
        empty="مفيش إقفالات لسه"
        columns={[
          { key: 'week_start', label: 'الأسبوع', render: (r) => `${r.week_start} ← ${r.week_end}` },
          { key: 'total_revenue', label: 'إيراد', render: (r) => money(r.total_revenue) },
          { key: 'total_expenses', label: 'مصروف', render: (r) => money(r.total_expenses) },
          { key: 'net_cash', label: 'صافي', render: (r) => money(r.net_cash) },
          { key: 'x', label: '', render: (r) => <button onClick={() => exportXlsx(r.week_start)}>Excel</button> },
        ]}
      />
    </Card>
  )
}

// ------------------------------------------------------------------
// المصروفات
// ------------------------------------------------------------------
function Expenses() {
  const [month, setMonth] = useState(thisMonth())
  const [f, setF] = useState({ category: 'electricity', amount: '', expense_date: today(), recurring: false, description: '' })
  const [editing, setEditing] = useState({})
  const { busy, msg, run } = useAction()
  const list = useLoad(
    () => select(supabase.from('expenses').select('*').eq('month', monthStart(month)).order('expense_date')),
    [month],
  )

  const add = (e) => {
    e.preventDefault()
    run(async () => {
      await select(supabase.from('expenses').insert({ ...f, amount: Number(f.amount), month: monthStart(month) }))
      setF({ ...f, amount: '', description: '' })
      list.reload()
    }, 'تم إضافة المصروف ✔')
  }

  const saveAmount = (id) =>
    run(async () => {
      await select(supabase.from('expenses').update({ amount: Number(editing[id]) }).eq('id', id))
      setEditing({ ...editing, [id]: undefined })
      list.reload()
    }, 'تم التعديل ✔')

  const remove = (id) =>
    run(async () => {
      if (!confirm('تمسح المصروف ده؟')) return
      await select(supabase.from('expenses').delete().eq('id', id))
      list.reload()
    })

  // نسخ المصروفات الثابتة من الشهر اللي فات
  const copyRecurring = () =>
    run(async () => {
      const [y, m] = month.split('-').map(Number)
      const prev = new Date(Date.UTC(y, m - 2, 1)).toISOString().slice(0, 10)
      const rows = await select(supabase.from('expenses').select('category, amount, recurring, description')
        .eq('month', prev).eq('recurring', true))
      if (!rows.length) throw new Error('مفيش مصروفات ثابتة في الشهر اللي فات')
      await select(supabase.from('expenses').insert(rows.map((r) => ({ ...r, month: monthStart(month), expense_date: monthStart(month) }))))
      list.reload()
    }, 'تم نسخ المصروفات الثابتة ✔')

  const total = (list.data || []).reduce((a, r) => a + Number(r.amount), 0)

  return (
    <Card title="المصروفات التشغيلية"
      subtitle="رواتب الموظفين المسجلين في النظام بتتحسب تلقائي — متدخلهاش هنا"
      actions={<button onClick={copyRecurring} disabled={busy}>نسخ الثابت من الشهر اللي فات</button>}>
      <form className="grid" onSubmit={add}>
        <Field label="الشهر"><input type="month" value={month} onChange={(e) => setMonth(e.target.value)} /></Field>
        <Field label="البند">
          <select value={f.category} onChange={(e) => setF({ ...f, category: e.target.value })}>
            {Object.entries(EXPENSE_CATEGORIES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </Field>
        <Field label="المبلغ"><input type="number" min="1" step="0.01" value={f.amount} onChange={(e) => setF({ ...f, amount: e.target.value })} required /></Field>
        <Field label="تاريخ الصرف"><input type="date" value={f.expense_date} onChange={(e) => setF({ ...f, expense_date: e.target.value })} /></Field>
        <Field label="البيان"><input value={f.description} onChange={(e) => setF({ ...f, description: e.target.value })} /></Field>
        <label className="check">
          <input type="checkbox" checked={f.recurring} onChange={(e) => setF({ ...f, recurring: e.target.checked })} /> مصروف ثابت كل شهر
        </label>
        <div className="full"><button className="primary" disabled={busy}>إضافة مصروف</button></div>
      </form>
      <Msg msg={msg} />
      <Table
        rows={list.data}
        empty="مفيش مصروفات للشهر ده"
        columns={[
          { key: 'expense_date', label: 'التاريخ' },
          { key: 'category', label: 'البند', render: (r) => EXPENSE_CATEGORIES[r.category] + (r.recurring ? ' ↻' : '') },
          { key: 'description', label: 'البيان' },
          {
            key: 'amount', label: 'المبلغ',
            render: (r) => editing[r.id] !== undefined ? (
              <span className="row">
                <input type="number" className="sm" value={editing[r.id]} onChange={(e) => setEditing({ ...editing, [r.id]: e.target.value })} />
                <button onClick={() => saveAmount(r.id)}>حفظ</button>
              </span>
            ) : money(r.amount),
          },
          {
            key: 'x', label: '',
            render: (r) => (
              <span className="row">
                <button onClick={() => setEditing({ ...editing, [r.id]: r.amount })}>تعديل</button>
                <button className="danger" onClick={() => remove(r.id)}>مسح</button>
              </span>
            ),
          },
        ]}
      />
      <p><strong>الإجمالي: {money(total)}</strong></p>
    </Card>
  )
}

// ------------------------------------------------------------------
// إقفال الشهر + الرواتب
// ------------------------------------------------------------------
function MonthClose() {
  const [month, setMonth] = useState(prevMonth())
  const m = monthStart(month)
  const { busy, msg, run } = useAction()
  const ledger = useLoad(() => select(supabase.from('profit_ledger').select('*').eq('month', m).maybeSingle()), [m])
  const preview = useLoad(() => (ledger.data === null ? rpc('compute_month_profit', { p_month: m }) : Promise.resolve(null)), [m, ledger.data])
  const payroll = useLoad(
    () => select(supabase.from('payroll_runs').select('*, staff(full_name, role)').eq('month', m).order('net_pay', { ascending: false })),
    [m],
  )
  const mLedger = useLoad(() => select(supabase.from('maintenance_course_ledger').select('*, courses(name)').eq('month', m)), [m])
  const aLedger = useLoad(() => select(supabase.from('advanced_course_ledger').select('*, courses(name), external_instructors(name)').eq('month', m)), [m])

  const closeMonth = () =>
    run(async () => {
      if (!confirm(`إقفال شهر ${month} نهائي — مش هينفع تعديل تحصيل أو مصروفات الشهر بعده. متأكد؟`)) return
      await rpc('close_profit_month', { p_month: m })
      ledger.reload(); mLedger.reload(); aLedger.reload()
    }, 'تم إقفال الشهر ✔')

  const runPayroll = () =>
    run(async () => { await rpc('run_payroll', { p_month: m }); payroll.reload() }, 'تم حساب الرواتب ✔')

  const setStatus = (status) =>
    run(async () => { await rpc('set_payroll_status', { p_month: m, p_status: status }); payroll.reload() }, 'تم ✔')

  const exportPayroll = () =>
    run(async () => {
      await (await xlsx(payroll.data, {
        sheet: 'الرواتب',
        rightToLeft: true,
        columns: [
          { header: bold('الموظف'), cell: (r) => r.staff.full_name, width: 24 },
          { header: bold('الدور'), cell: (r) => ROLES[r.staff.role], width: 12 },
          { header: bold('الأساسي'), cell: (r) => Number(r.base_salary), width: 12 },
          { header: bold('بونص'), cell: (r) => Number(r.bonus_total), width: 12 },
          { header: bold('عمولات'), cell: (r) => Number(r.commission_total), width: 12 },
          { header: bold('حصة ربح'), cell: (r) => Number(r.profit_share_total), width: 12 },
          { header: bold('الصافي'), cell: (r) => Number(r.net_pay), width: 12 },
        ],
      })).toFile(`afaq-payroll-${month}.xlsx`)
    })

  const status = payroll.data?.[0]?.status
  return (
    <Card title="إقفال الشهر والرواتب" wide
      subtitle="الترتيب: إقفال الشهر (بيقفل كورسات الصيانة والمتقدم تلقائي) ← حساب الرواتب ← اعتماد ← صرف">
      <div className="toolbar">
        <Field label="الشهر"><input type="month" value={month} onChange={(e) => setMonth(e.target.value)} /></Field>
        {ledger.data ? <span className="badge ok">مقفول</span> : (
          <button className="primary" onClick={closeMonth} disabled={busy || month >= thisMonth()}>إقفال الشهر</button>
        )}
      </div>
      <div className="cards inner">
        <div>
          <h4>{ledger.data ? 'الربح النهائي' : 'معاينة قبل الإقفال'}</h4>
          <ProfitBreakdown p={ledger.data || preview.data} />
        </div>
        <div>
          <h4>كورسات الصيانة</h4>
          <Table rows={mLedger.data} empty="—" columns={[
            { key: 'c', label: 'الكورس', render: (r) => r.courses.name },
            { key: 'total_revenue', label: 'الإيراد', render: (r) => money(r.total_revenue) },
            { key: 'consumables_deduction', label: 'للصندوق', render: (r) => money(r.consumables_deduction) },
            { key: 'engineer_share', label: 'م. معتز', render: (r) => money(r.engineer_share) },
            { key: 'center_share', label: 'المركز', render: (r) => money(r.center_share) },
          ]} />
          <h4>الكورسات المتقدمة</h4>
          <Table rows={aLedger.data} empty="—" columns={[
            { key: 'c', label: 'الكورس', render: (r) => r.courses.name },
            { key: 'total_revenue', label: 'الإيراد', render: (r) => money(r.total_revenue) },
            { key: 's', label: '7% إشراف', render: (r) => money(r.supervision_fee_7pct) },
            { key: 'i', label: 'المدرب', render: (r) => `${money(r.instructor_share)} ${r.external_instructors?.name || ''}` },
            { key: 'center_share', label: 'المركز', render: (r) => money(r.center_share) },
          ]} />
        </div>
      </div>

      <h4>الرواتب {status && <span className="badge">{{ draft: 'مسودة', approved: 'معتمدة', paid: 'اتصرفت' }[status]}</span>}</h4>
      <div className="row">
        <button onClick={runPayroll} disabled={busy || !ledger.data || (status && status !== 'draft')}>حساب الرواتب</button>
        <button onClick={() => setStatus('approved')} disabled={busy || status !== 'draft'}>اعتماد</button>
        <button onClick={() => setStatus('paid')} disabled={busy || status !== 'approved'}>تم الصرف</button>
        <button onClick={exportPayroll} disabled={busy || !payroll.data?.length}>تصدير Excel</button>
      </div>
      <Msg msg={msg} />
      <Table rows={payroll.data} empty="لسه متحسبتش" columns={[
        { key: 'n', label: 'الموظف', render: (r) => r.staff.full_name },
        { key: 'r', label: 'الدور', render: (r) => ROLES[r.staff.role] },
        { key: 'base_salary', label: 'الأساسي', render: (r) => money(r.base_salary) },
        { key: 'bonus_total', label: 'بونص', render: (r) => money(r.bonus_total) },
        { key: 'commission_total', label: 'عمولات', render: (r) => money(r.commission_total) },
        { key: 'profit_share_total', label: 'حصة ربح', render: (r) => money(r.profit_share_total) },
        { key: 'net_pay', label: 'الصافي', render: (r) => <b>{money(r.net_pay)}</b> },
      ]} />
    </Card>
  )
}

// ------------------------------------------------------------------
// صندوق التجديد
// ------------------------------------------------------------------
function MaintenanceFund() {
  const [f, setF] = useState({ amount: '', description: '', item_id: '', quantity: '' })
  const { busy, msg, run } = useAction()
  const ledger = useLoad(
    () => select(supabase.from('maintenance_fund_ledger').select('*, courses(name)').order('created_at', { ascending: false }).limit(15)),
    [],
  )
  const items = useLoad(() => select(supabase.from('inventory_items').select('id, name, unit').order('name')), [])

  const spend = (e) => {
    e.preventDefault()
    run(async () => {
      await rpc('spend_maintenance_fund', {
        p_amount: Number(f.amount),
        p_description: f.description,
        p_item_id: f.item_id || null,
        p_quantity: f.item_id ? Number(f.quantity) : null,
      })
      setF({ amount: '', description: '', item_id: '', quantity: '' })
      ledger.reload()
    }, 'تم الصرف من الصندوق ✔')
  }

  return (
    <Card title="صندوق تجديد المستهلكات" subtitle={`الرصيد الحالي: ${money(ledger.data?.[0]?.running_balance)}`}>
      <form className="grid" onSubmit={spend}>
        <Field label="المبلغ"><input type="number" min="1" step="0.01" value={f.amount} onChange={(e) => setF({ ...f, amount: e.target.value })} required /></Field>
        <Field label="البيان"><input value={f.description} onChange={(e) => setF({ ...f, description: e.target.value })} required /></Field>
        <Field label="صنف اتشرى (اختياري)">
          <select value={f.item_id} onChange={(e) => setF({ ...f, item_id: e.target.value })}>
            <option value="">—</option>
            {items.data?.map((i) => <option key={i.id} value={i.id}>{i.name}</option>)}
          </select>
        </Field>
        {f.item_id && <Field label="الكمية"><input type="number" min="0.01" step="0.01" value={f.quantity} onChange={(e) => setF({ ...f, quantity: e.target.value })} required /></Field>}
        <div className="full"><button className="primary" disabled={busy}>صرف من الصندوق</button></div>
      </form>
      <Msg msg={msg} />
      <Table rows={ledger.data} empty="الصندوق فاضي" columns={[
        { key: 'transaction_date', label: 'التاريخ' },
        { key: 'd', label: 'الحركة', render: (r) => (r.direction === 'in' ? '⬇ إيداع' : '⬆ صرف') },
        { key: 'description', label: 'البيان' },
        { key: 'amount', label: 'المبلغ', render: (r) => money(r.amount) },
        { key: 'running_balance', label: 'الرصيد', render: (r) => money(r.running_balance) },
      ]} />
    </Card>
  )
}

export default function Accountant() {
  return (
    <div className="cards">
      <WeeklyClosure />
      <Expenses />
      <MonthClose />
      <MaintenanceFund />
      <ReferralPayouts />
    </div>
  )
}
