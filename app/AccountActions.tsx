'use client'

import { useState } from 'react'
import { JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/client'

const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

export default function AccountActions({
  characterId,
  characterName,
}: {
  characterId: string
  characterName: string
}) {
  const [signingOut, setSigningOut] = useState(false)
  const [confirmingDelete, setConfirmingDelete] = useState(false)
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
    const { error: deleteError } = await supabase
      .from('characters')
      .delete()
      .eq('id', characterId)

    if (deleteError) {
      setError(deleteError.message)
      setDeleting(false)
      return
    }

    window.location.href = '/create-character'
  }

  return (
    <div className="flex flex-col items-stretch gap-3">
      {!confirmingDelete ? (
        <>
          <button
            onClick={signOut}
            disabled={signingOut}
            className={`${mono.className} text-left text-xs text-[#a89b7f] hover:text-[#f1e6c8] disabled:opacity-40 py-1.5`}
          >
            {signingOut ? 'Đang đăng xuất…' : 'Đăng xuất'}
          </button>
          <button
            onClick={() => setConfirmingDelete(true)}
            className={`${mono.className} text-left text-xs text-[#c98787] hover:text-[#e0a3a3] py-1.5`}
          >
            Xoá nhân vật
          </button>
        </>
      ) : (
        <div className="w-full max-w-sm rounded-sm border border-[#8c3f3f] bg-[#1d1512] p-5 space-y-3">
          <p className={`${mono.className} text-xs text-[#c98787] leading-relaxed`}>
            Toàn bộ trang bị, vật phẩm và vàng của <span className="text-[#f1e6c8]">{characterName}</span> sẽ
            mất vĩnh viễn. Hành động này không thể hoàn tác.
          </p>
          <p className={`${mono.className} text-[11px] text-[#8a7f68]`}>
            Gõ lại tên nhân vật (<span className="text-[#f1e6c8]">{characterName}</span>) để xác nhận:
          </p>
          <input
            type="text"
            value={confirmText}
            onChange={(e) => setConfirmText(e.target.value)}
            className={`${mono.className} w-full bg-transparent border-b border-[#4a4230] py-2 text-sm text-[#f1e6c8]
              focus:outline-none focus:border-[#8c3f3f]`}
          />

          {error && <p className={`${mono.className} text-xs text-[#c98787]`}>{error}</p>}

          <div className="flex items-center gap-3 pt-1">
            <button
              onClick={deleteCharacter}
              disabled={confirmText !== characterName || deleting}
              className={`${mono.className} text-xs border border-[#8c3f3f] text-[#c98787] px-3 py-2 rounded-sm
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
              className={`${mono.className} text-xs text-[#8a7f68] hover:text-[#a89b7f] disabled:opacity-40`}
            >
              Huỷ
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
