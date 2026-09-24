'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { portraitKeys } from '@/lib/portraits'
import Portrait from '../components/Portrait'

// Bấm avatar ở màn Nhân Vật để đổi chân dung
export default function PortraitPicker({
  characterId,
  classKey,
  portrait,
  children,
}: {
  characterId: string
  classKey: string
  portrait: string | null
  children: React.ReactNode
}) {
  const router = useRouter()
  const [open, setOpen] = useState(false)
  const [current, setCurrent] = useState(portrait ?? `${classKey}_1`)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function pick(key: string) {
    if (key === current) return setOpen(false)
    setBusy(true)
    setError(null)
    const { error: updateError } = await createClient().from('characters').update({ portrait: key }).eq('id', characterId)
    setBusy(false)
    if (updateError) return setError(updateError.message)
    setCurrent(key)
    setOpen(false)
    router.refresh()
  }

  return (
    <>
      <button type="button" onClick={() => setOpen(true)} aria-label="Đổi chân dung" className="absolute inset-0 rounded-full">
        {children}
      </button>
      {open && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-3" role="dialog" aria-modal="true">
          <button type="button" aria-label="Đóng" onClick={() => setOpen(false)} className="absolute inset-0 bg-black/60" />
          <div className="relative w-full max-w-lg rounded-2xl border border-white/10 bg-[#110f17] p-4 shadow-2xl">
            <p className="mb-3 text-sm font-semibold text-white">Chọn chân dung</p>
            <div className="grid grid-cols-5 gap-2">
              {portraitKeys(classKey).map((key) => (
                <button
                  key={key}
                  type="button"
                  disabled={busy}
                  onClick={() => pick(key)}
                  className={`h-28 rounded-xl border p-1.5 transition-colors disabled:opacity-50 ${
                    key === current
                      ? 'border-[#8fe0b0] bg-[#8fe0b0]/10'
                      : 'border-white/10 bg-white/[0.03] hover:bg-white/[0.08]'
                  }`}
                >
                  <Portrait classKey={classKey} portrait={key} />
                </button>
              ))}
            </div>
            {error && <p className="mt-3 text-xs text-[#e09595]">{error}</p>}
          </div>
        </div>
      )}
    </>
  )
}
