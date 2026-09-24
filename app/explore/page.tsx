import { ui } from '@/app/fonts'
import { getCurrentCharacter } from '@/lib/current-character'
import { applyRegen } from '@/lib/regen'
import { getCharacterStats } from '@/lib/character-stats'
import GlassPage from '../GlassPage'
import ExploreManager, { type Zone } from './ExploreManager'
import SupplyBar from '../components/SupplyBar'
import { getSupplies } from '@/lib/supplies'


export default async function ExplorePage() {
  const { supabase, character } = await getCurrentCharacter()

  const [regen, stats, { data: zonesRaw, error: zonesError }, { data: dropsRaw }, supplies] = await Promise.all([
    applyRegen(supabase, character),
    getCharacterStats(supabase, character.id),
    supabase
      .from('zones')
      .select('id, key, name, icon, description, min_level, max_level, ap_cost, zone_enemies(name, level, is_boss)')
      .order('sort_order'),
    supabase.from('zone_drops').select('zone_id, boss_only, item:items(key, name, icon, rarity)'),
    getSupplies(supabase, character.id),
  ])

  type EnemyRow = { name: string; level: number; is_boss: boolean }
  type DropRow = {
    zone_id: string
    boss_only: boolean
    item: { key: string; name: string; icon: string | null; rarity: string }
  }

  const drops = (dropsRaw ?? []) as unknown as DropRow[]
  const zones: Zone[] = (zonesRaw ?? []).map((z) => {
    const enemies = (z.zone_enemies ?? []) as EnemyRow[]
    return {
      id: z.id,
      name: z.name,
      icon: z.icon,
      description: z.description,
      minLevel: z.min_level,
      maxLevel: z.max_level,
      apCost: z.ap_cost,
      enemies: [...enemies].sort((a, b) => Number(a.is_boss) - Number(b.is_boss) || a.level - b.level),
      drops: drops.filter((d) => d.zone_id === z.id).map((d) => ({ ...d.item, bossOnly: d.boss_only })),
    }
  })

  return (
    <GlassPage
      back
      title="Thám Hiểm"
      subtitle="Mỗi 10 trận tốn 1 vé AP của vùng. Gục ngã: mất 10% vàng đang cầm và 15% EXP của cấp hiện tại."
    >
      {(zonesError || zones.length === 0) && (
        <p className={`${ui.className} text-sm text-[#e09595] mb-4`}>
          Không tải được danh sách vùng{zonesError ? `: ${zonesError.message}` : ''}.
        </p>
      )}

      <SupplyBar
        characterId={character.id}
        autoPotion={character.auto_potion ?? true}
        potionCount={supplies.potionCount}
        buffs={supplies.buffs}
      />

      <ExploreManager
        characterId={character.id}
        level={character.level}
        zones={zones}
        currentHp={Math.min(stats.maxHp, regen.currentHp ?? stats.maxHp)}
        maxHp={stats.maxHp}
        currentAp={regen.currentAp}
        maxAp={character.max_ap}
      />
    </GlassPage>
  )
}
