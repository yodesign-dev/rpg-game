'use client'

import { useEffect, useState } from 'react'
import { ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/client'
import PortraitCard from '../components/PortraitCard'
import { LEGENDARY_EFFECTS } from '@/lib/legendary-effects'
import { INVENTORY_SELECT, type MaterialInfo } from '@/lib/inventory'


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

// Viền trái của thẻ lưới theo độ hiếm (sáng hơn RARITY_BORDER để nhìn lướt là nhận ra)
const RARITY_ACCENT: Record<string, string> = {
  common: 'border-l-[#7d7a8c]',
  rare: 'border-l-[#5b8fd8]',
  epic: 'border-l-[#a66bd8]',
  legendary: 'border-l-[#e0902a]',
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
// Dòng tiện ích (rolled_extra): nhãn + trọng số điểm — khớp inventory_item_score
const EXTRA_AFFIX: Record<string, { label: (v: number) => string; weight: number }> = {
  pierce: { label: (v) => `Xuyên ${(v * 100).toFixed(1)}% DEF`, weight: 150 },
  double: { label: (v) => `+${(v * 100).toFixed(1)}% Đòn Kép`, weight: 300 },
  dmg_red: { label: (v) => `−${(v * 100).toFixed(1)}% sát thương nhận`, weight: 500 },
  regen: { label: (v) => `Hồi ${(v * 100).toFixed(2)}% HP mỗi lượt`, weight: 800 },
  skill_dmg: { label: (v) => `+${(v * 100).toFixed(1)}% sát thương skill`, weight: 200 },
}

function itemScore(row: InventoryRow) {
  const it = row.items
  return (
    (it.bonus_atk + row.rolled_atk) * 2 +
    (it.bonus_def + row.rolled_def) * 1.5 +
    (it.bonus_hp + row.rolled_hp) * 0.25 +
    (row.rolled_crit + row.rolled_lifesteal) * 400 +
    Object.entries(row.rolled_extra ?? {}).reduce((sum, [k, v]) => sum + (EXTRA_AFFIX[k]?.weight ?? 0) * v, 0) +
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

const TYPE_ORDER = ['weapon', 'armor', 'consumable', 'material']

// Nhóm hiển thị trong tab Túi đồ: trang bị chia theo ô, còn lại theo loại
const GROUPS: { key: string; label: string; icon: string }[] = [
  { key: 'weapon', label: 'Vũ khí', icon: '⚔️' },
  { key: 'shield', label: 'Khiên', icon: '🛡️' },
  { key: 'head', label: 'Mũ', icon: '🪖' },
  { key: 'chest', label: 'Áo', icon: '🎽' },
  { key: 'belt', label: 'Đai', icon: '🎗️' },
  { key: 'boot', label: 'Giày', icon: '👢' },
  { key: 'ring', label: 'Nhẫn', icon: '💍' },
  { key: 'amulet', label: 'Bùa', icon: '📿' },
  { key: 'consumable', label: 'Hồi phục', icon: '🧪' },
  { key: 'material', label: 'Nguyên liệu', icon: '🪨' },
]

function groupOf(item: { type: string; slot: string | null }) {
  return item.type === 'weapon' || item.type === 'armor' ? (item.slot ?? item.type) : item.type
}

const EQUIP_SLOT_LABEL: Record<string, string> = {
  head: 'Đầu',
  l_arm: 'Tay trái',
  r_arm: 'Tay phải',
  both_arms: '2 tay',
  chest: 'Ngực',
  belt: 'Thắt lưng',
  amulet: 'Bùa',
  boot: 'Giày',
  ring_1: 'Nhẫn 1',
  ring_2: 'Nhẫn 2',
}

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
  rolled_extra?: Record<string, number>
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
  resultItem: {
    id: string
    key: string
    name: string
    rarity: string
    icon: string | null
    type: string
    slot?: string | null
    item_level?: number
  }
  ingredients: { item: { id: string; key: string; name: string }; quantity: number }[]
}

export default function InventoryManager({
  characterId,
  characterName,
  classIcon,
  classKey,
  portrait,
  frame,
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
  classKey?: string
  portrait?: string | null
  frame?: string | null
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
  const [groupFilter, setGroupFilter] = useState<string>('all')
  const [showEquipped, setShowEquipped] = useState(true)
  const [detailId, setDetailId] = useState<string | null>(null)
  const [craftFilter, setCraftFilter] = useState<string>('all')
  const [focusId, setFocusId] = useState<string | null>(null)
  const [craftableOnly, setCraftableOnly] = useState(false)
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

  // Tab Trang bị: đồ đang mặc. Tab Túi đồ: mọi món (kể cả đang mặc, có nhãn), lọc theo ô.
  const bagRows = rows.filter((r) => !r.equipped)
  const bagView = rows.filter((r) => showEquipped || !r.equipped)
  const listRows =
    tab === 'equip'
      ? rows.filter((r) => r.equipped)
      : bagView.filter((r) => groupFilter === 'all' || groupOf(r.items) === groupFilter)
  // Lưới tab Túi đồ: xếp theo thứ tự ô (vũ khí → … → nguyên liệu), rồi món mạnh hơn, rồi theo điểm
  const groupIndex = (r: InventoryRow) => GROUPS.findIndex((g) => g.key === groupOf(r.items))
  const byGroupThenScore = (a: InventoryRow, b: InventoryRow) =>
    groupIndex(a) - groupIndex(b) ||
    Number(isUpgrade(b)) - Number(isUpgrade(a)) ||
    itemScore(b) - itemScore(a)
  const wornTiles = listRows.filter((r) => r.equipped).sort(byGroupThenScore)
  const bagTiles = listRows.filter((r) => !r.equipped).sort(byGroupThenScore)
  const detailRow = rows.find((r) => r.id === detailId) ?? null

  const canCraftRecipe = (recipe: Recipe) =>
    localGold >= recipe.goldCost &&
    recipe.ingredients.every(
      (ing) => rows.filter((r) => r.items.id === ing.item.id).reduce((sum, r) => sum + r.quantity, 0) >= ing.quantity
    )
  const craftableCount = recipes.filter(canCraftRecipe).length
  const craftGroupOf = (recipe: Recipe) => groupOf({ type: recipe.resultItem.type, slot: recipe.resultItem.slot ?? null })
  const recipeView = recipes
    .filter((recipe) => craftFilter === 'all' || craftGroupOf(recipe) === craftFilter)
    .filter((recipe) => !craftableOnly || canCraftRecipe(recipe))
    .sort((a, b) => (a.resultItem.item_level ?? 1) - (b.resultItem.item_level ?? 1) || a.goldCost - b.goldCost)

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
        <div className="w-16 h-16 sm:w-[72px] sm:h-[72px] rounded-lg border border-dashed border-[#2a2533]
          flex flex-col items-center justify-center gap-0.5 opacity-50 shrink-0">
          <span className="text-lg">{SLOT_ICON[slotKey]}</span>
          <span className={`${ui.className} text-[10px] text-[#5c5470]`}>{label}</span>
        </div>
      )
    }

    const item = row.items
    const focused = focusId === row.id
    return (
      <button
        type="button"
        onClick={() => setFocusId(focused ? null : row.id)}
        aria-pressed={focused}
        title={`${item.name} [${RARITY_LABEL[tierOf(row)]}]`}
        className={`w-16 h-16 sm:w-[72px] sm:h-[72px] rounded-lg border ${RARITY_BORDER[tierOf(row)] ?? RARITY_BORDER.common}
          bg-[#15121d] flex flex-col items-center justify-center gap-0.5 px-1 shrink-0 transition-shadow
          ${focused ? 'ring-2 ring-[#8fe0b0] ring-offset-2 ring-offset-[#07070a]' : 'hover:brightness-125'}`}
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
          className={`${ui.className} text-[10px] text-center leading-tight line-clamp-2
            ${RARITY_COLOR[tierOf(row)] ?? RARITY_COLOR.common}`}
        >
          {item.name}
        </span>
      </button>
    )
  }

  // Dòng chỉ số gọn cho thẻ lưới: "ATK +80 · Chí mạng +6.6% · Xuyên 12% DEF"
  function statLine(row: InventoryRow) {
    const it = row.items
    if (it.type === 'consumable') return [it.restore_ap > 0 ? `Hồi ${it.restore_ap} AP` : `Hồi ${it.heal_amount} HP`]
    if (it.type === 'material') return [it.sell_price != null ? `Bán ${it.sell_price} vàng` : 'Nguyên liệu']
    const parts: string[] = []
    const atk = it.bonus_atk + row.rolled_atk
    const def = it.bonus_def + row.rolled_def
    const hp = it.bonus_hp + row.rolled_hp
    if (atk) parts.push(`ATK +${atk}`)
    if (def) parts.push(`DEF +${def}`)
    if (hp) parts.push(`HP +${hp}`)
    if (row.rolled_crit > 0) parts.push(`Chí mạng +${(row.rolled_crit * 100).toFixed(1)}%`)
    if (row.rolled_lifesteal > 0) parts.push(`Hút máu +${(row.rolled_lifesteal * 100).toFixed(1)}%`)
    for (const [k, v] of Object.entries(row.rolled_extra ?? {})) if (EXTRA_AFFIX[k]) parts.push(EXTRA_AFFIX[k].label(v))
    return parts
  }

  // Thẻ gọn trong lưới — bấm để mở chi tiết (chế độ bán: bấm để chọn)
  const renderTile = (row: InventoryRow) => {
    const item = row.items
    const tier = tierOf(row)
    const isGear = item.type === 'weapon' || item.type === 'armor'
    const group = GROUPS.find((g) => g.key === groupOf(item))
    const selectable = sellMode && !row.equipped && !row.locked
    const picked = sellMode && selected.has(row.id)
    return (
      <button
        key={row.id}
        type="button"
        onClick={() => (sellMode ? selectable && toggleRow(row.id) : setDetailId(row.id))}
        disabled={sellMode && !selectable}
        className={`${ui.className} relative text-left rounded-xl border border-white/[0.08] border-l-4 p-3 transition-colors
          ${RARITY_ACCENT[isGear ? tier : 'common']}
          ${picked ? 'bg-[#e0b050]/15 border-[#e0b050]/60' : row.equipped ? 'bg-[#8fe0b0]/[0.06]' : 'bg-white/[0.04] hover:bg-white/[0.08]'}
          ${sellMode && !selectable ? 'opacity-40' : ''}`}
      >
        <div className="flex items-start gap-2.5">
          <div
            className={`w-11 h-11 rounded-lg border ${RARITY_BORDER[tier] ?? RARITY_BORDER.common} bg-[#0b0a10]
              flex items-center justify-center shrink-0`}
          >
            {item.icon ? (
              <img src={`/items/${item.icon}`} alt="" className="w-8 h-8" style={{ imageRendering: 'pixelated' }} />
            ) : (
              <span className="text-lg">{group?.icon}</span>
            )}
          </div>
          <div className="min-w-0 flex-1">
            <p className={`text-sm font-semibold leading-snug ${RARITY_COLOR[tier] ?? RARITY_COLOR.common}`}>
              {item.name}
              {row.enchant_level > 0 && <span className="text-[#e0b050]"> +{row.enchant_level}</span>}
              {row.legendary_effect && <span className="text-[#f0c060]"> ✦</span>}
            </p>
            <p className="mt-0.5 text-[11px] uppercase tracking-wider text-[#7d7a8c] leading-tight">
              {isGear ? `${RARITY_LABEL[tier]} · ${group?.label ?? ''}` : group?.label}
              {row.quantity > 1 && ` · ×${row.quantity}`}
            </p>
          </div>
        </div>
        <p className="mt-2 border-t border-white/[0.07] pt-2 text-xs leading-relaxed text-[#c9c4d4]">
          {statLine(row).join(' · ')}
        </p>
        <span className="absolute right-2 top-2 flex gap-1 text-[11px]">
          {row.locked && <span title="Đã khoá">🔒</span>}
          {isUpgrade(row) && <span className="rounded bg-[#8fe0b0]/20 px-1 text-[#c8f5dc]" title="Mạnh hơn đồ đang mặc">▲</span>}
          {picked && <span className="rounded bg-[#e0b050] px-1 text-[#0e0c13]">✓</span>}
        </span>
      </button>
    )
  }

  // Thẻ 1 món đồ — dùng cho danh sách tab Túi đồ và thẻ chi tiết khi bấm ô ở tab Trang bị
  const renderRow = (row: InventoryRow) => {
    const item = row.items
    const isPending = pendingRowId === row.id
    const tier = tierOf(row)
    const rarityClass = RARITY_COLOR[tier] ?? RARITY_COLOR.common
    const isArmItem = item.slot === 'weapon' || item.slot === 'shield'
    const isRingItem = item.slot === 'ring'
    const isSingleSlot = !!item.slot && !isArmItem && !isRingItem
    const btnBase = `${ui.className} text-xs border border-[#8a8499] text-[#f2ede4] px-3 py-2 rounded-lg
      disabled:opacity-30 hover:bg-[#8a8499] hover:text-[#0e0c13] transition-colors whitespace-nowrap`
    const hasAffix = row.rolled_crit > 0 || row.rolled_lifesteal > 0

    return (
      <div
        key={row.id}
        onClick={sellMode && !row.equipped && !row.locked ? () => toggleRow(row.id) : undefined}
        className={`rounded-2xl border p-4 flex flex-wrap items-center justify-between gap-3
          ${sellMode && selected.has(row.id)
            ? 'border-[#e0b050]/70 bg-[#221c10]'
            : row.equipped ? 'border-[#8fe0b0]/45 bg-[#8fe0b0]/[0.07]' : 'border-white/[0.09] bg-white/[0.045]'}
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
              className={`w-11 h-11 rounded-lg border ${RARITY_BORDER[tier] ?? RARITY_BORDER.common}
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
          <div className="min-w-0">
            <p className={rarityClass}>
              {(item.type === 'weapon' || item.type === 'armor') && (
                <span className={`${ui.className} block text-xs tracking-widest`}>
                  {RARITY_LABEL[tier]?.toUpperCase()}
                </span>
              )}
              {item.name}
              {row.enchant_level > 0 && (
                <span className={`${ui.className} text-sm text-[#e0b050]`}> +{row.enchant_level}</span>
              )}
              {row.locked && <span className="text-xs"> 🔒</span>}
              {row.equipped && (
                <span className={`${ui.className} ml-1.5 whitespace-nowrap rounded-lg border border-[#8fe0b0]/60 bg-[#8fe0b0]/15 px-1.5 text-xs text-[#c8f5dc]`}>
                  ✓ Đang mặc{row.equip_slot && EQUIP_SLOT_LABEL[row.equip_slot] ? ` · ${EQUIP_SLOT_LABEL[row.equip_slot]}` : ''}
                </span>
              )}
              {isUpgrade(row) && (
                <span className={`${ui.className} ml-1.5 text-xs text-[#8fe0b0] border border-[#8fe0b0]/50 rounded-lg px-1`}>
                  ▲ Mạnh hơn
                </span>
              )}
              {row.quantity > 1 && (
                <span className={`${ui.className} text-xs text-[#5c5470]`}> ×{row.quantity}</span>
              )}
            </p>
            {item.description && (
              <p className={`${ui.className} text-xs text-[#8a8499] mt-1`}>
                {item.description}
              </p>
            )}
            <p className={`${ui.className} text-xs text-[#5c5470] mt-1`}>
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
              <p className={`${ui.className} text-xs text-[#e0b050] mt-0.5`}>
                {row.rolled_crit > 0 && `+${(row.rolled_crit * 100).toFixed(1)}% Chí mạng`}
                {row.rolled_crit > 0 && row.rolled_lifesteal > 0 && ' · '}
                {row.rolled_lifesteal > 0 && `+${(row.rolled_lifesteal * 100).toFixed(1)}% Hút máu`}
              </p>
            )}
            {Object.keys(row.rolled_extra ?? {}).length > 0 && (
              <p className={`${ui.className} text-xs text-[#8fc4e0] mt-0.5`}>
                {Object.entries(row.rolled_extra ?? {})
                  .filter(([k]) => EXTRA_AFFIX[k])
                  .map(([k, v]) => EXTRA_AFFIX[k].label(v))
                  .join(' · ')}
              </p>
            )}
            {row.legendary_effect && LEGENDARY_EFFECTS[row.legendary_effect] && (
              <p className={`${ui.className} text-xs text-[#f0c060] mt-0.5`}>
                ✦ {LEGENDARY_EFFECTS[row.legendary_effect].name}
                <span className="text-[#a29fb3]"> — {LEGENDARY_EFFECTS[row.legendary_effect].description}</span>
              </p>
            )}
          </div>
        </div>

        {sellMode ? (
          <span className={`${ui.className} text-xs shrink-0 ${row.equipped ? 'text-[#5c5470]' : 'text-[#e0b050]'}`}>
            {row.equipped ? 'Đang mặc' : row.locked ? 'Đã khóa' : `${sellPriceOf(row)} vàng`}
          </span>
        ) : (
        <div className="ml-auto flex flex-wrap items-center justify-end gap-2 max-w-full">
          <button
            onClick={() => toggleLock(row)}
            disabled={isPending}
            title={row.locked ? 'Mở khóa' : 'Khóa — không bán được'}
            aria-label={row.locked ? 'Mở khóa' : 'Khóa'}
            className={`${ui.className} text-xs border px-2 py-2 rounded-lg disabled:opacity-30 ${
              row.locked
                ? 'border-[#e0b050]/70 bg-[#e0b050]/15 text-[#e0b050]'
                : 'border-[#2a2533] opacity-50 hover:opacity-100 hover:border-[#8a8499]'
            }`}
          >
            {row.locked ? '🔒 Khóa' : '🔓'}
          </button>

          {(item.type === 'weapon' || item.type === 'armor') && (
            <button
              onClick={() => setOpenPanel((p) => (p?.rowId === row.id && p.kind === 'enchant' ? null : { rowId: row.id, kind: 'enchant' }))}
              disabled={row.enchant_level >= 5}
              className={`${ui.className} text-xs border border-[#e0b050]/50 text-[#e0b050] px-2.5 py-2 rounded-lg disabled:opacity-30 hover:bg-[#e0b050]/10 whitespace-nowrap`}
            >
              {row.enchant_level >= 5 ? '🔨 Max' : '🔨 Cường hóa'}
            </button>
          )}

          {item.type === 'material' && item.material_tier != null && (
            <button
              onClick={() => setOpenPanel((p) => (p?.rowId === row.id && p.kind === 'convert' ? null : { rowId: row.id, kind: 'convert' }))}
              className={`${ui.className} text-xs border border-[#8fb4c4]/50 text-[#8fb4c4] px-2.5 py-2 rounded-lg hover:bg-[#8fb4c4]/10 whitespace-nowrap`}
            >
              ⇅ Rã / Ghép
            </button>
          )}

          {row.equipped && (
            <button
              onClick={() => unequip(row)}
              disabled={isPending}
              className={`${ui.className} text-xs border border-[#8c3f3f] text-[#e09595] px-3 py-2 rounded-lg
                disabled:opacity-30 hover:bg-[#8c3f3f] hover:text-[#f2ede4] transition-colors whitespace-nowrap`}
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
                className={`${ui.className} text-xs border border-[#3d5a45] text-[#8fe0b0] px-3 py-2 rounded-lg
                  disabled:opacity-30 hover:bg-[#3d5a45] hover:text-[#f2ede4] transition-colors whitespace-nowrap`}
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
          <p className={`${ui.className} basis-full text-xs ${actionMsg.ok ? 'text-[#8fe0b0]' : 'text-[#e09595]'}`}>
            {actionMsg.text}
          </p>
        )}
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
        className={`${ui.className} sticky top-0 z-20 -mx-4 px-4 pt-2 bg-[#07070a]/90 backdrop-blur-md border-b border-white/10`}
      >
        <div className="flex items-center justify-center gap-4 text-sm text-[#a29fb3] mb-1">
          <span className="text-[#e0b050]">💰 {localGold}</span>
          <span>❤️ {localHp}/{totalMaxHp}</span>
          <span className="text-[#6b8a5a]">⚡ {localAp}/{maxAp}</span>
        </div>
        <div role="tablist" className="flex">
          {TABS.map((t) => (
            <button
              key={t.key}
              role="tab"
              aria-selected={tab === t.key}
              onClick={() => setTab(t.key)}
              className={`flex-1 -mb-px border-b-2 px-1 py-3 text-sm font-medium whitespace-nowrap transition-colors outline-none focus-visible:ring-1 focus-visible:ring-[#8a8499] ${
                tab === t.key ? 'text-[#8fe0b0] border-[#8fe0b0]' : 'text-[#a29fb3] border-transparent hover:text-white'
              }`}
            >
              {t.label}
              {t.badge ? <span className="ml-1 text-[#7d7a8c]">{t.badge}</span> : null}
            </button>
          ))}
        </div>
      </div>

      {error && (
        <p className={`${ui.className} text-xs text-[#e09595] text-center`}>{error}</p>
      )}

      {tab === 'equip' && (
        <div className={`${ui.className} flex items-center justify-between gap-3`}>
          <span className="text-xs text-[#5c5470]">
            {upgradeCount ? `Có ${upgradeCount} món trong túi mạnh hơn đồ đang mặc` : 'Đang mặc đồ tốt nhất trong túi'}
          </span>
          <button
              onClick={autoEquip}
              disabled={pendingRowId === 'auto'}
              className="text-xs border border-[#8fe0b0]/60 text-[#8fe0b0] px-3 py-2 rounded-lg hover:bg-[#8fe0b0]/10 disabled:opacity-40 whitespace-nowrap"
            >
              {pendingRowId === 'auto' ? '…' : `⚡ Tự mặc đồ tốt nhất${upgradeCount ? ` (${upgradeCount})` : ''}`}
            </button>
        </div>
      )}
      {tab === 'equip' && autoMsg && <p className={`${ui.className} text-xs text-[#8fe0b0]`}>{autoMsg}</p>}

      {tab === 'equip' && (
      // Màn rộng: paper doll bên trái, chi tiết món đang chọn bên phải
      <div className="grid gap-4 md:grid-cols-2 md:items-start">
      <section>
        <div className="rounded-2xl border border-white/[0.09] bg-white/[0.03] p-4 sm:p-5">
          {/* max-w-md: trên màn rộng không để 2 cột ô trang bị dạt ra 2 mép */}
          <div className="mx-auto max-w-md flex items-stretch justify-center gap-2 sm:gap-4">
            <div className="flex flex-col gap-2">
              {LEFT_SLOTS.map((s) => (
                <SlotBox key={s.key} slotKey={s.key} label={s.label} />
              ))}
            </div>

            <div className="flex-1 flex flex-col items-center justify-center gap-2 min-w-0">
              {classKey ? (
                <PortraitCard classKey={classKey} portrait={portrait} frame={frame} className="w-24 sm:w-28" />
              ) : (
                <div className="text-5xl sm:text-6xl">{classIcon}</div>
              )}
              <p className={`${ui.className} text-xs text-[#f2ede4] text-center truncate max-w-full`}>
                {characterName}
              </p>
              <div className="w-full max-w-[140px] h-1.5 bg-[#2a2533] rounded-full overflow-hidden">
                <div
                  className="h-full bg-[#8fe0b0]"
                  style={{ width: `${Math.min(100, Math.round((localHp / totalMaxHp) * 100))}%` }}
                />
              </div>
              <p className={`${ui.className} text-xs text-[#8a8499]`}>
                HP {localHp} / {totalMaxHp}
              </p>
              <p className={`${ui.className} text-xs text-[#6b8a5a]`}>
                AP {localAp} / {maxAp}
              </p>
            </div>

            <div className="flex flex-col gap-2">
              {RIGHT_SLOTS.map((s) => (
                <SlotBox key={s.key} slotKey={s.key} label={s.label} />
              ))}
            </div>
          </div>

          <div className={`${ui.className} mx-auto max-w-md mt-4 pt-3 border-t border-[#2a2533] flex items-center justify-around text-xs text-[#a29fb3]`}>
            <span>⚔️ {totalAtk}</span>
            <span>🛡️ {totalDef}</span>
            <span>💨 {baseSpd}</span>
          </div>
        </div>
      </section>
      {listRows.length > 0 && (() => {
        const focusRow = rows.find((r) => r.id === focusId && r.equipped)
        return focusRow ? (
          renderRow(focusRow)
        ) : (
          <p className={`${ui.className} rounded-2xl border border-dashed border-white/10 p-6 text-center text-xs text-[#7d7a8c]`}>
            Chạm vào một ô trang bị để xem chi tiết, cường hoá hoặc gỡ.
          </p>
        )
      })()}
      </div>
      )}

      {tab === 'equip' && listRows.length === 0 && (
        <p className={`${ui.className} text-center text-xs text-[#5c5470]`}>
          Chưa mặc món nào. Vào tab Túi đồ để trang bị.
        </p>
      )}

      {tab === 'bag' && bagRows.length === 0 && (
        <p className={`${ui.className} text-center text-xs text-[#5c5470]`}>
          Túi đồ trống. Đi thám hiểm hoặc đánh dungeon để nhặt đồ.
        </p>
      )}

      {tab === 'bag' && rows.length > 0 && (
        <div className={`${ui.className} space-y-2`}>
          <div className="-mx-4 px-4 flex gap-1.5 overflow-x-auto pb-1 [scrollbar-width:none]">
            {[{ key: 'all', label: 'Tất cả', icon: '' }, ...GROUPS].map((g) => {
              const n = g.key === 'all' ? bagView.length : bagView.filter((r) => groupOf(r.items) === g.key).length
              if (n === 0 && g.key !== 'all') return null
              const on = groupFilter === g.key
              return (
                <button
                  key={g.key}
                  onClick={() => setGroupFilter(g.key)}
                  className={`shrink-0 rounded-full border px-3 py-1.5 text-xs whitespace-nowrap transition-colors ${
                    on
                      ? 'border-[#8fe0b0]/60 bg-[#8fe0b0]/15 text-[#c8f5dc]'
                      : 'border-white/10 text-[#a29fb3] hover:text-white'
                  }`}
                >
                  {g.icon && <span aria-hidden>{g.icon} </span>}
                  {g.label} <span className="text-[#7d7a8c]">{n}</span>
                </button>
              )
            })}
          </div>
          <label className="flex items-center gap-2 text-xs text-[#a29fb3] cursor-pointer w-fit">
            <input
              type="checkbox"
              checked={showEquipped}
              onChange={(e) => setShowEquipped(e.target.checked)}
              className="accent-[#8fe0b0]"
            />
            Hiện đồ đang mặc
          </label>
        </div>
      )}

      {tab === 'bag' && bagRows.length > 0 && (
        <div className={`${ui.className} space-y-3`}>
          <div className="flex items-center justify-between gap-3">
            {!sellMode ? (
              <button
              onClick={autoEquip}
              disabled={pendingRowId === 'auto'}
              className="text-xs border border-[#8fe0b0]/60 text-[#8fe0b0] px-3 py-2 rounded-lg hover:bg-[#8fe0b0]/10 disabled:opacity-40 whitespace-nowrap"
            >
              {pendingRowId === 'auto' ? '…' : `⚡ Tự mặc đồ tốt nhất${upgradeCount ? ` (${upgradeCount})` : ''}`}
            </button>
            ) : (
              <span className="text-xs text-[#5c5470]">Chọn nhiều món để bán một lần</span>
            )}
            <button
              onClick={() => (sellMode ? exitSellMode() : (setSellMode(true), setSellResult(null)))}
              className={`text-xs border px-3 py-2 rounded-lg transition-colors ${
                sellMode
                  ? 'border-[#8a8499] text-[#f2ede4] bg-[#2a2533]'
                  : 'border-[#e0b050]/60 text-[#e0b050] hover:bg-[#e0b050]/10'
              }`}
            >
              {sellMode ? 'Xong' : '💰 Bán đồ'}
            </button>
          </div>

          {sellResult && <p className="text-xs text-[#8fe0b0]">{sellResult}</p>}
          {autoMsg && <p className="text-xs text-[#8fe0b0]">{autoMsg}</p>}

          {sellMode && (
            <div className="rounded-lg border border-[#2a2533] bg-[#0b0a10] p-3 space-y-2">
              <p className="text-xs text-[#8a8499]">
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

      {tab === 'bag' && (
        <>
          {wornTiles.length > 0 && (
            <section>
              <h2 className={`${ui.className} mb-3 text-xs font-semibold tracking-[2px] text-[#a29fb3]`}>
                ĐANG MẶC <span className="font-normal tracking-normal text-[#7d7a8c]">{wornTiles.length}</span>
              </h2>
              <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-3 lg:grid-cols-5">{wornTiles.map(renderTile)}</div>
            </section>
          )}
          {bagTiles.length > 0 && (
            <section>
              <h2 className={`${ui.className} mb-3 text-xs font-semibold tracking-[2px] text-[#a29fb3]`}>
                TRONG TÚI <span className="font-normal tracking-normal text-[#7d7a8c]">{bagTiles.length}</span>
              </h2>
              <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-3 lg:grid-cols-5">{bagTiles.map(renderTile)}</div>
            </section>
          )}
        </>
      )}

      {/* Chi tiết 1 món: đủ nút trang bị / cường hoá / khoá / dùng */}
      {tab === 'bag' && detailRow && !sellMode && (
        <div className="fixed inset-0 z-40 flex items-end sm:items-center justify-center p-3" role="dialog" aria-modal="true">
          <button type="button" aria-label="Đóng" onClick={() => setDetailId(null)} className="absolute inset-0 bg-black/60" />
          <div className="relative w-full max-w-lg max-h-[85vh] overflow-y-auto rounded-2xl border border-white/10 bg-[#110f17] p-2 shadow-2xl">
            <button
              type="button"
              onClick={() => setDetailId(null)}
              aria-label="Đóng"
              className="absolute right-3 top-3 z-10 h-8 w-8 rounded-full bg-white/10 text-[#c9c4d4] hover:bg-white/20"
            >
              ✕
            </button>
            {renderRow(detailRow)}
          </div>
        </div>
      )}

      {sellMode && selected.size > 0 && (
        <div className={`${ui.className} sticky bottom-24 z-10 rounded-lg border border-[#e0b050]/60 bg-[#1a150c]/95 backdrop-blur p-3 flex items-center justify-between gap-3`}>
          <div className="text-xs min-w-0">
            <p className="text-[#f2ede4]">
              Đã chọn {selected.size} món · <span className="text-[#e0b050]">+{selectedGold} vàng</span>
            </p>
            {confirmSell && selectedHighTier && (
              <p className="text-[#e09595] mt-0.5">Có đồ Sử Thi/Huyền Thoại trong danh sách!</p>
            )}
          </div>
          <button
            onClick={sellSelected}
            disabled={selling}
            className="text-xs border border-[#e0b050] text-[#0e0c13] bg-[#e0b050] px-4 py-2 rounded-lg font-semibold
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
            className={`${ui.className} text-xs text-center mb-3 ${
              craftResult.ok
                ? (craftResult.rarity && RARITY_COLOR[craftResult.rarity]) || 'text-[#8fe0b0]'
                : 'text-[#e09595]'
            }`}
          >
            {craftResult.rarity === 'legendary' && '✨ '}
            {craftResult.text}
          </p>
        )}

        {recipes.length > 0 && (
          <div className={`${ui.className} space-y-2 mb-4`}>
            <div className="-mx-4 px-4 flex gap-1.5 overflow-x-auto pb-1 [scrollbar-width:none]">
              {[{ key: 'all', label: 'Tất cả', icon: '' }, ...GROUPS].map((g) => {
                const n = g.key === 'all' ? recipes.length : recipes.filter((rc) => craftGroupOf(rc) === g.key).length
                if (n === 0 && g.key !== 'all') return null
                const on = craftFilter === g.key
                return (
                  <button
                    key={g.key}
                    onClick={() => setCraftFilter(g.key)}
                    className={`shrink-0 rounded-full border px-3 py-1.5 text-xs whitespace-nowrap transition-colors ${
                      on
                        ? 'border-[#8fe0b0]/60 bg-[#8fe0b0]/15 text-[#c8f5dc]'
                        : 'border-white/10 text-[#a29fb3] hover:text-white'
                    }`}
                  >
                    {g.icon && <span aria-hidden>{g.icon} </span>}
                    {g.label} <span className="text-[#7d7a8c]">{n}</span>
                  </button>
                )
              })}
            </div>
            <label className="flex items-center gap-2 text-xs text-[#a29fb3] cursor-pointer w-fit">
              <input
                type="checkbox"
                checked={craftableOnly}
                onChange={(e) => setCraftableOnly(e.target.checked)}
                className="accent-[#8fe0b0]"
              />
              Chỉ hiện món chế được ngay ({craftableCount})
            </label>
          </div>
        )}

        {recipeView.length === 0 ? (
          <p className={`${ui.className} text-center text-xs text-[#7d7a8c]`}>
            {recipes.length === 0 ? 'Chưa có công thức chế tạo nào.' : 'Không có công thức nào khớp bộ lọc.'}
          </p>
        ) : (
          <div className="space-y-3">
            {recipeView.map((recipe) => {
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
                <div key={recipe.id} className="rounded-2xl border border-white/[0.09] bg-white/[0.045] p-4">
                  <div className="flex items-center justify-between gap-4">
                    <div className="flex items-center gap-3 min-w-0">
                      {recipe.resultItem.icon && (
                        <div
                          className={`w-11 h-11 rounded-lg border ${RARITY_BORDER[recipe.resultItem.rarity] ?? RARITY_BORDER.common}
                            bg-[#0b0a10] flex items-center justify-center shrink-0`}
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
                        <p className={`${ui.className} text-xs text-[#8a8499] mt-1`}>
                          {recipe.resultItem.item_level && recipe.resultItem.item_level > 1
                            ? `Lv${recipe.resultItem.item_level} · `
                            : ''}
                          {Math.round(recipe.successRate * 100)}% thành công
                          {cost > 0 && ` · ${cost} vàng`}
                        </p>
                        {isEquipment && (
                          <p className={`${ui.className} text-xs text-[#5c5470] mt-0.5`}>
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
                      className={`${ui.className} text-xs border border-[#8a8499] text-[#f2ede4] px-3 py-2 rounded-lg
                        disabled:opacity-30 hover:bg-[#8a8499] hover:text-[#0e0c13] transition-colors whitespace-nowrap`}
                    >
                      {isPending ? '…' : 'Chế tạo'}
                    </button>
                  </div>
                  {isEquipment && (
                    <label className={`${ui.className} flex items-center gap-2 mt-2 text-xs text-[#a29fb3] cursor-pointer`}>
                      <input
                        type="checkbox"
                        checked={isBoosted}
                        onChange={(e) => setBoosted((b) => ({ ...b, [recipe.id]: e.target.checked }))}
                        className="accent-[#e0b050]"
                      />
                      Tăng tỉ lệ tier cao ({boostCost(recipe.goldCost)} vàng thay vì {recipe.goldCost})
                    </label>
                  )}
                  <div className={`${ui.className} text-xs mt-2 space-y-0.5`}>
                    {recipe.ingredients.map((ing) => {
                      const have = rows
                        .filter((r) => r.items.id === ing.item.id)
                        .reduce((sum, r) => sum + r.quantity, 0)
                      const enough = have >= ing.quantity
                      return (
                        <p key={ing.item.id} className={enough ? 'text-[#8a8499]' : 'text-[#e09595]'}>
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
  className = 'text-[#a29fb3]',
}: {
  children: React.ReactNode
  onClick: () => void
  className?: string
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`${ui.className} text-xs border border-[#2a2533] bg-[#15121d] hover:border-[#8a8499] rounded-full px-2.5 py-1 ${className}`}
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
    <div className={`${ui.className} basis-full rounded-lg border border-[#e0b050]/30 bg-[#0b0a10] p-3 text-xs space-y-2`}>
      {!cost ? (
        <p className="text-[#5c5470]">Đang tính chi phí…</p>
      ) : (
        <>
          <p className="text-[#f2ede4]">
            Lên <b className="text-[#e0b050]">+{next}</b> · tỉ lệ{' '}
            <b className={cost.out_rate < 1 ? 'text-[#e09595]' : 'text-[#8fe0b0]'}>{Math.round(cost.out_rate * 100)}%</b>
            {cost.out_rate < 1 && <span className="text-[#8a8499]"> (thất bại mất nguyên liệu, không tụt cấp)</span>}
          </p>
          <ul className="space-y-0.5">
            {need.map((n, i) => (
              <li key={i} className={countOf(n.m.id) >= n.qty ? 'text-[#a29fb3]' : 'text-[#e09595]'}>
                {n.qty} × {n.m.name} <span className="text-[#5c5470]">(có {countOf(n.m.id)})</span>
              </li>
            ))}
            <li className={gold >= cost.out_gold ? 'text-[#a29fb3]' : 'text-[#e09595]'}>
              {cost.out_gold} vàng <span className="text-[#5c5470]">(có {gold})</span>
            </li>
          </ul>
          <button
            onClick={onEnchant}
            disabled={!enough || pending}
            className="border border-[#e0b050] bg-[#e0b050] text-[#0e0c13] font-semibold px-3 py-1.5 rounded-lg disabled:opacity-30"
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
    <div className={`${ui.className} basis-full rounded-lg border border-[#8fb4c4]/30 bg-[#0b0a10] p-3 text-xs space-y-2`}>
      <label className="flex items-center gap-2 text-[#a29fb3]">
        Số lần
        <input
          type="number"
          min={1}
          value={times}
          onChange={(e) => setTimes(Math.max(1, Math.floor(Number(e.target.value) || 1)))}
          className="w-16 bg-[#15121d] border border-[#2a2533] rounded-lg px-2 py-1 text-[#f2ede4]"
        />
      </label>
      <div className="flex flex-wrap gap-2">
        {up && (
          <button
            onClick={() => onConvert('combine', times)}
            disabled={pending || have < 3 * times || gold < combineFee}
            className="border border-[#8fb4c4]/60 text-[#8fb4c4] px-3 py-1.5 rounded-lg disabled:opacity-30"
          >
            ⬆ Ghép {3 * times} → {times} {up.name} · {combineFee} vàng
          </button>
        )}
        {down && (
          <button
            onClick={() => onConvert('break', times)}
            disabled={pending || have < times || gold < breakFee}
            className="border border-[#8a8499] text-[#a29fb3] px-3 py-1.5 rounded-lg disabled:opacity-30"
          >
            ⬇ Rã {times} → {3 * times} {down.name} · {breakFee} vàng
          </button>
        )}
      </div>
      {!up && <p className="text-[#5c5470]">Đây là nguyên liệu cao nhất, chỉ rã được.</p>}
    </div>
  )
}
