'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/client'

const RARITY_COLOR: Record<string, string> = {
  common: 'text-[#c9c4d4]',
  rare: 'text-[#8fb4c4]',
  epic: 'text-[#b79bc4]',
  legendary: 'text-[#e0b050]',
}

const RARITY_BORDER: Record<string, string> = {
  common: 'border-[#3a3348]',
  rare: 'border-[#4a6b7a]',
  epic: 'border-[#6b4a7a]',
  legendary: 'border-[#8a6a1f]',
}

type ShopItem = {
  id: string
  key: string
  name: string
  type: string
  rarity: string
  heal_amount: number
  heal_pct: number
  restore_ap: number
  buy_price: number | null
  price_per_level: number
  daily_limit: number | null
  buff_key: string | null
  description: string | null
  icon: string | null
  net_tier: number | null
}

// Khớp buy_item: giá = buy_price + price_per_level × cấp
export function shopPrice(item: ShopItem, level: number) {
  return (item.buy_price ?? 0) + item.price_per_level * level
}

export default function MarketManager({
  characterId,
  gold,
  level,
  items,
  boughtToday,
  pendingBuffs,
}: {
  characterId: string
  gold: number
  level: number
  items: ShopItem[]
  boughtToday: Record<string, number>
  pendingBuffs: string[]
}) {
  const router = useRouter()
  const [localGold, setLocalGold] = useState(gold)
  const [bought, setBought] = useState(boughtToday)
  const [pendingItemId, setPendingItemId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [qty, setQty] = useState<Record<string, number>>({})
  const [sectionKey, setSectionKey] = useState('supply')
  const [openId, setOpenId] = useState<string | null>(null)  // dòng đang mở mô tả đầy đủ

  // Số lượng tối đa mua được: theo vàng, lượt còn lại hôm nay, trần 99
  function maxQty(item: ShopItem) {
    const price = shopPrice(item, level)
    const byGold = price > 0 ? Math.floor(localGold / price) : 99
    const left = item.daily_limit == null ? 99 : Math.max(0, item.daily_limit - (bought[item.id] ?? 0))
    return Math.max(0, Math.min(99, byGold, left))
  }

  function setItemQty(item: ShopItem, n: number) {
    const max = Math.max(1, maxQty(item))
    setQty((q) => ({
      ...q,
      [item.id]: Math.min(max, Math.max(1, Math.floor(n) || 1)),
    }))
  }

  async function buy(item: ShopItem, quantity: number) {
    setError(null)
    setNotice(null)
    setPendingItemId(item.id)
    const { data, error: rpcError } = await createClient().rpc('buy_item', {
      p_character_id: characterId,
      p_item_id: item.id,
      p_quantity: quantity,
    })
    setPendingItemId(null)
    if (rpcError) return setError(rpcError.message)

    const res = (Array.isArray(data) ? data[0] : data) as { new_gold: number } | undefined
    if (res) {
      setLocalGold(res.new_gold)
      setBought((b) => ({ ...b, [item.id]: (b[item.id] ?? 0) + quantity }))
      setQty((q) => ({ ...q, [item.id]: 1 }))
      setNotice(`Đã mua ${quantity > 1 ? `${quantity}× ` : ''}${item.name} — vào Túi Đồ để dùng.`)
      router.refresh()
    }
  }

  if (items.length === 0) {
    return <p className={`${ui.className} text-center text-xs text-[#7d7a8c]`}>Chợ hiện chưa có gì để bán.</p>
  }

  const sections = [
    {
      key: 'supply',
      title: '🧪 Tiếp tế',
      note: 'Bình máu tự uống trong khám phá / tháp khi HP dưới 35% (tối đa 2 bình mỗi chuyến).',
      rows: items.filter((i) => !i.buff_key && !i.net_tier),
    },
    {
      key: 'net',
      title: '🕸️ Lưới pet',
      note: 'Ném vào pet hoang dã gặp khi Thám Hiểm (trang Pet). Lưới xịn hơn bắt pet hiếm dễ hơn.',
      rows: items.filter((i) => i.net_tier),
    },
    {
      key: 'buff',
      title: '📜 Cuộn & Bùa',
      note: 'Dùng từ Túi Đồ trước khi đi — hiệu lực cho chuyến khám phá hoặc lần leo tháp kế tiếp.',
      rows: items.filter((i) => i.buff_key),
    },
  ].filter((s) => s.rows.length > 0)
  const section = sections.find((s) => s.key === sectionKey) ?? sections[0]

  return (
    <div className={`${ui.className} space-y-3`}>
      {error && <p className="text-xs text-[#e09595] text-center">{error}</p>}
      {notice && <p className="text-xs text-[#8fe0b0] text-center">{notice}</p>}

      <div className="flex gap-1.5 overflow-x-auto [scrollbar-width:none]">
        {sections.map((sec) => (
          <button
            key={sec.key}
            onClick={() => setSectionKey(sec.key)}
            className={`shrink-0 whitespace-nowrap rounded-full border px-3 py-1.5 text-xs transition-colors ${
              sec.key === section.key
                ? 'border-[#8fe0b0]/60 bg-[#8fe0b0]/15 text-[#c8f5dc]'
                : 'border-white/10 text-[#a29fb3] hover:text-white'
            }`}
          >
            {sec.title} <span className="text-[#7d7a8c]">{sec.rows.length}</span>
          </button>
        ))}
      </div>

      <section>
          <p className="mb-2 text-[11px] text-[#7d7a8c]">{section.note}</p>
          <div className="grid gap-1.5 sm:grid-cols-2">
            {section.rows.map((item) => {
              const price = shopPrice(item, level)
              const left = item.daily_limit == null ? null : Math.max(0, item.daily_limit - (bought[item.id] ?? 0))
              const waiting = !!item.buff_key && pendingBuffs.includes(item.buff_key)
              const multi = !item.buff_key
              const max = maxQty(item)
              const n = multi ? Math.min(qty[item.id] ?? 1, Math.max(1, max)) : 1
              const canBuy = localGold >= price * n && left !== 0
              const isPending = pendingItemId === item.id
              const open = openId === item.id
              return (
                <div
                  key={item.id}
                  className="flex items-center gap-2.5 rounded-lg border border-white/[0.08] bg-white/[0.04] px-2.5 py-2"
                >
                  {item.icon && (
                    <div
                      className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-md border ${
                        RARITY_BORDER[item.rarity] ?? RARITY_BORDER.common
                      } bg-[#0b0a10]`}
                    >
                      {/* eslint-disable-next-line @next/next/no-img-element -- icon pixel 32-64 px */}
                      <img src={`/items/${item.icon}`} alt="" className="h-7 w-7 [image-rendering:pixelated]" />
                    </div>
                  )}
                  <button type="button" onClick={() => setOpenId(open ? null : item.id)} className="min-w-0 flex-1 text-left">
                    <p className={`truncate text-[13px] font-semibold leading-tight ${RARITY_COLOR[item.rarity] ?? RARITY_COLOR.common}`}>
                      {item.name}
                    </p>
                    {item.description && (
                      <p className={`text-[11px] leading-snug text-[#a29fb3] ${open ? '' : 'truncate'}`}>{item.description}</p>
                    )}
                    {(left !== null || waiting) && (
                      <p className="text-[11px] leading-snug text-[#7d7a8c]">
                        {left !== null && `Còn ${left}/${item.daily_limit} hôm nay`}
                        {waiting && <span className="text-[#8fe0b0]"> · đang chờ dùng</span>}
                      </p>
                    )}
                  </button>
                  <div className="flex shrink-0 flex-col items-end gap-1">
                    {multi && left !== 0 && (
                      <div className="flex items-center gap-1 text-xs">
                        <button
                          onClick={() => setItemQty(item, n - 1)}
                          disabled={n <= 1 || isPending}
                          className="h-6 w-6 rounded-md border border-white/15 text-[#c9c4d4] hover:bg-white/10 disabled:opacity-30"
                        >
                          −
                        </button>
                        <input
                          type="number"
                          inputMode="numeric"
                          min={1}
                          max={Math.max(1, max)}
                          value={n}
                          onChange={(e) => setItemQty(item, Number(e.target.value))}
                          disabled={isPending}
                          className="h-6 w-9 rounded-md border border-white/15 bg-[#0b0a10] text-center text-[#e8e4f0]
                          [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
                        />
                        <button
                          onClick={() => setItemQty(item, n + 1)}
                          disabled={n >= max || isPending}
                          className="h-6 w-6 rounded-md border border-white/15 text-[#c9c4d4] hover:bg-white/10 disabled:opacity-30"
                        >
                          +
                        </button>
                        <button
                          onClick={() => setItemQty(item, max)}
                          disabled={max <= 1 || n >= max || isPending}
                          className="h-6 rounded-md border border-white/15 px-1 text-[10px] text-[#a29fb3] hover:bg-white/10 disabled:opacity-30"
                        >
                          MAX
                        </button>
                      </div>
                    )}
                    <button
                      onClick={() => buy(item, n)}
                      disabled={!canBuy || isPending}
                      className="shrink-0 whitespace-nowrap rounded-lg border border-[#e0b050]/60 px-2.5 py-1 text-xs text-[#f1dba0]
                      transition-colors hover:bg-[#e0b050]/15 disabled:opacity-30"
                    >
                      {isPending ? '…' : left === 0 ? 'Hết lượt' : `🪙 ${(price * n).toLocaleString('vi-VN')}`}
                    </button>
                  </div>
                </div>
              )
            })}
          </div>
      </section>
    </div>
  )
}
