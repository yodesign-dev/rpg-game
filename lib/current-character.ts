import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

// Nhân vật mới nhất của người chơi đang đăng nhập (cùng quy ước các trang khác)
export async function getCurrentCharacter() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: character } = await supabase
    .from('characters')
    .select('*, classes(*)')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (!character) redirect('/create-character')

  return { supabase, character }
}
