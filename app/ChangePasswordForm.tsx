'use client'

import { useEffect, useState } from 'react'
import { ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/client'

// Đổi mật khẩu (menu Cài đặt). Tài khoản email phải nhập đúng mật khẩu hiện tại — xác minh bằng
// signInWithPassword vì updateUser của Supabase không tự kiểm tra. Tài khoản chỉ đăng nhập bằng
// Discord chưa có mật khẩu: đặt mới để đăng nhập được thêm bằng email.
export default function ChangePasswordForm({ onDone }: { onDone: () => void }) {
  const [email, setEmail] = useState<string | null>(null)
  const [hasPassword, setHasPassword] = useState(true)
  const [current, setCurrent] = useState('')
  const [next, setNext] = useState('')
  const [confirm, setConfirm] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [done, setDone] = useState(false)

  useEffect(() => {
    createClient()
      .auth.getUser()
      .then(({ data }) => {
        setEmail(data.user?.email ?? null)
        setHasPassword(!!data.user?.identities?.some((i) => i.provider === 'email'))
      })
  }, [])

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    if (next.length < 6) return setError('Mật khẩu mới cần ít nhất 6 ký tự.')
    if (next !== confirm) return setError('Nhập lại mật khẩu mới không khớp.')
    if (hasPassword && next === current) return setError('Mật khẩu mới phải khác mật khẩu hiện tại.')
    if (!email) return setError('Không đọc được email của tài khoản, thử tải lại trang.')

    setSaving(true)
    const supabase = createClient()
    if (hasPassword) {
      const { error: authError } = await supabase.auth.signInWithPassword({ email, password: current })
      if (authError) {
        setSaving(false)
        return setError('Mật khẩu hiện tại không đúng.')
      }
    }
    const { error: updateError } = await supabase.auth.updateUser({ password: next })
    setSaving(false)
    if (updateError) return setError(updateError.message)
    setDone(true)
  }

  const input = `${ui.className} w-full bg-transparent border-b border-[#4a4230] py-2 text-sm text-[#f1e6c8]
    focus:outline-none focus:border-[#8a7f68]`
  const label = `${ui.className} block text-[11px] tracking-widest text-[#8a7f68] mb-1`

  if (done) {
    return (
      <div className="space-y-3">
        <p className={`${ui.className} text-xs text-[#8fe0b0]`}>✅ Đã đổi mật khẩu. Lần sau đăng nhập bằng mật khẩu mới.</p>
        <button onClick={onDone} className={`${ui.className} text-xs text-[#a89b7f] hover:text-[#f1e6c8]`}>
          Đóng
        </button>
      </div>
    )
  }

  return (
    <form onSubmit={submit} className="space-y-3">
      <p className={`${ui.className} text-xs text-[#f1e6c8]`}>
        {hasPassword ? 'Đổi mật khẩu' : 'Đặt mật khẩu để đăng nhập thêm bằng email'}
        {email && <span className="block text-[11px] text-[#8a7f68] mt-0.5">{email}</span>}
      </p>
      {hasPassword && (
        <div>
          <label className={label}>Mật khẩu hiện tại</label>
          <input type="password" required autoComplete="current-password" value={current}
            onChange={(e) => setCurrent(e.target.value)} className={input} />
        </div>
      )}
      <div>
        <label className={label}>Mật khẩu mới</label>
        <input type="password" required minLength={6} autoComplete="new-password" value={next}
          onChange={(e) => setNext(e.target.value)} className={input} />
      </div>
      <div>
        <label className={label}>Nhập lại mật khẩu mới</label>
        <input type="password" required minLength={6} autoComplete="new-password" value={confirm}
          onChange={(e) => setConfirm(e.target.value)} className={input} />
      </div>

      {error && <p className={`${ui.className} text-xs text-[#c98787]`}>{error}</p>}

      <div className="flex items-center gap-3 pt-1">
        <button
          type="submit"
          disabled={saving}
          className={`${ui.className} text-xs border border-[#8a7f68] text-[#f1e6c8] px-3 py-2 rounded-sm
            disabled:opacity-30 hover:bg-[#8a7f68]/30 transition-colors`}
        >
          {saving ? 'Đang lưu…' : 'Lưu mật khẩu'}
        </button>
        <button type="button" onClick={onDone} disabled={saving}
          className={`${ui.className} text-xs text-[#8a7f68] hover:text-[#a89b7f] disabled:opacity-40`}>
          Huỷ
        </button>
      </div>
    </form>
  )
}
