export const WEEKDAYS = ['الأحد', 'الاتنين', 'التلات', 'الأربع', 'الخميس', 'الجمعة', 'السبت']
export const AREAS = ['الصف', 'العياط', 'أطفيح', 'أخرى']

export const LEAD_TYPES = {
  paid_ad: 'إعلان ممول',
  influencer: 'مؤثر',
  promo_code: 'كود ترويجي',
  direct: 'مباشر',
}

export const COURSE_TYPES = { normal: 'عادي', maintenance: 'صيانة', advanced: 'متقدم' }

export const PAYMENT_METHODS = {
  cash: 'كاش',
  vodafone_cash: 'فودافون كاش',
  instapay: 'إنستاباي',
  bank_transfer: 'تحويل بنكي',
}

export const EXPENSE_CATEGORIES = {
  electricity: 'كهرباء',
  internet: 'إنترنت',
  rent: 'إيجار',
  fixed_salaries: 'رواتب خارج النظام',
  other: 'أخرى',
}

export const ROLES = {
  manager: 'مدير',
  secretary: 'سكرتارية',
  instructor: 'مدرب',
  accountant: 'محاسب',
}

export const ENROLLMENT_STATUS = {
  pending: 'معلّق',
  active: 'نشط',
  suspended: 'موقوف',
  completed: 'منتهي',
  cancelled: 'ملغي',
}

export const money = (n) =>
  `${Number(n || 0).toLocaleString('ar-EG', { maximumFractionDigits: 2 })} ج`

// تاريخ النهارده بتوقيت القاهرة بصيغة YYYY-MM-DD
export function today() {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo' }).format(new Date())
}

// "2026-10" ← → "2026-10-01"
export const monthStart = (ym) => `${ym.slice(0, 7)}-01`
export const thisMonth = () => today().slice(0, 7)

export function prevMonth() {
  const [y, m] = thisMonth().split('-').map(Number)
  const d = new Date(Date.UTC(y, m - 2, 1))
  return d.toISOString().slice(0, 7)
}

export function addDays(iso, n) {
  const d = new Date(`${iso}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}

// بداية آخر أسبوع كامل (الأسبوع بيبدأ السبت)
export function lastFullWeekStart() {
  const t = today()
  const dow = new Date(`${t}T00:00:00Z`).getUTCDay() // 6 = السبت
  const sinceSaturday = (dow + 1) % 7
  return addDays(t, -sinceSaturday - 7)
}

export const weekdayOf = (iso) => new Date(`${iso}T00:00:00Z`).getUTCDay()

// تنضيف نص البحث قبل ما يدخل فلتر PostgREST (.or)
export const searchTerm = (s) => s.replace(/[,()%*\\]/g, ' ').trim()
