'use client'

import { useEffect, useState } from 'react'
import { JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/client'
import { LEGENDARY_EFFECTS } from '@/lib/legendary-effects'
import { INVENTORY_SELECT, type MaterialInfo } from '@/lib/inventory'

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

const RARITY_LABEL: Record<string, string> = {
  common: 'Thường',
  rare: 'Hiếm',
  epic: 'Sử Thi',
  legendary: 'Huyền Thoại',
}

// Tier của từng món: đồ rơi/chế tạo có tier riêng (inventory.rarity), đồ mua ở
// chợ và vật phẩm gộp chồng thì dùng tier gốc của loại đồ.
function tierOf(row: { rarity: string | null; items: { rarity: string } }) {
  return row.rarity ?? row.items.rarity
}

const RARITY_RANK: Record<string, number> = { common: 0, rare: 1, epic: 2, legendary: 3 }

// Khớp inventory_sell_price (schema.sql): trang bị có tier riêng bán ×1.5
// mỗi bậc trên tier gốc; đồ mua ở chợ/vật phẩm gộp chồng bán đúng giá gốc.
function sellPriceOf(row: InventoryRow) {
  const base = row.items.sell_price ?? 0
  const steps = Math.max(0, (RARITY_RANK[tierOf(row)] ?? 0) - (RARITY_RANK[row.items.rarity] ?? 0))
  return Math.round(base * 1.5 ** steps * row.quantity)
}

// Điểm 1 món — cùng trọng số với inventory_item_score / character_power ở server
function itemScore(row: InventoryRow) {
  const it = row.items
  return (
    (it.bonus_atk + row.rolled_atk) * 2 +
    (it.bonus_def + row.rolled_def) * 1.5 +
    (it.bonus_hp + row.rolled_hp) * 0.25 +
    (row.rolled_crit + row.rolled_lifesteal) * 400 +
    (row.legendary_effect ? 60 : 0)
  )
}

// Chế tạo có "tăng tỉ lệ": tốn gấp đôi vàng, tối thiểu 50 — khớp craft_item
function boostCost(goldCost: number) {
  return Math.max(50, goldCost * 2)
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

export type InventoryTab = 'equip' | 'bag' | 'craft'

const TYPE_SHORT: Record<string, string> = {
  weapon: 'Vũ khí',
  armor: 'Giáp',
  consumable: 'Hồi phục',
  material: 'Nguyên liệu',
}

const TYPE_ORDER = ['weapon', 'armor', 'consumable', 'material']

type Item = {
  id: string
  key: string
  name: string
  type: string
  slot: string | null
  hand: string | null
  school: string | null
  rarity: string
  bonus_atk: number
  bonus_def: number
  bonus_hp: number
  heal_amount: number
  restore_ap: number
  sell_price: number | null
  description: string | null
  icon: string | null
  item_level: number
  material_tier: number | null
}

type InventoryRow = {
  id: string
  quantity: number
  equipped: boolean
  equip_slot: string | null
  rolled_atk: number
  rolled_def: number
  rolled_hp: number
  rolled_crit: number
  rolled_lifesteal: number
  rarity: string | null
  legendary_effect: string | null
  locked: boolean
  enchant_level: number
  items: Item
}

type Recipe = {
  id: string
  name: string
  goldCost: number
  successRate: number
  description: string | null
  resultItem: { id: string; key: string; name: string; rarity: string; icon: string | null; type: string }
  ingredients: { item: { id: string; key: string; name: string }; quantity: number }[]
}

export default function InventoryManager({
  characterId,
  characterName,
  classIcon,
  items,
  currentHp,
  baseMaxHp,
  baseAtk,
  baseDef,
  baseSpd,
  gold,
  currentAp,
  maxAp,
  recipes,
  initialTab,
  materialChain,
}: {
  characterId: string
  characterName: string
  classIcon: string | null
  items: InventoryRow[]
  currentHp: number
  baseMaxHp: number
  baseAtk: number
  baseDef: number
  baseSpd: number
  gold: number
  currentAp: number
  maxAp: number
  recipes: Recipe[]
  initialTab: InventoryTab
  materialChain: MaterialInfo[]
}) {
  const [tab, setTabState] = useState<InventoryTab>(initialTab)
  const [typeFilter, setTypeFilter] = useState<string>('all')
  const [rows, setRows] = useState<InventoryRow[]>(items)
  const [pendingRowId, setPendingRowId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [localHp, setLocalHp] = useState(currentHp)
  const [localAp, setLocalAp] = useState(currentAp)
  const [localGold, setLocalGold] = useState(gold)
  const [pendingRecipeId, setPendingRecipeId] = useState<string | null>(null)
  const [craftResult, setCraftResult] = useState<{ text: string; rarity: string | null; ok: boolean } | null>(null)
  const [boosted, setBoosted] = useState<Record<string, boolean>>({})
  const [sellMode, setSellMode] = useState(false)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [confirmSell, setConfirmSell] = useState(false)
  const [selling, setSelling] = useState(false)
  const [sellResult, setSellResult] = useState<string | null>(null)
  // Panel mở rộng dưới 1 dòng: cường hóa (trang bị) hoặc rã/ghép (nguyên liệu)
  const [openPanel, setOpenPanel] = useState<{ rowId: string; kind: 'enchant' | 'convert' } | null>(null)
  const [actionMsg, setActionMsg] = useState<{ rowId: string; text: string; ok: boolean } | null>(null)

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
      | { new_current_hp: number; new_current_ap: number; new_quantity: number }
      | undefined

    if (res) {
      setLocalHp(res.new_current_hp)
      setLocalAp(res.new_current_ap)
      setRows((prev) =>
        res.new_quantity <= 0
          ? prev.filter((r) => r.id !== row.id)
          : prev.map((r) => (r.id === row.id ? { ...r, quantity: res.new_quantity } : r))
      )
    }
  }

  // Mặc `row` vào khớp `targetSlot` ('head'|'chest'|'belt'|'amulet'|'boot'
  // cho đồ 1 slot, hoặc 'l_arm'|'r_arm'|'both_arms'|'ring_1'|'ring_2').
  async function equip(row: InventoryRow, targetSlot: string) {
    setError(null)
    setPendingRowId(row.id)

    // Server kiểm tra khớp hợp lệ và tự gỡ món đang chiếm khớp đó (vũ khí 2
    // tay chiếm cả hai khớp tay), trả về id các dòng vừa bị gỡ.
    const { data, error: equipError } = await createClient().rpc('equip_item', {
      p_character_id: characterId,
      p_inventory_id: row.id,
      p_slot: targetSlot,
    })

    setPendingRowId(null)

    if (equipError) {
      setError(equipError.message)
      return
    }

    const unequippedIds = (data as string[] | null) ?? []

    setRows((prev) =>
      prev.map((r) => {
        if (r.id === row.id) return { ...r, equipped: true, equip_slot: targetSlot }
        if (unequippedIds.includes(r.id)) return { ...r, equipped: false, equip_slot: null }
        return r
      })
    )
  }

  async function unequip(row: InventoryRow) {
    setError(null)
    setPendingRowId(row.id)

    const { error: updateError } = await createClient().rpc('unequip_item', {
      p_character_id: characterId,
      p_inventory_id: row.id,
    })

    setPendingRowId(null)

    if (updateError) {
      setError(updateError.message)
      return
    }

    setRows((prev) =>
      prev.map((r) => (r.id === row.id ? { ...r, equipped: false, equip_slot: null } : r))
    )
  }

  async function craft(recipe: Recipe) {
    setError(null)
    setCraftResult(null)
    setPendingRecipeId(recipe.id)

    const supabase = createClient()
    const { data, error: rpcError } = await supabase.rpc('craft_item', {
      p_character_id: characterId,
      p_recipe_id: recipe.id,
      p_boost: !!boosted[recipe.id],
    })

    if (rpcError) {
      setError(rpcError.message)
      setPendingRecipeId(null)
      return
    }

    const res = (Array.isArray(data) ? data[0] : data) as
      | { success: boolean; result_name: string | null; new_gold: number; result_rarity: string | null }
      | undefined

    if (res) {
      setLocalGold(res.new_gold)
      setCraftResult(
        res.success
          ? {
              ok: true,
              rarity: res.result_rarity,
              text: `Thành công! Nhận được ${res.result_name}${
                res.result_rarity ? ` [${RARITY_LABEL[res.result_rarity]}]` : ''
              }.`,
            }
          : { ok: false, rarity: null, text: 'Thất bại — nguyên liệu đã mất.' }
      )
    }

    await reloadRows()
    setPendingRecipeId(null)
  }

  // Nguyên liệu bị trừ dần qua nhiều dòng inventory ở server theo cách
  // không đoán trước chính xác được — tải lại danh sách túi đồ thay vì
  // cố vá state cục bộ cho đúng.
  async function reloadRows() {
    const { data: fresh } = await createClient()
      .from('inventory')
      .select(INVENTORY_SELECT)
      .eq('character_id', characterId)
    if (fresh) setRows(fresh as unknown as InventoryRow[])
  }

  function countOf(itemId: string) {
    return rows.filter((r) => r.items.id === itemId && !r.equipped).reduce((sum, r) => sum + r.quantity, 0)
  }

  const [autoMsg, setAutoMsg] = useState<string | null>(null)

  async function autoEquip() {
    setError(null)
    setAutoMsg(null)
    setPendingRowId('auto')
    const { data, error: rpcError } = await createClient().rpc('auto_equip_best', { p_character_id: characterId })
    setPendingRowId(null)
    if (rpcError) return setError(rpcError.message)
    const res = data as { changed: number; power_before: number; power_after: number }
    setAutoMsg(
      res.changed === 0
        ? 'Đồ đang mặc đã là tốt nhất rồi.'
        : `Đã thay ${res.changed} món · Lực chiến ${res.power_before} → ${res.power_after}`
    )
    await reloadRows()
  }

  // Món chưa mặc có mạnh hơn món đang ở ô tương ứng không (để gắn nhãn ▲)
  function isUpgrade(row: InventoryRow) {
    if (row.equipped || (row.items.type !== 'weapon' && row.items.type !== 'armor') || !row.items.slot) return false
    const at = (slot: string) => {
      const r = rows.find((x) => x.equipped && x.equip_slot === slot)
      return r ? itemScore(r) : 0
    }
    const score = itemScore(row)
    const slot = row.items.slot
    if (slot === 'ring') return score > Math.min(at('ring_1'), at('ring_2'))
    if (slot === 'weapon' || slot === 'shield') {
      const both = rows.find((x) => x.equipped && x.equip_slot === 'both_arms')
      if (row.items.hand === 'two_hand') return score > (both ? itemScore(both) : at('l_arm') + at('r_arm'))
      return both ? score > itemScore(both) : score > Math.min(at('l_arm'), at('r_arm'))
    }
    return score > at(slot)
  }

  const upgradeCount = rows.filter(isUpgrade).length

  async function toggleLock(row: InventoryRow) {
    setError(null)
    setPendingRowId(row.id)
    const { data, error: rpcError } = await createClient().rpc('toggle_item_lock', {
      p_character_id: characterId,
      p_inventory_id: row.id,
    })
    setPendingRowId(null)
    if (rpcError) {
      setError(rpcError.message)
      return
    }
    setRows((prev) => prev.map((r) => (r.id === row.id ? { ...r, locked: data as boolean } : r)))
  }

  async function enchant(row: InventoryRow) {
    setError(null)
    setPendingRowId(row.id)
    const { data, error: rpcError } = await createClient().rpc('enchant_item', {
      p_character_id: characterId,
      p_inventory_id: row.id,
    })
    setPendingRowId(null)
    if (rpcError) {
      setActionMsg({ rowId: row.id, text: rpcError.message, ok: false })
      return
    }
    const res = (Array.isArray(data) ? data[0] : data) as { out_success: boolean; out_level: number; out_gold: number }
    setLocalGold(res.out_gold)
    setActionMsg({
      rowId: row.id,
      ok: res.out_success,
      text: res.out_success
        ? `Thành công! ${row.items.name} lên +${res.out_level}.`
        : `Thất bại — mất nguyên liệu, vẫn giữ +${res.out_level}.`,
    })
    await reloadRows()
  }

  async function convert(row: InventoryRow, mode: 'combine' | 'break', times: number) {
    setError(null)
    setPendingRowId(row.id)
    const { data, error: rpcError } = await createClient().rpc('convert_material', {
      p_character_id: characterId,
      p_item_id: row.items.id,
      p_mode: mode,
      p_times: times,
    })
    setPendingRowId(null)
    if (rpcError) {
      setActionMsg({ rowId: row.id, text: rpcError.message, ok: false })
      return
    }
    const idx = materialChain.findIndex((m) => m.id === row.items.id)
    const target = materialChain[mode === 'combine' ? idx + 1 : idx - 1]
    const fee = (mode === 'combine' ? target.sell_price : row.items.sell_price ?? 0) * times
    setLocalGold((g) => g - fee)
    setActionMsg({ rowId: row.id, ok: true, text: `Nhận ${data} × ${target.name} (−${fee} vàng).` })
    await reloadRows()
  }

  const sellable = rows.filter((r) => !r.equipped && !r.locked)
  const selectedRows = rows.filter((r) => selected.has(r.id))
  const selectedGold = selectedRows.reduce((sum, r) => sum + sellPriceOf(r), 0)
  const selectedHighTier = selectedRows.some((r) => (RARITY_RANK[tierOf(r)] ?? 0) >= 2)

  function toggleRow(id: string) {
    setConfirmSell(false)
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  // Chọn nhanh: chọn hết đồ chưa mặc khớp điều kiện; nếu đã chọn hết rồi thì bỏ chọn
  function toggleWhere(match: (r: InventoryRow) => boolean) {
    setConfirmSell(false)
    const ids = sellable.filter(match).map((r) => r.id)
    setSelected((prev) => {
      const next = new Set(prev)
      const allIn = ids.length > 0 && ids.every((id) => next.has(id))
      ids.forEach((id) => (allIn ? next.delete(id) : next.add(id)))
      return next
    })
  }

  function exitSellMode() {
    setSellMode(false)
    setSelected(new Set())
    setConfirmSell(false)
  }

  async function sellSelected() {
    if (selectedRows.length === 0) return
    if (!confirmSell) {
      setConfirmSell(true)
      return
    }
    setSelling(true)
    setError(null)
    const ids = selectedRows.map((r) => r.id)
    const { data, error: rpcError } = await createClient().rpc('sell_items', {
      p_character_id: characterId,
      p_inventory_ids: ids,
    })
    setSelling(false)
    setConfirmSell(false)

    if (rpcError) {
      setError(rpcError.message)
      return
    }

    const res = (Array.isArray(data) ? data[0] : data) as
      | { out_sold: number; out_gold_gained: number; out_new_gold: number }
      | undefined
    if (res) {
      setLocalGold(res.out_new_gold)
      setSellResult(`Đã bán ${res.out_sold} món, nhận ${res.out_gold_gained} vàng.`)
    }
    setRows((prev) => prev.filter((r) => !ids.includes(r.id)))
    setSelected(new Set())
  }

  // Tab Trang bị: đồ đang mặc. Tab Túi đồ: đồ chưa mặc, lọc theo loại.
  const bagRows = rows.filter((r) => !r.equipped)
  const listRows =
    tab === 'equip'
      ? rows.filter((r) => r.equipped)
      : bagRows.filter((r) => typeFilter === 'all' || r.items.type === typeFilter)
  const groups = TYPE_ORDER.map((type) => ({
    type,
    rows: listRows.filter((r) => r.items.type === type),
  })).filter((g) => g.rows.length > 0)

  const craftableCount = recipes.filter(
    (recipe) =>
      localGold >= recipe.goldCost &&
      recipe.ingredients.every(
        (ing) =>
          rows.filter((r) => r.items.id === ing.item.id).reduce((sum, r) => sum + r.quantity, 0) >= ing.quantity
      )
  ).length

  function setTab(next: InventoryTab) {
    if (next === tab) return
    exitSellMode()
    setSellResult(null)
    setTabState(next)
    // Giữ tab trên URL để tải lại trang không bị nhảy về tab đầu
    window.history.replaceState(null, '', `?tab=${next}`)
  }

  const equippedRows = rows.filter((r) => r.equipped)
  const totalAtk = baseAtk + equippedRows.reduce((sum, r) => sum + r.items.bonus_atk + r.rolled_atk, 0)
  const totalDef = baseDef + equippedRows.reduce((sum, r) => sum + r.items.bonus_def + r.rolled_def, 0)
  const totalMaxHp = baseMaxHp + equippedRows.reduce((sum, r) => sum + r.items.bonus_hp + r.rolled_hp, 0)

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
        title={`${item.name} [${RARITY_LABEL[tierOf(row)]}]`}
        className={`w-16 h-16 sm:w-[72px] sm:h-[72px] rounded-sm border ${RARITY_BORDER[tierOf(row)] ?? RARITY_BORDER.common}
          bg-[#17140f] flex flex-col items-center justify-center gap-0.5 px-1 shrink-0`}
      >
        {item.icon ? (
          <img
            src={`/items/${item.icon}`}
            alt=""
            className="w-7 h-7"
            style={{ imageRendering: 'pixelated' }}
          />
        ) : (
          <span className="text-lg">{SLOT_ICON[slotKey]}</span>
        )}
        <span
          className={`${mono.className} text-[8px] text-center leading-tight line-clamp-2
            ${RARITY_COLOR[tierOf(row)] ?? RARITY_COLOR.common}`}
        >
          {item.name}
        </span>
      </div>
    )
  }

  const TABS: { key: InventoryTab; label: string; badge?: number }[] = [
    { key: 'equip', label: '🛡️ Trang bị', badge: rows.filter((r) => r.equipped).length },
    { key: 'bag', label: '🎒 Túi đồ', badge: bagRows.length },
    { key: 'craft', label: '⚒️ Chế tạo', badge: craftableCount || undefined },
  ]

  return (
    <div className="space-y-6">
      <div
        className={`${mono.className} sticky top-0 z-20 -mx-6 px-6 pt-2 pb-3 bg-[#100e0c]/95 backdrop-blur border-b border-[#2c261c]`}
      >
        <div className="flex items-center justify-center gap-4 text-xs text-[#a89b7f] mb-3">
          <span className="text-[#e0b050]">💰 {localGold}</span>
          <span>❤️ {localHp}/{totalMaxHp}</span>
          <span className="text-[#6b8a5a]">⚡ {localAp}/{maxAp}</span>
        </div>
        <div role="tablist" className="grid grid-cols-3 gap-1.5">
          {TABS.map((t) => (
            <button
              key={t.key}
              role="tab"
              aria-selected={tab === t.key}
              onClick={() => setTab(t.key)}
              className={`rounded-sm border px-1 py-2 text-xs whitespace-nowrap transition-colors outline-none focus-visible:ring-1 focus-visible:ring-[#8a7f68] ${
                tab === t.key
                  ? 'border-[#8a7f68] bg-[#2c261c] text-[#f1e6c8]'
                  : 'border-[#2c261c] text-[#8a7f68] hover:text-[#a89b7f]'
              }`}
            >
              {t.label}
              {t.badge ? <span className="ml-1 text-[#6b6249]">{t.badge}</span> : null}
            </button>
          ))}
        </div>
      </div>

      {error && (
        <p className={`${mono.className} text-xs text-[#c98787] text-center`}>{error}</p>
      )}

      {tab === 'equip' && (
        <div className={`${mono.className} flex items-center justify-between gap-3`}>
          <span className="text-[11px] text-[#6b6249]">
            {upgradeCount ? `Có ${upgradeCount} món trong túi mạnh hơn đồ đang mặc` : 'Đang mặc đồ tốt nhất trong túi'}
          </span>
          <button
              onClick={autoEquip}
              disabled={pendingRowId === 'auto'}
              className="text-xs border border-[#8fc4a8]/60 text-[#8fc4a8] px-3 py-2 rounded-sm hover:bg-[#8fc4a8]/10 disabled:opacity-40 whitespace-nowrap"
            >
              {pendingRowId === 'auto' ? '…' : `⚡ Tự mặc đồ tốt nhất${upgradeCount ? ` (${upgradeCount})` : ''}`}
            </button>
        </div>
      )}
      {tab === 'equip' && autoMsg && <p className={`${mono.className} text-xs text-[#8fc4a8]`}>{autoMsg}</p>}

      {tab === 'equip' && (
      <section>
        <div className="rounded-sm border border-[#2c261c] bg-[#0d0b09] p-4 sm:p-5">
          {/* max-w-md: trên màn rộng không để 2 cột ô trang bị dạt ra 2 mép */}
          <div className="mx-auto max-w-md flex items-stretch justify-center gap-2 sm:gap-4">
            <div className="flex flex-col gap-2">
              {LEFT_SLOTS.map((s) => (
                <SlotBox key={s.key} slotKey={s.key} label={s.label} />
              ))}
            </div>

            <div className="flex-1 flex flex-col items-center justify-center gap-2 min-w-0">
              <div className="text-5xl sm:text-6xl">{classIcon}</div>
              <p className={`${mono.className} text-xs text-[#f1e6c8] text-center truncate max-w-full`}>
                {characterName}
              </p>
              <div className="w-full max-w-[140px] h-1.5 bg-[#2c261c] rounded-full overflow-hidden">
                <div
                  className="h-full bg-[#8fc4a8]"
                  style={{ width: `${Math.min(100, Math.round((localHp / totalMaxHp) * 100))}%` }}
                />
              </div>
              <p className={`${mono.className} text-[10px] text-[#8a7f68]`}>
                HP {localHp} / {totalMaxHp}
              </p>
              <p className={`${mono.className} text-[10px] text-[#6b8a5a]`}>
                AP {localAp} / {maxAp}
              </p>
            </div>

            <div className="flex flex-col gap-2">
              {RIGHT_SLOTS.map((s) => (
                <SlotBox key={s.key} slotKey={s.key} label={s.label} />
              ))}
            </div>
          </div>

          <div className={`${mono.className} mx-auto max-w-md mt-4 pt-3 border-t border-[#2c261c] flex items-center justify-around text-xs text-[#a89b7f]`}>
            <span>⚔️ {totalAtk}</span>
            <span>🛡️ {totalDef}</span>
            <span>💨 {baseSpd}</span>
          </div>
        </div>
      </section>
      )}

      {tab === 'equip' && listRows.length === 0 && (
        <p className={`${mono.className} text-center text-xs text-[#6b6249]`}>
          Chưa mặc món nào. Vào tab Túi đồ để trang bị.
        </p>
      )}

      {tab === 'bag' && bagRows.length === 0 && (
        <p className={`${mono.className} text-center text-xs text-[#6b6249]`}>
          Túi đồ trống. Đi thám hiểm hoặc đánh dungeon để nhặt đồ.
        </p>
      )}

      {tab === 'bag' && bagRows.length > 0 && (
        <div className={`${mono.className} flex flex-wrap gap-1.5`}>
          {['all', ...TYPE_ORDER].map((type) => {
            const n = type === 'all' ? bagRows.length : bagRows.filter((r) => r.items.type === type).length
            if (n === 0) return null
            return (
              <button
                key={type}
                onClick={() => setTypeFilter(type)}
                className={`rounded-full border px-3 py-1 text-[11px] ${
                  typeFilter === type
                    ? 'border-[#8a7f68] bg-[#2c261c] text-[#f1e6c8]'
                    : 'border-[#2c261c] text-[#8a7f68]'
                }`}
              >
                {type === 'all' ? 'Tất cả' : TYPE_SHORT[type]} ({n})
              </button>
            )
          })}
        </div>
      )}

      {tab === 'bag' && bagRows.length > 0 && (
        <div className={`${mono.className} space-y-3`}>
          <div className="flex items-center justify-between gap-3">
            {!sellMode ? (
              <button
              onClick={autoEquip}
              disabled={pendingRowId === 'auto'}
              className="text-xs border border-[#8fc4a8]/60 text-[#8fc4a8] px-3 py-2 rounded-sm hover:bg-[#8fc4a8]/10 disabled:opacity-40 whitespace-nowrap"
            >
              {pendingRowId === 'auto' ? '…' : `⚡ Tự mặc đồ tốt nhất${upgradeCount ? ` (${upgradeCount})` : ''}`}
            </button>
            ) : (
              <span className="text-[11px] text-[#6b6249]">Chọn nhiều món để bán một lần</span>
            )}
            <button
              onClick={() => (sellMode ? exitSellMode() : (setSellMode(true), setSellResult(null)))}
              className={`text-xs border px-3 py-2 rounded-sm transition-colors ${
                sellMode
                  ? 'border-[#8a7f68] text-[#f1e6c8] bg-[#2c261c]'
                  : 'border-[#e0b050]/60 text-[#e0b050] hover:bg-[#e0b050]/10'
              }`}
            >
              {sellMode ? 'Xong' : '💰 Bán đồ'}
            </button>
          </div>

          {sellResult && <p className="text-xs text-[#8fc4a8]">{sellResult}</p>}
          {autoMsg && <p className="text-xs text-[#8fc4a8]">{autoMsg}</p>}

          {sellMode && (
            <div className="rounded-sm border border-[#2c261c] bg-[#0d0b09] p-3 space-y-2">
              <p className="text-[11px] text-[#8a7f68]">
                Chọn nhanh (bấm lần nữa để bỏ chọn). Đồ đang mặc không bao giờ bị chọn.
              </p>
              <div className="flex flex-wrap gap-1.5">
                {TYPE_ORDER.map((type) => {
                  const n = sellable.filter((r) => r.items.type === type).length
                  if (n === 0) return null
                  return (
                    <QuickChip key={type} onClick={() => toggleWhere((r) => r.items.type === type)}>
                      {TYPE_LABEL[type]?.toLowerCase() ?? type} ({n})
                    </QuickChip>
                  )
                })}
              </div>
              <div className="flex flex-wrap gap-1.5">
                {Object.keys(RARITY_LABEL).map((tier) => {
                  const match = (r: InventoryRow) =>
                    (r.items.type === 'weapon' || r.items.type === 'armor') && tierOf(r) === tier
                  const n = sellable.filter(match).length
                  if (n === 0) return null
                  return (
                    <QuickChip key={tier} className={RARITY_COLOR[tier]} onClick={() => toggleWhere(match)}>
                      trang bị {RARITY_LABEL[tier]} ({n})
                    </QuickChip>
                  )
                })}
                {selected.size > 0 && (
                  <QuickChip onClick={() => (setSelected(new Set()), setConfirmSell(false))}>bỏ chọn hết</QuickChip>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      {tab !== 'craft' && groups.map((group) => (
        <section key={group.type}>
          <h2 className={`${mono.className} text-xs tracking-widest text-[#8a7f68] mb-3`}>
            {TYPE_LABEL[group.type] ?? group.type.toUpperCase()}
          </h2>

          <div className="space-y-3">
            {group.rows.map((row) => {
              const item = row.items
              const isPending = pendingRowId === row.id
              const tier = tierOf(row)
              const rarityClass = RARITY_COLOR[tier] ?? RARITY_COLOR.common
              const isArmItem = item.slot === 'weapon' || item.slot === 'shield'
              const isRingItem = item.slot === 'ring'
              const isSingleSlot = !!item.slot && !isArmItem && !isRingItem
              const btnBase = `${mono.className} text-xs border border-[#8a7f68] text-[#f1e6c8] px-3 py-2 rounded-sm
                disabled:opacity-30 hover:bg-[#8a7f68] hover:text-[#100e0c] transition-colors whitespace-nowrap`
              const hasAffix = row.rolled_crit > 0 || row.rolled_lifesteal > 0

              return (
                <div
                  key={row.id}
                  onClick={sellMode && !row.equipped && !row.locked ? () => toggleRow(row.id) : undefined}
                  className={`rounded-sm border p-4 flex flex-wrap items-center justify-between gap-3
                    ${sellMode && selected.has(row.id)
                      ? 'border-[#e0b050]/70 bg-[#221c10]'
                      : row.equipped ? 'border-[#3d5a45] bg-[#151d17]' : 'border-[#2c261c] bg-[#17140f]'}
                    ${sellMode && !row.equipped && !row.locked ? 'cursor-pointer' : ''}
                    ${sellMode && (row.equipped || row.locked) ? 'opacity-40' : ''}`}
                >
                  <div className="flex items-center gap-3 min-w-0 flex-1 basis-56">
                    {sellMode && (
                      <input
                        type="checkbox"
                        aria-label={`Chọn bán ${item.name}`}
                        checked={selected.has(row.id)}
                        disabled={row.equipped || row.locked}
                        onChange={() => toggleRow(row.id)}
                        onClick={(e) => e.stopPropagation()}
                        className="accent-[#e0b050] w-4 h-4 shrink-0"
                      />
                    )}
                    {item.icon && (
                      <div
                        className={`w-11 h-11 rounded-sm border ${RARITY_BORDER[tier] ?? RARITY_BORDER.common}
                          bg-[#0d0b09] flex items-center justify-center shrink-0`}
                      >
                        <img
                          src={`/items/${item.icon}`}
                          alt=""
                          className="w-8 h-8"
                          style={{ imageRendering: 'pixelated' }}
                        />
                      </div>
                    )}
                    <div className="min-w-0">
                      <p className={rarityClass}>
                        {(item.type === 'weapon' || item.type === 'armor') && (
                          <span className={`${mono.className} block text-[10px] tracking-widest`}>
                            {RARITY_LABEL[tier]?.toUpperCase()}
                          </span>
                        )}
                        {item.name}
                        {row.enchant_level > 0 && (
                          <span className={`${mono.className} text-sm text-[#e0b050]`}> +{row.enchant_level}</span>
                        )}
                        {row.locked && <span className="text-xs"> 🔒</span>}
                        {isUpgrade(row) && (
                          <span className={`${mono.className} ml-1.5 text-[10px] text-[#8fc4a8] border border-[#8fc4a8]/50 rounded-sm px-1`}>
                            ▲ Mạnh hơn
                          </span>
                        )}
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
                          `+${item.bonus_atk + row.rolled_atk} ATK${item.hand === 'two_hand' ? ' · 2 tay' : ''}${item.school === 'magic' ? ' · Phép' : ''}`}
                        {item.type === 'armor' &&
                          [
                            item.bonus_atk + row.rolled_atk ? `+${item.bonus_atk + row.rolled_atk} ATK` : null,
                            item.bonus_def + row.rolled_def ? `+${item.bonus_def + row.rolled_def} DEF` : null,
                            item.bonus_hp + row.rolled_hp ? `+${item.bonus_hp + row.rolled_hp} HP` : null,
                          ]
                            .filter(Boolean)
                            .join(' · ')}
                        {item.type === 'consumable' &&
                          (item.restore_ap > 0 ? `Hồi ${item.restore_ap} AP` : `Hồi ${item.heal_amount} HP`)}
                        {item.type === 'material' && item.sell_price != null && `Bán được ${item.sell_price} vàng`}
                      </p>
                      {hasAffix && (
                        <p className={`${mono.className} text-[11px] text-[#e0b050] mt-0.5`}>
                          {row.rolled_crit > 0 && `+${(row.rolled_crit * 100).toFixed(1)}% Chí mạng`}
                          {row.rolled_crit > 0 && row.rolled_lifesteal > 0 && ' · '}
                          {row.rolled_lifesteal > 0 && `+${(row.rolled_lifesteal * 100).toFixed(1)}% Hút máu`}
                        </p>
                      )}
                      {row.legendary_effect && LEGENDARY_EFFECTS[row.legendary_effect] && (
                        <p className={`${mono.className} text-[11px] text-[#f0c060] mt-0.5`}>
                          ✦ {LEGENDARY_EFFECTS[row.legendary_effect].name}
                          <span className="text-[#a89b7f]"> — {LEGENDARY_EFFECTS[row.legendary_effect].description}</span>
                        </p>
                      )}
                    </div>
                  </div>

                  {sellMode ? (
                    <span className={`${mono.className} text-xs shrink-0 ${row.equipped ? 'text-[#6b6249]' : 'text-[#e0b050]'}`}>
                      {row.equipped ? 'Đang mặc' : row.locked ? 'Đã khóa' : `${sellPriceOf(row)} vàng`}
                    </span>
                  ) : (
                  <div className="ml-auto flex flex-wrap items-center justify-end gap-2 max-w-full">
                    <button
                      onClick={() => toggleLock(row)}
                      disabled={isPending}
                      title={row.locked ? 'Mở khóa' : 'Khóa — không bán được'}
                      aria-label={row.locked ? 'Mở khóa' : 'Khóa'}
                      className={`${mono.className} text-xs border px-2 py-2 rounded-sm disabled:opacity-30 ${
                        row.locked
                          ? 'border-[#e0b050]/70 bg-[#e0b050]/15 text-[#e0b050]'
                          : 'border-[#2c261c] opacity-50 hover:opacity-100 hover:border-[#8a7f68]'
                      }`}
                    >
                      {row.locked ? '🔒 Khóa' : '🔓'}
                    </button>

                    {(item.type === 'weapon' || item.type === 'armor') && (
                      <button
                        onClick={() => setOpenPanel((p) => (p?.rowId === row.id && p.kind === 'enchant' ? null : { rowId: row.id, kind: 'enchant' }))}
                        disabled={row.enchant_level >= 5}
                        className={`${mono.className} text-xs border border-[#e0b050]/50 text-[#e0b050] px-2.5 py-2 rounded-sm disabled:opacity-30 hover:bg-[#e0b050]/10 whitespace-nowrap`}
                      >
                        {row.enchant_level >= 5 ? '🔨 Max' : '🔨 Cường hóa'}
                      </button>
                    )}

                    {item.type === 'material' && item.material_tier != null && (
                      <button
                        onClick={() => setOpenPanel((p) => (p?.rowId === row.id && p.kind === 'convert' ? null : { rowId: row.id, kind: 'convert' }))}
                        className={`${mono.className} text-xs border border-[#8fb4c4]/50 text-[#8fb4c4] px-2.5 py-2 rounded-sm hover:bg-[#8fb4c4]/10 whitespace-nowrap`}
                      >
                        ⇅ Rã / Ghép
                      </button>
                    )}

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

                    {item.type === 'consumable' && (() => {
                      const isApPotion = item.restore_ap > 0
                      const isFull = isApPotion ? localAp >= maxAp : localHp >= totalMaxHp
                      return (
                        <button
                          onClick={() => useItem(row)}
                          disabled={isPending || isFull}
                          className={`${mono.className} text-xs border border-[#3d5a45] text-[#8fc4a8] px-3 py-2 rounded-sm
                            disabled:opacity-30 hover:bg-[#3d5a45] hover:text-[#f1e6c8] transition-colors whitespace-nowrap`}
                        >
                          {isPending ? '…' : isFull ? (isApPotion ? 'AP đầy' : 'HP đầy') : 'Dùng'}
                        </button>
                      )
                    })()}
                  </div>
                  )}

                  {!sellMode && openPanel?.rowId === row.id && openPanel.kind === 'enchant' && (
                    <EnchantPanel
                      row={row}
                      chain={materialChain}
                      countOf={countOf}
                      gold={localGold}
                      pending={isPending}
                      onEnchant={() => enchant(row)}
                    />
                  )}
                  {!sellMode && openPanel?.rowId === row.id && openPanel.kind === 'convert' && (
                    <ConvertPanel
                      row={row}
                      chain={materialChain}
                      gold={localGold}
                      pending={isPending}
                      onConvert={(mode, times) => convert(row, mode, times)}
                    />
                  )}
                  {actionMsg?.rowId === row.id && (
                    <p className={`${mono.className} basis-full text-xs ${actionMsg.ok ? 'text-[#8fc4a8]' : 'text-[#c98787]'}`}>
                      {actionMsg.text}
                    </p>
                  )}
                </div>
              )
            })}
          </div>
        </section>
      ))}

      {sellMode && selected.size > 0 && (
        <div className={`${mono.className} sticky bottom-24 z-10 rounded-sm border border-[#e0b050]/60 bg-[#1a150c]/95 backdrop-blur p-3 flex items-center justify-between gap-3`}>
          <div className="text-xs min-w-0">
            <p className="text-[#f1e6c8]">
              Đã chọn {selected.size} món · <span className="text-[#e0b050]">+{selectedGold} vàng</span>
            </p>
            {confirmSell && selectedHighTier && (
              <p className="text-[#e09595] mt-0.5">Có đồ Sử Thi/Huyền Thoại trong danh sách!</p>
            )}
          </div>
          <button
            onClick={sellSelected}
            disabled={selling}
            className="text-xs border border-[#e0b050] text-[#100e0c] bg-[#e0b050] px-4 py-2 rounded-sm font-semibold
              disabled:opacity-40 hover:bg-[#f0c060] whitespace-nowrap"
          >
            {selling ? 'Đang bán…' : confirmSell ? 'Chắc chắn bán?' : 'Bán'}
          </button>
        </div>
      )}

      {tab === 'craft' && (
      <section>

        {craftResult && (
          <p
            className={`${mono.className} text-xs text-center mb-3 ${
              craftResult.ok
                ? (craftResult.rarity && RARITY_COLOR[craftResult.rarity]) || 'text-[#8fc4a8]'
                : 'text-[#c98787]'
            }`}
          >
            {craftResult.rarity === 'legendary' && '✨ '}
            {craftResult.text}
          </p>
        )}

        {recipes.length === 0 ? (
          <p className={`${mono.className} text-center text-xs text-[#6b6249]`}>
            Chưa có công thức chế tạo nào.
          </p>
        ) : (
          <div className="space-y-3">
            {recipes.map((recipe) => {
              const isPending = pendingRecipeId === recipe.id
              const isEquipment = recipe.resultItem.type === 'weapon' || recipe.resultItem.type === 'armor'
              const isBoosted = isEquipment && !!boosted[recipe.id]
              const cost = isBoosted ? boostCost(recipe.goldCost) : recipe.goldCost
              const canAffordGold = localGold >= cost
              const hasAllMaterials = recipe.ingredients.every((ing) => {
                const have = rows
                  .filter((r) => r.items.id === ing.item.id)
                  .reduce((sum, r) => sum + r.quantity, 0)
                return have >= ing.quantity
              })
              const canCraft = canAffordGold && hasAllMaterials

              return (
                <div key={recipe.id} className="rounded-sm border border-[#2c261c] bg-[#17140f] p-4">
                  <div className="flex items-center justify-between gap-4">
                    <div className="flex items-center gap-3 min-w-0">
                      {recipe.resultItem.icon && (
                        <div
                          className={`w-11 h-11 rounded-sm border ${RARITY_BORDER[recipe.resultItem.rarity] ?? RARITY_BORDER.common}
                            bg-[#0d0b09] flex items-center justify-center shrink-0`}
                        >
                          <img
                            src={`/items/${recipe.resultItem.icon}`}
                            alt=""
                            className="w-8 h-8"
                            style={{ imageRendering: 'pixelated' }}
                          />
                        </div>
                      )}
                      <div>
                        <p className={RARITY_COLOR[recipe.resultItem.rarity] ?? RARITY_COLOR.common}>
                          {recipe.name}
                        </p>
                        <p className={`${mono.className} text-[11px] text-[#8a7f68] mt-1`}>
                          {Math.round(recipe.successRate * 100)}% thành công
                          {cost > 0 && ` · ${cost} vàng`}
                        </p>
                        {isEquipment && (
                          <p className={`${mono.className} text-[11px] text-[#6b6249] mt-0.5`}>
                            Tier ngẫu nhiên
                            {recipe.resultItem.rarity !== 'common' &&
                              ` (tối thiểu ${RARITY_LABEL[recipe.resultItem.rarity]})`}
                            {isBoosted ? ' · Huyền Thoại 5%' : ' · Huyền Thoại 2%'}
                          </p>
                        )}
                      </div>
                    </div>
                    <button
                      onClick={() => craft(recipe)}
                      disabled={!canCraft || isPending}
                      className={`${mono.className} text-xs border border-[#8a7f68] text-[#f1e6c8] px-3 py-2 rounded-sm
                        disabled:opacity-30 hover:bg-[#8a7f68] hover:text-[#100e0c] transition-colors whitespace-nowrap`}
                    >
                      {isPending ? '…' : 'Chế tạo'}
                    </button>
                  </div>
                  {isEquipment && (
                    <label className={`${mono.className} flex items-center gap-2 mt-2 text-[11px] text-[#a89b7f] cursor-pointer`}>
                      <input
                        type="checkbox"
                        checked={isBoosted}
                        onChange={(e) => setBoosted((b) => ({ ...b, [recipe.id]: e.target.checked }))}
                        className="accent-[#e0b050]"
                      />
                      Tăng tỉ lệ tier cao ({boostCost(recipe.goldCost)} vàng thay vì {recipe.goldCost})
                    </label>
                  )}
                  <div className={`${mono.className} text-[11px] mt-2 space-y-0.5`}>
                    {recipe.ingredients.map((ing) => {
                      const have = rows
                        .filter((r) => r.items.id === ing.item.id)
                        .reduce((sum, r) => sum + r.quantity, 0)
                      const enough = have >= ing.quantity
                      return (
                        <p key={ing.item.id} className={enough ? 'text-[#8a7f68]' : 'text-[#c98787]'}>
                          {ing.item.name}: {have} / {ing.quantity}
                        </p>
                      )
                    })}
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </section>
      )}
    </div>
  )
}

function QuickChip({
  children,
  onClick,
  className = 'text-[#a89b7f]',
}: {
  children: React.ReactNode
  onClick: () => void
  className?: string
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`${mono.className} text-[11px] border border-[#2c261c] bg-[#17140f] hover:border-[#8a7f68] rounded-full px-2.5 py-1 ${className}`}
    >
      {children}
    </button>
  )
}

type EnchantCost = {
  out_mat: string
  out_mat_qty: number
  out_mat2: string | null
  out_mat2_qty: number
  out_gold: number
  out_rate: number
}

// Chi phí bước cường hóa kế tiếp lấy từ RPC enchant_cost (cùng công thức server dùng)
function EnchantPanel({
  row,
  chain,
  countOf,
  gold,
  pending,
  onEnchant,
}: {
  row: InventoryRow
  chain: MaterialInfo[]
  countOf: (itemId: string) => number
  gold: number
  pending: boolean
  onEnchant: () => void
}) {
  const next = row.enchant_level + 1
  const [cost, setCost] = useState<EnchantCost | null>(null)

  useEffect(() => {
    let cancelled = false
    createClient()
      .rpc('enchant_cost', { p_item_level: row.items.item_level, p_next_level: next })
      .then(({ data }) => {
        const c = (Array.isArray(data) ? data[0] : data) as EnchantCost | undefined
        if (!cancelled) setCost(c ?? null)
      })
    return () => {
      cancelled = true
    }
  }, [row.items.item_level, next])

  const mat = cost ? chain.find((m) => m.id === cost.out_mat) : null
  const mat2 = cost?.out_mat2 ? chain.find((m) => m.id === cost.out_mat2) : null
  const need = [
    mat && cost ? { m: mat, qty: cost.out_mat_qty } : null,
    mat2 && cost && cost.out_mat2_qty > 0 ? { m: mat2, qty: cost.out_mat2_qty } : null,
  ].filter(Boolean) as { m: MaterialInfo; qty: number }[]
  // Cùng 1 nguyên liệu có thể xuất hiện 2 lần (khi không có bậc trên) → cộng dồn khi kiểm tra
  const enough =
    !!cost &&
    gold >= cost.out_gold &&
    need.every((n) => countOf(n.m.id) >= need.filter((x) => x.m.id === n.m.id).reduce((a, x) => a + x.qty, 0))

  return (
    <div className={`${mono.className} basis-full rounded-sm border border-[#e0b050]/30 bg-[#0d0b09] p-3 text-[11px] space-y-2`}>
      {!cost ? (
        <p className="text-[#6b6249]">Đang tính chi phí…</p>
      ) : (
        <>
          <p className="text-[#f1e6c8]">
            Lên <b className="text-[#e0b050]">+{next}</b> · tỉ lệ{' '}
            <b className={cost.out_rate < 1 ? 'text-[#e09595]' : 'text-[#8fc4a8]'}>{Math.round(cost.out_rate * 100)}%</b>
            {cost.out_rate < 1 && <span className="text-[#8a7f68]"> (thất bại mất nguyên liệu, không tụt cấp)</span>}
          </p>
          <ul className="space-y-0.5">
            {need.map((n, i) => (
              <li key={i} className={countOf(n.m.id) >= n.qty ? 'text-[#a89b7f]' : 'text-[#c98787]'}>
                {n.qty} × {n.m.name} <span className="text-[#6b6249]">(có {countOf(n.m.id)})</span>
              </li>
            ))}
            <li className={gold >= cost.out_gold ? 'text-[#a89b7f]' : 'text-[#c98787]'}>
              {cost.out_gold} vàng <span className="text-[#6b6249]">(có {gold})</span>
            </li>
          </ul>
          <button
            onClick={onEnchant}
            disabled={!enough || pending}
            className="border border-[#e0b050] bg-[#e0b050] text-[#100e0c] font-semibold px-3 py-1.5 rounded-sm disabled:opacity-30"
          >
            {pending ? 'Đang cường hóa…' : `Cường hóa +${next}`}
          </button>
        </>
      )}
    </div>
  )
}

function ConvertPanel({
  row,
  chain,
  gold,
  pending,
  onConvert,
}: {
  row: InventoryRow
  chain: MaterialInfo[]
  gold: number
  pending: boolean
  onConvert: (mode: 'combine' | 'break', times: number) => void
}) {
  const [times, setTimes] = useState(1)
  const idx = chain.findIndex((m) => m.id === row.items.id)
  const up = chain[idx + 1]
  const down = idx > 0 ? chain[idx - 1] : undefined
  const have = row.quantity
  const combineFee = up ? up.sell_price * times : 0
  const breakFee = (row.items.sell_price ?? 0) * times

  return (
    <div className={`${mono.className} basis-full rounded-sm border border-[#8fb4c4]/30 bg-[#0d0b09] p-3 text-[11px] space-y-2`}>
      <label className="flex items-center gap-2 text-[#a89b7f]">
        Số lần
        <input
          type="number"
          min={1}
          value={times}
          onChange={(e) => setTimes(Math.max(1, Math.floor(Number(e.target.value) || 1)))}
          className="w-16 bg-[#17140f] border border-[#2c261c] rounded-sm px-2 py-1 text-[#f1e6c8]"
        />
      </label>
      <div className="flex flex-wrap gap-2">
        {up && (
          <button
            onClick={() => onConvert('combine', times)}
            disabled={pending || have < 3 * times || gold < combineFee}
            className="border border-[#8fb4c4]/60 text-[#8fb4c4] px-3 py-1.5 rounded-sm disabled:opacity-30"
          >
            ⬆ Ghép {3 * times} → {times} {up.name} · {combineFee} vàng
          </button>
        )}
        {down && (
          <button
            onClick={() => onConvert('break', times)}
            disabled={pending || have < times || gold < breakFee}
            className="border border-[#8a7f68] text-[#a89b7f] px-3 py-1.5 rounded-sm disabled:opacity-30"
          >
            ⬇ Rã {times} → {3 * times} {down.name} · {breakFee} vàng
          </button>
        )}
      </div>
      {!up && <p className="text-[#6b6249]">Đây là nguyên liệu cao nhất, chỉ rã được.</p>}
    </div>
  )
}
