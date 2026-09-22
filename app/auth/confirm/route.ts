import { type EmailOtpType } from '@supabase/supabase-js'
import { type NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

// Route này xử lý link xác nhận email Supabase gửi.
// Hỗ trợ cả 2 kiểu link Supabase có thể tạo ra:
//  - ?code=...                          (PKCE, phổ biến nhất hiện tại)
//  - ?token_hash=...&type=...           (kiểu OTP cũ hơn)
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')
  const token_hash = searchParams.get('token_hash')
  const type = searchParams.get('type') as EmailOtpType | null
  const next = searchParams.get('next') ?? '/create-character'

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
  return NextResponse.redirect(`${origin}/login?error=Không thể xác nhận email, thử đăng nhập lại`)
}
