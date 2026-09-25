'use client'

import { useState } from 'react'
import { ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/client'
import ChangePasswordForm from './ChangePasswordForm'


export default function AccountActions({
  characterId,
  characterName,
}: {
  characterId: string
  characterName: string
}) {
  const [signingOut, setSigningOut] = useState(false)
  const [confirmingDelete, setConfirmingDelete] = useState(false)
  const [changingPassword, setChangingPassword] = useState(false)
  const [confirmText, setConfirmText] = useState('')
  const [deleting, setDeleting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function signOut() {
    setSigningOut(true)
    const supabase = createClient()
    await supabase.auth.signOut()
    window.location.href = '/login'
  }

  async function deleteCharacter() {
    setError(null)
    setDeleting(true)

    const supabase = createClient()
    // Xoá qua RPC (client không có quyền DELETE trực tiếp trên characters)
    const { error: deleteError } = await supabase.rpc('delete_character', { p_character_id: characterId })

    if (deleteError) {
      setError(deleteError.message)
      setDeleting(false)
      return
    }

    window.location.href = '/create-character'
  }

  return (
    <div className="flex flex-col items-stretch gap-3">
      {changingPassword ? (
        <ChangePasswordForm onDone={() => setChangingPassword(false)} />
      ) : !confirmingDelete ? (
        <>
          <button
            onClick={() => setChangingPassword(true)}
            className={`${ui.className} text-left text-xs text-[#a89b7f] hover:text-[#f1e6c8] py-1.5`}
          >
            Đổi mật khẩu
          </button>
          <button
            onClick={signOut}
            disabled={signingOut}
            className={`${ui.className} text-left text-xs text-[#a89b7f] hover:text-[#f1e6c8] disabled:opacity-40 py-1.5`}
          >
            {signingOut ? 'Đang đăng xuất…' : 'Đăng xuất'}
          </button>
          <button
            onClick={() => setConfirmingDelete(true)}
            className={`${ui.className} text-left text-xs text-[#c98787] hover:text-[#e0a3a3] py-1.5`}
          >
            Xoá nhân vật
          </button>
        </>
      ) : (
        <div className="w-full max-w-sm rounded-sm border border-[#8c3f3f] bg-[#1d1512] p-5 space-y-3">
          <p className={`${ui.className} text-xs text-[#c98787] leading-relaxed`}>
            Toàn bộ trang bị, vật phẩm và vàng của <span className="text-[#f1e6c8]">{characterName}</span> sẽ
            mất vĩnh viễn. Hành động này không thể hoàn tác.
          </p>
          <p className={`${ui.className} text-xs text-[#8a7f68]`}>
            Gõ lại tên nhân vật (<span className="text-[#f1e6c8]">{characterName}</span>) để xác nhận:
          </p>
          <input
            type="text"
            value={confirmText}
            onChange={(e) => setConfirmText(e.target.value)}
            className={`${ui.className} w-full bg-transparent border-b border-[#4a4230] py-2 text-sm text-[#f1e6c8]
              focus:outline-none focus:border-[#8c3f3f]`}
          />

          {error && <p className={`${ui.className} text-xs text-[#c98787]`}>{error}</p>}

          <div className="flex items-center gap-3 pt-1">
            <button
              onClick={deleteCharacter}
              disabled={confirmText !== characterName || deleting}
              className={`${ui.className} text-xs border border-[#8c3f3f] text-[#c98787] px-3 py-2 rounded-sm
                disabled:opacity-30 hover:bg-[#8c3f3f] hover:text-[#f1e6c8] transition-colors`}
            >
              {deleting ? 'Đang xoá…' : 'Xác nhận xoá'}
            </button>
            <button
              onClick={() => {
                setConfirmingDelete(false)
                setConfirmText('')
                setError(null)
              }}
              disabled={deleting}
              className={`${ui.className} text-xs text-[#8a7f68] hover:text-[#a89b7f] disabled:opacity-40`}
            >
              Huỷ
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
