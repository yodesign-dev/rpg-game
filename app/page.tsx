import { redirect } from 'next/navigation'
import Link from 'next/link'
import { Cinzel, JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/server'

const display = Cinzel({ subsets: ['latin'], weight: ['500', '700'] })
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

const CLASS_ACCENT: Record<string, { bar: string; text: string }> = {
  warrior:  { bar: 'bg-[#8c3f3f]', text: 'text-[#c98787]' },
  mage:     { bar: 'bg-[#4a4e8c]', text: 'text-[#9ea2d6]' },
  archer:   { bar: 'bg-[#3d6b52]', text: 'text-[#8fc4a8]' },
  assassin: { bar: 'bg-[#6b4a7a]', text: 'text-[#b79bc4]' },
}

export default async function CharacterPage() {
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

  const cls = character.classes as {
    key: string
    name: string
    icon: string | null
    base_hp: number
    hp_per_level: number
  }

  const maxHp = cls.base_hp + (character.level - 1) * cls.hp_per_level
  const currentHp = character.current_hp ?? maxHp

  // --- Tính hồi AP kiểu lazy: dựa vào thời gian trôi qua từ lần cập nhật gần nhất ---
  const lastUpdate = new Date(character.last_ap_update)
  const elapsedMs = Date.now() - lastUpdate.getTime()
  const elapsedMinutes = Math.floor(elapsedMs / 60000)
  const regenTicks = Math.floor(elapsedMinutes / character.ap_regen_minutes)

  let currentAp = character.current_ap
  let nextApMinutes: number | null = null

  if (regenTicks > 0 && character.current_ap < character.max_ap) {
    const newAp = Math.min(character.max_ap, character.current_ap + regenTicks)
    const newLastUpdate = new Date(
      lastUpdate.getTime() + regenTicks * character.ap_regen_minutes * 60000
    )
    await supabase
      .from('characters')
      .update({ current_ap: newAp, last_ap_update: newLastUpdate.toISOString() })
      .eq('id', character.id)
    currentAp = newAp
  }

  if (currentAp < character.max_ap) {
    nextApMinutes = character.ap_regen_minutes - (elapsedMinutes % character.ap_regen_minutes)
  }

  const accent = CLASS_ACCENT[cls.key] ?? CLASS_ACCENT.warrior
  const expPct = Math.min(100, Math.round((character.exp / character.exp_to_next) * 100))
  const hpPct = Math.min(100, Math.round((currentHp / maxHp) * 100))
  const apPct = Math.min(100, Math.round((currentAp / character.max_ap) * 100))

  return (
    <main className="min-h-screen bg-[#100e0c] text-[#ece3d0] px-6 py-16">
      <div className="mx-auto max-w-2xl">
        <header className="text-center mb-10">
          <p className={`${mono.className} text-xs tracking-widest text-[#8a7f68] mb-3`}>
            Chương {character.current_chapter}
          </p>
          <div className="text-4xl mb-2">{cls.icon}</div>
          <h1 className={`${display.className} text-3xl text-[#f1e6c8]`}>
            {character.name}
          </h1>
          <p className={`${mono.className} text-sm ${accent.text} mt-1`}>
            {cls.name} · Cấp {character.level}
          </p>
        </header>

        <div className="rounded-sm border border-[#2c261c] bg-[#17140f] p-6 space-y-5">
          <StatRow label="EXP" value={`${character.exp} / ${character.exp_to_next}`} pct={expPct} barClass="bg-[#8a7f68]" />
          <StatRow label="HP" value={`${currentHp} / ${maxHp}`} pct={hpPct} barClass={accent.bar} />
          <StatRow
            label="AP"
            value={`${currentAp} / ${character.max_ap}`}
            pct={apPct}
            barClass="bg-[#6b8a5a]"
            note={
              nextApMinutes !== null
                ? `Hồi tiếp trong ${nextApMinutes} phút`
                : 'Đã đầy'
            }
          />

          <div className="flex items-center justify-between pt-2 border-t border-[#2c261c]">
            <span className={`${mono.className} text-xs tracking-widest text-[#8a7f68]`}>
              VÀNG
            </span>
            <span className={`${mono.className} text-lg text-[#f1e6c8]`}>
              {character.gold}
            </span>
          </div>
        </div>

        <nav className="grid grid-cols-3 gap-4 mt-8">
          <NavCard href="/dungeon" label="Dungeon" icon="🗝️" />
          <NavCard href="/inventory" label="Túi Đồ" icon="🎒" />
          <NavCard href="/quests" label="Nhiệm Vụ" icon="📜" />
        </nav>
      </div>
    </main>
  )
}

function StatRow({
  label,
  value,
  pct,
  barClass,
  note,
}: {
  label: string
  value: string
  pct: number
  barClass: string
  note?: string
}) {
  const mono2 = mono.className
  return (
    <div>
      <div className="flex items-center justify-between mb-1.5">
        <span className={`${mono2} text-xs tracking-widest text-[#8a7f68]`}>{label}</span>
        <span className={`${mono2} text-xs text-[#a89b7f]`}>{value}</span>
      </div>
      <div className="h-2 bg-[#2c261c] rounded-full overflow-hidden">
        <div className={`h-full ${barClass}`} style={{ width: `${pct}%` }} />
      </div>
      {note && (
        <p className={`${mono2} text-[10px] text-[#6b6249] mt-1 text-right`}>{note}</p>
      )}
    </div>
  )
}

function NavCard({ href, label, icon }: { href: string; label: string; icon: string }) {
  return (
    <Link
      href={href}
      className="flex flex-col items-center gap-2 rounded-sm border border-[#2c261c] bg-[#17140f]
        py-6 hover:border-[#4a4230] transition-colors"
    >
      <span className="text-2xl">{icon}</span>
      <span className={`${mono.className} text-xs tracking-widest text-[#a89b7f]`}>{label}</span>
    </Link>
  )
}
