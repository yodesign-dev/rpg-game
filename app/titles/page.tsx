import { getCurrentCharacter } from '@/lib/current-character'
import GlassPage from '../GlassPage'
import TitleList, { type TitleRow } from './TitleList'

export default async function TitlesPage() {
  const { supabase, character } = await getCurrentCharacter()
  const [{ data: titles }, { data: owned }] = await Promise.all([
    supabase.from('titles').select('key, name, emoji, description, stat, threshold').order('sort_order'),
    supabase.from('character_titles').select('title_key, earned_at').eq('character_id', character.id),
  ])

  const progress: Record<string, number> = {
    kills: character.kills,
    boss_kills: character.boss_kills,
    level: character.level,
    legendary_found: character.legendary_found,
    best_enchant: character.best_enchant,
    daily_bonus_count: character.daily_bonus_count,
  }
  const ownedKeys = new Set((owned ?? []).map((o) => o.title_key))
  const rows: TitleRow[] = (titles ?? []).map((t) => ({
    ...t,
    owned: ownedKeys.has(t.key),
    progress: Math.min(t.threshold, progress[t.stat] ?? 0),
  }))

  return (
    <GlassPage back title="Danh Hiệu" subtitle="Mở khóa bằng thành tích. Đeo 1 danh hiệu — hiện cạnh tên, trên bảng tin và bảng xếp hạng.">
      <TitleList characterId={character.id} rows={rows} equipped={character.title_key} />
    </GlassPage>
  )
}
