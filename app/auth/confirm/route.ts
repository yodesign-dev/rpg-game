import { type EmailOtpType } from '@supabase/supabase-js'
import { type NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

// Route này xử lý link xác nhận email Supabase gửi và callback đăng nhập Discord (OAuth).
// Hỗ trợ:
//  - ?code=...                          (PKCE: email mới + OAuth)
//  - ?token_hash=...&type=...           (kiểu OTP email cũ hơn)
//  - ?error=...&error_description=...   (người dùng huỷ / Discord từ chối)
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')
  const token_hash = searchParams.get('token_hash')
  const type = searchParams.get('type') as EmailOtpType | null
  // Chỉ nhận đường dẫn nội bộ ("/..."), chặn "//host" để không bị dùng làm open redirect
  const rawNext = searchParams.get('next') ?? '/create-character'
  const next = rawNext.startsWith('/') && !rawNext.startsWith('//') ? rawNext : '/'
  const oauthError = searchParams.get('error_description') ?? searchParams.get('error')

  if (oauthError) {
    const msg = oauthError === 'access_denied' ? 'Bạn đã huỷ đăng nhập Discord' : `Đăng nhập thất bại: ${oauthError}`
    return NextResponse.redirect(`${origin}/login?error=${encodeURIComponent(msg)}`)
  }

  const supabase = await createClient()

  if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code)
    if (!error) {
      return NextResponse.redirect(`${origin}${next}`)
    }
  }

  if (token_hash && type) {
    const { error } = await supabase.auth.verifyOtp({ type, token_hash })
    if (!error) {
      return NextResponse.redirect(`${origin}${next}`)
    }
  }

  // Link hỏng, hết hạn, hoặc đã dùng rồi
  return NextResponse.redirect(
    `${origin}/login?error=${encodeURIComponent('Link đăng nhập / xác nhận không hợp lệ hoặc đã hết hạn, thử lại')}`
  )
}
