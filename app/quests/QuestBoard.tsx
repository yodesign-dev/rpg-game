'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

type Reward = { key: string; name: string; icon: string | null } | null

export type DailyQuests = {
  date: string
  quests: { type: string; target: number; label: string; progress: number; claimed: boolean }[]
  bonus_claimed: boolean
  reward_gold: number
  reward_material: Reward
  bonus_gold: number
  bonus_item: Reward
}

const QUEST_ICON: Record<string, string> = {
  kills: '🗡️',
  boss: '👑',
  explore: '🧭',
  dungeon: '🗼',
  enchant: '🔨',
  convert: '⇅',
}

const QUEST_LINK: Record<string, string> = {
  kills: '/explore',
  boss: '/explore',
  explore: '/explore',
  dungeon: '/dungeon',
  enchant: '/inventory?tab=bag',
  convert: '/inventory?tab=bag',
}

export default function QuestBoard({ characterId, initial }: { characterId: string; initial: DailyQuests }) {
  const router = useRouter()
  const [data, setData] = useState(initial)
  const [busy, setBusy] = useState<number | 'bonus' | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const allClaimed = data.quests.every((q) => q.claimed)

  async function claim(index: number) {
    setBusy(index)
    setError(null)
    const { error: rpcError } = await createClient().rpc('claim_daily_quest', {
      p_character_id: characterId,
      p_index: index,
    })
    setBusy(null)
    if (rpcError) return setError(rpcError.message)
    setData((d) => ({ ...d, quests: d.quests.map((q, i) => (i === index ? { ...q, claimed: true } : q)) }))
    setMessage(`Nhận ${data.reward_gold} vàng + ${data.reward_material?.name ?? 'nguyên liệu'}.`)
    router.refresh()
  }

  async function claimBonus() {
    setBusy('bonus')
    setError(null)
    const { error: rpcError } = await createClient().rpc('claim_daily_bonus', { p_character_id: characterId })
    setBusy(null)
    if (rpcError) return setError(rpcError.message)
    setData((d) => ({ ...d, bonus_claimed: true }))
    setMessage(`🎉 Nhận quà hoàn thành: ${data.bonus_gold} vàng + ${data.bonus_item?.name ?? ''}.`)
    router.refresh()
  }

  return (
    <div className="space-y-3">
      {data.quests.map((q, i) => {
        const done = q.progress >= q.target
        const pct = Math.min(100, Math.round((q.progress / q.target) * 100))
        return (
          <div key={i} className="rounded-2xl bg-white/[0.045] border border-white/[0.09] p-4">
            <div className="flex items-center gap-3">
              <span className="text-2xl shrink-0">{QUEST_ICON[q.type] ?? '📜'}</span>
              <div className="flex-grow min-w-0">
                <p className={`text-sm font-semibold ${q.claimed ? 'text-[#7d7a8c] line-through' : 'text-white'}`}>
                  {q.label}
                </p>
                <div className="mt-2 h-1.5 rounded-full bg-white/[0.07] overflow-hidden">
                  <div
                    className="h-full rounded-full"
                    style={{ width: `${pct}%`, background: done ? '#8fe0b0' : 'linear-gradient(90deg,#b06fd8,#e086b0)' }}
                  />
                </div>
                <p className="text-xs text-[#7d7a8c] mt-1">
                  {q.progress}/{q.target} · Thưởng {data.reward_gold} vàng + 2–4 {data.reward_material?.name ?? 'nguyên liệu'}
                </p>
              </div>
              {q.claimed ? (
                <span className="text-xs text-[#8fe0b0] shrink-0">✓ Đã nhận</span>
              ) : done ? (
                <button
                  onClick={() => claim(i)}
                  disabled={busy !== null}
                  className="shrink-0 rounded-xl border border-[#8fe0b0]/60 bg-[#8fe0b0]/15 text-[#c8f5dc] text-xs font-semibold px-3 py-2 disabled:opacity-40"
                >
                  {busy === i ? '…' : 'Nhận thưởng'}
                </button>
              ) : (
                <a href={QUEST_LINK[q.type] ?? '/'} className="shrink-0 text-xs text-[#a29fb3] hover:text-white">
                  Đi làm →
                </a>
              )}
            </div>
          </div>
        )
      })}

      <div className="rounded-2xl border border-[#f0c060]/30 bg-gradient-to-r from-[#8a6a1f]/25 to-transparent p-4 flex items-center gap-3">
        <span className="text-2xl">🎁</span>
        <div className="flex-grow text-sm">
          <p className="text-white font-semibold">Quà hoàn thành cả 3</p>
          <p className="text-xs text-[#c9b982]">
            {data.bonus_gold} vàng + 1 {data.bonus_item?.name ?? 'Bình Hồi AP Lớn'}
          </p>
        </div>
        {data.bonus_claimed ? (
          <span className="text-xs text-[#8fe0b0]">✓ Đã nhận</span>
        ) : (
          <button
            onClick={claimBonus}
            disabled={!allClaimed || busy !== null}
            className="shrink-0 whitespace-nowrap rounded-xl border border-[#f0c060]/70 bg-[#f0c060]/20 text-[#f7dca0] text-xs font-semibold px-3 py-2 disabled:opacity-30"
          >
            {busy === 'bonus' ? '…' : 'Nhận quà'}
          </button>
        )}
      </div>

      {message && <p className="text-sm text-[#8fe0b0]">{message}</p>}
      {error && <p className="text-sm text-[#e09595]">{error}</p>}
    </div>
  )
}
