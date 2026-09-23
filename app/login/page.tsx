'use client'

import { useState } from 'react'
import { Cinzel, JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/client'

const display = Cinzel({ subsets: ['latin'], weight: ['500', '700'] })
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

export default function LoginPage() {
  const [mode, setMode] = useState<'login' | 'signup'>('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

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
        <p className={`${mono.className} text-xs tracking-widest text-[#8a7f68] mb-3 text-center`}>
          Cổng Vào
        </p>
        <h1 className={`${display.className} text-3xl text-[#f1e6c8] text-center mb-10`}>
          {mode === 'login' ? 'Đăng Nhập' : 'Tạo Tài Khoản'}
        </h1>

        <form onSubmit={handleSubmit} className="space-y-6">
          <div>
            <label className={`${mono.className} block text-xs tracking-widest text-[#8a7f68] mb-2`}>
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
            <label className={`${mono.className} block text-xs tracking-widest text-[#8a7f68] mb-2`}>
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
          className={`${mono.className} mt-6 w-full text-center text-xs text-[#8a7f68] hover:text-[#a89b7f]`}
        >
          {mode === 'login' ? 'Chưa có tài khoản? Đăng ký' : 'Đã có tài khoản? Đăng nhập'}
        </button>
      </div>
    </main>
  )
}
