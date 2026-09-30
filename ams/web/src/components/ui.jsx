import { useCallback, useEffect, useState } from 'react'

export function Card({ title, subtitle, actions, children, wide }) {
  return (
    <section className={`card${wide ? ' wide' : ''}`}>
      {(title || actions) && (
        <header className="card-head">
          <div>
            {title && <h3>{title}</h3>}
            {subtitle && <p className="muted">{subtitle}</p>}
          </div>
          {actions && <div className="row">{actions}</div>}
        </header>
      )}
      {children}
    </section>
  )
}

export function Field({ label, children, hint }) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
      {hint && <small className="muted">{hint}</small>}
    </label>
  )
}

export function Stat({ label, value, tone }) {
  return (
    <div className={`stat ${tone || ''}`}>
      <span className="muted">{label}</span>
      <strong>{value}</strong>
    </div>
  )
}

export function Msg({ msg }) {
  if (!msg) return null
  return <div className={`msg ${msg.type}`}>{msg.text}</div>
}

// زرار بيشغّل عملية async ويعرض نتيجتها
export function useAction() {
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState(null)
  const run = useCallback(async (fn, okText) => {
    setBusy(true)
    setMsg(null)
    try {
      const result = await fn()
      if (okText) setMsg({ type: 'ok', text: okText })
      return result
    } catch (e) {
      setMsg({ type: 'err', text: e.message })
      return undefined
    } finally {
      setBusy(false)
    }
  }, [])
  return { busy, msg, setMsg, run }
}

// تحميل بيانات مع إعادة تحميل عند تغيّر deps
export function useLoad(fn, deps) {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)
  const [tick, setTick] = useState(0)
  useEffect(() => {
    let alive = true
    setError(null)
    fn()
      .then((d) => alive && setData(d))
      .catch((e) => alive && setError(e.message))
    return () => {
      alive = false
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick])
  return { data, error, reload: () => setTick((t) => t + 1) }
}

export function Table({ columns, rows, empty = 'مفيش بيانات' }) {
  if (!rows) return <p className="muted">جاري التحميل…</p>
  if (!rows.length) return <p className="muted">{empty}</p>
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.key}>{c.label}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={r.id || i}>
              {columns.map((c) => (
                <td key={c.key}>{c.render ? c.render(r) : r[c.key]}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
