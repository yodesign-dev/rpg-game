'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/client'

const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

const RARITY_TEXT: Record<string, string> = {
  common: 'text-[#c9c4d4]',
  rare: 'text-[#8fc4e0]',
  epic: 'text-[#d0a8f0]',
  legendary: 'text-[#f0c060]',
}

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
  exp: number
  gold: number
  drops: string[]
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
  const [result, setResult] = useState<ExploreResult | null>(null)
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
    setResult(res)
    setLocalHp(res.hp_left)
    setLocalAp(res.ap_left)
    router.refresh()
  }

  return (
    <div className={mono.className}>
      {/* HP / AP hiện tại */}
      <div className="grid grid-cols-2 gap-3 mb-5">
        <Meter label="HP" value={localHp} max={maxHp} color="linear-gradient(90deg,#b06fd8,#e086b0)" note="Hồi 2%/phút" />
        <Meter label="AP" value={localAp} max={maxAp} color="linear-gradient(90deg,#3d9e6b,#8fe0b0)" note="+1 mỗi 5 phút" />
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
                          {d.icon && (
                            // eslint-disable-next-line @next/next/no-img-element
                            <img src={`/items/${d.icon}`} alt="" width={16} height={16} className="[image-rendering:pixelated]" />
                          )}
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
          : exhausted
            ? 'Kiệt sức — chờ hồi HP'
            : lackAp
              ? `Thiếu AP (cần ${zone?.apCost ?? 0})`
              : `Thám hiểm ${turns} lượt · −${zone?.apCost} AP`}
      </button>

      {error && <p className="text-sm text-[#e09595] mt-3">{error}</p>}

      {result && <ResultPanel result={result} />}
    </div>
  )
}

function Meter({ label, value, max, color, note }: { label: string; value: number; max: number; color: string; note: string }) {
  const pct = Math.min(100, Math.round((value / Math.max(1, max)) * 100))
  return (
    <div className="rounded-2xl bg-white/[0.045] border border-white/[0.09] p-3">
      <div className="flex justify-between text-xs text-[#a29fb3] mb-2">
        <span>{label}</span>
        <span className="text-sm text-white">
          {value} / {max}
        </span>
      </div>
      <div className="h-2 rounded-full bg-white/[0.07] overflow-hidden">
        <div className="h-full rounded-full" style={{ width: `${pct}%`, background: color }} />
      </div>
      {value < max && <p className="text-[11px] text-[#7d7a8c] text-right mt-1.5">{note}</p>}
    </div>
  )
}

function ResultPanel({ result }: { result: ExploreResult }) {
  const [showFights, setShowFights] = useState(false)
  const bosses = result.fights.filter((f) => f.boss && f.result === 'win').length

  return (
    <div className="mt-5 rounded-2xl bg-white/[0.045] border border-white/[0.09] p-4">
      <p className={`text-base font-semibold ${result.died ? 'text-[#e09595]' : 'text-[#8fe0b0]'}`}>
        {result.died
          ? `💀 Gục ngã ở lượt ${result.turns_completed}/${result.turns_requested}`
          : `✓ Hoàn thành ${result.turns_completed} lượt`}
      </p>
      <p className="text-xs text-[#a29fb3] mt-1">
        {result.zone} · thắng {result.wins} trận
        {bosses > 0 && ` · hạ ${bosses} boss 🏆`}
        {result.died && ' · trận cuối không có thưởng'}
      </p>

      <div className="grid grid-cols-3 gap-2 mt-4">
        <Stat label="EXP" value={`+${result.exp_gained}`} />
        <Stat label="VÀNG" value={`+${result.gold_gained}`} />
        <Stat label="HP" value={`${result.hp_left}/${result.max_hp}`} />
      </div>

      {result.leveled_up && (
        <p className="text-sm text-[#f0c060] mt-3">⭐ Lên cấp {result.new_level}! Vào trang nhân vật để cộng điểm chỉ số.</p>
      )}

      {result.drops.length > 0 && (
        <div className="mt-4">
          <p className="text-xs tracking-wide text-[#7d7a8c] mb-2">ĐỒ NHẶT ĐƯỢC</p>
          <div className="flex flex-wrap gap-2">
            {result.drops.map((d) => (
              <span
                key={d.key}
                className="flex items-center gap-1.5 rounded-xl bg-white/[0.05] border border-white/[0.08] px-2 py-1 text-sm"
              >
                {d.icon && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={`/items/${d.icon}`} alt="" width={20} height={20} className="[image-rendering:pixelated]" />
                )}
                <span className={RARITY_TEXT[d.rarity] ?? RARITY_TEXT.common}>{d.name}</span>
                <span className="text-[#a29fb3]">×{d.quantity}</span>
              </span>
            ))}
          </div>
        </div>
      )}

      <button
        type="button"
        onClick={() => setShowFights((v) => !v)}
        className="mt-4 text-xs text-[#a29fb3] hover:text-white"
      >
        {showFights ? '▾ Ẩn' : '▸ Xem'} chi tiết {result.fights.length} trận
      </button>

      {showFights && (
        <div className="mt-2 max-h-72 overflow-y-auto space-y-1 pr-1">
          {result.fights.map((f) => (
            <div key={f.turn} className="flex items-center gap-2 text-xs">
              <span className="w-8 text-[#7d7a8c]">#{f.turn}</span>
              <span className="w-4">{f.result === 'win' ? '✓' : f.result === 'flee' ? '⏱' : '✗'}</span>
              <span className={`flex-grow truncate ${f.boss ? 'text-[#f0a8a8]' : 'text-[#e5e1ed]'}`}>
                {f.boss && '👑 '}
                {f.enemy} <span className="text-[#7d7a8c]">Lv{f.level}</span>
                {f.drops.length > 0 && <span className="text-[#f0c060]"> 🎁</span>}
              </span>
              <span className="text-[#7d7a8c] shrink-0">
                {f.result === 'win' ? `+${f.exp} exp` : f.result === 'flee' ? 'rút lui' : 'gục'}
              </span>
              <span className="w-12 text-right text-[#a29fb3] shrink-0">{f.hp_left} HP</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl bg-white/[0.04] px-2 py-2 text-center">
      <div className="text-[11px] tracking-wide text-[#7d7a8c]">{label}</div>
      <div className="text-sm font-semibold text-white">{value}</div>
    </div>
  )
}
