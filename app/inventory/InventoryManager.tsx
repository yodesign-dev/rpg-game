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

const TYPE_LABEL: Record<string, string> = {
  weapon: 'VŨ KHÍ',
  armor: 'GIÁP',
  consumable: 'VẬT PHẨM HỒI PHỤC',
  material: 'NGUYÊN LIỆU',
}

const TYPE_ORDER = ['weapon', 'armor', 'consumable', 'material']

type Item = {
  id: string
  key: string
  name: string
  type: string
  slot: string | null
  rarity: string
  bonus_atk: number
  bonus_def: number
  bonus_hp: number
  heal_amount: number
  sell_price: number | null
  description: string | null
}

type InventoryRow = {
  id: string
  quantity: number
  equipped: boolean
  items: Item
}

export default function InventoryManager({
  characterId,
  items,
  currentHp,
  maxHp,
}: {
  characterId: string
  items: InventoryRow[]
  currentHp: number
  maxHp: number
}) {
  const [rows, setRows] = useState<InventoryRow[]>(items)
  const [pendingRowId, setPendingRowId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [localHp, setLocalHp] = useState(currentHp)

  async function useItem(row: InventoryRow) {
    setError(null)
    setPendingRowId(row.id)

    const supabase = createClient()
    const { data, error: rpcError } = await supabase.rpc('use_item', {
      p_character_id: characterId,
      p_inventory_id: row.id,
    })

    setPendingRowId(null)

    if (rpcError) {
      setError(rpcError.message)
      return
    }

    const res = (Array.isArray(data) ? data[0] : data) as
      | { new_current_hp: number; new_quantity: number }
      | undefined

    if (res) {
      setLocalHp(res.new_current_hp)
      setRows((prev) =>
        res.new_quantity <= 0
          ? prev.filter((r) => r.id !== row.id)
          : prev.map((r) => (r.id === row.id ? { ...r, quantity: res.new_quantity } : r))
      )
    }
  }

  async function equip(row: InventoryRow) {
    setError(null)
    setPendingRowId(row.id)

    const supabase = createClient()
    const slot = row.items.slot

    // Chỉ 1 món trang bị cho mỗi slot — gỡ món cùng slot đang mặc trước khi mặc món mới.
    const sameSlotEquipped = rows.filter(
      (r) => r.id !== row.id && r.equipped && r.items.slot === slot
    )

    if (sameSlotEquipped.length > 0) {
      const { error: unequipError } = await supabase
        .from('inventory')
        .update({ equipped: false })
        .in('id', sameSlotEquipped.map((r) => r.id))

      if (unequipError) {
        setError(unequipError.message)
        setPendingRowId(null)
        return
      }
    }

    const { error: equipError } = await supabase
      .from('inventory')
      .update({ equipped: true })
      .eq('id', row.id)

    setPendingRowId(null)

    if (equipError) {
      setError(equipError.message)
      return
    }

    setRows((prev) =>
      prev.map((r) => {
        if (r.id === row.id) return { ...r, equipped: true }
        if (sameSlotEquipped.some((s) => s.id === r.id)) return { ...r, equipped: false }
        return r
      })
    )
  }

  async function unequip(row: InventoryRow) {
    setError(null)
    setPendingRowId(row.id)

    const supabase = createClient()
    const { error: updateError } = await supabase
      .from('inventory')
      .update({ equipped: false })
      .eq('id', row.id)

    setPendingRowId(null)

    if (updateError) {
      setError(updateError.message)
      return
    }

    setRows((prev) => prev.map((r) => (r.id === row.id ? { ...r, equipped: false } : r)))
  }

  const groups = TYPE_ORDER.map((type) => ({
    type,
    rows: rows.filter((r) => r.items.type === type),
  })).filter((g) => g.rows.length > 0)

  return (
    <div className="space-y-8">
      <div className={`${mono.className} text-center text-xs text-[#6b6249] -mt-4`}>
        HP hiện tại: {localHp} / {maxHp}
      </div>

      {error && (
        <p className={`${mono.className} text-xs text-[#c98787] text-center`}>{error}</p>
      )}

      {rows.length === 0 && (
        <p className={`${mono.className} text-center text-xs text-[#6b6249]`}>
          Túi đồ trống. Đánh quái trong dungeon để nhặt trang bị.
        </p>
      )}

      {groups.map((group) => (
        <section key={group.type}>
          <h2 className={`${mono.className} text-xs tracking-widest text-[#8a7f68] mb-3`}>
            {TYPE_LABEL[group.type] ?? group.type.toUpperCase()}
          </h2>

          <div className="space-y-3">
            {group.rows.map((row) => {
              const item = row.items
              const isEquippable = item.type === 'weapon' || item.type === 'armor'
              const isPending = pendingRowId === row.id
              const rarityClass = RARITY_COLOR[item.rarity] ?? RARITY_COLOR.common

              return (
                <div
                  key={row.id}
                  className={`rounded-sm border p-4 flex items-center justify-between gap-4
                    ${row.equipped ? 'border-[#3d5a45] bg-[#151d17]' : 'border-[#2c261c] bg-[#17140f]'}`}
                >
                  <div>
                    <p className={rarityClass}>
                      {item.name}
                      {row.quantity > 1 && (
                        <span className={`${mono.className} text-xs text-[#6b6249]`}> ×{row.quantity}</span>
                      )}
                    </p>
                    {item.description && (
                      <p className={`${mono.className} text-[11px] text-[#8a7f68] mt-1`}>
                        {item.description}
                      </p>
                    )}
                    <p className={`${mono.className} text-[11px] text-[#6b6249] mt-1`}>
                      {item.type === 'weapon' && `+${item.bonus_atk} ATK`}
                      {item.type === 'armor' &&
                        [
                          item.bonus_def ? `+${item.bonus_def} DEF` : null,
                          item.bonus_hp ? `+${item.bonus_hp} HP` : null,
                        ]
                          .filter(Boolean)
                          .join(' · ')}
                      {item.type === 'consumable' && `Hồi ${item.heal_amount} HP`}
                      {item.type === 'material' && item.sell_price != null && `Bán được ${item.sell_price} vàng`}
                    </p>
                  </div>

                  {isEquippable &&
                    (row.equipped ? (
                      <button
                        onClick={() => unequip(row)}
                        disabled={isPending}
                        className={`${mono.className} text-xs border border-[#8c3f3f] text-[#c98787] px-3 py-2 rounded-sm
                          disabled:opacity-30 hover:bg-[#8c3f3f] hover:text-[#f1e6c8] transition-colors whitespace-nowrap`}
                      >
                        {isPending ? '…' : 'Gỡ'}
                      </button>
                    ) : (
                      <button
                        onClick={() => equip(row)}
                        disabled={isPending}
                        className={`${mono.className} text-xs border border-[#8a7f68] text-[#f1e6c8] px-3 py-2 rounded-sm
                          disabled:opacity-30 hover:bg-[#8a7f68] hover:text-[#100e0c] transition-colors whitespace-nowrap`}
                      >
                        {isPending ? '…' : 'Trang bị'}
                      </button>
                    ))}

                  {item.type === 'consumable' && (
                    <button
                      onClick={() => useItem(row)}
                      disabled={isPending || localHp >= maxHp}
                      className={`${mono.className} text-xs border border-[#3d5a45] text-[#8fc4a8] px-3 py-2 rounded-sm
                        disabled:opacity-30 hover:bg-[#3d5a45] hover:text-[#f1e6c8] transition-colors whitespace-nowrap`}
                    >
                      {isPending ? '…' : localHp >= maxHp ? 'HP đầy' : 'Dùng'}
                    </button>
                  )}
                </div>
              )
            })}
          </div>
        </section>
      ))}
    </div>
  )
}
