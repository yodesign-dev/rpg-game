'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/client'


const RARITY_COLOR: Record<string, string> = {
  common: 'text-[#a29fb3]',
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
  hand: string | null
  rarity: string
  heal_amount: number
  restore_ap: number
  bonus_atk: number
  bonus_def: number
  bonus_hp: number
  buy_price: number | null
  description: string | null
  icon: string | null
}

export default function MarketManager({
  characterId,
  gold,
  items,
}: {
  characterId: string
  gold: number
  items: ShopItem[]
}) {
  const router = useRouter()
  const [localGold, setLocalGold] = useState(gold)
  const [pendingItemId, setPendingItemId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  async function buy(item: ShopItem) {
    setError(null)
    setNotice(null)
    setPendingItemId(item.id)

    const supabase = createClient()
    const { data, error: rpcError } = await supabase.rpc('buy_item', {
      p_character_id: characterId,
      p_item_id: item.id,
      p_quantity: 1,
    })

    setPendingItemId(null)

    if (rpcError) {
      setError(rpcError.message)
      return
    }

    const res = (Array.isArray(data) ? data[0] : data) as { new_gold: number } | undefined
    if (res) {
      setLocalGold(res.new_gold)
      setNotice(`Đã mua ${item.name}`)
      router.refresh()
    }
  }

  if (items.length === 0) {
    return (
      <p className={`${ui.className} text-center text-xs text-[#5c5470]`}>
        Chợ hiện chưa có gì để bán.
      </p>
    )
  }

  return (
    <div className="space-y-4">
      {error && (
        <p className={`${ui.className} text-xs text-[#e09595] text-center`}>{error}</p>
      )}
      {notice && (
        <p className={`${ui.className} text-xs text-[#8fe0b0] text-center`}>{notice}</p>
      )}

      <div className="space-y-3">
        {items.map((item) => {
          const isPending = pendingItemId === item.id
          const canAfford = item.buy_price !== null && localGold >= item.buy_price
          const rarityClass = RARITY_COLOR[item.rarity] ?? RARITY_COLOR.common

          return (
            <div
              key={item.id}
              className="rounded-2xl border border-white/[0.09] bg-white/[0.045] p-4 flex items-center justify-between gap-4"
            >
              <div className="flex items-center gap-3 min-w-0">
                {item.icon && (
                  <div
                    className={`w-11 h-11 rounded-lg border ${RARITY_BORDER[item.rarity] ?? RARITY_BORDER.common}
                      bg-[#0b0a10] flex items-center justify-center shrink-0`}
                  >
                    <img
                      src={`/items/${item.icon}`}
                      alt=""
                      className="w-8 h-8"
                      style={{ imageRendering: 'pixelated' }}
                    />
                  </div>
                )}
                <div>
                  <p className={`font-semibold ${rarityClass}`}>{item.name}</p>
                  {item.description && (
                    <p className={`${ui.className} text-xs text-[#8a8499] mt-1`}>
                      {item.description}
                    </p>
                  )}
                  <p className={`${ui.className} text-xs text-[#5c5470] mt-1`}>
                    {item.type === 'consumable' &&
                      (item.restore_ap > 0 ? `Hồi ${item.restore_ap} AP` : `Hồi ${item.heal_amount} HP`)}
                    {item.type === 'weapon' &&
                      `+${item.bonus_atk} ATK${item.hand === 'two_hand' ? ' · 2 tay' : ''}`}
                    {item.type === 'armor' &&
                      [
                        item.bonus_atk ? `+${item.bonus_atk} ATK` : null,
                        item.bonus_def ? `+${item.bonus_def} DEF` : null,
                        item.bonus_hp ? `+${item.bonus_hp} HP` : null,
                      ]
                        .filter(Boolean)
                        .join(' · ')}
                  </p>
                </div>
              </div>

              <button
                onClick={() => buy(item)}
                disabled={!canAfford || isPending}
                className={`${ui.className} text-xs border border-[#8a8499] text-[#f2ede4] px-3 py-2 rounded-lg
                  disabled:opacity-30 hover:bg-[#8a8499] hover:text-[#0e0c13] transition-colors whitespace-nowrap`}
              >
                {isPending ? '…' : canAfford ? `Mua · ${item.buy_price} vàng` : 'Thiếu vàng'}
              </button>
            </div>
          )
        })}
      </div>
    </div>
  )
}
