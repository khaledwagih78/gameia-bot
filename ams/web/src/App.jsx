import { useEffect, useState } from 'react'
import { supabase } from './lib/supabase'
import { ROLES } from './lib/format'
import { Msg } from './components/ui'
import Reception from './pages/Reception'
import Manager from './pages/Manager'
import Accountant from './pages/Accountant'
import Setup from './pages/Setup'

// اللوحات المتاحة لكل دور
const TABS = {
  secretary: ['reception'],
  instructor: ['reception'],
  accountant: ['accountant'],
  manager: ['manager', 'reception', 'accountant', 'setup'],
}
const TAB_LABELS = {
  reception: 'الاستقبال',
  manager: 'لوحة المدير',
  accountant: 'المحاسب',
  setup: 'الإعدادات',
}

function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [msg, setMsg] = useState(null)
  const submit = async (e) => {
    e.preventDefault()
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) setMsg({ type: 'err', text: 'الإيميل أو الباسورد غلط' })
  }
  return (
    <form className="login card" onSubmit={submit}>
      <h2>آفاق للبرمجة والذكاء الاصطناعي</h2>
      <p className="muted">نظام إدارة الأكاديمية</p>
      <input type="email" placeholder="الإيميل" value={email} onChange={(e) => setEmail(e.target.value)} required />
      <input type="password" placeholder="الباسورد" value={password} onChange={(e) => setPassword(e.target.value)} required />
      <button className="primary">دخول</button>
      <Msg msg={msg} />
    </form>
  )
}

export default function App() {
  const [session, setSession] = useState(undefined)
  const [staff, setStaff] = useState(undefined)
  const [tab, setTab] = useState(null)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session))
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSession(s))
    return () => data.subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!session) {
      setStaff(session === null ? null : undefined)
      return
    }
    supabase
      .from('staff')
      .select('*')
      .eq('auth_user_id', session.user.id)
      .eq('active', true)
      .maybeSingle()
      .then(({ data }) => {
        setStaff(data)
        if (data) setTab(TABS[data.role][0])
      })
  }, [session])

  if (session === undefined) return <p className="center muted">جاري التحميل…</p>
  if (!session) return <Login />
  if (staff === undefined) return <p className="center muted">جاري التحميل…</p>
  if (!staff)
    return (
      <div className="login card">
        <p>الحساب ده مش مربوط بموظف نشط. كلّم المدير يربطه من الإعدادات.</p>
        <button onClick={() => supabase.auth.signOut()}>خروج</button>
      </div>
    )

  const tabs = TABS[staff.role]
  return (
    <div className="app">
      <nav className="topbar">
        <strong>آفاق AMS</strong>
        <div className="tabs">
          {tabs.map((t) => (
            <button key={t} className={t === tab ? 'active' : ''} onClick={() => setTab(t)}>
              {TAB_LABELS[t]}
            </button>
          ))}
        </div>
        <div className="row">
          <span className="muted">
            {staff.full_name} · {ROLES[staff.role]}
          </span>
          <button onClick={() => supabase.auth.signOut()}>خروج</button>
        </div>
      </nav>
      <main>
        {tab === 'reception' && <Reception staff={staff} />}
        {tab === 'manager' && <Manager />}
        {tab === 'accountant' && <Accountant />}
        {tab === 'setup' && <Setup />}
      </main>
    </div>
  )
}
