import { cache } from 'react'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

// Nhân vật mới nhất của người chơi đang đăng nhập (cùng quy ước các trang khác).
// cache(): layout/page/component trong cùng một request gọi nhiều lần vẫn chỉ tốn 1 lần truy vấn.
export const getCurrentCharacter = cache(async () => {
  const supabase = await createClient()

  // getClaims() xác thực chữ ký JWT (không tin cookie mù quáng như getSession()); với JWT
  // signing keys bất đối xứng thì kiểm tra tại chỗ, khỏi một vòng mạng tới Supabase Auth.
  // Mọi truy vấn phía sau vẫn đi kèm JWT này nên RLS (auth.uid() = user_id) vẫn chặn ở DB.
  const { data: auth } = await supabase.auth.getClaims()
  const userId = auth?.claims?.sub
  if (!userId) redirect('/login')

  const { data: character, error } = await supabase
    .from('characters')
    // characters ↔ titles có 2 quan hệ (title_key trực tiếp + bảng character_titles)
    // → phải chỉ rõ khóa ngoại, nếu không PostgREST báo lỗi "more than one relationship"
    .select('*, classes(*), title:titles!characters_title_key_fkey(name, emoji)')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  // Lỗi truy vấn ≠ chưa có nhân vật — không được đẩy sang trang tạo nhân vật
  if (error) throw new Error(`Không tải được nhân vật: ${error.message}`)
  if (!character) redirect('/create-character')

  return { supabase, character }
})
