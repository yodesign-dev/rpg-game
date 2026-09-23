'use client'

import { useEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/client'
import { ItemIcon, LastFightLog, Meter, RARITY_TEXT, type LastFight } from '../components/combat-ui'

const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })


export type Zone = {
  id: string
  name: string
  icon: string
  description: string | null
  minLevel: number
  maxLevel: number
  apCost: number
  boss: string | null
  drops: { key: string; name: string; icon: string | null; rarity: string; bossOnly: boolean }[]
}

type Fight = {
  turn: number
  enemy: string
  level: number
  boss: boolean
  result: 'win' | 'lose' | 'flee'
  hp_left: number
  dmg_taken: number
  exp: number
  gold: number
  drops: { key: string; rarity: string }[]
}


type ExploreResult = {
  zone: string
  turns_requested: number
  turns_completed: number
  wins: number
  died: boolean
  exp_gained: number
  gold_gained: number
  leveled_up: boolean
  new_level: number
  hp_left: number
  max_hp: number
  ap_left: number
  drops: { key: string; name: string; icon: string | null; rarity: string; quantity: number }[]
  fights: Fight[]
  last_fight: LastFight | null
}

const TURN_PRESETS = [10, 25, 50, 100]

export default function ExploreManager({
  characterId,
  level,
  zones,
  currentHp,
  maxHp,
  currentAp,
  maxAp,
}: {
  characterId: string
  level: number
  zones: Zone[]
  currentHp: number
  maxHp: number
  currentAp: number
  maxAp: number
}) {
  const router = useRouter()
  const [selectedId, setSelectedId] = useState(
    // Mặc định: vùng cao nhất mà level hiện tại đã đạt mức tối thiểu
    [...zones].reverse().find((z) => level >= z.minLevel)?.id ?? zones[0]?.id ?? null
  )
  const [turns, setTurns] = useState(100)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<{ data: ExploreResult; zone: Zone } | null>(null)
  const [localHp, setLocalHp] = useState(currentHp)
  const [localAp, setLocalAp] = useState(currentAp)

  const zone = zones.find((z) => z.id === selectedId) ?? null
  const exhausted = localHp <= 1
  const lackAp = zone ? localAp < zone.apCost : true

  async function explore() {
    if (!zone) return
    setBusy(true)
    setError(null)
    setResult(null)

    const { data, error: rpcError } = await createClient().rpc('explore_zone', {
      p_character_id: characterId,
      p_zone_id: zone.id,
      p_turns: turns,
    })

    setBusy(false)

    if (rpcError) {
      setError(rpcError.message)
      return
    }

    const res = data as ExploreResult
    setResult({ data: res, zone })
    setLocalHp(res.hp_left)
    setLocalAp(res.ap_left)
    router.refresh()
  }

  return (
    <div className={mono.className}>
      {/* HP / AP hiện tại */}
      <div className="grid grid-cols-2 gap-3 mb-5">
        <Meter label="HP" value={localHp} max={maxHp} color="linear-gradient(90deg,#b06fd8,#e086b0)" note="Hồi 2%/phút" />
        <Meter label="AP" value={localAp} max={maxAp} color="linear-gradient(90deg,#3d9e6b,#8fe0b0)" note="+1 mỗi phút" />
      </div>

      {/* Danh sách vùng */}
      <div className="flex flex-col gap-2 mb-5">
        {zones.map((z) => {
          const selected = z.id === selectedId
          const underLevel = level < z.minLevel
          const overLevel = level > z.maxLevel
          return (
            <button
              key={z.id}
              type="button"
              onClick={() => setSelectedId(z.id)}
              className={`text-left rounded-2xl border px-4 py-3 transition-colors ${
                selected
                  ? 'bg-[#8fe0b0]/[0.08] border-[#8fe0b0]/50'
                  : 'bg-white/[0.04] border-white/[0.08] hover:bg-white/[0.07]'
              }`}
            >
              <div className="flex items-center gap-3">
                <span className="text-2xl shrink-0">{z.icon}</span>
                <div className="flex-grow min-w-0">
                  <div className="flex items-baseline gap-2 flex-wrap">
                    <span className="text-base font-semibold text-white">{z.name}</span>
                    <span className="text-xs text-[#a29fb3]">
                      Lv {z.minLevel}–{z.maxLevel}
                    </span>
                  </div>
                  {underLevel && (
                    <div className="text-xs text-[#f0b070] mt-0.5">
                      ⚠️ Quái mạnh hơn bạn — dễ chết, nhưng EXP cao hơn
                    </div>
                  )}
                  {overLevel && <div className="text-xs text-[#7d7a8c] mt-0.5">Quái yếu hơn bạn — EXP giảm</div>}
                </div>
                <span className="text-xs text-[#8fe0b0] shrink-0">{z.apCost} AP</span>
              </div>

              {selected && (
                <div className="mt-3 pt-3 border-t border-white/[0.08] text-xs text-[#a29fb3] space-y-1.5">
                  {z.description && <p>{z.description}</p>}
                  {z.boss && (
                    <p>
                      Boss hiếm: <span className="text-[#f0a8a8]">{z.boss}</span> (Lv {z.maxLevel + 1})
                    </p>
                  )}
                  {z.drops.length > 0 && (
                    <div className="flex flex-wrap gap-1.5 pt-1">
                      {z.drops.map((d) => (
                        <span
                          key={d.key}
                          className="flex items-center gap-1 rounded-full bg-white/[0.05] border border-white/[0.08] pl-1 pr-2 py-0.5"
                        >
                          <ItemIcon icon={d.icon} size={16} />
                          <span className={RARITY_TEXT[d.rarity] ?? RARITY_TEXT.common}>{d.name}</span>
                          {d.bossOnly && <span className="text-[#f0a8a8]">· boss</span>}
                        </span>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </button>
          )
        })}
      </div>

      {/* Số lượt */}
      <div className="rounded-2xl bg-white/[0.045] border border-white/[0.09] p-4 mb-4">
        <div className="flex items-center justify-between mb-3">
          <label htmlFor="turns" className="text-sm text-[#a29fb3]">
            Số lượt chiến đấu
          </label>
          <span className="text-lg font-semibold text-white">{turns}</span>
        </div>
        <input
          id="turns"
          type="range"
          min={1}
          max={100}
          value={turns}
          onChange={(e) => setTurns(Number(e.target.value))}
          className="w-full accent-[#8fe0b0]"
        />
        <div className="flex gap-2 mt-3">
          {TURN_PRESETS.map((n) => (
            <button
              key={n}
              type="button"
              onClick={() => setTurns(n)}
              className={`flex-1 rounded-lg py-1.5 text-sm border ${
                turns === n
                  ? 'bg-[#8fe0b0]/15 border-[#8fe0b0]/50 text-white'
                  : 'bg-white/[0.04] border-white/[0.08] text-[#a29fb3]'
              }`}
            >
              {n}
            </button>
          ))}
        </div>
      </div>

      <button
        type="button"
        onClick={explore}
        disabled={busy || !zone || exhausted || lackAp}
        className="w-full rounded-2xl py-4 text-lg font-bold text-white border border-[#8fe0b0]/40
          bg-gradient-to-r from-[#3d6b52]/70 to-[#3d6b52]/25 hover:border-[#8fe0b0]/70
          disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
      >
        {busy
          ? 'Đang thám hiểm…'
          : !zone
            ? 'Chưa chọn vùng'
            : exhausted
              ? 'Kiệt sức — chờ hồi HP'
              : lackAp
                ? `Thiếu AP (cần ${zone.apCost})`
                : `Thám hiểm ${turns} lượt · −${zone.apCost} AP`}
      </button>

      {error && <p className="text-sm text-[#e09595] mt-3">{error}</p>}

      {result && <ResultPanel result={result.data} zone={result.zone} />}
    </div>
  )
}


function ResultPanel({ result, zone }: { result: ExploreResult; zone: Zone }) {
  const [showLastFight, setShowLastFight] = useState(false)
  const listRef = useRef<HTMLDivElement>(null)
  const bosses = result.fights.filter((f) => f.boss && f.result === 'win').length
  const dropInfo = Object.fromEntries(result.drops.map((d) => [d.key, d]))

  // Cuộn tới lượt cuối — thường là lượt người chơi quan tâm nhất
  useEffect(() => {
    if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight
  }, [result])

  return (
    <div className="mt-5 rounded-2xl bg-white/[0.045] border border-white/[0.09] p-4">
      <p className="text-base font-semibold text-white">
        {result.died ? '💀 Gục ngã' : '🗺️ Thám hiểm hoàn tất'}
        <span className="font-normal text-[#a29fb3]">
          {' '}— {zone.icon} {zone.name} (Lv{zone.minLevel}–{zone.maxLevel}) · {result.turns_completed}/{result.turns_requested} lượt
        </span>
      </p>

      {/* Log từng lượt */}
      <div
        ref={listRef}
        className="mt-3 max-h-96 overflow-y-auto rounded-xl bg-black/30 border border-white/[0.06] divide-y divide-white/[0.05]"
      >
        {result.fights.map((f) => (
          <TurnRow key={f.turn} fight={f} maxHp={result.max_hp} dropInfo={dropInfo} />
        ))}
      </div>

      {result.last_fight && (
        <>
          <button
            type="button"
            onClick={() => setShowLastFight((v) => !v)}
            className="mt-3 text-xs text-[#a29fb3] hover:text-white"
          >
            📜 {showLastFight ? 'Ẩn' : 'Xem'} chi tiết trận cuối (T{result.last_fight.turn} · {result.last_fight.enemy})
          </button>
          {showLastFight && <LastFightLog fight={result.last_fight} />}
        </>
      )}

      {/* Tổng kết */}
      <div className="mt-4 pt-4 border-t border-white/[0.08] space-y-1.5 text-sm">
        <p className="text-white">
          ✨ Tổng: <b className="text-[#f0c060]">+{result.exp_gained} EXP</b> ·{' '}
          <b className="text-[#f0c060]">+{result.gold_gained} Vàng</b>
          <span className="text-[#a29fb3]">
            {' '}· thắng {result.wins} trận{bosses > 0 && ` · hạ ${bosses} boss 🏆`}
          </span>
        </p>
        <p className="text-[#e5e1ed]">
          ❤️ HP còn: {result.hp_left}/{result.max_hp}
          <span className="text-[#7d7a8c]"> · hồi 2%/phút</span>
        </p>
        {result.died && <p className="text-[#e09595]">Trận cuối gục ngã nên không có thưởng.</p>}
        {result.leveled_up && (
          <p className="text-[#f0c060]">⭐ Lên cấp {result.new_level}! Vào trang nhân vật để cộng điểm chỉ số.</p>
        )}
      </div>

      {result.drops.length > 0 && (
        <div className="mt-3 flex flex-wrap gap-2">
          {result.drops.map((d) => (
            <span
              key={`${d.key}|${d.rarity}`}
              className="flex items-center gap-1.5 rounded-xl bg-white/[0.05] border border-white/[0.08] px-2 py-1 text-sm"
            >
              <ItemIcon icon={d.icon} size={20} />
              <span className={RARITY_TEXT[d.rarity] ?? RARITY_TEXT.common}>{d.name}</span>
              <span className="text-[#a29fb3]">×{d.quantity}</span>
            </span>
          ))}
        </div>
      )}
    </div>
  )
}

function TurnRow({
  fight: f,
  maxHp,
  dropInfo,
}: {
  fight: Fight
  maxHp: number
  dropInfo: Record<string, { name: string; icon: string | null; rarity: string }>
}) {
  const pct = Math.max(0, Math.min(100, (f.hp_left / Math.max(1, maxHp)) * 100))
  const barColor = pct > 50 ? '#8fe0b0' : pct > 20 ? '#f0c060' : '#e07070'

  return (
    <div className={`px-3 py-2 text-xs ${f.result === 'lose' ? 'bg-[#e07070]/[0.08]' : ''}`}>
      <div className="flex items-baseline gap-1.5 flex-wrap">
        <span>{f.result === 'win' ? '✅' : f.result === 'flee' ? '⏱️' : '💀'}</span>
        <b className="text-white">T{f.turn}</b>
        <span className={f.boss ? 'text-[#f0a8a8] font-semibold' : 'text-[#e5e1ed]'}>
          {f.boss && '👑 '}
          {f.enemy} <span className="text-[#7d7a8c] font-normal">Lv{f.level}</span>
        </span>
        <span className="text-[#7d7a8c]">→</span>
        {f.result === 'win' ? (
          <span className="text-[#f0c060]">
            +{f.exp}EXP +{f.gold}G
          </span>
        ) : (
          <span className={f.result === 'flee' ? 'text-[#f0c060]' : 'text-[#e09595]'}>
            {f.result === 'flee' ? 'rút lui' : 'gục ngã'}
          </span>
        )}
        {f.drops.map((d, i) => (
          <span key={i} className={`flex items-center gap-1 ${RARITY_TEXT[d.rarity] ?? RARITY_TEXT.common}`}>
            <ItemIcon icon={dropInfo[d.key]?.icon ?? null} size={14} />+{dropInfo[d.key]?.name ?? d.key}
          </span>
        ))}
      </div>
      <div className="flex items-center gap-2 mt-1.5">
        <span className="w-12 shrink-0 text-[#e09595]">😓 -{f.dmg_taken}</span>
        <span className="text-[#e0839c]">❤️</span>
        <div className="flex-grow h-1.5 rounded-full bg-white/[0.08] overflow-hidden">
          <div className="h-full rounded-full" style={{ width: `${pct}%`, background: barColor }} />
        </div>
        <span className="shrink-0 text-[#a29fb3] tabular-nums">
          {f.hp_left}/{maxHp}
        </span>
      </div>
    </div>
  )
}


