import { redirect } from 'next/navigation'
import Link from 'next/link'
import { Cinzel, JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/server'
import SkillManager from './SkillManager'

const display = Cinzel({ subsets: ['latin'], weight: ['500', '700'] })
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

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

  const { data: skills } = await supabase
    .from('skills')
    .select('*')
    .eq('class_id', character.class_id)
    .order('skill_type')
    .order('unlock_level')

  const { data: equipped } = await supabase
    .from('character_equipped_skills')
    .select('id, skill_id')
    .eq('character_id', character.id)

  const cls = character.classes as { name: string; icon: string | null }

  return (
    <main className="min-h-screen bg-[#100e0c] text-[#ece3d0] px-6 py-16">
      <div className="mx-auto max-w-2xl">
        <div className="mb-8">
          <Link href="/" className={`${mono.className} text-xs text-[#8a7f68] hover:text-[#a89b7f]`}>
            ← Về nhân vật
          </Link>
        </div>

        <header className="text-center mb-10">
          <div className="text-3xl mb-2">{cls.icon}</div>
          <h1 className={`${display.className} text-3xl text-[#f1e6c8]`}>Kỹ Năng</h1>
          <p className="text-sm text-[#a89b7f] mt-2">
            {cls.name} · Cấp {character.level}
          </p>
        </header>

        <SkillManager
          characterId={character.id}
          characterLevel={character.level}
          skills={skills ?? []}
          initialEquipped={equipped ?? []}
        />
      </div>
    </main>
  )
}
