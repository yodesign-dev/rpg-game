import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

// Nhân vật mới nhất của người chơi đang đăng nhập (cùng quy ước các trang khác)
export async function getCurrentCharacter() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: character, error } = await supabase
    .from('characters')
    .select('*, classes(*)')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  // Lỗi truy vấn ≠ chưa có nhân vật — không được đẩy sang trang tạo nhân vật
  if (error) throw new Error(`Không tải được nhân vật: ${error.message}`)
  if (!character) redirect('/create-character')

  return { supabase, character }
}
