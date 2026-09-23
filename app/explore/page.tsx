import { redirect } from 'next/navigation'
import Link from 'next/link'
import { Cinzel, JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/server'
import { applyRegen } from '@/lib/regen'
import { getCharacterStats } from '@/lib/character-stats'
import BottomNav from '../BottomNav'
import ExploreManager, { type Zone } from './ExploreManager'

const display = Cinzel({ subsets: ['latin'], weight: ['500', '700'] })
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

export default async function ExplorePage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: character } = await supabase
    .from('characters')
    .select('*')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (!character) redirect('/create-character')

  const [regen, stats, { data: zonesRaw, error: zonesError }, { data: dropsRaw }] = await Promise.all([
    applyRegen(supabase, character),
    getCharacterStats(supabase, character.id),
    supabase
      .from('zones')
      .select('id, key, name, icon, description, min_level, max_level, ap_cost, zone_enemies(name, level, is_boss)')
      .order('sort_order'),
    supabase.from('zone_drops').select('zone_id, boss_only, item:items(key, name, icon, rarity)'),
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
      boss: enemies.find((e) => e.is_boss)?.name ?? null,
      drops: drops.filter((d) => d.zone_id === z.id).map((d) => ({ ...d.item, bossOnly: d.boss_only })),
    }
  })

  return (
    <main
      className="min-h-screen text-[#f2ede4] pb-28"
      style={{
        background:
          'radial-gradient(480px 260px at 15% 0%, rgba(61,107,82,.25), transparent 60%),' +
          'radial-gradient(480px 260px at 100% 10%, rgba(107,74,122,.2), transparent 55%),' +
          '#07070a',
      }}
    >
      <div className="mx-auto max-w-2xl px-4 pt-6">
        <div className="mb-6">
          <Link href="/" className={`${mono.className} text-sm text-[#a29fb3] hover:text-white`}>
            ← Về nhân vật
          </Link>
        </div>

        <header className="mb-6">
          <h1 className={`${display.className} text-3xl text-white`}>Thám Hiểm</h1>
          <p className={`${mono.className} text-sm text-[#a29fb3] mt-2`}>
            Chọn vùng và số lượt. AP chỉ trừ một lần khi vào vùng — đánh tới khi đủ lượt hoặc hết HP.
          </p>
        </header>

        {(zonesError || zones.length === 0) && (
          <p className={`${mono.className} text-sm text-[#e09595] mb-4`}>
            Không tải được danh sách vùng{zonesError ? `: ${zonesError.message}` : ''}.
          </p>
        )}

        <ExploreManager
          characterId={character.id}
          level={character.level}
          zones={zones}
          currentHp={Math.min(stats.maxHp, regen.currentHp ?? stats.maxHp)}
          maxHp={stats.maxHp}
          currentAp={regen.currentAp}
          maxAp={character.max_ap}
        />
      </div>
      <BottomNav />
    </main>
  )
}
