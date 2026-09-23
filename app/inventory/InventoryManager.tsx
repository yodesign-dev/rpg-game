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

const RARITY_BORDER: Record<string, string> = {
  common: 'border-[#4a4230]',
  rare: 'border-[#4a6b7a]',
  epic: 'border-[#6b4a7a]',
  legendary: 'border-[#8a6a1f]',
}

const SLOT_ICON: Record<string, string> = {
  head: '🪖',
  l_arm: '⚔️',
  r_arm: '⚔️',
  chest: '🎽',
  belt: '🎗️',
  amulet: '📿',
  boot: '👢',
  ring_1: '💍',
  ring_2: '💍',
}

// Bố cục kiểu "paper doll": nhân vật ở giữa, trang bị chia 2 cột trái/phải
// quanh nhân vật, giống layout Equip Info của các ARPG. ring_1/ring_2 là 2
// khớp nhẫn độc lập (giống l_arm/r_arm) — mỗi khớp mặc 1 chiếc nhẫn riêng.
const LEFT_SLOTS = [
  { key: 'head', label: 'Đầu' },
  { key: 'l_arm', label: 'Tay Trái' },
  { key: 'chest', label: 'Ngực' },
  { key: 'belt', label: 'Thắt Lưng' },
  { key: 'ring_1', label: 'Nhẫn 1' },
] as const

const RIGHT_SLOTS = [
  { key: 'r_arm', label: 'Tay Phải' },
  { key: 'amulet', label: 'Bùa' },
  { key: 'boot', label: 'Giày' },
  { key: 'ring_2', label: 'Nhẫn 2' },
] as const

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
  characterName,
  classIcon,
  items,
  currentHp,
  maxHp,
  baseAtk,
  baseDef,
  baseSpd,
}: {
  characterId: string
  characterName: string
  classIcon: string | null
  items: InventoryRow[]
  currentHp: number
  maxHp: number
  baseAtk: number
  baseDef: number
  baseSpd: number
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

  const equippedRows = rows.filter((r) => r.equipped)
  const totalAtk = baseAtk + equippedRows.reduce((sum, r) => sum + r.items.bonus_atk, 0)
  const totalDef = baseDef + equippedRows.reduce((sum, r) => sum + r.items.bonus_def, 0)

  function findEquipped(slotKey: string) {
    return slotKey === 'l_arm' || slotKey === 'r_arm'
      ? equippedRows.find((r) => r.equip_slot === slotKey || r.equip_slot === 'both_arms')
      : equippedRows.find((r) => r.equip_slot === slotKey)
  }

  function SlotBox({ slotKey, label }: { slotKey: string; label: string }) {
    const row = findEquipped(slotKey)

    if (!row) {
      return (
        <div className="w-16 h-16 sm:w-[72px] sm:h-[72px] rounded-sm border border-dashed border-[#2c261c]
          flex flex-col items-center justify-center gap-0.5 opacity-50 shrink-0">
          <span className="text-lg">{SLOT_ICON[slotKey]}</span>
          <span className={`${mono.className} text-[8px] text-[#6b6249]`}>{label}</span>
        </div>
      )
    }

    const item = row.items
    return (
      <div
        title={item.name}
        className={`w-16 h-16 sm:w-[72px] sm:h-[72px] rounded-sm border ${RARITY_BORDER[item.rarity] ?? RARITY_BORDER.common}
          bg-[#17140f] flex flex-col items-center justify-center gap-0.5 px-1 shrink-0`}
      >
        <span className="text-lg">{SLOT_ICON[slotKey]}</span>
        <span
          className={`${mono.className} text-[8px] text-center leading-tight line-clamp-2
            ${RARITY_COLOR[item.rarity] ?? RARITY_COLOR.common}`}
        >
          {item.name}
        </span>
      </div>
    )
  }

  return (
    <div className="space-y-8">
      {error && (
        <p className={`${mono.className} text-xs text-[#c98787] text-center`}>{error}</p>
      )}

      <section>
        <h2 className={`${mono.className} text-xs tracking-widest text-[#8a7f68] mb-3 text-center`}>
          TRANG BỊ
        </h2>
        <div className="rounded-sm border border-[#2c261c] bg-[#0d0b09] p-4 sm:p-5">
          <div className="flex items-start justify-center gap-2 sm:gap-4">
            <div className="flex flex-col gap-2">
              {LEFT_SLOTS.map((s) => (
                <SlotBox key={s.key} slotKey={s.key} label={s.label} />
              ))}
            </div>

            <div className="flex-1 flex flex-col items-center gap-2 pt-2 min-w-0">
              <div className="text-5xl sm:text-6xl">{classIcon}</div>
              <p className={`${mono.className} text-xs text-[#f1e6c8] text-center truncate max-w-full`}>
                {characterName}
              </p>
              <div className="w-full max-w-[140px] h-1.5 bg-[#2c261c] rounded-full overflow-hidden">
                <div
                  className="h-full bg-[#8fc4a8]"
                  style={{ width: `${Math.min(100, Math.round((localHp / maxHp) * 100))}%` }}
                />
              </div>
              <p className={`${mono.className} text-[10px] text-[#8a7f68]`}>
                HP {localHp} / {maxHp}
              </p>
            </div>

            <div className="flex flex-col gap-2">
              {RIGHT_SLOTS.map((s) => (
                <SlotBox key={s.key} slotKey={s.key} label={s.label} />
              ))}
            </div>
          </div>

          <div className={`${mono.className} mt-4 pt-3 border-t border-[#2c261c] flex items-center justify-around text-xs text-[#a89b7f]`}>
            <span>⚔️ {totalAtk}</span>
            <span>🛡️ {totalDef}</span>
            <span>💨 {baseSpd}</span>
          </div>
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
              const isRingItem = item.slot === 'ring'
              const isSingleSlot = !!item.slot && !isArmItem && !isRingItem
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

                    {!row.equipped && isRingItem && (
                      <>
                        <button onClick={() => equip(row, 'ring_1')} disabled={isPending} className={btnBase}>
                          {isPending ? '…' : 'Nhẫn 1'}
                        </button>
                        <button onClick={() => equip(row, 'ring_2')} disabled={isPending} className={btnBase}>
                          {isPending ? '…' : 'Nhẫn 2'}
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
