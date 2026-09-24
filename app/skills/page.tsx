import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import GlassPage from '../GlassPage'
import SkillManager from './SkillManager'


export default async function SkillsPage() {
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
    <GlassPage title="Kỹ Năng" subtitle={`${cls.icon ?? ''} ${cls.name} · Cấp ${character.level} · trang bị 2 chủ động + 1 bị động`}>
      <SkillManager
        characterId={character.id}
        characterLevel={character.level}
        skills={skills ?? []}
        initialEquipped={equipped ?? []}
      />
    </GlassPage>
  )
}
