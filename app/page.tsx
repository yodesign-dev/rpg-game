import { redirect } from 'next/navigation'
import { Cinzel, JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/server'
import { applyApRegen } from '@/lib/ap-regen'
import { getEquippedStats } from '@/lib/equipped-stats'
import ClassArt from './ClassArt'
import SettingsMenu from './SettingsMenu'
import BottomNav from './BottomNav'
import DungeonCta from './DungeonCta'

const display = Cinzel({ subsets: ['latin'], weight: ['500', '700'] })
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

const CLASS_TAG: Record<string, string> = {
  warrior: 'text-[#e0a3a3] bg-[#8c3f3f]/[0.18] border-[#8c3f3f]/40',
  mage: 'text-[#b3b7e8] bg-[#4a4e8c]/[0.18] border-[#4a4e8c]/40',
  archer: 'text-[#9fd8b8] bg-[#3d6b52]/[0.18] border-[#3d6b52]/40',
  assassin: 'text-[#d9c3ee] bg-[#6b4a7a]/[0.18] border-[#6b4a7a]/40',
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

  const [{ currentAp, nextApMinutes }, equippedStats] = await Promise.all([
    applyApRegen(supabase, character),
    getEquippedStats(supabase, character.id),
  ])

  const maxHp = cls.base_hp + (character.level - 1) * cls.hp_per_level + equippedStats.bonusHp
  const currentHp = character.current_hp ?? maxHp

  const expPct = Math.min(100, Math.round((character.exp / character.exp_to_next) * 100))
  const hpPct = Math.min(100, Math.round((currentHp / maxHp) * 100))
  const apPct = Math.min(100, Math.round((currentAp / character.max_ap) * 100))
  const tag = CLASS_TAG[cls.key] ?? CLASS_TAG.warrior

  return (
    <main
      className="min-h-screen text-[#f2ede4] pb-28"
      style={{
        background:
          'radial-gradient(480px 260px at 15% 0%, rgba(107,74,122,.28), transparent 60%),' +
          'radial-gradient(480px 260px at 100% 10%, rgba(143,196,168,.12), transparent 55%),' +
          '#07070a',
      }}
    >
      <div className="mx-auto max-w-2xl px-4 pt-6">

        {/* Top bar */}
        <div className="flex items-center justify-between mb-5">
          <SettingsMenu characterId={character.id} characterName={character.name} />
          <p className={`${mono.className} text-[10px] tracking-[3px] text-[#83809a]`}>
            CHƯƠNG {character.current_chapter}
          </p>
          <div
            className={`${mono.className} flex items-center gap-1.5 bg-white/[0.06] border border-[#e0b050]/35
              rounded-full pl-2 pr-3 py-1.5`}
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#e0b050" strokeWidth="1.6">
              <circle cx="12" cy="12" r="8.5" />
              <path d="M9.5 10a2.5 2 0 0 1 2.5-1.5c1.5 0 2.5.6 2.5 1.7 0 2.3-5 1.3-5 3.6 0 1.1 1 1.7 2.5 1.7s2.5-.6 2.5-1.5" strokeLinecap="round" />
              <path d="M12 8v8" strokeLinecap="round" />
            </svg>
            <span className="text-[13px] font-semibold text-[#f1dba0]">{character.gold}</span>
          </div>
        </div>

        {/* Character glass card */}
        <div className="rounded-[22px] bg-white/[0.045] border border-white/[0.09] p-[18px] mb-3.5">
          <div className="flex items-center gap-3.5 mb-4">
            <div className="relative w-[62px] h-[62px] shrink-0">
              <div
                className="absolute inset-0 rounded-full p-[2px]"
                style={{ background: 'linear-gradient(135deg,#b06fd8,#6b4a7a 60%,#3a2a48)' }}
              >
                <div className="w-full h-full rounded-full bg-[#16121c] flex items-center justify-center">
                  <ClassArt classKey={cls.key} seed={character.id} size={40} />
                </div>
              </div>
              <div
                className={`${mono.className} absolute -right-1 -bottom-1 bg-[#1c1526] border-[1.5px] border-[#b06fd8]
                  rounded-full px-1.5 text-[9px] font-bold text-[#e3caf5]`}
              >
                Lv.{character.level}
              </div>
            </div>
            <div className="flex-grow min-w-0">
              <div className={`${display.className} text-[17px] font-semibold text-white tracking-[.3px] truncate`}>
                {character.name}
              </div>
              <div className="flex items-center gap-1.5 mt-1.5">
                <span className={`${mono.className} text-[9px] tracking-wide border rounded-full px-2 py-[3px] ${tag}`}>
                  {cls.name.toUpperCase()}
                </span>
              </div>
            </div>
          </div>

          <div className="flex flex-col gap-3">
            <StatBar
              label="EXP"
              value={`${character.exp} / ${character.exp_to_next}`}
              pct={expPct}
              gradient="linear-gradient(90deg,#a3925a,#e0c072)"
              glow="rgba(224,192,114,.5)"
              icon={
                <path d="M12 3 14.5 9.5 21 10.5 16 15 17.5 21.5 12 18 6.5 21.5 8 15 3 10.5 9.5 9.5Z" strokeLinejoin="round" />
              }
              iconColor="#c9b982"
            />
            <StatBar
              label="HP"
              value={`${currentHp} / ${maxHp}`}
              pct={hpPct}
              gradient="linear-gradient(90deg,#b06fd8,#e086b0)"
              glow="rgba(224,134,176,.55)"
              icon={<path d="M12 20 4 13a5 5 0 0 1 7-7l1 1 1-1a5 5 0 0 1 7 7Z" strokeLinejoin="round" strokeLinecap="round" />}
              iconColor="#e0839c"
            />
            <StatBar
              label="AP"
              value={`${currentAp} / ${character.max_ap}`}
              pct={apPct}
              gradient="linear-gradient(90deg,#3d9e6b,#8fe0b0)"
              glow="rgba(143,224,176,.5)"
              icon={<path d="M13 3 5 14h6l-1 7 8-11h-6Z" strokeLinejoin="round" strokeLinecap="round" />}
              iconColor="#8fe0b0"
              note={nextApMinutes !== null ? `Hồi tiếp trong ${nextApMinutes} phút` : 'Đã đầy'}
            />
          </div>
        </div>

        <DungeonCta />

      </div>

      <BottomNav />
    </main>
  )
}

function StatBar({
  label,
  value,
  pct,
  gradient,
  glow,
  icon,
  iconColor,
  note,
}: {
  label: string
  value: string
  pct: number
  gradient: string
  glow: string
  icon: React.ReactNode
  iconColor: string
  note?: string
}) {
  return (
    <div>
      <div className={`${mono.className} flex justify-between text-[9px] tracking-[1.5px] text-[#83809a] mb-[5px]`}>
        <span className="flex items-center gap-[5px]">
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke={iconColor} strokeWidth="1.8">
            {icon}
          </svg>
          {label}
        </span>
        <span className="text-[#c7c2d3]">{value}</span>
      </div>
      <div className="h-[6px] rounded-full bg-white/[0.07] overflow-hidden">
        <div
          className="h-full rounded-full"
          style={{ width: `${pct}%`, background: gradient, boxShadow: `0 0 8px ${glow}` }}
        />
      </div>
      {note && (
        <p className={`${mono.className} text-[9px] text-[#5c5a6e] text-right mt-1`}>{note}</p>
      )}
    </div>
  )
}
