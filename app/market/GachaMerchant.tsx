'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/client'
import { LEGENDARY_EFFECTS } from '@/lib/legendary-effects'
import { ItemIcon } from '../components/combat-ui'


const PITY = 50
const COST_1 = 400
const COST_10 = 3600

type Tier = 'common' | 'rare' | 'epic' | 'legendary' | 'jackpot'

const TIER: Record<Tier, { label: string; rate: string; card: string; text: string }> = {
  common: { label: 'Thường', rate: '55%', card: 'border-[#3a3348] bg-[#15121d]', text: 'text-[#c9c4d4]' },
  rare: { label: 'Hiếm', rate: '28%', card: 'border-[#4a6b7a] bg-[#101a1f]', text: 'text-[#8fc4e0]' },
  epic: { label: 'Sử Thi', rate: '12%', card: 'border-[#6b4a7a] bg-[#1a1220]', text: 'text-[#d0a8f0]' },
  legendary: {
    label: 'Huyền Thoại',
    rate: '4.5%',
    card: 'border-[#e0b050] bg-[#241c0c] shadow-[0_0_18px_rgba(224,176,80,.45)]',
    text: 'text-[#f0c060]',
  },
  jackpot: {
    label: 'Jackpot',
    rate: '0.5%',
    card: 'border-[#f0a8f0] bg-[#2a1028] shadow-[0_0_24px_rgba(240,168,240,.6)]',
    text: 'text-[#f7c8f7]',
  },
}

type PullResult = {
  tier: Tier
  key: string
  name: string
  icon: string | null
  rarity: string
  qty: number
  effect?: string | null
}

export type GachaHistory = {
  id: string
  tier: Tier
  rarity: string
  quantity: number
  created_at: string
  item: { name: string; icon: string | null } | null
}

