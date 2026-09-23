import { applyRegen } from '@/lib/regen'
import { getCharacterStats } from '@/lib/character-stats'
import { getCurrentCharacter } from '@/lib/current-character'
import GlassPage from '../GlassPage'
import TowerClimber from './TowerClimber'

export default async function TowerPage() {
  const { supabase, character } = await getCurrentCharacter()
  const [regen, stats] = await Promise.all([applyRegen(supabase, character), getCharacterStats(supabase, character.id)])

  return (
    <GlassPage
      title="Tháp Vực Sâu"
      subtitle="100 tầng, càng lên cao càng khó. Mỗi tầng 5 AP, HP giữ nguyên (qua tầng hồi 20%). Điểm hồi sinh mỗi 10 tầng."
    >
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
