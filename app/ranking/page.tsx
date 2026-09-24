import Link from 'next/link'
import { getCurrentCharacter } from '@/lib/current-character'
import GlassPage from '../GlassPage'
import PortraitCard from '../components/PortraitCard'

const SORTS = [
  { key: 'level', label: 'Cấp độ' },
  { key: 'power', label: 'Lực chiến' },
  { key: 'boss_kills', label: 'Boss đã hạ' },
  { key: 'tower', label: 'Tháp' },
] as const

type Row = {
  out_rank: number
  out_character_id: string
  out_name: string
  out_class_key: string
  out_class_name: string
  out_portrait: string | null
  out_frame: string | null
  out_level: number
  out_power: number
  out_boss_kills: number
  out_kills: number
  out_tower_best: number
  out_title: string | null
}

const MEDAL = ['🥇', '🥈', '🥉']

export default async function RankingPage({ searchParams }: { searchParams: Promise<{ sort?: string }> }) {
  const { sort: sortParam } = await searchParams
  const sort = SORTS.some((s) => s.key === sortParam) ? sortParam! : 'level'
  const { supabase, character } = await getCurrentCharacter()
  const { data, error } = await supabase.rpc('get_leaderboard', { p_sort: sort })
  const rows = (data ?? []) as Row[]

  return (
    <GlassPage back title="Xếp Hạng" subtitle="Top 50 người chơi. Lực chiến tính từ ATK, DEF, HP, chí mạng, hút máu và hiệu ứng Huyền Thoại.">
      <div role="tablist" className="grid grid-cols-4 gap-1.5 mb-4">
        {SORTS.map((s) => (
          <Link
            key={s.key}
            href={`/ranking?sort=${s.key}`}
            role="tab"
            aria-selected={sort === s.key}
            className={`rounded-xl border px-2 py-2 text-center text-xs ${
              sort === s.key
                ? 'border-[#f0c060]/60 bg-[#f0c060]/15 text-white'
                : 'border-white/[0.09] text-[#a29fb3] hover:text-white'
            }`}
          >
            {s.label}
          </Link>
        ))}
      </div>

      {error && <p className="text-sm text-[#e09595]">Không tải được bảng xếp hạng: {error.message}</p>}

      <ol className="rounded-2xl bg-white/[0.045] border border-white/[0.09] divide-y divide-white/[0.06]">
        {rows.map((r) => {
          const me = r.out_character_id === character.id
          const value =
            sort === 'power'
              ? `${r.out_power} LC`
              : sort === 'boss_kills'
                ? `${r.out_boss_kills} boss`
                : sort === 'tower'
                  ? `Tầng ${r.out_tower_best}`
                  : `Lv ${r.out_level}`
          return (
            <li key={r.out_character_id} className={`flex items-center gap-3 px-4 py-3 ${me ? 'bg-[#b06fd8]/[0.12]' : ''}`}>
              <span className="w-8 text-center text-sm shrink-0">
                {r.out_rank <= 3 ? MEDAL[r.out_rank - 1] : <span className="text-[#7d7a8c]">#{r.out_rank}</span>}
              </span>
              <PortraitCard classKey={r.out_class_key} portrait={r.out_portrait} frame={r.out_frame} className="w-9" />
              <div className="flex-grow min-w-0">
                <p className={`text-sm truncate ${me ? 'text-[#e3caf5] font-semibold' : 'text-white'}`}>
                  {r.out_name}
                  {me && ' (bạn)'}
                </p>
                <p className="text-xs text-[#7d7a8c] truncate">
                  {r.out_title ? `${r.out_title} · ` : ''}
                  {r.out_class_name} · Lv {r.out_level}
                </p>
              </div>
              <span className="text-sm text-[#f0c060] shrink-0 tabular-nums">{value}</span>
            </li>
          )
        })}
        {rows.length === 0 && !error && <li className="px-4 py-6 text-center text-sm text-[#7d7a8c]">Chưa có ai.</li>}
      </ol>
    </GlassPage>
  )
}
