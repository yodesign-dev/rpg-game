import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

// Các route bắt buộc phải đăng nhập mới vào được.
// Không đưa /character vào đây: đó là route xử lý link xác nhận email
// (?code=...), phải truy cập được TRƯỚC KHI đăng nhập vì chính nó tạo ra
// session — chặn ở đây sẽ làm hỏng luôn cả việc xác nhận email lẫn tạo ra
// vòng lặp redirect (middleware đá /login -> /character, trang /character
// không thấy code lại đá về /login).
const PROTECTED_PATHS = ['/create-character', '/dungeon']

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          response = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  // getClaims() (chứ không phải getSession()) — xác thực chữ ký JWT nên không giả mạo
  // cookie để bypass được. Với JWT signing keys bất đối xứng, nó kiểm tra tại chỗ bằng
  // JWKS (được cache) nên không tốn một vòng mạng tới Supabase Auth mỗi lần chuyển trang
  // như getUser(); token hết hạn vẫn được refresh + ghi cookie qua setAll ở trên.
  const { data } = await supabase.auth.getClaims()
  const user = data?.claims ?? null

  const path = request.nextUrl.pathname
  const isProtected = PROTECTED_PATHS.some((p) => path.startsWith(p))

  if (isProtected && !user) {
    const redirectUrl = request.nextUrl.clone()
    redirectUrl.pathname = '/login'
    redirectUrl.searchParams.set('redirectTo', path)
    const redirectResponse = NextResponse.redirect(redirectUrl)
    response.cookies.getAll().forEach((cookie) => redirectResponse.cookies.set(cookie))
    return redirectResponse
  }

  // Đã đăng nhập rồi mà vẫn cố vào /login thì đá thẳng qua trang nhân vật
  if (path === '/login' && user) {
    const redirectUrl = request.nextUrl.clone()
    redirectUrl.pathname = '/'
    const redirectResponse = NextResponse.redirect(redirectUrl)
    response.cookies.getAll().forEach((cookie) => redirectResponse.cookies.set(cookie))
    return redirectResponse
  }

  return response
}
