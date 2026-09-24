'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { portraitKeys } from '@/lib/portraits'
import { FRAMES, type FrameProgress } from '@/lib/frames'
import Portrait from '../components/Portrait'
import PortraitCard from '../components/PortraitCard'

// Bấm chân dung ở màn Nhân Vật để đổi chân dung và khung (khung mở bằng thành tích)
export default function PortraitPicker({
  characterId,
  classKey,
  portrait,
  frame,
  progress,
  children,
}: {
  characterId: string
  classKey: string
  portrait: string | null
  frame: string | null
  progress: FrameProgress
  children: React.ReactNode
}) {
  const router = useRouter()
  const [open, setOpen] = useState(false)
  const [current, setCurrent] = useState({ portrait: portrait ?? `${classKey}_1`, frame: frame ?? 'wood' })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function save(patch: { portrait?: string; frame?: string }) {
    setBusy(true)
    setError(null)
    const { error: updateError } = await createClient().from('characters').update(patch).eq('id', characterId)
    setBusy(false)
    if (updateError) return setError(updateError.message)
    setCurrent((c) => ({ ...c, ...patch }))
    router.refresh()
  }

  return (
    <>
      <button type="button" onClick={() => setOpen(true)} aria-label="Đổi chân dung và khung" className="absolute inset-0 rounded-lg">
        {children}
      </button>
      {open && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-3" role="dialog" aria-modal="true">
          <button type="button" aria-label="Đóng" onClick={() => setOpen(false)} className="absolute inset-0 bg-black/60" />
          <div className="relative w-full max-w-lg max-h-[88vh] overflow-y-auto rounded-2xl border border-white/10 bg-[#110f17] p-4 shadow-2xl">
            <button
              type="button"
              onClick={() => setOpen(false)}
              aria-label="Đóng"
              className="absolute right-3 top-3 h-8 w-8 rounded-full bg-white/10 text-[#c9c4d4] hover:bg-white/20"
            >
              ✕
            </button>
            <div className="flex items-center gap-4 mb-4">
              <PortraitCard classKey={classKey} portrait={current.portrait} frame={current.frame} className="w-20" />
              <div>
                <p className="text-sm font-semibold text-white">Chân dung & khung</p>
                <p className="text-xs text-[#a29fb3] mt-1">
                  Khung hiện ở màn Nhân Vật, Túi Đồ và bảng xếp hạng. Mở thêm khung bằng thành tích.
                </p>
              </div>
            </div>

            <p className="mb-2 text-xs font-semibold tracking-[2px] text-[#a29fb3]">CHÂN DUNG</p>
            <div className="grid grid-cols-5 gap-2">
              {portraitKeys(classKey).map((key) => (
                <button
                  key={key}
                  type="button"
                  disabled={busy}
                  onClick={() => key !== current.portrait && save({ portrait: key })}
                  className={`h-24 rounded-xl border p-1.5 transition-colors disabled:opacity-50 ${
                    key === current.portrait
                      ? 'border-[#8fe0b0] bg-[#8fe0b0]/10'
                      : 'border-white/10 bg-white/[0.03] hover:bg-white/[0.08]'
                  }`}
                >
                  <Portrait classKey={classKey} portrait={key} />
                </button>
              ))}
            </div>

            <p className="mb-2 mt-5 text-xs font-semibold tracking-[2px] text-[#a29fb3]">KHUNG</p>
            <div className="grid grid-cols-4 gap-2 sm:grid-cols-7">
              {FRAMES.map((f) => {
                const unlocked = f.unlocked(progress)
                const on = f.key === current.frame
                return (
                  <button
                    key={f.key}
                    type="button"
                    disabled={busy || !unlocked}
                    onClick={() => !on && save({ frame: f.key })}
                    title={unlocked ? f.name : `${f.name} — ${f.hint}`}
                    className={`flex flex-col items-center gap-1 rounded-xl border p-1.5 transition-colors ${
                      on ? 'border-[#8fe0b0] bg-[#8fe0b0]/10' : 'border-white/10 bg-white/[0.03] hover:bg-white/[0.08]'
                    } disabled:cursor-not-allowed`}
                  >
                    <PortraitCard
                      classKey={classKey}
                      portrait={current.portrait}
                      frame={f.key}
                      className={`w-full ${unlocked ? '' : 'grayscale opacity-40'}`}
                    />
                    <span className={`text-[11px] leading-tight text-center ${unlocked ? 'text-white' : 'text-[#7d7a8c]'}`}>
                      {unlocked ? f.name : `🔒 ${f.hint}`}
                    </span>
                  </button>
                )
              })}
            </div>
            {error && <p className="mt-3 text-xs text-[#e09595]">{error}</p>}
          </div>
        </div>
      )}
    </>
  )
}
