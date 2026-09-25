'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

export type RefillResult = {
  hp: number
  max_hp: number
  ap: number
  max_ap: number
  full: boolean
  used: { name: string; qty: number }[]
}

// Nút "Hồi đầy": quick_refill uống bình liên tục tới khi HP/AP đầy hoặc hết bình.
// Kết quả (bình đã dùng / lỗi) hiện ngay dưới nút.
export default function QuickRefill({
  characterId,
  kind,
  disabled = false,
  onDone,
}: {
  characterId: string
  kind: 'hp' | 'ap'
  disabled?: boolean
  onDone: (res: RefillResult) => void
}) {
  const router = useRouter()
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<{ text: string; ok: boolean } | null>(null)

  async function refill() {
    setBusy(true)
    setMsg(null)
    const { data, error } = await createClient().rpc('quick_refill', { p_character_id: characterId, p_kind: kind })
    setBusy(false)
    if (error) return setMsg({ text: error.message, ok: false })
    const res = data as RefillResult
    onDone(res)
    const used = res.used.map((u) => `${u.qty}× ${u.name}`).join(', ')
    setMsg({ text: `${res.full ? 'Đã đầy' : 'Hết bình'} · ${used}`, ok: res.full })
    router.refresh()
  }

  return (
    <div className="mt-2">
      <button
        type="button"
        onClick={refill}
        disabled={disabled || busy}
        className={`w-full rounded-lg border px-2 py-1.5 text-xs font-medium transition-colors disabled:opacity-30 ${
          kind === 'hp'
            ? 'border-[#e086b0]/40 text-[#f5c8dc] hover:bg-[#e086b0]/15'
            : 'border-[#8fe0b0]/40 text-[#c8f5dc] hover:bg-[#8fe0b0]/15'
        }`}
      >
        {busy ? '…' : kind === 'hp' ? '🧪 Hồi đầy HP' : '⚡ Hồi đầy AP'}
      </button>
      {msg && <p className={`mt-1 text-[11px] leading-snug ${msg.ok ? 'text-[#a29fb3]' : 'text-[#f0b070]'}`}>{msg.text}</p>}
    </div>
  )
}
