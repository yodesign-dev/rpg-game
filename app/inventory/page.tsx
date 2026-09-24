import { redirect } from 'next/navigation'
import { ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/server'
import { applyRegen } from '@/lib/regen'
import { getCharacterStats } from '@/lib/character-stats'
import { INVENTORY_SELECT, type MaterialInfo } from '@/lib/inventory'
import GlassPage from '../GlassPage'
import InventoryManager, { type InventoryTab } from './InventoryManager'


const TABS: InventoryTab[] = ['equip', 'bag', 'craft']

export default async function InventoryPage({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string }>
}) {
  const { tab } = await searchParams
  const initialTab = TABS.includes(tab as InventoryTab) ? (tab as InventoryTab) : 'bag'

  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: character } = await supabase
    .from('characters')
    .select('*, classes(*)')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (!character) redirect('/create-character')

  const [
    { data: inventory, error: inventoryError },
    { data: recipesRaw },
    { data: ingredientsRaw },
    { currentAp, currentHp: regenHp },
    stats,
    { data: chainRaw },
  ] = await Promise.all([
    supabase
      .from('inventory')
      .select(INVENTORY_SELECT)
      .eq('character_id', character.id),
    supabase
      .from('recipes')
      .select('id, key, name, gold_cost, success_rate, description, result_item:items(id, key, name, rarity, icon, type)'),
    supabase
      .from('recipe_ingredients')
      .select('recipe_id, quantity, item:items(id, key, name)'),
    applyRegen(supabase, character),
    getCharacterStats(supabase, character.id),
    supabase
      .from('items')
      .select('id, key, name, icon, material_tier, sell_price')
      .not('material_tier', 'is', null)
      .order('material_tier'),
  ])

  const recipes = (recipesRaw ?? []).map((r: any) => ({
    id: r.id,
    name: r.name,
    goldCost: r.gold_cost,
    successRate: r.success_rate,
    description: r.description,
    resultItem: r.result_item,
    ingredients: (ingredientsRaw ?? [])
      .filter((ing: any) => ing.recipe_id === r.id)
      .map((ing: any) => ({ item: ing.item, quantity: ing.quantity })),
  }))

  const cls = character.classes as { icon: string | null }
  // base* = class + cấp + điểm chỉ số, chưa cộng trang bị — InventoryManager
  // tự cộng thêm phản ứng theo state trang bị hiện tại (kể cả affix roll) để
  // cập nhật ngay khi mặc/gỡ đồ mà không cần tải lại trang.
  const { baseMaxHp, baseAtk, baseDef, baseSpd } = stats
  const currentHp = Math.min(stats.maxHp, regenHp ?? stats.maxHp)

  return (
    <GlassPage title="Túi Đồ">
      {inventoryError && (
        <p className={`${ui.className} text-xs text-[#e09595] text-center mb-6`}>
          Không tải được túi đồ: {inventoryError.message}
        </p>
      )}

      <InventoryManager
        characterId={character.id}
        characterName={character.name}
        classIcon={cls.icon}
        items={(inventory as any) ?? []}
        currentHp={currentHp}
        baseMaxHp={baseMaxHp}
        baseAtk={baseAtk}
        baseDef={baseDef}
        baseSpd={baseSpd}
        gold={character.gold}
        currentAp={currentAp}
        maxAp={character.max_ap}
        recipes={recipes}
        initialTab={initialTab}
        materialChain={(chainRaw ?? []) as MaterialInfo[]}
      />
    </GlassPage>
  )
}
