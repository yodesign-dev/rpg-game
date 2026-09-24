'use client'

import { useState } from 'react'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'

const BUFF_LABEL: Record<string, string> = {
  exp: '📜 +25% EXP',
  luck: '🍀 +30% rơi đồ',
  guard: '🛡️ Bùa Hộ Mệnh',
}

// Tiếp tế trước khi đi: bật/tắt tự uống bình (tối đa 3/chuyến), số bình trong túi, cuộn/bùa đang chờ
export default function SupplyBar({
  characterId,
  autoPotion,
  potionCount,
  buffs,
}: {
  characterId: string
  autoPotion: boolean
  potionCount: number
  buffs: string[]
}) {
  const [auto, setAuto] = useState(autoPotion)
  const [busy, setBusy] = useState(false)

  async function toggle() {
    const next = !auto
    setAuto(next)
    setBusy(true)
    const { error } = await createClient().from('characters').update({ auto_potion: next }).eq('id', characterId)
    setBusy(false)
    if (error) setAuto(!next)
  }

  return (
    <div className="mb-4 rounded-2xl border border-white/[0.09] bg-white/[0.045] p-3 text-xs">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <label className="flex cursor-pointer items-center gap-2 text-[#c9c4d4]">
          <input type="checkbox" checked={auto} disabled={busy} onChange={toggle} className="accent-[#8fe0b0]" />
          🧪 Tự uống bình khi HP &lt; 35% <span className="text-[#7d7a8c]">(tối đa 3 · có {potionCount} bình)</span>
        </label>
        <Link href="/market" className="text-[#a29fb3] hover:text-white">
          Mua thêm →
        </Link>
      </div>
      {buffs.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {buffs.map((b) => (
            <span key={b} className="rounded-full border border-[#8fe0b0]/40 bg-[#8fe0b0]/10 px-2 py-0.5 text-[#c8f5dc]">
              {BUFF_LABEL[b] ?? b}
            </span>
          ))}
          <span className="text-[#7d7a8c]">— áp vào chuyến kế tiếp</span>
        </div>
      )}
    </div>
  )
}
