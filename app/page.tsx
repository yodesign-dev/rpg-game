import { redirect } from 'next/navigation'
import Link from 'next/link'
import { display, ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/server'
import { applyRegen } from '@/lib/regen'
import { getCharacterStats } from '@/lib/character-stats'
import ClassArt from './ClassArt'
import SettingsMenu from './SettingsMenu'
import BottomNav from './BottomNav'
import DungeonCta from './DungeonCta'
import ExploreCta from './ExploreCta'
import StatAllocator from './StatAllocator'
import ActivityFeed, { type FeedEntry } from './ActivityFeed'
import QuestBoard, { type DailyQuests } from './quests/QuestBoard'


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

  const { data: character, error: characterError } = await supabase
    .from('characters')
    // characters ↔ titles có 2 quan hệ (title_key trực tiếp + bảng character_titles)
    // → phải chỉ rõ khóa ngoại, nếu không PostgREST báo lỗi "more than one relationship"
    .select('*, classes(*), title:titles!characters_title_key_fkey(name, emoji)')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  // Lỗi truy vấn ≠ chưa có nhân vật — không được đẩy sang trang tạo nhân vật
  if (characterError) throw new Error(`Không tải được nhân vật: ${characterError.message}`)
  if (!character) redirect('/create-character')

  const cls = character.classes as {
    key: string
    name: string
    icon: string | null
    main_stat: string
  }

  // Hồi phục trước rồi mới đọc chỉ số (apply_regen ghi HP/AP mới vào DB)
  const regen = await applyRegen(supabase, character)
  const { currentAp, nextApMinutes } = regen
  const [stats, { data: feed }, { data: quests, error: questsError }] = await Promise.all([
    getCharacterStats(supabase, character.id),
    supabase
      .from('activity_feed')
      .select('id, character_id, character_name, character_title, kind, payload, created_at')
      .order('created_at', { ascending: false })
      .limit(15),
    supabase.rpc('get_daily_quests', { p_character_id: character.id }),
  ])

  const maxHp = stats.maxHp
  const currentHp = Math.min(maxHp, regen.currentHp ?? maxHp)

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
        <div className="flex items-center justify-between mb-6">
          <SettingsMenu characterId={character.id} characterName={character.name} />
          <p className={`${ui.className} text-sm tracking-[3px] text-[#a29fb3]`}>
            🗼 TẦNG {character.tower_best}
          </p>
          <div
            className={`${ui.className} flex items-center gap-2 bg-white/[0.06] border border-[#e0b050]/35
              rounded-full pl-2.5 pr-3.5 py-2`}
          >
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#e0b050" strokeWidth="1.6">
              <circle cx="12" cy="12" r="8.5" />
              <path d="M9.5 10a2.5 2 0 0 1 2.5-1.5c1.5 0 2.5.6 2.5 1.7 0 2.3-5 1.3-5 3.6 0 1.1 1 1.7 2.5 1.7s2.5-.6 2.5-1.5" strokeLinecap="round" />
              <path d="M12 8v8" strokeLinecap="round" />
            </svg>
            <span className="text-base font-semibold text-[#f1dba0]">{character.gold}</span>
          </div>
        </div>

        {/* Character glass card */}
        <div className="rounded-[22px] bg-white/[0.045] border border-white/[0.09] p-5 mb-4">
          <div className="flex items-center gap-4 mb-5">
            <div className="relative w-20 h-20 shrink-0">
              <div
                className="absolute inset-0 rounded-full p-[2px]"
                style={{ background: 'linear-gradient(135deg,#b06fd8,#6b4a7a 60%,#3a2a48)' }}
              >
                <div className="w-full h-full rounded-full bg-[#16121c] flex items-center justify-center">
                  <ClassArt classKey={cls.key} seed={character.id} size={52} />
                </div>
              </div>
              <div
                className={`${ui.className} absolute -right-1.5 -bottom-1.5 bg-[#1c1526] border-2 border-[#b06fd8]
                  rounded-full px-2 py-0.5 text-xs font-bold text-[#e3caf5]`}
              >
                Lv.{character.level}
              </div>
            </div>
            <div className="flex-grow min-w-0">
              <div className={`${display.className} text-2xl font-semibold text-white tracking-[.3px] truncate`}>
                {character.name}
              </div>
              <div className="flex items-center gap-1.5 mt-2">
                <span className={`${ui.className} text-xs tracking-wide border rounded-full px-2.5 py-1 ${tag}`}>
                  {cls.name.toUpperCase()}
                </span>
              </div>
              <Link
                href="/titles"
                className={`${ui.className} inline-block mt-2 text-xs text-[#f0c060] hover:underline`}
              >
                {character.title
                  ? `${(character.title as { emoji: string }).emoji} ${(character.title as { name: string }).name}`
                  : '🎖️ Chọn danh hiệu'}
              </Link>
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
              note={currentHp < maxHp ? `Hồi ${Math.max(1, Math.ceil(maxHp * 0.02))} HP mỗi phút` : undefined}
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

        <ExploreCta />
        <DungeonCta />

        {/* Nhiệm vụ hằng ngày — nằm ngay trong tab Nhân Vật */}
        <section className="rounded-[22px] bg-white/[0.045] border border-white/[0.09] p-3.5 sm:p-5 mb-4">
          <div className="flex items-baseline justify-between gap-3 mb-3 px-1.5 sm:px-0">
            <h2 className={`${display.className} text-xl text-white`}>📜 Nhiệm Vụ Hằng Ngày</h2>
            <span className="text-xs text-[#7d7a8c]">làm mới 0h</span>
          </div>
          {questsError ? (
            <p className="text-sm text-[#e09595]">Không tải được nhiệm vụ: {questsError.message}</p>
          ) : (
            <QuestBoard characterId={character.id} initial={quests as DailyQuests} />
          )}
        </section>

        <div className={`${ui.className} grid grid-cols-5 gap-2 mb-4`}>
          {[
            { href: '/talents', icon: '🌟', label: 'Thiên phú' },
            { href: '/classes', icon: '📖', label: 'Lớp' },
            { href: '/ranking', icon: '🏆', label: 'Xếp hạng' },
            { href: '/titles', icon: '🎖️', label: 'Danh hiệu' },
            { href: '/training', icon: '🎯', label: 'Nộm tập' },
          ].map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className="rounded-[16px] bg-white/[0.045] border border-white/[0.09] py-3 px-1 text-center hover:bg-white/[0.08]"
            >
              <div className="text-xl">{l.icon}</div>
              <div className="text-xs leading-tight text-[#c9c4d4] mt-1">{l.label}</div>
            </Link>
          ))}
        </div>

        <StatAllocator
          characterId={character.id}
          mainStat={cls.main_stat}
          attributes={{
            str: character.stat_str,
            int: character.stat_int,
            agi: character.stat_agi,
            dex: character.stat_dex,
            vit: character.stat_vit,
          }}
          statPoints={character.stat_points}
          autoAllocate={character.auto_allocate_stats}
          freeResetUsed={character.free_stat_reset_used}
          resetCost={character.level * 50}
          gold={character.gold}
          totals={{ atk: stats.atk, def: stats.def, maxHp: stats.maxHp, crit: stats.critBonus }}
        />

        {/* eslint-disable-next-line react-hooks/purity -- server component: thời điểm render là "bây giờ" */}
        <ActivityFeed entries={(feed ?? []) as FeedEntry[]} myCharacterId={character.id} now={Date.now()} />

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
      <div className={`${ui.className} flex items-center justify-between text-xs tracking-wide text-[#a29fb3] mb-2`}>
        <span className="flex items-center gap-1.5 font-medium">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={iconColor} strokeWidth="1.8">
            {icon}
          </svg>
          {label}
        </span>
        <span className="text-sm text-[#e5e1ed] font-medium">{value}</span>
      </div>
      <div className="h-2 rounded-full bg-white/[0.07] overflow-hidden">
        <div
          className="h-full rounded-full"
          style={{ width: `${pct}%`, background: gradient, boxShadow: `0 0 8px ${glow}` }}
        />
      </div>
      {note && (
        <p className={`${ui.className} text-xs text-[#7d7a8c] text-right mt-1.5`}>{note}</p>
      )}
    </div>
  )
}
