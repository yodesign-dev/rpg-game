'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/client'
import {
  ATTRIBUTE_INFO,
  ATTRIBUTE_KEYS,
  attributeBonuses,
  type AttributeKey,
  type Attributes,
} from '@/lib/character-stats'


const EMPTY: Attributes = { str: 0, int: 0, agi: 0, dex: 0, vit: 0 }

export default function StatAllocator({
  characterId,
  mainStat,
  attributes,
  statPoints,
  autoAllocate,
  freeResetUsed,
  resetCost,
  gold,
  totals,
}: {
  characterId: string
  mainStat: string
  attributes: Attributes
  statPoints: number
  autoAllocate: boolean
  freeResetUsed: boolean
  resetCost: number
  gold: number
  // Chỉ số tổng (đã cộng trang bị) từ get_character_stats
  totals: { atk: number; def: number; maxHp: number; crit: number }
}) {
  const router = useRouter()
  const [pending, setPending] = useState<Attributes>(EMPTY)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [confirmReset, setConfirmReset] = useState(false)
  const [localAuto, setLocalAuto] = useState(autoAllocate)

  const pendingTotal = ATTRIBUTE_KEYS.reduce((s, k) => s + pending[k], 0)
  const remaining = statPoints - pendingTotal
  const spentTotal = ATTRIBUTE_KEYS.reduce((s, k) => s + attributes[k], 0)
  const actualResetCost = freeResetUsed ? resetCost : 0

  // Xem trước: chênh lệch hiệu ứng giữa (hiện tại + đang chọn) và hiện tại
  const next = Object.fromEntries(ATTRIBUTE_KEYS.map((k) => [k, attributes[k] + pending[k]])) as Attributes
  const before = attributeBonuses(mainStat, attributes)
  const after = attributeBonuses(mainStat, next)
  const preview = {
    atk: totals.atk + after.atk - before.atk,
    def: totals.def + after.def - before.def,
    maxHp: totals.maxHp + after.hp - before.hp,
    crit: totals.crit + after.crit - before.crit,
  }

  function bump(key: AttributeKey, delta: number) {
    setError(null)
    setPending((p) => {
      const v = p[key] + delta
      if (v < 0 || (delta > 0 && remaining <= 0)) return p
      return { ...p, [key]: v }
    })
  }

  async function run(fn: () => PromiseLike<{ error: { message: string } | null }>) {
    setBusy(true)
    setError(null)
    const { error: rpcError } = await fn()
    setBusy(false)
    if (rpcError) {
      setError(rpcError.message)
      return false
    }
    setPending(EMPTY)
    setConfirmReset(false)
    router.refresh()
    return true
  }

  const confirm = () =>
    run(() =>
      createClient().rpc('allocate_stats', {
        p_character_id: characterId,
        p_str: pending.str,
        p_int: pending.int,
        p_agi: pending.agi,
        p_dex: pending.dex,
        p_vit: pending.vit,
      })
    )

  const autoAllocateNow = () => run(() => createClient().rpc('auto_allocate_stats', { p_character_id: characterId }))

  const reset = () => {
    if (!confirmReset) {
      setConfirmReset(true)
      return
    }
    run(() => createClient().rpc('reset_stats', { p_character_id: characterId }))
  }

  async function toggleAuto() {
    const value = !localAuto
    setLocalAuto(value)
    const ok = await run(() =>
      createClient().from('characters').update({ auto_allocate_stats: value }).eq('id', characterId)
    )
    if (!ok) setLocalAuto(!value)
  }

  return (
    <div className={`${ui.className} rounded-[22px] bg-white/[0.045] border border-white/[0.09] p-5 mb-4`}>
      <div className="flex items-center justify-between mb-4">
        <span className="text-sm tracking-[3px] text-[#a29fb3]">CHỈ SỐ</span>
        {remaining > 0 ? (
          <span className="text-xs font-semibold text-[#e3caf5] bg-[#b06fd8]/20 border border-[#b06fd8]/50 rounded-full px-2.5 py-1">
            +{remaining} điểm
          </span>
        ) : (
          <span className="text-xs text-[#7d7a8c]">Hết điểm</span>
        )}
      </div>

      {/* Chỉ số tổng + xem trước */}
      <div className="grid grid-cols-4 gap-2 mb-4">
        <Derived label="ATK" value={totals.atk} next={preview.atk} />
        <Derived label="DEF" value={totals.def} next={preview.def} />
        <Derived label="HP" value={totals.maxHp} next={preview.maxHp} />
        <Derived
          label="CRIT"
          value={totals.crit}
          next={preview.crit}
          format={(v) => `${(Math.min(0.75, v) * 100).toFixed(1)}%`}
        />
      </div>

      {/* 5 chỉ số gốc */}
      <div className="flex flex-col gap-1.5">
        {ATTRIBUTE_KEYS.map((key) => {
          const info = ATTRIBUTE_INFO[key]
          const isMain = key === mainStat
          const useless = (key === 'str' || key === 'int') && !isMain
          return (
            <div
              key={key}
              className={`flex items-center gap-3 rounded-xl px-3 py-2 border ${
                isMain ? 'bg-[#b06fd8]/[0.12] border-[#b06fd8]/40' : 'bg-white/[0.03] border-transparent'
              } ${useless ? 'opacity-50' : ''}`}
            >
              <div className="w-11 shrink-0">
                <div className={`text-sm font-semibold ${isMain ? 'text-[#e3caf5]' : 'text-[#e5e1ed]'}`}>
                  {info.label}
                </div>
                {isMain && <div className="text-xs tracking-wide text-[#b06fd8]">CHÍNH</div>}
              </div>
              <div className="flex-grow min-w-0">
                <div className="text-xs text-[#a29fb3]">{info.name}</div>
                <div className="text-xs leading-snug text-[#7d7a8c]">{info.effect(isMain)}</div>
              </div>
              <div className="flex items-center gap-1.5 shrink-0">
                <StepButton label="−" disabled={busy || pending[key] === 0} onClick={() => bump(key, -1)} />
                <span className="w-11 text-center text-sm text-white">
                  {attributes[key]}
                  {pending[key] > 0 && <span className="text-[#8fe0b0]">+{pending[key]}</span>}
                </span>
                <StepButton label="+" disabled={busy || remaining <= 0} onClick={() => bump(key, 1)} />
              </div>
            </div>
          )
        })}
      </div>

      {error && <p className="text-xs text-[#e09595] mt-3">{error}</p>}

      {/* Hành động */}
      <div className="flex gap-2 mt-4">
        {pendingTotal > 0 ? (
          <>
            <ActionButton primary disabled={busy} onClick={confirm}>
              Cộng {pendingTotal} điểm
            </ActionButton>
            <ActionButton disabled={busy} onClick={() => setPending(EMPTY)}>
              Hủy
            </ActionButton>
          </>
        ) : (
          <ActionButton primary disabled={busy || statPoints === 0} onClick={autoAllocateNow}>
            Tự cộng
          </ActionButton>
        )}
        <ActionButton disabled={busy || spentTotal === 0} onClick={reset}>
          {confirmReset ? 'Chắc chưa?' : 'Tẩy điểm'}
        </ActionButton>
      </div>
      {confirmReset && (
        <p className={`text-xs mt-2 ${actualResetCost > gold ? 'text-[#e09595]' : 'text-[#a29fb3]'}`}>
          {actualResetCost === 0
            ? 'Lần tẩy đầu miễn phí — bấm lần nữa để trả lại toàn bộ điểm.'
            : actualResetCost > gold
              ? `Cần ${actualResetCost} vàng, bạn chỉ có ${gold}.`
              : `Tốn ${actualResetCost} vàng — bấm lần nữa để trả lại toàn bộ điểm.`}
        </p>
      )}

      <label className="flex items-center justify-between mt-4 text-xs text-[#a29fb3] cursor-pointer">
        <span>Tự cộng khi lên cấp</span>
        <button
          type="button"
          role="switch"
          aria-checked={localAuto}
          disabled={busy}
          onClick={toggleAuto}
          className={`relative w-10 h-6 rounded-full transition-colors ${
            localAuto ? 'bg-[#b06fd8]' : 'bg-white/[0.12]'
          }`}
        >
          <span
            className={`absolute top-1 left-1 w-4 h-4 rounded-full bg-white transition-transform ${
              localAuto ? 'translate-x-4' : ''
            }`}
          />
        </button>
      </label>
    </div>
  )
}

