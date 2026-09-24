import { applyRegen } from '@/lib/regen'
import { getCharacterStats } from '@/lib/character-stats'
import { getCurrentCharacter } from '@/lib/current-character'
import GlassPage from '../GlassPage'
import TowerClimber from './TowerClimber'
import SupplyBar from '../components/SupplyBar'
import { getSupplies } from '@/lib/supplies'

export default async function TowerPage() {
  const { supabase, character } = await getCurrentCharacter()
  const [regen, stats, supplies] = await Promise.all([
    applyRegen(supabase, character),
    getCharacterStats(supabase, character.id),
    getSupplies(supabase, character.id),
  ])

  return (
    <GlassPage
      title="Tháp Vực Sâu"
      subtitle="100 tầng, càng lên cao càng khó. Mỗi tầng 5 AP, qua tầng hồi 20% HP, điểm hồi sinh mỗi 10 tầng. Gục ngã: mất 10% vàng và 15% EXP của cấp."
    >
      <SupplyBar
        characterId={character.id}
        autoPotion={character.auto_potion ?? true}
        potionCount={supplies.potionCount}
        buffs={supplies.buffs}
      />
      <TowerClimber
        characterId={character.id}
        towerBest={character.tower_best}
        currentHp={Math.min(stats.maxHp, regen.currentHp ?? stats.maxHp)}
        maxHp={stats.maxHp}
        currentAp={regen.currentAp}
        maxAp={character.max_ap}
      />
    </GlassPage>
  )
}
