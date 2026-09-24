'use client'

import { useState } from 'react'
import { display, ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/client'


// initialError: lỗi từ /auth/confirm (?error=...); redirectTo: trang middleware muốn quay lại
export default function LoginForm({ initialError, redirectTo }: { initialError: string | null; redirectTo: string }) {
  const [mode, setMode] = useState<'login' | 'signup'>('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(initialError)
  const [notice, setNotice] = useState<string | null>(null)
  const [discordLoading, setDiscordLoading] = useState(false)

  async function signInWithDiscord() {
    setDiscordLoading(true)
    setError(null)
    setNotice(null)
    const { error } = await createClient().auth.signInWithOAuth({
      provider: 'discord',
      options: {
        redirectTo: `${window.location.origin}/auth/confirm?next=${encodeURIComponent(redirectTo)}`,
        scopes: 'identify email',
      },
    })
    // Thành công thì trình duyệt đã chuyển sang Discord; tới đây nghĩa là lỗi
    if (error) {
      setError(error.message)
      setDiscordLoading(false)
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setError(null)
    setNotice(null)

    const supabase = createClient()

    if (mode === 'signup') {
      const { error } = await supabase.auth.signUp({ email, password })
      if (error) {
        setError(error.message)
      } else {
        setNotice('Đã gửi email xác nhận. Kiểm tra hộp thư để hoàn tất đăng ký.')
      }
    } else {
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) {
        setError(error.message)
      } else {
        window.location.href = '/'
      }
    }

    setLoading(false)
  }

  return (
    <main className="min-h-screen bg-[#100e0c] text-[#ece3d0] flex items-center justify-center px-6">
      <div className="w-full max-w-sm">
        <p className={`${ui.className} text-xs tracking-widest text-[#8a7f68] mb-3 text-center`}>
          Cổng Vào
        </p>
        <h1 className={`${display.className} text-3xl text-[#f1e6c8] text-center mb-8`}>
          {mode === 'login' ? 'Đăng Nhập' : 'Tạo Tài Khoản'}
        </h1>

        <button
          type="button"
          onClick={signInWithDiscord}
          disabled={discordLoading}
          className={`${ui.className} w-full flex items-center justify-center gap-2.5 py-3 rounded-sm
            bg-[#5865F2] text-white font-semibold hover:bg-[#4752c4] disabled:opacity-50 transition-colors`}
        >
          <svg width="20" height="20" viewBox="0 0 127.14 96.36" fill="currentColor" aria-hidden="true">
            <path d="M107.7 8.07A105.15 105.15 0 0 0 81.47 0a72.06 72.06 0 0 0-3.36 6.83 97.68 97.68 0 0 0-29.11 0A72.37 72.37 0 0 0 45.64 0a105.89 105.89 0 0 0-26.25 8.09C2.79 32.65-1.71 56.6.54 80.21a105.73 105.73 0 0 0 32.17 16.15 77.7 77.7 0 0 0 6.89-11.11 68.42 68.42 0 0 1-10.85-5.18c.91-.66 1.8-1.34 2.66-2a75.57 75.57 0 0 0 64.32 0c.87.71 1.76 1.39 2.66 2a68.68 68.68 0 0 1-10.87 5.19 77 77 0 0 0 6.89 11.1 105.25 105.25 0 0 0 32.19-16.14c2.64-27.38-4.51-51.11-18.9-72.15ZM42.45 65.69C36.18 65.69 31 60 31 53s5-12.74 11.43-12.74S54 46 53.89 53s-5.05 12.69-11.44 12.69Zm42.24 0C78.41 65.69 73.25 60 73.25 53s5-12.74 11.44-12.74S96.23 46 96.12 53s-5.04 12.69-11.43 12.69Z" />
          </svg>
          {discordLoading ? 'Đang chuyển sang Discord…' : 'Tiếp tục với Discord'}
        </button>

        <div className={`${ui.className} flex items-center gap-3 my-8 text-xs tracking-widest text-[#5c5442]`}>
          <span className="h-px flex-1 bg-[#2e2920]" />
          HOẶC DÙNG EMAIL
          <span className="h-px flex-1 bg-[#2e2920]" />
        </div>

        <form onSubmit={handleSubmit} className="space-y-6">
          <div>
            <label className={`${ui.className} block text-xs tracking-widest text-[#8a7f68] mb-2`}>
              Email
            </label>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full bg-transparent border-b border-[#4a4230] py-2 text-[#f1e6c8]
                focus:outline-none focus:border-[#8a7f68]"
            />
          </div>

          <div>
            <label className={`${ui.className} block text-xs tracking-widest text-[#8a7f68] mb-2`}>
              Mật khẩu
            </label>
            <input
              type="password"
              required
              minLength={6}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full bg-transparent border-b border-[#4a4230] py-2 text-[#f1e6c8]
                focus:outline-none focus:border-[#8a7f68]"
            />
          </div>

          {error && <p className="text-sm text-[#c98787]">{error}</p>}
          {notice && <p className="text-sm text-[#8fc4a8]">{notice}</p>}

          <button
            type="submit"
            disabled={loading}
            className="w-full py-3 rounded-sm border border-[#8a7f68] text-[#f1e6c8]
              disabled:opacity-40 hover:bg-[#8a7f68] hover:text-[#100e0c] transition-colors"
          >
            {loading ? 'Đang xử lý…' : mode === 'login' ? 'Đăng Nhập' : 'Đăng Ký'}
          </button>
        </form>

        <button
          onClick={() => {
            setMode(mode === 'login' ? 'signup' : 'login')
            setError(null)
            setNotice(null)
          }}
          className={`${ui.className} mt-6 w-full text-center text-xs text-[#8a7f68] hover:text-[#a89b7f]`}
        >
          {mode === 'login' ? 'Chưa có tài khoản? Đăng ký' : 'Đã có tài khoản? Đăng nhập'}
        </button>
      </div>
    </main>
  )
}
