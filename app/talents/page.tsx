import Link from 'next/link'
import { getCurrentCharacter } from '@/lib/current-character'
import GlassPage from '../GlassPage'
import TalentTree, { type TalentEdge, type TalentNode, type TalentState } from './TalentTree'

export default async function TalentsPage() {
  const { supabase, character } = await getCurrentCharacter()
  const [{ data: nodes }, { data: edges }, { data: state, error }] = await Promise.all([
    supabase.from('talent_nodes').select('key, name, icon, branch, kind, cost, x, y, effects, description'),
    supabase.from('talent_edges').select('a, b'),
    supabase.rpc('get_talent_state', { p_character_id: character.id }),
  ])

  return (
    <GlassPage
      title="Thiên Phú"
      subtitle="1 điểm mỗi 2 cấp + 1 điểm mỗi tầng boss Tháp đã qua. Chỉ học được ô liền kề ô đã học."
    >
      {error ? (
        <p className="text-sm text-[#e09595]">Không tải được cây thiên phú: {error.message}</p>
      ) : (
        <TalentTree
          characterId={character.id}
          nodes={(nodes ?? []) as TalentNode[]}
          edges={(edges ?? []) as TalentEdge[]}
          initialState={state as TalentState}
          gold={character.gold}
        />
      )}
      <p className="text-xs text-[#7d7a8c] mt-6">
        <Link href="/classes" className="underline hover:text-white">
          📖 Xem thông tin các lớp nhân vật
        </Link>
      </p>
    </GlassPage>
  )
}
