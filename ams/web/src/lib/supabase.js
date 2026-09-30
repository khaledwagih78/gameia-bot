import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !key) {
  throw new Error('ناقص VITE_SUPABASE_URL أو VITE_SUPABASE_ANON_KEY في ملف .env.local')
}

export const supabase = createClient(url, key)

// استدعاء دالة في القاعدة ورمي الخطأ برسالة عربية واضحة
export async function rpc(name, args = {}) {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw new Error(error.message)
  return data
}

// قراءة من جدول/view مع رمي الخطأ
export async function select(query) {
  const { data, error } = await query
  if (error) throw new Error(error.message)
  return data
}
