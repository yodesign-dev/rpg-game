import { redirect } from 'next/navigation'
import Link from 'next/link'
import { display, ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/server'
import { applyRegen } from '@/lib/regen'
import { getCharacterStats } from '@/lib/character-stats'
import Portrait from './components/Portrait'
import PortraitPicker from './hub/PortraitPicker'
import SettingsMenu from './SettingsMenu'
import BottomNav from './BottomNav'
import StatAllocator from './StatAllocator'
import ActivityFeed, { type FeedEntry } from './ActivityFeed'
import QuestBoard, { type DailyQuests } from './quests/QuestBoard'
import TalentTree, { type TalentEdge, type TalentNode, type TalentState } from './talents/TalentTree'
import HubTabs, { hubHref, parseHubTab } from './hub/HubTabs'

const CLASS_TAG: Record<string, string> = {
  warrior: 'text-[#e0a3a3] bg-[#8c3f3f]/[0.18] border-[#8c3f3f]/40',
  mage: 'text-[#b3b7e8] bg-[#4a4e8c]/[0.18] border-[#4a4e8c]/40',
  archer: 'text-[#9fd8b8] bg-[#3d6b52]/[0.18] border-[#3d6b52]/40',
  assassin: 'text-[#d9c3ee] bg-[#6b4a7a]/[0.18] border-[#6b4a7a]/40',
}

export default async function CharacterPage({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const tab = parseHubTab((await searchParams).tab)
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
  // Nhiệm vụ + thiên phú luôn tải (cần cho số đỏ trên tab); cây thiên phú chỉ tải khi mở tab đó
  const [stats, { data: feed }, { data: quests, error: questsError }, { data: talentState }, { data: zones }, tree] =
    await Promise.all([
      getCharacterStats(supabase, character.id),
      supabase
        .from('activity_feed')
        .select('id, character_id, character_name, character_title, kind, payload, created_at')
        .order('created_at', { ascending: false })
        .limit(15),
      supabase.rpc('get_daily_quests', { p_character_id: character.id }),
      supabase.rpc('get_talent_state', { p_character_id: character.id }),
      supabase.from('zones').select('name, icon, min_level').order('min_level'),
      tab === 'talents'
        ? Promise.all([
            supabase.from('talent_nodes').select('key, name, icon, branch, kind, cost, x, y, effects, description'),
            supabase.from('talent_edges').select('a, b'),
          ])
        : null,
    ])

  const maxHp = stats.maxHp
  const currentHp = Math.min(maxHp, regen.currentHp ?? maxHp)
  const tag = CLASS_TAG[cls.key] ?? CLASS_TAG.warrior

  const daily = quests as DailyQuests | null
  const questsDone = daily?.quests.filter((q) => q.claimed).length ?? 0
  const questsClaimable =
    (daily?.quests.filter((q) => !q.claimed && q.progress >= q.target).length ?? 0) +
    (daily && !daily.bonus_claimed && daily.quests.every((q) => q.claimed) ? 1 : 0)
  const talentPoints = (talentState as TalentState | null)?.available ?? 0
  // Vùng gợi ý: vùng cao nhất có cấp tối thiểu ≤ cấp nhân vật
  const suggestedZone = [...(zones ?? [])].reverse().find((z) => z.min_level <= character.level)

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
      <div className="mx-auto max-w-2xl px-4">
        {/* Header gọn, dính trên đầu khi cuộn */}
        <header className="sticky top-0 z-20 -mx-4 px-4 pt-4 pb-3 bg-[#07070a]/85 backdrop-blur-md">
          <div className="flex items-center gap-3">
            <div className="relative w-14 h-14 shrink-0">
              <PortraitPicker characterId={character.id} classKey={cls.key} portrait={character.portrait}>
                <div
                  className="absolute inset-0 rounded-full p-[2px]"
                  style={{ background: 'linear-gradient(135deg,#b06fd8,#6b4a7a 60%,#3a2a48)' }}
                >
                  <div className="w-full h-full rounded-full bg-[#16121c] overflow-hidden flex items-start justify-center">
                    <Portrait classKey={cls.key} portrait={character.portrait} variant="bust" />
                  </div>
                </div>
              </PortraitPicker>
              <div
                className="absolute -right-1 -bottom-1 bg-[#1c1526] border-2 border-[#b06fd8] rounded-full px-1.5 text-xs font-bold text-[#e3caf5]"
              >
                {character.level}
              </div>
            </div>
            <div className="flex-grow min-w-0">
              <div className={`${display.className} text-xl font-semibold text-white truncate`}>{character.name}</div>
              <div className="flex items-center gap-1.5 mt-0.5 min-w-0 text-xs">
                <span className={`shrink-0 border rounded-full px-2 py-px ${tag}`}>{cls.name}</span>
                <Link href="/titles" className="truncate text-[#f0c060] hover:underline">
                  {character.title
                    ? `${(character.title as { emoji: string }).emoji} ${(character.title as { name: string }).name}`
                    : '🎖️ Chọn danh hiệu'}
                </Link>
              </div>
            </div>
            <div className="flex items-center gap-2 shrink-0">
              <span
                className="flex items-center gap-1 rounded-full bg-white/[0.06] border border-[#e0b050]/35 px-2.5 py-1 text-sm font-semibold text-[#f1dba0] tabular-nums"
                title="Vàng"
              >
                <span aria-hidden>🪙</span>
                {character.gold.toLocaleString('vi-VN')}
              </span>
              <SettingsMenu characterId={character.id} characterName={character.name} />
            </div>
          </div>

          <div className="grid grid-cols-3 gap-3 mt-3">
            <MiniBar
              label="HP"
              value={currentHp}
              max={maxHp}
              color="linear-gradient(90deg,#b06fd8,#e086b0)"
              title={currentHp < maxHp ? `Hồi ${Math.max(1, Math.ceil(maxHp * 0.02))} HP mỗi phút` : 'Đầy'}
            />
            <MiniBar
              label="AP"
              value={currentAp}
              max={character.max_ap}
              color="linear-gradient(90deg,#3d9e6b,#8fe0b0)"
              title={nextApMinutes !== null ? `+1 AP sau ${nextApMinutes} phút` : 'Đầy'}
            />
            <MiniBar
              label="EXP"
              value={character.exp}
              max={character.exp_to_next}
              color="linear-gradient(90deg,#a3925a,#e0c072)"
              title={`${Math.round((character.exp / character.exp_to_next) * 100)}% tới cấp ${character.level + 1}`}
            />
          </div>
        </header>

        <HubTabs
          active={tab}
          badges={{ stats: character.stat_points, talents: talentPoints, quests: questsClaimable }}
        />

        {tab === 'overview' && (
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <ActionCard
                href="/explore"
                title="Khám phá"
                note={suggestedZone ? `Gợi ý: ${suggestedZone.icon} ${suggestedZone.name}` : 'Cày quái theo vùng'}
                icon="🧭"
                tone="border-[#8fe0b0]/30 from-[#3d6b52]/45 to-[#3d6b52]/10 hover:border-[#8fe0b0]/60"
              />
              <ActionCard
                href="/dungeon"
                title="Tháp Vực Sâu"
                note={`Kỷ lục tầng ${character.tower_best}`}
                icon="🗼"
                tone="border-[#e09595]/30 from-[#8c3f3f]/40 to-[#8c3f3f]/10 hover:border-[#e09595]/60"
              />
            </div>

            <SummaryRow
              href={hubHref('quests')}
              icon="📜"
              title="Nhiệm vụ hằng ngày"
              note={questsError ? 'Không tải được' : `Đã xong ${questsDone}/${daily?.quests.length ?? 3}`}
              badge={questsClaimable > 0 ? `Nhận ${questsClaimable} quà` : undefined}
            />

            <Link
              href={hubHref('stats')}
              scroll={false}
              className="block rounded-[18px] bg-white/[0.045] border border-white/[0.09] p-4 hover:bg-white/[0.07] transition-colors"
            >
              <div className="grid grid-cols-4 gap-2 text-center">
                <StatCell label="ATK" value={stats.atk} />
                <StatCell label="DEF" value={stats.def} />
                <StatCell label="HP" value={stats.maxHp} />
                <StatCell label="CRIT" value={`${(Math.min(0.75, stats.critBonus) * 100).toFixed(1)}%`} />
              </div>
              {(character.stat_points > 0 || talentPoints > 0) && (
                <p className="mt-3 text-sm text-[#e3caf5]">
                  {character.stat_points > 0 && <>+{character.stat_points} điểm chỉ số </>}
                  {character.stat_points > 0 && talentPoints > 0 && '· '}
                  {talentPoints > 0 && <>+{talentPoints} điểm thiên phú </>}
                  chưa dùng →
                </p>
              )}
            </Link>

            {/* eslint-disable-next-line react-hooks/purity -- server component: thời điểm render là "bây giờ" */}
            <ActivityFeed entries={(feed ?? []) as FeedEntry[]} myCharacterId={character.id} now={Date.now()} />

            <div className="grid grid-cols-4 gap-2 pt-1">
              {[
                { href: '/titles', icon: '🎖️', label: 'Danh hiệu' },
                { href: '/ranking', icon: '🏆', label: 'Xếp hạng' },
                { href: '/training', icon: '🎯', label: 'Nộm tập' },
                { href: '/classes', icon: '📖', label: 'Lớp' },
              ].map((l) => (
                <Link
                  key={l.href}
                  href={l.href}
                  className="rounded-2xl border border-white/[0.07] py-2.5 text-center hover:bg-white/[0.06] transition-colors"
                >
                  <div className="text-lg">{l.icon}</div>
                  <div className="text-xs leading-tight text-[#a29fb3] mt-0.5">{l.label}</div>
                </Link>
              ))}
            </div>
          </div>
        )}

        {tab === 'stats' && (
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
        )}

        {tab === 'talents' && (
          <>
            <p className="text-sm text-[#a29fb3] mb-4">
              Điểm mở ở cấp 6 / 14 / 22 / 30 / 50 / 65 / 75, cộng 1 điểm mỗi 25 tầng Tháp (tối đa 7). Ô lớn mở từ
              cấp 20, ô trùm từ cấp 40. Chỉ học được ô liền kề ô đã học.
            </p>
            {!talentState || tree?.[0].error ? (
              <p className="text-sm text-[#e09595]">Không tải được cây thiên phú.</p>
            ) : (
              <TalentTree
                characterId={character.id}
                nodes={(tree?.[0].data ?? []) as TalentNode[]}
                edges={(tree?.[1].data ?? []) as TalentEdge[]}
                initialState={talentState as TalentState}
                gold={character.gold}
              />
            )}
          </>
        )}

        {tab === 'quests' && (
          <>
            <p className="text-sm text-[#a29fb3] mb-4">
              3 nhiệm vụ mỗi ngày, làm mới lúc 0h. Làm đủ 3 để nhận quà thêm.
            </p>
            {questsError || !daily ? (
              <p className="text-sm text-[#e09595]">Không tải được nhiệm vụ: {questsError?.message}</p>
            ) : (
              <QuestBoard characterId={character.id} initial={daily} />
            )}
          </>
        )}
      </div>

      <BottomNav />
    </main>
  )
}

function MiniBar({
  label,
  value,
  max,
  color,
  title,
}: {
  label: string
  value: number
  max: number
  color: string
  title: string
}) {
  const pct = Math.min(100, Math.round((value / Math.max(1, max)) * 100))
  return (
    <div title={title}>
      <div className={`${ui.className} flex items-baseline justify-between text-xs mb-1`}>
        <span className="font-semibold text-[#a29fb3]">{label}</span>
        <span className="text-[#e5e1ed] tabular-nums">
          {value}
          <span className="text-[#7d7a8c]">/{max}</span>
        </span>
      </div>
      <div className="h-1.5 rounded-full bg-white/[0.08] overflow-hidden">
        <div className="h-full rounded-full" style={{ width: `${pct}%`, background: color }} />
      </div>
    </div>
  )
}

function ActionCard({ href, title, note, icon, tone }: { href: string; title: string; note: string; icon: string; tone: string }) {
  return (
    <Link href={href} className={`rounded-[18px] border bg-gradient-to-br p-4 transition-colors ${tone}`}>
      <div className="text-2xl" aria-hidden>
        {icon}
      </div>
      <div className="mt-2 text-base font-bold text-white">{title}</div>
      <div className="text-xs text-[#c9c4d4] mt-0.5 truncate">{note}</div>
    </Link>
  )
}

function SummaryRow({
  href,
  icon,
  title,
  note,
  badge,
}: {
  href: string
  icon: string
  title: string
  note: string
  badge?: string
}) {
  return (
    <Link
      href={href}
      scroll={false}
      className="flex items-center gap-3 rounded-[18px] bg-white/[0.045] border border-white/[0.09] px-4 py-3 hover:bg-white/[0.07] transition-colors"
    >
      <span className="text-xl" aria-hidden>
        {icon}
      </span>
      <div className="flex-grow min-w-0">
        <div className="text-sm font-semibold text-white">{title}</div>
        <div className="text-xs text-[#a29fb3]">{note}</div>
      </div>
      {badge && (
        <span className="shrink-0 rounded-full bg-[#8fe0b0]/15 border border-[#8fe0b0]/50 text-[#c8f5dc] text-xs font-semibold px-2.5 py-1">
          {badge}
        </span>
      )}
      <span className="text-[#7d7a8c]" aria-hidden>
        ›
      </span>
    </Link>
  )
}

function StatCell({ label, value }: { label: string; value: number | string }) {
  return (
    <div>
      <div className="text-xs text-[#7d7a8c]">{label}</div>
      <div className="text-base font-semibold text-white tabular-nums">{value}</div>
    </div>
  )
}
