import { redirect } from 'next/navigation'
import Link from 'next/link'
import { Cinzel, JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/server'
import { applyApRegen } from '@/lib/ap-regen'
import { getCharacterStats } from '@/lib/character-stats'
import BottomNav from '../BottomNav'
import InventoryManager from './InventoryManager'

const display = Cinzel({ subsets: ['latin'], weight: ['500', '700'] })
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

export default async function InventoryPage() {
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
    { currentAp },
    stats,
  ] = await Promise.all([
    supabase
      .from('inventory')
      .select('id, quantity, equipped, equip_slot, rolled_atk, rolled_def, rolled_hp, rolled_crit, rolled_lifesteal, items(*)')
      .eq('character_id', character.id),
    supabase
      .from('recipes')
      .select('id, key, name, gold_cost, success_rate, description, result_item:items(id, key, name, rarity, icon)'),
    supabase
      .from('recipe_ingredients')
      .select('recipe_id, quantity, item:items(id, key, name)'),
    applyApRegen(supabase, character),
    getCharacterStats(supabase, character.id),
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
  const currentHp = character.current_hp ?? stats.maxHp

  return (
    <main className="min-h-screen bg-[#100e0c] text-[#ece3d0] px-6 pt-16 pb-28">
      <div className="mx-auto max-w-2xl">
        <div className="mb-8">
          <Link href="/" className={`${mono.className} text-xs text-[#8a7f68] hover:text-[#a89b7f]`}>
            ← Về nhân vật
          </Link>
        </div>

        <header className="text-center mb-10">
          <h1 className={`${display.className} text-3xl text-[#f1e6c8]`}>Túi Đồ</h1>
          <p className={`${mono.className} text-xs text-[#8a7f68] mt-2`}>
            {character.gold} vàng
          </p>
        </header>

        {inventoryError && (
          <p className={`${mono.className} text-xs text-[#c98787] text-center mb-6`}>
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
        />
      </div>
      <BottomNav />
    </main>
  )
}
