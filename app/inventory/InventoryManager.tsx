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

// 7 khớp trang bị trên nhân vật. l_arm/r_arm là 2 khớp tay độc lập — vũ khí/
// khiên 1 tay chiếm đúng 1 khớp, vũ khí 2 tay (item.hand === 'two_hand')
// chiếm cả hai cùng lúc (equip_slot lưu 'both_arms' cho trường hợp đó).
const EQUIP_SLOTS = [
  { key: 'head', label: 'Đầu' },
  { key: 'l_arm', label: 'Tay Trái' },
  { key: 'r_arm', label: 'Tay Phải' },
  { key: 'chest', label: 'Ngực' },
  { key: 'belt', label: 'Thắt Lưng' },
  { key: 'amulet', label: 'Bùa' },
  { key: 'boot', label: 'Giày' },
] as const

type Item = {
  id: string
  key: string
  name: string
  type: string
  slot: string | null
  hand: string | null
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
  equip_slot: string | null
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

  // Mặc `row` vào khớp `targetSlot` ('head'|'chest'|'belt'|'amulet'|'boot'
  // cho đồ 1 slot, hoặc 'l_arm'|'r_arm'|'both_arms' cho vũ khí/khiên).
  async function equip(row: InventoryRow, targetSlot: string) {
    setError(null)
    setPendingRowId(row.id)

    const supabase = createClient()

    // Mặc 2 tay thì gỡ cả 2 khớp tay hiện có; mặc vào 1 khớp tay cụ thể thì
    // vẫn phải gỡ vũ khí 2 tay đang chiếm cả hai khớp (nếu có).
    const slotsToClear =
      targetSlot === 'both_arms' ? ['l_arm', 'r_arm', 'both_arms'] : [targetSlot, 'both_arms']

    const toUnequip = rows.filter(
      (r) => r.id !== row.id && r.equipped && r.equip_slot && slotsToClear.includes(r.equip_slot)
    )

    if (toUnequip.length > 0) {
      const { error: unequipError } = await supabase
        .from('inventory')
        .update({ equipped: false, equip_slot: null })
        .in('id', toUnequip.map((r) => r.id))

      if (unequipError) {
        setError(unequipError.message)
        setPendingRowId(null)
        return
      }
    }

    const { error: equipError } = await supabase
      .from('inventory')
      .update({ equipped: true, equip_slot: targetSlot })
      .eq('id', row.id)

    setPendingRowId(null)

    if (equipError) {
      setError(equipError.message)
      return
    }

    setRows((prev) =>
      prev.map((r) => {
        if (r.id === row.id) return { ...r, equipped: true, equip_slot: targetSlot }
        if (toUnequip.some((u) => u.id === r.id)) return { ...r, equipped: false, equip_slot: null }
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
      .update({ equipped: false, equip_slot: null })
      .eq('id', row.id)

    setPendingRowId(null)

    if (updateError) {
      setError(updateError.message)
      return
    }

    setRows((prev) =>
      prev.map((r) => (r.id === row.id ? { ...r, equipped: false, equip_slot: null } : r))
    )
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

      <section>
        <h2 className={`${mono.className} text-xs tracking-widest text-[#8a7f68] mb-3`}>
          ĐANG TRANG BỊ
        </h2>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          {EQUIP_SLOTS.map(({ key, label }) => {
            const equippedRow =
              key === 'l_arm' || key === 'r_arm'
                ? rows.find((r) => r.equipped && (r.equip_slot === key || r.equip_slot === 'both_arms'))
                : rows.find((r) => r.equipped && r.equip_slot === key)
            const isPending = !!equippedRow && pendingRowId === equippedRow.id

            return (
              <div key={key} className="rounded-sm border border-[#2c261c] bg-[#0d0b09] p-3">
                <p className={`${mono.className} text-[10px] tracking-widest text-[#6b6249] mb-1.5`}>
                  {label}
                </p>
                {equippedRow ? (
                  <>
                    <p className={`text-sm ${RARITY_COLOR[equippedRow.items.rarity] ?? RARITY_COLOR.common}`}>
                      {equippedRow.items.name}
                      {equippedRow.equip_slot === 'both_arms' && (
                        <span className={`${mono.className} text-[10px] text-[#6b6249]`}> (2 tay)</span>
                      )}
                    </p>
                    <button
                      onClick={() => unequip(equippedRow)}
                      disabled={isPending}
                      className={`${mono.className} text-[10px] text-[#c98787] hover:text-[#f1e6c8] mt-1 disabled:opacity-30`}
                    >
                      {isPending ? '…' : 'Gỡ'}
                    </button>
                  </>
                ) : (
                  <p className={`${mono.className} text-xs text-[#4a4230]`}>Trống</p>
                )}
              </div>
            )
          })}
        </div>
      </section>

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
              const isPending = pendingRowId === row.id
              const rarityClass = RARITY_COLOR[item.rarity] ?? RARITY_COLOR.common
              const isArmItem = item.slot === 'weapon' || item.slot === 'shield'
              const isSingleSlot = !!item.slot && !isArmItem
              const btnBase = `${mono.className} text-xs border border-[#8a7f68] text-[#f1e6c8] px-3 py-2 rounded-sm
                disabled:opacity-30 hover:bg-[#8a7f68] hover:text-[#100e0c] transition-colors whitespace-nowrap`

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
                      {item.type === 'weapon' &&
                        `+${item.bonus_atk} ATK${item.hand === 'two_hand' ? ' · 2 tay' : ''}`}
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

                  <div className="flex items-center gap-2">
                    {row.equipped && (
                      <button
                        onClick={() => unequip(row)}
                        disabled={isPending}
                        className={`${mono.className} text-xs border border-[#8c3f3f] text-[#c98787] px-3 py-2 rounded-sm
                          disabled:opacity-30 hover:bg-[#8c3f3f] hover:text-[#f1e6c8] transition-colors whitespace-nowrap`}
                      >
                        {isPending ? '…' : 'Gỡ'}
                      </button>
                    )}

                    {!row.equipped && isSingleSlot && (
                      <button onClick={() => equip(row, item.slot!)} disabled={isPending} className={btnBase}>
                        {isPending ? '…' : 'Trang bị'}
                      </button>
                    )}

                    {!row.equipped && isArmItem && item.hand === 'two_hand' && (
                      <button onClick={() => equip(row, 'both_arms')} disabled={isPending} className={btnBase}>
                        {isPending ? '…' : 'Trang bị (2 tay)'}
                      </button>
                    )}

                    {!row.equipped && isArmItem && item.hand !== 'two_hand' && (
                      <>
                        <button onClick={() => equip(row, 'l_arm')} disabled={isPending} className={btnBase}>
                          {isPending ? '…' : 'Trái'}
                        </button>
                        <button onClick={() => equip(row, 'r_arm')} disabled={isPending} className={btnBase}>
                          {isPending ? '…' : 'Phải'}
                        </button>
                      </>
                    )}

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
                </div>
              )
            })}
          </div>
        </section>
      ))}
    </div>
  )
}
