import { useState } from 'react'
import { rpc, select, supabase } from '../lib/supabase'
import { COURSE_TYPES, WEEKDAYS, money, monthStart, thisMonth } from '../lib/format'
import { Card, Field, Msg, Stat, Table, useAction, useLoad } from '../components/ui'

export function ProfitBreakdown({ p }) {
  if (!p) return <p className="muted">جاري الحساب…</p>
  const rows = [
    ['إجمالي التحصيل', p.gross_revenue],
    ['− استقطاع صندوق التجديد', p.maintenance_fund_reserve],
    ['− حصة م. معتز من الصيانة', p.maintenance_engineer_share],
    ['− إشراف 7% على المتقدم', p.advanced_supervision_fees],
    ['− حصة المدربين الخارجيين', p.external_instructor_share],
    ['= إيراد المركز', p.center_revenue, 'sum'],
    ['− مصروفات تشغيل', p.operating_expenses],
    ['− رواتب ثابتة', p.staff_base_salaries],
    ['− بونص السكرتارية', p.staff_bonuses],
    ['− عمولات أكواد', p.referral_commissions],
    ['= صافي الربح', p.net_profit, 'sum'],
    ['حصة الشركاء (5%)', p.equity_share_total, 'accent'],
  ]
  return (
    <table className="breakdown">
      <tbody>
        {rows.map(([l, v, cls]) => (
          <tr key={l} className={cls}>
            <td>{l}</td>
            <td>{money(v)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

function OccupancyGrid() {
  const periods = useLoad(() => select(supabase.from('periods').select('*').order('slot_no')), [])
  const groups = useLoad(() => select(supabase.from('v_group_occupancy').select('*').eq('active', true)), [])
  if (!periods.data || !groups.data) return <p className="muted">جاري التحميل…</p>
  const days = [6, 0, 1, 2, 3, 4, 5] // السبت → الجمعة
  const cell = (pid, d) => groups.data.filter((g) => g.period_id === pid && g.weekday === d)
  const total = groups.data.length
  const slots = periods.data.length * 7
  return (
    <>
      <p className="muted">
        {total} مجموعة نشطة من {slots} خانة ({Math.round((total / Math.max(slots, 1)) * 100)}% إشغال للمعمل)
      </p>
      <div className="table-wrap">
        <table className="grid-table">
          <thead>
            <tr>
              <th>الفترة</th>
              {days.map((d) => <th key={d}>{WEEKDAYS[d]}</th>)}
            </tr>
          </thead>
          <tbody>
            {periods.data.map((p) => (
              <tr key={p.id}>
                <th>
                  {p.label}
                  <br />
                  <small>{p.start_time.slice(0, 5)}</small>
                </th>
                {days.map((d) => (
                  <td key={d}>
                    {cell(p.id, d).map((g) => {
                      const used = g.active_count + g.pending_count
                      const pct = used / g.capacity
                      return (
                        <div key={g.group_id} className={`slot ${pct >= 1 ? 'full' : pct >= 0.7 ? 'mid' : 'low'}`}
                          title={`${g.track_name} · ${g.room}`}>
                          {g.course_name}
                          <b>{used}/{g.capacity}</b>
                        </div>
                      )
                    })}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  )
}

export function ReferralPayouts() {
  const { busy, msg, run } = useAction()
  const rows = useLoad(
    () => select(supabase.from('referral_commissions')
      .select('id, amount, status, month, created_at, promo_codes(code, owner_name, owner_phone), students(full_name)')
      .eq('status', 'pending').order('created_at')),
    [],
  )
  const pay = (id) => run(async () => { await rpc('pay_referral_commission', { p_id: id }); rows.reload() }, 'تم الصرف ✔')
  return (
    <Card title="عمولات أكواد مستحقة" subtitle="بتتصرف بعد أول دفعة للطالب">
      <Table
        rows={rows.data}
        empty="مفيش عمولات مستحقة"
        columns={[
          { key: 'code', label: 'الكود', render: (r) => r.promo_codes.code },
          { key: 'owner', label: 'صاحبه', render: (r) => `${r.promo_codes.owner_name} ${r.promo_codes.owner_phone || ''}` },
          { key: 'student', label: 'الطالب', render: (r) => r.students.full_name },
          { key: 'amount', label: 'المبلغ', render: (r) => money(r.amount) },
          { key: 'a', label: '', render: (r) => <button disabled={busy} onClick={() => pay(r.id)}>صرف</button> },
        ]}
      />
      <Msg msg={msg} />
    </Card>
  )
}

export default function Manager() {
  const [month, setMonth] = useState(thisMonth())
  const m = monthStart(month)

  const revenue = useLoad(() => select(supabase.from('v_revenue_by_track').select('*').eq('month', m)), [m])
  const fund = useLoad(() => select(supabase.from('v_maintenance_fund_balance').select('balance').single()), [])
  const profit = useLoad(() => rpc('compute_month_profit', { p_month: m }), [m])
  const promos = useLoad(
    () => select(supabase.from('v_promo_performance').select('*').order('students_activated', { ascending: false })),
    [],
  )
  const closed = useLoad(() => select(supabase.from('closed_months').select('month').eq('month', m)), [m])

  const byTrack = Object.values(
    (revenue.data || []).reduce((acc, r) => {
      acc[r.track_name] ??= { track: r.track_name, revenue: 0, count: 0 }
      acc[r.track_name].revenue += Number(r.revenue)
      acc[r.track_name].count += r.payments_count
      return acc
    }, {}),
  ).sort((a, b) => b.revenue - a.revenue)
  const maxRev = Math.max(1, ...byTrack.map((r) => r.revenue))

  return (
    <>
      <div className="toolbar">
        <Field label="الشهر">
          <input type="month" value={month} onChange={(e) => setMonth(e.target.value)} />
        </Field>
        {closed.data?.length ? <span className="badge ok">الشهر مقفول</span> : <span className="badge">تقديري — لسه مااتقفلش</span>}
      </div>

      <div className="stats">
        <Stat label="إجمالي تحصيل الشهر" value={money(profit.data?.gross_revenue)} />
        <Stat label="صافي الربح" value={money(profit.data?.net_profit)} tone={profit.data?.net_profit < 0 ? 'bad' : 'good'} />
        <Stat label="رصيد صندوق التجديد" value={money(fund.data?.balance)} />
        <Stat label="حصة الشركاء (5%)" value={money(profit.data?.equity_share_total)} />
      </div>

      <div className="cards">
        <Card title="إيراد الشهر بالمسار">
          {byTrack.length ? byTrack.map((r) => (
            <div key={r.track} className="bar-row">
              <span>{r.track}</span>
              <div className="bar"><i style={{ width: `${(r.revenue / maxRev) * 100}%` }} /></div>
              <b>{money(r.revenue)}</b>
            </div>
          )) : <p className="muted">مفيش تحصيل للشهر ده</p>}
          {revenue.data?.length > 0 && (
            <p className="muted">
              {Object.entries(COURSE_TYPES).map(([k, v]) => {
                const s = revenue.data.filter((r) => r.course_type === k).reduce((a, r) => a + Number(r.revenue), 0)
                return s ? `${v}: ${money(s)}  ` : ''
              })}
            </p>
          )}
        </Card>

        <Card title="صافي الربح التقديري" subtitle="قبل إقفال المحاسب">
          {profit.error ? <Msg msg={{ type: 'err', text: profit.error }} /> : <ProfitBreakdown p={profit.data} />}
        </Card>

        <Card title="أداء أكواد الإحالة" subtitle="مرتبة بعدد التسجيلات الفعلية">
          <Table
            rows={promos.data}
            empty="مفيش أكواد"
            columns={[
              { key: 'code', label: 'الكود' },
              { key: 'owner_name', label: 'صاحبه' },
              { key: 'students_registered', label: 'مسجلين' },
              { key: 'students_activated', label: 'مفعّلين' },
              { key: 'commission_pending', label: 'مستحق', render: (r) => money(r.commission_pending) },
              { key: 'commission_paid', label: 'اتصرف', render: (r) => money(r.commission_paid) },
            ]}
          />
        </Card>

        <ReferralPayouts />

        <Card title="إشغال الفترات اليومية" subtitle="7 فترات × أيام الأسبوع" wide>
          <OccupancyGrid />
        </Card>
      </div>
    </>
  )
}
