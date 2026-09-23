import { getCurrentCharacter } from '@/lib/current-character'
import GlassPage from '../GlassPage'
import QuestBoard, { type DailyQuests } from './QuestBoard'

export default async function QuestsPage() {
  const { supabase, character } = await getCurrentCharacter()
  const { data, error } = await supabase.rpc('get_daily_quests', { p_character_id: character.id })

  return (
    <GlassPage title="Nhiệm Vụ" subtitle="3 nhiệm vụ mỗi ngày, làm mới lúc 0h (giờ Việt Nam). Làm đủ 3 để nhận quà thêm.">
      {error ? (
        <p className="text-sm text-[#e09595]">Không tải được nhiệm vụ: {error.message}</p>
      ) : (
        <QuestBoard characterId={character.id} initial={data as DailyQuests} />
      )}
    </GlassPage>
  )
}
