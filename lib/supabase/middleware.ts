import { type NextRequest } from 'next/server'
import { updateSession } from '@/lib/supabase/middleware'

export async function middleware(request: NextRequest) {
  return await updateSession(request)
}

export const config = {
  matcher: [
    /*
     * Chạy middleware trên mọi route TRỪ:
     * - file tĩnh (_next/static, _next/image)
     * - favicon, ảnh svg/png/jpg...
     * Tránh middleware chạy thừa trên asset, gây chậm.
     */
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