export default function GachaMerchant({
  characterId,
  gold,
  pity,
  freeAvailable,
  history,
}: {
  characterId: string
  gold: number
  pity: number
  freeAvailable: boolean
  history: GachaHistory[]
}) {
  const router = useRouter()
  const [localGold, setLocalGold] = useState(gold)
  const [localPity, setLocalPity] = useState(pity)
  const [free, setFree] = useState(freeAvailable)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [results, setResults] = useState<PullResult[]>([])
  const [revealed, setRevealed] = useState(0)

  // Lật lần lượt từng thẻ
  useEffect(() => {
    if (revealed >= results.length) return
    const t = setTimeout(() => setRevealed((n) => n + 1), revealed === 0 ? 150 : 180)
    return () => clearTimeout(t)
  }, [revealed, results.length])

  async function pull(count: 1 | 10, isFree: boolean) {
    setBusy(true)
    setError(null)
    setResults([])
    setRevealed(0)
    const { data, error: rpcError } = await createClient().rpc('gacha_pull', {
      p_character_id: characterId,
      p_count: count,
      p_free: isFree,
    })
    setBusy(false)
    if (rpcError) return setError(rpcError.message)
    const res = data as { results: PullResult[]; gold_left: number; pity: number; free_used: boolean }
    setLocalGold(res.gold_left)
    setLocalPity(res.pity)
    if (res.free_used) setFree(false)
    setResults(res.results)
    router.refresh()
  }

  return (
    <div className={`${ui.className} space-y-5`}>
      {/* NPC */}
      <div className="rounded-lg border border-[#6b4a7a]/60 bg-gradient-to-br from-[#241a2c] to-[#0e0c13] p-4 flex gap-4 items-center">
        <div className="text-5xl shrink-0">🧙</div>
        <div className="min-w-0">
          <p className="text-[#f2ede4] text-sm font-semibold">Thương Nhân Bí Ẩn</p>
          <p className="text-xs text-[#a29fb3] mt-1 leading-relaxed">
            “Vàng đổi vận may, lữ khách. Mỗi rương một bất ngờ — có khi chỉ là vài nắm quặng, có khi là thứ các vị
            vua cũng thèm muốn.”
          </p>
        </div>
      </div>

      <div className="flex items-center justify-between text-xs">
        <span className="text-[#e0b050]">💰 {localGold.toLocaleString('vi-VN')} vàng</span>
        <span className="text-[#a29fb3]">
          Bảo hiểm Huyền Thoại: <b className="text-[#f0c060]">{localPity}</b>/{PITY}
        </span>
      </div>
      <div className="h-1.5 rounded-full bg-[#2a2533] overflow-hidden -mt-3">
        <div className="h-full bg-[#e0b050]" style={{ width: `${Math.min(100, (localPity / PITY) * 100)}%` }} />
      </div>

      <div className="grid grid-cols-2 gap-2">
        <button
          onClick={() => pull(1, false)}
          disabled={busy || localGold < COST_1}
          className="rounded-lg border border-[#8a8499] py-3 text-sm text-[#f2ede4] hover:bg-[#2a2533] disabled:opacity-30"
        >
          Mở x1
          <span className="block text-xs text-[#e0b050]">{COST_1} vàng</span>
        </button>
        <button
          onClick={() => pull(10, false)}
          disabled={busy || localGold < COST_10}
          className="rounded-lg border border-[#e0b050] bg-[#e0b050]/15 py-3 text-sm text-[#f2ede4] hover:bg-[#e0b050]/25 disabled:opacity-30"
        >
          Mở x10
          <span className="block text-xs text-[#e0b050]">
            {COST_10.toLocaleString('vi-VN')} vàng · chắc chắn ≥ 1 Sử Thi
          </span>
        </button>
      </div>
      {free && (
        <button
          onClick={() => pull(1, true)}
          disabled={busy}
          className="w-full rounded-lg border border-[#8fe0b0] bg-[#3d5a45]/30 py-2.5 text-sm text-[#c8f0d8] disabled:opacity-40"
        >
          🎁 Mở miễn phí hôm nay
        </button>
      )}

      {error && <p className="text-xs text-[#e09595]">{error}</p>}
      {busy && <p className="text-xs text-[#a29fb3] text-center">Thương nhân đang lục rương…</p>}

      {results.length > 0 && (
        <div className="grid grid-cols-2 sm:grid-cols-5 gap-2">
          {results.map((r, i) => {
            const shown = i < revealed
            const t = TIER[r.tier]
            return (
              <div
                key={i}
                className={`rounded-lg border p-2 text-center transition-all duration-300 ${
                  shown ? `${t.card} opacity-100 scale-100` : 'border-[#2a2533] bg-[#0b0a10] opacity-60 scale-95'
                }`}
              >
                {shown ? (
                  <>
                    <p className={`text-xs tracking-widest ${t.text}`}>
                      {r.tier === 'jackpot' ? '💎 JACKPOT' : t.label.toUpperCase()}
                    </p>
                    <div className="flex justify-center my-1.5">
                      <ItemIcon icon={r.icon} size={36} />
                    </div>
                    <p className={`text-xs leading-tight ${t.text}`}>
                      {r.name}
                      {r.qty > 1 && <span className="text-[#a29fb3]"> ×{r.qty}</span>}
                    </p>
                    {r.effect && LEGENDARY_EFFECTS[r.effect] && (
                      <p className="text-xs text-[#f0c060] mt-0.5">✦ {LEGENDARY_EFFECTS[r.effect].name}</p>
                    )}
                  </>
                ) : (
                  <div className="h-[86px] flex items-center justify-center text-2xl">❔</div>
                )}
              </div>
            )
          })}
        </div>
      )}

      {/* Tỉ lệ công khai */}
      <div className="rounded-lg border border-[#2a2533] bg-[#0b0a10] p-3">
        <p className="text-xs tracking-widest text-[#8a8499] mb-2">TỈ LỆ MỖI LƯỢT</p>
        <ul className="space-y-1 text-xs">
          {(Object.keys(TIER) as Tier[]).map((k) => (
            <li key={k} className="flex justify-between">
              <span className={TIER[k].text}>{TIER[k].label}</span>
              <span className="text-[#a29fb3]">{TIER[k].rate}</span>
            </li>
          ))}
        </ul>
        <p className="text-xs text-[#5c5470] mt-2 leading-relaxed">
          Thường: nguyên liệu hoặc bình máu · Hiếm: nguyên liệu hoặc trang bị Hiếm · Sử Thi: trang bị Sử Thi hoặc 2
          Bình Hồi AP Lớn · Huyền Thoại: trang bị Huyền Thoại có hiệu ứng · Jackpot: vũ khí boss Huyền Thoại. Tất cả theo
          level nhân vật. {PITY} lượt liền không ra Huyền Thoại → lượt thứ {PITY} chắc chắn ra.
        </p>
      </div>

      {history.length > 0 && (
        <div>
          <p className="text-xs tracking-widest text-[#8a8499] mb-2">LỊCH SỬ GẦN ĐÂY</p>
          <ul className="space-y-1">
            {history.map((h) => (
              <li key={h.id} className="flex items-center gap-2 text-xs">
                <ItemIcon icon={h.item?.icon ?? null} size={16} />
                <span className={TIER[h.tier]?.text ?? 'text-[#c9c4d4]'}>
                  {h.item?.name ?? '?'}
                  {h.quantity > 1 && ` ×${h.quantity}`}
                </span>
                <span className="ml-auto text-[#5c5470]">{TIER[h.tier]?.label}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}
