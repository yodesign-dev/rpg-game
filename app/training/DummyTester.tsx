'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { LEGENDARY_EFFECTS } from '@/lib/legendary-effects'

type DummyResult = {
  turns: number
  dummy_def: number
  total: number
  hits: number
  max_hit: number
  crits: number
  doubles: number
  atk: number
  crit_chance: number
  effects: string[]
  log: { turn: number; skill: string; damage: number; crit: boolean; double?: boolean; opening?: boolean }[]
}

export default function DummyTester({ characterId }: { characterId: string }) {
  const [armored, setArmored] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<DummyResult | null>(null)

  async function run() {
    setBusy(true)
    setError(null)
    const { data, error: rpcError } = await createClient().rpc('training_dummy', {
      p_character_id: characterId,
      p_armored: armored,
    })
    setBusy(false)
    if (rpcError) return setError(rpcError.message)
    setResult(data as DummyResult)
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-2">
        {[
          { v: false, label: '🎯 Nộm thường', note: 'DEF 0' },
          { v: true, label: '🛡️ Nộm bọc giáp', note: 'DEF như quái cùng cấp' },
        ].map((o) => (
          <button
            key={String(o.v)}
            onClick={() => setArmored(o.v)}
            className={`rounded-2xl border p-3 text-left ${
              armored === o.v ? 'border-[#f0c060]/60 bg-[#f0c060]/10' : 'border-white/[0.09] bg-white/[0.045]'
            }`}
          >
            <p className="text-sm text-white">{o.label}</p>
            <p className="text-[11px] text-[#7d7a8c]">{o.note}</p>
          </button>
        ))}
      </div>

      <button
        onClick={run}
        disabled={busy}
        className="w-full rounded-2xl py-3.5 text-base font-bold text-white border border-[#f0c060]/40 bg-gradient-to-r from-[#8a6a1f]/60 to-[#8a6a1f]/20 disabled:opacity-40"
      >
        {busy ? 'Đang đánh…' : 'Đánh 30 lượt'}
      </button>

      {error && <p className="text-sm text-[#e09595]">{error}</p>}

      {result && (
        <div className="rounded-2xl bg-white/[0.045] border border-white/[0.09] p-4 space-y-3">
          <div className="grid grid-cols-3 gap-2">
            <Stat label="TỔNG" value={result.total.toLocaleString('vi-VN')} />
            <Stat label="TB / LƯỢT" value={Math.round(result.total / result.turns).toLocaleString('vi-VN')} />
            <Stat label="ĐÒN CAO NHẤT" value={result.max_hit.toLocaleString('vi-VN')} />
          </div>
          <p className="text-xs text-[#a29fb3]">
            ATK {result.atk} · chí mạng {(result.crit_chance * 100).toFixed(1)}% ({result.crits}/{result.hits} đòn)
            {result.doubles > 0 && ` · ⚡ Đòn Kép ${result.doubles} lần`}
            {result.dummy_def > 0 && ` · DEF nộm ${result.dummy_def}`}
          </p>
          {result.effects.length > 0 && (
            <p className="text-xs text-[#f0c060]">
              Hiệu ứng: {result.effects.map((e) => LEGENDARY_EFFECTS[e]?.name ?? e).join(', ')}
            </p>
          )}
          <div className="max-h-64 overflow-y-auto space-y-0.5 border-l border-white/[0.1] pl-3">
            {result.log.map((e, i) => (
              <p key={i} className="text-[11px] text-[#c9c4d4]">
                <span className="text-[#7d7a8c]">#{e.turn}</span> {e.double ? '⚡' : '⚔️'} {e.opening && 'Khai Cuộc! '}
                {e.skill} <b className={e.crit ? 'text-[#f0c060]' : 'text-white'}>{e.damage}</b>
                {e.crit && ' (chí mạng!)'}
              </p>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl bg-white/[0.04] px-2 py-2 text-center">
      <div className="text-[10px] tracking-wide text-[#7d7a8c]">{label}</div>
      <div className="text-sm font-semibold text-white">{value}</div>
    </div>
  )
}