function Derived({
  label,
  value,
  next,
  format = (v) => String(v),
}: {
  label: string
  value: number
  next: number
  format?: (v: number) => string
}) {
  const changed = format(next) !== format(value)
  return (
    <div className="rounded-xl bg-white/[0.04] px-2 py-2 text-center">
      <div className="text-xs tracking-wide text-[#7d7a8c]">{label}</div>
      <div className="text-sm font-semibold text-white">{format(value)}</div>
      {changed && <div className="text-xs text-[#8fe0b0]">→ {format(next)}</div>}
    </div>
  )
}

function StepButton({ label, disabled, onClick }: { label: string; disabled: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-label={label === '+' ? 'Tăng' : 'Giảm'}
      disabled={disabled}
      onClick={onClick}
      className="w-8 h-8 rounded-lg bg-white/[0.07] border border-white/[0.1] text-base text-white
        hover:bg-white/[0.12] disabled:opacity-30 disabled:cursor-not-allowed"
    >
      {label}
    </button>
  )
}

function ActionButton({
  children,
  primary,
  disabled,
  onClick,
}: {
  children: React.ReactNode
  primary?: boolean
  disabled: boolean
  onClick: () => void
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className={`flex-1 whitespace-nowrap rounded-xl px-2 py-2.5 text-sm font-semibold border transition-colors
        disabled:opacity-40 disabled:cursor-not-allowed ${
          primary
            ? 'bg-[#b06fd8]/25 border-[#b06fd8]/60 text-[#f0e0fb] hover:bg-[#b06fd8]/35'
            : 'bg-white/[0.05] border-white/[0.1] text-[#e5e1ed] hover:bg-white/[0.09]'
        }`}
    >
      {children}
    </button>
  )
}
