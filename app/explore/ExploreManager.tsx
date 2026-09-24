'use client'

import { useEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/client'
import { ItemIcon, LastFightLog, Meter, RARITY_TEXT, type LastFight } from '../components/combat-ui'
import EnemyAvatar, { ENEMY_TIER_TEXT, EnemyTraits, enemyTier } from '../components/EnemyAvatar'
import { ENEMY_TRAITS } from '@/lib/enemies'
import SupplyResult from '../components/SupplyResult'



export type Zone = {
  id: string
  name: string
  icon: string
  description: string | null
  minLevel: number
  maxLevel: number
  apCost: number
  traits: string[]
  enemies: { name: string; level: number; is_boss: boolean }[]
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
  potion?: string
  guard?: boolean
  log?: LastFight['log']
  traits?: string[]
}


type ExploreResult = {
  zone: string
  turns_requested: number
  turns_completed: number
  wins: number
  died: boolean
  potions_used?: number
  guard_used?: boolean
  buffs?: { exp?: boolean; luck?: boolean }
  exp_gained: number
  gold_gained: number
  leveled_up: boolean
  new_level: number
  hp_left: number
  max_hp: number
  ap_left: number
  ap_spent?: number
  penalty?: { gold: number; exp: number }
  drops: { key: string; name: string; icon: string | null; rarity: string; quantity: number }[]
  fights: Fight[]
  last_fight: LastFight | null
}

const TURN_PRESETS = [10, 25, 50, 100]

// Mức nguy hiểm theo cấp tối thiểu của vùng so với cấp nhân vật (khớp cân bằng mới:
// quái luôn gây ≥15% ATK, đánh vượt cấp bị giảm sát thương)
function zoneDanger(level: number, z: Zone) {
  if (level > z.maxLevel) return { label: 'Dễ', note: 'EXP giảm', cls: 'text-[#a29fb3] border-white/15 bg-white/[0.04]' }
  if (level >= z.minLevel) return { label: 'Phù hợp', note: null, cls: 'text-[#8fe0b0] border-[#8fe0b0]/40 bg-[#8fe0b0]/10' }
  if (z.minLevel - level <= 7)
    return { label: 'Nguy hiểm', note: 'Quái mạnh hơn — EXP cao hơn', cls: 'text-[#f0b070] border-[#f0b070]/40 bg-[#f0b070]/10' }
  return { label: 'Tử địa', note: 'Gần như chắc chết', cls: 'text-[#f08080] border-[#f08080]/40 bg-[#f08080]/10' }
}

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
  // Mặc định chỉ hiện vùng quanh cấp hiện tại; vùng quá dễ / quá khó ẩn sau nút
  const [showAll, setShowAll] = useState(false)
  const nearby = zones.filter((z) => level <= z.maxLevel + 5 && z.minLevel - level <= 10)
  const visibleZones = showAll || nearby.length === 0 ? zones : nearby

  const zone = zones.find((z) => z.id === selectedId) ?? null
  const exhausted = localHp <= 1
  // Vé AP tính cho mỗi 10 trận (khớp explore_zone)
  const apCostFor = (n: number) => (zone ? zone.apCost * Math.ceil(n / 10) : 0)
  const maxTurnsByAp = zone ? Math.min(100, Math.floor(localAp / zone.apCost) * 10) : 0
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
    <div className={ui.className}>
      {/* HP / AP hiện tại */}
      <div className="grid grid-cols-2 gap-3 mb-5">
        <Meter label="HP" value={localHp} max={maxHp} color="linear-gradient(90deg,#b06fd8,#e086b0)" note="Hồi 2%/phút" />
        <Meter label="AP" value={localAp} max={maxAp} color="linear-gradient(90deg,#3d9e6b,#8fe0b0)" note="+1 mỗi phút" />
      </div>

      {/* Danh sách vùng */}
      <div className="flex flex-col gap-2 mb-5">
        {visibleZones.map((z) => {
          const selected = z.id === selectedId
          const danger = zoneDanger(level, z)
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
                  {danger.note && <div className="text-xs text-[#7d7a8c] mt-0.5">{danger.note}</div>}
                </div>
                <div className="flex flex-col items-end gap-1 shrink-0">
                  <span className={`rounded-full border px-2 py-0.5 text-xs font-semibold ${danger.cls}`}>{danger.label}</span>
                  <span className="text-xs text-[#a29fb3]">{z.apCost} AP/10 trận</span>
                </div>
              </div>

              {selected && (
                <div className="mt-3 pt-3 border-t border-white/[0.08] text-xs text-[#a29fb3] space-y-1.5">
                  {z.description && <p>{z.description}</p>}
                  {z.enemies.length > 0 && (
                    <div className="flex flex-wrap gap-2 pt-1">
                      {z.enemies.map((e) => (
                        <span key={e.name} className="flex w-16 flex-col items-center gap-1 text-center">
                          <EnemyAvatar name={e.name} size={48} boss={e.is_boss} />
                          <span className={`leading-tight ${e.is_boss ? 'text-[#f0a8a8]' : 'text-[#c9c4d4]'}`}>
                            {e.is_boss && '👑 '}
                            {e.name}
                          </span>
                          <span className="text-[#7d7a8c]">Lv{e.level}</span>
                        </span>
                      ))}
                    </div>
                  )}
                  {z.traits.length > 0 && (
                    <div className="space-y-0.5">
                      {z.traits.map((t) => (
                        <p key={t}>
                          Đặc tính vùng: {ENEMY_TRAITS[t]?.icon}{' '}
                          <span className="text-[#e5e1ed]">{ENEMY_TRAITS[t]?.name ?? t}</span>
                          <span className="text-[#7d7a8c]"> — {ENEMY_TRAITS[t]?.desc}</span>
                        </p>
                      ))}
                    </div>
                  )}
                  <p className="text-[#7d7a8c]">
                    Quái thường có thể xuất hiện dạng <span className="text-[#8fc4e0]">Tinh Anh</span> hoặc hiếm hơn là{' '}
                    <span className="text-[#f0c060]">Hung Thần</span> — mạnh hơn, thêm 1–2 đặc tính, thưởng lớn hơn. Boss luôn Cuồng Nộ.
                  </p>
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
        {visibleZones.length < zones.length || showAll ? (
          <button
            type="button"
            onClick={() => setShowAll((v) => !v)}
            className="rounded-2xl border border-dashed border-white/15 py-2.5 text-sm text-[#a29fb3] hover:text-white"
          >
            {showAll ? 'Chỉ hiện vùng hợp cấp' : `Hiện tất cả ${zones.length} vùng`}
          </button>
        ) : null}
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
                ? `Thiếu AP (cần ${zone.apCost} cho 10 trận)`
                : `Thám hiểm ${Math.min(turns, maxTurnsByAp)} lượt · −${apCostFor(Math.min(turns, maxTurnsByAp))} AP`}
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
  // Chạm trán đáng chú ý: Hung Thần + boss hiện ảnh lớn; Tinh Anh chỉ đếm
  const notable = result.fights.filter((f) => ['champion', 'boss'].includes(enemyTier(f.enemy, f.boss)))
  const elites = result.fights.filter((f) => enemyTier(f.enemy, f.boss) === 'elite')
  const elitesWon = elites.filter((f) => f.result === 'win').length
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

      {(notable.length > 0 || elites.length > 0) && (
        <div className="mt-3 rounded-xl bg-black/20 border border-white/[0.06] p-3">
          {notable.length > 0 && (
            <div className="flex flex-wrap gap-3 mb-2">
              {notable.map((f) => (
                <div key={f.turn} className="flex w-20 flex-col items-center gap-1 text-center text-xs">
                  <EnemyAvatar name={f.enemy} size={64} boss={f.boss} />
                  <span className={`leading-tight ${ENEMY_TIER_TEXT[enemyTier(f.enemy, f.boss)]}`}>{f.enemy}</span>
                  <span className={f.result === 'win' ? 'text-[#8fe0b0]' : 'text-[#e09595]'}>
                    T{f.turn} · {f.result === 'win' ? 'hạ' : f.result === 'flee' ? 'rút lui' : 'gục'}
                  </span>
                </div>
              ))}
            </div>
          )}
          {elites.length > 0 && (
            <p className="text-xs text-[#a29fb3]">
              <span className="text-[#8fc4e0]">Tinh Anh</span>: gặp {elites.length}, hạ {elitesWon}
            </p>
          )}
        </div>
      )}

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
        <SupplyResult potionsUsed={result.potions_used} guardUsed={result.guard_used} buffs={result.buffs} />
        {!!(result.penalty && (result.penalty.gold || result.penalty.exp)) && (
          <p className="text-[#e09595]">
            💀 Phạt khi gục: −{result.penalty.gold.toLocaleString('vi-VN')} vàng · −{result.penalty.exp} EXP
          </p>
        )}
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
  const [open, setOpen] = useState(false)
  const pct = Math.max(0, Math.min(100, (f.hp_left / Math.max(1, maxHp)) * 100))
  const barColor = pct > 50 ? '#8fe0b0' : pct > 20 ? '#f0c060' : '#e07070'
  const hasLog = !!f.log?.length

  return (
    <div className={`px-3 py-2 text-xs ${f.result === 'lose' ? 'bg-[#e07070]/[0.08]' : ''}`}>
      <div
        className={`flex items-center gap-1.5 flex-wrap ${hasLog ? 'cursor-pointer' : ''}`}
        onClick={hasLog ? () => setOpen((v) => !v) : undefined}
      >
        {hasLog && <span className="text-[#7d7a8c] w-2.5">{open ? '▾' : '▸'}</span>}
        <span>{f.result === 'win' ? '✅' : f.result === 'flee' ? '⏱️' : '💀'}</span>
        <b className="text-white">T{f.turn}</b>
        <EnemyAvatar name={f.enemy} size={24} boss={f.boss} />
        <span className={ENEMY_TIER_TEXT[enemyTier(f.enemy, f.boss)]}>
          {f.boss && '👑 '}
          {f.enemy} <span className="text-[#7d7a8c] font-normal">Lv{f.level}</span>
        </span>
        <EnemyTraits traits={f.traits} />
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
        {f.guard && <span className="text-[#c8f5dc]">🛡️ Bùa cứu</span>}
        {f.potion && <span className="text-[#c8f5dc]">🧪 {f.potion}</span>}
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
      {open && f.log && <LastFightLog fight={{ turn: f.turn, enemy: f.enemy, log: f.log }} />}
    </div>
  )
}


