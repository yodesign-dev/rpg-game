import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ code?: string }>
}) {
  const { code } = await searchParams

  // Link xác nhận email của Supabase đổ về đây kèm ?code=... — xử lý ngay tại đây
  // thay vì bắt người dùng tự bấm lại gì cả.
  if (code) {
    const supabase = await createClient()
    const { error } = await supabase.auth.exchangeCodeForSession(code)
    if (!error) {
      redirect('/create-character')
    }
    redirect('/login?error=Link xác nhận không hợp lệ hoặc đã hết hạn')
  }

  redirect('/login')
}
