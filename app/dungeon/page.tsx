import { redirect } from 'next/navigation'
import Link from 'next/link'
import { Cinzel, JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/server'
import { applyApRegen } from '@/lib/ap-regen'
import { getEquippedStats } from '@/lib/equipped-stats'
import FloorList from './FloorList'

const display = Cinzel({ subsets: ['latin'], weight: ['500', '700'] })
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

export default async function DungeonPage() {
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

  const [{ data: dungeon }, { currentAp }, equippedStats] = await Promise.all([
    supabase
      .from('dungeons')
      .select('*, dungeon_floors(*)')
      .eq('chapter_number', character.current_chapter)
      .maybeSingle(),
    applyApRegen(supabase, character),
    getEquippedStats(supabase, character.id),
  ])

  const { data: clearedRuns } = await supabase
    .from('dungeon_runs')
    .select('floor_number')
    .eq('character_id', character.id)
    .eq('dungeon_id', dungeon?.id)
    .eq('status', 'cleared')

  const highestCleared = clearedRuns?.length
    ? Math.max(...clearedRuns.map((r) => r.floor_number))
    : 0

  const cls = character.classes as { base_hp: number; hp_per_level: number }
  const maxHp = cls.base_hp + (character.level - 1) * cls.hp_per_level + equippedStats.bonusHp

  const floors = ((dungeon?.dungeon_floors as any[]) ?? []).sort(
    (a, b) => a.floor_number - b.floor_number
  )

  return (
    <main className="min-h-screen bg-[#100e0c] text-[#ece3d0] px-6 py-16">
      <div className="mx-auto max-w-2xl">
        <div className="mb-8">
          <Link href="/" className={`${mono.className} text-xs text-[#8a7f68] hover:text-[#a89b7f]`}>
            ← Về nhân vật
          </Link>
        </div>

        {!dungeon ? (
          <p className={`${mono.className} text-center text-[#8a7f68]`}>
            Chưa có dungeon nào cho chương này.
          </p>
        ) : (
          <>
            <header className="text-center mb-4">
              <p className={`${mono.className} text-xs tracking-widest text-[#8a7f68] mb-2`}>
                Chương {dungeon.chapter_number}
              </p>
              <h1 className={`${display.className} text-3xl text-[#f1e6c8]`}>{dungeon.name}</h1>
              <p className="text-sm text-[#a89b7f] mt-2 max-w-md mx-auto">{dungeon.description}</p>
            </header>

            <div className={`${mono.className} text-center text-xs text-[#6b6249] mb-10`}>
              AP hiện tại: {currentAp} / {character.max_ap} · cần {dungeon.ap_cost} AP mỗi lần vào tầng
            </div>

            <FloorList
              characterId={character.id}
              floors={floors}
              highestCleared={highestCleared}
              currentHp={character.current_hp ?? maxHp}
              maxHp={maxHp}
              currentAp={currentAp}
              apCost={dungeon.ap_cost}
            />
          </>
        )}
      </div>
    </main>
  )
}
