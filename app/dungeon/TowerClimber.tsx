'use client'

import { useEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { ItemIcon, LastFightLog, Meter, RARITY_TEXT, type LastFight } from '../components/combat-ui'
import EnemyAvatar, { ENEMY_TIER_TEXT, EnemyTraits, enemyTier } from '../components/EnemyAvatar'
import SupplyResult from '../components/SupplyResult'

const AP_PER_FLOOR = 5
const PREVIEW_FLOORS = 10

type FloorEnemy = {
  out_idx: number
  out_name: string
  out_level: number
  out_kind: 'normal' | 'elite' | 'boss'
  out_traits?: string[]
}

type ClimbFloor = {
  floor: number
  cleared: boolean
  first_clear?: boolean
  exp?: number
  gold?: number
  drops?: { key: string; name: string; icon: string | null; rarity: string; qty: number }[]
  enemies: {
    name: string
    level: number
    kind: string
    result: 'win' | 'lose' | 'flee'
    hp_left: number
    dmg_taken: number
    log?: LastFight['log']
    traits?: string[]
  }[]
}

type ClimbResult = {
  start_floor: number
  floors_attempted: number
  floors_cleared: number
  stop: 'died' | 'fled' | 'no_ap' | 'max_floors' | 'top'
  tower_best: number
  exp_gained: number
  potions_used?: number
  guard_used?: boolean
  buffs?: { exp?: boolean; luck?: boolean }
  gold_gained: number
  leveled_up: boolean
  new_level: number
  hp_left: number
  max_hp: number
  ap_left: number
  penalty?: { gold: number; exp: number }
  floors: ClimbFloor[]
  last_fight: { floor: number; enemy: string; log: LastFight['log'] } | null
}

const STOP_TEXT: Record<ClimbResult['stop'], string> = {
  died: '💀 Gục ngã',
  fled: '⏱️ Hết 30 lượt, phải rút lui',
  no_ap: '⚡ Hết AP',
  max_floors: '✓ Đủ số tầng đã chọn',
  top: '🌌 Đã lên tới đỉnh tháp!',
}

const KIND_ICON: Record<string, string> = { normal: '•', elite: '⭐', boss: '👑' }

export default function TowerClimber({
  characterId,
  towerBest,
  currentHp,
  maxHp,
  currentAp,
  maxAp,
}: {
  characterId: string
  towerBest: number
  currentHp: number
  maxHp: number
  currentAp: number
  maxAp: number
}) {
  const router = useRouter()
  const [best, setBest] = useState(towerBest)
  const checkpoints = Array.from({ length: Math.floor(Math.min(best, 99) / 10) + 1 }, (_, i) => i * 10 + 1)
  const [start, setStart] = useState(checkpoints[checkpoints.length - 1])
  const [maxFloors, setMaxFloors] = useState(10)
  const [hp, setHp] = useState(currentHp)
  const [ap, setAp] = useState(currentAp)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<ClimbResult | null>(null)
  const [preview, setPreview] = useState<Record<number, FloorEnemy[]>>({})

  const affordable = Math.floor(ap / AP_PER_FLOOR)
  const floors = Math.min(maxFloors, affordable, 101 - start)

  // Xem trước thành phần các tầng sắp leo (cố định theo số tầng, lấy từ server)
  useEffect(() => {
    const wanted = Array.from({ length: Math.min(PREVIEW_FLOORS, 101 - start) }, (_, i) => start + i).filter(
      (f) => !preview[f]
    )
    if (wanted.length === 0) return
    const supabase = createClient()
    Promise.all(wanted.map((f) => supabase.rpc('tower_floor_enemies', { p_floor: f }))).then((res) => {
      const next: Record<number, FloorEnemy[]> = {}
      res.forEach((r, i) => {
        if (r.data) next[wanted[i]] = r.data as FloorEnemy[]
      })
      setPreview((p) => ({ ...p, ...next }))
    })
  }, [start, preview])

  async function climb() {
    setBusy(true)
    setError(null)
    setResult(null)
    const { data, error: rpcError } = await createClient().rpc('climb_tower', {
      p_character_id: characterId,
      p_start_floor: start,
      p_max_floors: maxFloors,
    })
    setBusy(false)
    if (rpcError) return setError(rpcError.message)
    const res = data as ClimbResult
    setResult(res)
    setHp(res.hp_left)
    setAp(res.ap_left)
    setBest(res.tower_best)
    router.refresh()
  }

  const exhausted = hp <= 1

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3">
        <Meter label="HP" value={hp} max={maxHp} color="linear-gradient(90deg,#b06fd8,#e086b0)" note="Hồi 2%/phút" />
        <Meter label="AP" value={ap} max={maxAp} color="linear-gradient(90deg,#3d9e6b,#8fe0b0)" note="+1 mỗi phút" />
      </div>

      <div className="rounded-2xl bg-white/[0.045] border border-white/[0.09] p-4">
        <p className="text-xs text-[#a29fb3]">Tầng cao nhất đã qua</p>
        <p className="text-2xl font-bold text-white">
          {best}
          <span className="text-sm text-[#7d7a8c]"> / 100</span>
        </p>
        <p className="text-xs text-[#7d7a8c] mt-1">
          Lần đầu qua tầng: +50% vàng + nguyên liệu · Tầng boss lần đầu: chắc chắn rơi trang bị
        </p>
      </div>

      {/* Điểm bắt đầu */}
      <div>
        <p className="text-sm text-[#a29fb3] mb-2">Bắt đầu từ tầng</p>
        <div className="flex flex-wrap gap-1.5">
          {checkpoints.map((c) => (
            <button
              key={c}
              onClick={() => setStart(c)}
              className={`rounded-lg border px-3 py-1.5 text-sm ${
                start === c ? 'border-[#b06fd8]/70 bg-[#b06fd8]/20 text-white' : 'border-white/[0.09] text-[#a29fb3]'
              }`}
            >
              {c}
            </button>
          ))}
        </div>
      </div>

      {/* Số tầng tối đa */}
      <div className="rounded-2xl bg-white/[0.045] border border-white/[0.09] p-4">
        <div className="flex items-center justify-between mb-3">
          <label htmlFor="floors" className="text-sm text-[#a29fb3]">
            Leo tối đa
          </label>
          <span className="text-lg font-semibold text-white">{maxFloors} tầng</span>
        </div>
        <input
          id="floors"
          type="range"
          min={1}
          max={20}
          value={maxFloors}
          onChange={(e) => setMaxFloors(Number(e.target.value))}
          className="w-full accent-[#b06fd8]"
        />
        <p className="text-xs text-[#7d7a8c] mt-2">
          Tối đa {maxFloors * AP_PER_FLOOR} AP · AP hiện có đủ cho {affordable} tầng. Chỉ trừ AP cho tầng thật sự đánh.
        </p>
      </div>

      {/* Xem trước */}
      <div className="rounded-2xl bg-white/[0.045] border border-white/[0.09] p-4">
        <p className="text-sm text-[#a29fb3] mb-2">Các tầng phía trước</p>
        <ul className="space-y-1.5">
          {Array.from({ length: Math.min(PREVIEW_FLOORS, 101 - start) }, (_, i) => start + i).map((f) => {
            const enemies = preview[f]
            const boss = f % 10 === 0
            return (
              <li key={f} className={`flex items-center gap-2 text-xs ${boss ? 'text-[#f0a8a8]' : 'text-[#c9c4d4]'}`}>
                <span className={`w-12 shrink-0 ${f <= best ? 'text-[#7d7a8c]' : 'text-white'}`}>T{f}</span>
                <span className="min-w-0 flex flex-wrap items-center gap-x-3 gap-y-1">
                  {enemies
                    ? enemies.map((e) => (
                        <span key={e.out_idx} className="inline-flex items-center gap-1.5">
                          <EnemyAvatar name={e.out_name} size={boss ? 40 : 32} boss={e.out_kind === 'boss'} />
                          <span className={ENEMY_TIER_TEXT[enemyTier(e.out_name, e.out_kind === 'boss')]}>
                            {KIND_ICON[e.out_kind]} {e.out_name}
                          </span>
                          <span className="text-[#7d7a8c]">Lv{e.out_level}</span>
                          <EnemyTraits traits={e.out_traits} />
                        </span>
                      ))
                    : '…'}
                </span>
              </li>
            )
          })}
        </ul>
      </div>

      <button
        onClick={climb}
        disabled={busy || exhausted || floors < 1}
        className="w-full rounded-2xl py-4 text-lg font-bold text-white border border-[#b06fd8]/50
          bg-gradient-to-r from-[#6b4a7a]/70 to-[#6b4a7a]/25 disabled:opacity-40"
      >
        {busy
          ? 'Đang leo…'
          : exhausted
            ? 'Kiệt sức — chờ hồi HP'
            : floors < 1
              ? `Thiếu AP (mỗi tầng ${AP_PER_FLOOR})`
              : `Leo từ tầng ${start} · tối đa ${floors} tầng`}
      </button>

      {error && <p className="text-sm text-[#e09595]">{error}</p>}
      {result && <ClimbReport result={result} />}
    </div>
  )
}

function ClimbReport({ result }: { result: ClimbResult }) {
  const [showLast, setShowLast] = useState(false)
  const listRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (listRef.current) listRef.current.scrollTop = listRef.current.scrollHeight
  }, [result])

  const drops = result.floors.flatMap((f) => f.drops ?? [])

  return (
    <div className="rounded-2xl bg-white/[0.045] border border-white/[0.09] p-4">
      <p className="text-base font-semibold text-white">
        {STOP_TEXT[result.stop]}
        <span className="font-normal text-[#a29fb3]">
          {' '}
          · qua {result.floors_cleared}/{result.floors_attempted} tầng (từ tầng {result.start_floor})
        </span>
      </p>

      <div
        ref={listRef}
        className="mt-3 max-h-96 overflow-y-auto rounded-xl bg-black/30 border border-white/[0.06] divide-y divide-white/[0.05]"
      >
        {result.floors.map((f) => (
          <div key={f.floor} className={`px-3 py-2 text-xs ${f.cleared ? '' : 'bg-[#e07070]/[0.08]'}`}>
            <div className="flex items-baseline gap-1.5 flex-wrap">
              <span>{f.cleared ? '✅' : '💀'}</span>
              <b className={f.floor % 10 === 0 ? 'text-[#f0a8a8]' : 'text-white'}>Tầng {f.floor}</b>
              {f.first_clear && <span className="text-[#f0c060]">· lần đầu!</span>}
              {f.cleared && (
                <span className="text-[#f0c060]">
                  +{f.exp}EXP +{f.gold}G
                </span>
              )}
            </div>
            <div className="mt-1 space-y-0.5">
              {f.enemies.map((e, i) => (
                <EnemyRow key={i} floor={f.floor} enemy={e} maxHp={result.max_hp} />
              ))}
            </div>
            {(f.drops ?? []).length > 0 && (
              <div className="mt-1 flex flex-wrap gap-2">
                {f.drops!.map((d, i) => (
                  <span key={i} className={`flex items-center gap-1 ${RARITY_TEXT[d.rarity] ?? RARITY_TEXT.common}`}>
                    <ItemIcon icon={d.icon} size={14} />+{d.name}
                    {d.qty > 1 && ` ×${d.qty}`}
                  </span>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>

      {result.last_fight && (
        <>
          <button onClick={() => setShowLast((v) => !v)} className="mt-3 text-xs text-[#a29fb3] hover:text-white">
            📜 {showLast ? 'Ẩn' : 'Xem'} chi tiết trận cuối (Tầng {result.last_fight.floor} · {result.last_fight.enemy})
          </button>
          {showLast && (
            <LastFightLog fight={{ turn: result.last_fight.floor, enemy: result.last_fight.enemy, log: result.last_fight.log }} />
          )}
        </>
      )}

      <div className="mt-4 pt-4 border-t border-white/[0.08] space-y-1.5 text-sm">
        <p className="text-white">
          ✨ Tổng: <b className="text-[#f0c060]">+{result.exp_gained} EXP</b> ·{' '}
          <b className="text-[#f0c060]">+{result.gold_gained} Vàng</b>
        </p>
        <p className="text-[#e5e1ed]">
          🗼 Tầng cao nhất: {result.tower_best} · ❤️ HP còn {result.hp_left}/{result.max_hp} · ⚡ AP còn {result.ap_left}
        </p>
        <SupplyResult potionsUsed={result.potions_used} guardUsed={result.guard_used} buffs={result.buffs} />
        {!!(result.penalty && (result.penalty.gold || result.penalty.exp)) && (
          <p className="text-[#e09595]">
            💀 Phạt khi gục: −{result.penalty.gold.toLocaleString('vi-VN')} vàng · −{result.penalty.exp} EXP
          </p>
        )}
        {result.leveled_up && <p className="text-[#f0c060]">⭐ Lên cấp {result.new_level}!</p>}
        {drops.length > 0 && (
          <p className="text-[#a29fb3]">🎁 Nhặt được {drops.reduce((n, d) => n + d.qty, 0)} vật phẩm — xem trong Túi Đồ</p>
        )}
      </div>
    </div>
  )
}

function EnemyRow({ floor, enemy: e, maxHp }: { floor: number; enemy: ClimbFloor['enemies'][number]; maxHp: number }) {
  const [open, setOpen] = useState(false)
  const hasLog = !!e.log?.length
  return (
    <div>
      <p
        className={`flex flex-wrap items-center gap-x-1 text-[#a29fb3] ${hasLog ? 'cursor-pointer' : ''}`}
        onClick={hasLog ? () => setOpen((v) => !v) : undefined}
      >
        {hasLog && <span className="text-[#7d7a8c] w-2.5">{open ? '▾' : '▸'}</span>}
        <EnemyAvatar name={e.name} size={24} boss={e.kind === 'boss'} />
        <span className={ENEMY_TIER_TEXT[enemyTier(e.name, e.kind === 'boss')]}>
          {KIND_ICON[e.kind]} {e.name}
        </span>
        <EnemyTraits traits={e.traits} /> Lv{e.level} →{' '}
        <span className={e.result === 'win' ? 'text-[#8fe0b0]' : 'text-[#e09595]'}>
          {e.result === 'win' ? 'hạ' : e.result === 'flee' ? 'rút lui' : 'gục'}
        </span>{' '}
        · 😓 -{e.dmg_taken} · ❤️ {e.hp_left}/{maxHp}
      </p>
      {open && e.log && <LastFightLog fight={{ turn: floor, enemy: e.name, log: e.log }} />}
    </div>
  )
}
