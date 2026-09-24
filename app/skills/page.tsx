import { getCurrentCharacter } from '@/lib/current-character'
import GlassPage from '../GlassPage'
import SkillManager from './SkillManager'


export default async function SkillsPage() {
  const { supabase, character } = await getCurrentCharacter()

  const [{ data: skills }, { data: equipped }] = await Promise.all([
    supabase
      .from('skills')
      .select('*')
      .eq('class_id', character.class_id)
      .order('skill_type')
      .order('unlock_level'),
    supabase
      .from('character_equipped_skills')
      .select('id, skill_id')
      .eq('character_id', character.id),
  ])

  const cls = character.classes as { name: string; icon: string | null }

  return (
    <GlassPage title="Kỹ Năng" subtitle={`${cls.icon ?? ''} ${cls.name} · Cấp ${character.level} · ô chủ động thứ 2 mở ở Lv8, ô bị động ở Lv5`}>
      <SkillManager
        characterId={character.id}
        characterLevel={character.level}
        skills={skills ?? []}
        initialEquipped={equipped ?? []}
      />
    </GlassPage>
  )
}
