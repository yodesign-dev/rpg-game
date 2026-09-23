'use client'

import { useState } from 'react'
import { JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/client'

const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

const RARITY_COLOR: Record<string, string> = {
  common: 'text-[#a89b7f]',
  rare: 'text-[#8fb4c4]',
  epic: 'text-[#b79bc4]',
  legendary: 'text-[#e0b050]',
}

type ShopItem = {
  id: string
  key: string
  name: string
  type: string
  rarity: string
  heal_amount: number
  bonus_atk: number
  bonus_def: number
  bonus_hp: number
  buy_price: number | null
  description: string | null
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

    const res = (Array.isArray(data) ? data[0] : data) as { gold: number } | undefined
    if (res) {
      setLocalGold(res.gold)
      setNotice(`Đã mua ${item.name}`)
    }
  }

  if (items.length === 0) {
    return (
      <p className={`${mono.className} text-center text-xs text-[#6b6249]`}>
        Chợ hiện chưa có gì để bán.
      </p>
    )
  }

  return (
    <div className="space-y-4">
      <div className={`${mono.className} text-center text-xs text-[#6b6249] mb-2`}>
        Vàng hiện có: {localGold}
      </div>

      {error && (
        <p className={`${mono.className} text-xs text-[#c98787] text-center`}>{error}</p>
      )}
      {notice && (
        <p className={`${mono.className} text-xs text-[#8fc4a8] text-center`}>{notice}</p>
      )}

      <div className="space-y-3">
        {items.map((item) => {
          const isPending = pendingItemId === item.id
          const canAfford = item.buy_price !== null && localGold >= item.buy_price
          const rarityClass = RARITY_COLOR[item.rarity] ?? RARITY_COLOR.common

          return (
            <div
              key={item.id}
              className="rounded-sm border border-[#2c261c] bg-[#17140f] p-4 flex items-center justify-between gap-4"
            >
              <div>
                <p className={rarityClass}>{item.name}</p>
                {item.description && (
                  <p className={`${mono.className} text-[11px] text-[#8a7f68] mt-1`}>
                    {item.description}
                  </p>
                )}
                <p className={`${mono.className} text-[11px] text-[#6b6249] mt-1`}>
                  {item.type === 'consumable' && `Hồi ${item.heal_amount} HP`}
                  {item.type === 'weapon' && `+${item.bonus_atk} ATK`}
                  {item.type === 'armor' &&
                    [
                      item.bonus_def ? `+${item.bonus_def} DEF` : null,
                      item.bonus_hp ? `+${item.bonus_hp} HP` : null,
                    ]
                      .filter(Boolean)
                      .join(' · ')}
                </p>
              </div>

              <button
                onClick={() => buy(item)}
                disabled={!canAfford || isPending}
                className={`${mono.className} text-xs border border-[#8a7f68] text-[#f1e6c8] px-3 py-2 rounded-sm
                  disabled:opacity-30 hover:bg-[#8a7f68] hover:text-[#100e0c] transition-colors whitespace-nowrap`}
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
