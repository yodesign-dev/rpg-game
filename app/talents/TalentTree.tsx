'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

export type TalentNode = {
  key: string
  name: string
  icon: string
  branch: string
  kind: 'start' | 'small' | 'notable' | 'keystone'
  cost: number
  x: number
  y: number
  effects: Record<string, number>
  description: string
}
export type TalentEdge = { a: string; b: string }
export type TalentState = {
  total: number
  spent: number
  available: number
  learned: string[]
  totals: Record<string, number>
  reset_cost: number
}

const RADIUS: Record<TalentNode['kind'], number> = { start: 6, small: 3.6, notable: 5, keystone: 6.6 }

// Hiển thị tổng hiệu ứng: nhãn + định dạng
const EFFECT_LABEL: Record<string, (v: number) => string> = {
  atk_pct: (v) => `${v > 0 ? '+' : '−'}${Math.round(Math.abs(v) * 100)}% ATK gốc`,
  def_pct: (v) => `${v > 0 ? '+' : '−'}${Math.round(Math.abs(v) * 100)}% DEF gốc`,
  hp_pct: (v) => `${v > 0 ? '+' : '−'}${Math.round(Math.abs(v) * 100)}% HP gốc`,
  crit: (v) => `+${(v * 100).toFixed(1)}% chí mạng`,
  lifesteal: (v) => `+${(v * 100).toFixed(1)}% hút máu`,
  dmg_red: (v) => `giảm ${Math.round(v * 100)}% sát thương nhận`,
  double: (v) => `+${Math.round(v * 100)}% Đòn Kép`,
  crit_mult: (v) => `chí mạng ×${v}`,
  opening: (v) => `đòn đầu ×${v}`,
  low_hp_ls: (v) => `hút máu ×${v} khi HP < 30%`,
}

export default function TalentTree({
  characterId,
  nodes,
  edges,
  initialState,
  gold,
}: {
  characterId: string
  nodes: TalentNode[]
  edges: TalentEdge[]
  initialState: TalentState
  gold: number
}) {
  const router = useRouter()
  const [state, setState] = useState(initialState)
  const [selected, setSelected] = useState<string | null>(null)
  const [hovered, setHovered] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [confirmReset, setConfirmReset] = useState(false)

  const byKey = useMemo(() => Object.fromEntries(nodes.map((n) => [n.key, n])), [nodes])
  const learned = useMemo(() => new Set(['origin', ...state.learned]), [state.learned])
  const neighbors = useMemo(() => {
    const m: Record<string, string[]> = {}
    for (const e of edges) {
      ;(m[e.a] ??= []).push(e.b)
      ;(m[e.b] ??= []).push(e.a)
    }
    return m
  }, [edges])

  const reachable = (key: string) => !learned.has(key) && (neighbors[key] ?? []).some((n) => learned.has(n))
  const learnable = (n: TalentNode) => reachable(n.key) && state.available >= n.cost

  const sel = selected ? byKey[selected] : null
  const hov = hovered ? byKey[hovered] : null

  const status = (n: TalentNode) =>
    learned.has(n.key)
      ? { text: '✓ Đã học', cls: 'text-[#f0c060]' }
      : learnable(n)
        ? { text: 'Bấm để học', cls: 'text-[#8fe0b0]' }
        : !reachable(n.key)
          ? { text: '🔒 Cần học ô liền kề trước', cls: 'text-[#8a8499]' }
          : { text: `Thiếu điểm (cần ${n.cost})`, cls: 'text-[#e09595]' }

  async function learn(key: string) {
    setBusy(true)
    setError(null)
    const { data, error: rpcError } = await createClient().rpc('learn_talent', {
      p_character_id: characterId,
      p_node_key: key,
    })
    setBusy(false)
    if (rpcError) return setError(rpcError.message)
    setState(data as TalentState)
    router.refresh()
  }

  async function reset() {
    if (!confirmReset) return setConfirmReset(true)
    setBusy(true)
    setError(null)
    const { data, error: rpcError } = await createClient().rpc('reset_talents', { p_character_id: characterId })
    setBusy(false)
    setConfirmReset(false)
    if (rpcError) return setError(rpcError.message)
    setState(data as TalentState)
    setSelected(null)
    router.refresh()
  }

  const totals = Object.entries(state.totals ?? {}).filter(([k]) => EFFECT_LABEL[k])

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <p className="text-sm text-white">
          Điểm còn: <b className="text-[#f0c060] text-lg">{state.available}</b>
          <span className="text-[#7d7a8c]"> / {state.total}</span>
        </p>
        {state.learned.length > 0 && (
          <button
            onClick={reset}
            disabled={busy || gold < state.reset_cost}
            className="text-xs rounded-lg border border-white/20 px-3 py-1.5 text-[#c9c4d4] hover:bg-white/10 disabled:opacity-40"
          >
            {confirmReset ? `Tẩy hết? −${state.reset_cost} vàng` : `↺ Tẩy cây (${state.reset_cost} vàng)`}
          </button>
        )}
      </div>

      <div className="rounded-2xl border border-white/[0.09] bg-[radial-gradient(circle_at_center,rgba(107,74,122,.18),transparent_70%)] p-2">
        <div className="relative">
          <svg
            viewBox="-100 -100 200 200"
            className="w-full h-auto select-none"
            role="img"
            aria-label="Cây thiên phú"
            onClick={(e) => e.target === e.currentTarget && setHovered(null)}
          >
            {edges.map((e) => {
              const a = byKey[e.a]
              const b = byKey[e.b]
              if (!a || !b) return null
              const on = learned.has(e.a) && learned.has(e.b)
              return (
                <line
                  key={`${e.a}-${e.b}`}
                  x1={a.x}
                  y1={a.y}
                  x2={b.x}
                  y2={b.y}
                  stroke={on ? '#f0c060' : '#4a3f5c'}
                  strokeWidth={on ? 0.9 : 0.6}
                  strokeOpacity={on ? 0.9 : 0.7}
                />
              )
            })}
            {nodes.map((n) => {
              const isLearned = learned.has(n.key)
              const canLearn = learnable(n)
              const r = RADIUS[n.kind]
              return (
                <g
                  key={n.key}
                  onClick={() => {
                    setSelected(n.key)
                    setHovered(n.key) // màn cảm ứng không có hover → chạm cũng hiện gợi ý
                  }}
                  onMouseEnter={() => setHovered(n.key)}
                  onMouseLeave={() => setHovered((h) => (h === n.key ? null : h))}
                  className="cursor-pointer"
                >
                  {n.kind === 'keystone' && (
                    <circle cx={n.x} cy={n.y} r={r + 1.4} fill="none" stroke="#c0703a" strokeWidth={0.7} />
                  )}
                  <circle
                    cx={n.x}
                    cy={n.y}
                    r={r}
                    fill={isLearned ? '#f0d890' : '#1e1a2a'}
                    stroke={selected === n.key ? '#ffffff' : isLearned ? '#f0c060' : canLearn ? '#8fe0b0' : '#3a3348'}
                    strokeWidth={selected === n.key ? 1 : canLearn ? 0.9 : 0.6}
                    opacity={isLearned || canLearn || n.kind === 'start' ? 1 : 0.7}
                  />
                  <text x={n.x} y={n.y + r * 0.38} textAnchor="middle" fontSize={r * 1.05}>
                    {n.icon}
                  </text>
                  {(n.kind === 'notable' || n.kind === 'keystone') && (
                    <text
                      x={n.x}
                      y={n.y + r + 4.4}
                      textAnchor="middle"
                      fontSize={n.kind === 'keystone' ? 4 : 3.4}
                      fill={isLearned ? '#f0c060' : '#c9c4d4'}
                      fontWeight={n.kind === 'keystone' ? 700 : 400}
                    >
                      {n.name}
                    </text>
                  )}
                </g>
              )
            })}
          </svg>
          {hov && <NodeTooltip node={hov} status={status(hov)} />}
        </div>
        <p className="flex flex-wrap gap-x-3 gap-y-1 text-xs text-[#a29fb3] px-2 pb-1">
          <span>
            <span className="text-[#f0c060]">●</span> đã học
          </span>
          <span>
            <span className="text-[#8fe0b0]">●</span> học được
          </span>
          <span>
            <span className="text-[#5c5470]">●</span> khoá
          </span>
          <span>· rê chuột hoặc chạm vào ô để xem gợi ý</span>
        </p>
      </div>

      {sel && sel.kind !== 'start' && (
        <div className="rounded-2xl bg-white/[0.045] border border-white/[0.09] p-4">
          <div className="flex items-start gap-3">
            <span className="text-2xl">{sel.icon}</span>
            <div className="flex-grow min-w-0">
              <p className={`text-sm font-semibold ${sel.kind === 'keystone' ? 'text-[#f0a060]' : 'text-white'}`}>
                {sel.name}
                <span className="ml-2 text-xs font-normal text-[#7d7a8c]">
                  {sel.kind === 'keystone' ? 'Ô trùm' : sel.kind === 'notable' ? 'Ô lớn' : 'Ô nhỏ'} · {sel.cost} điểm
                </span>
              </p>
              <p className="text-xs text-[#c9c4d4] mt-1">{sel.description}</p>
            </div>
            {learned.has(sel.key) ? (
              <span className="text-xs text-[#f0c060] shrink-0">✓ Đã học</span>
            ) : (
              <button
                onClick={() => learn(sel.key)}
                disabled={busy || !learnable(sel)}
                className="shrink-0 rounded-xl border border-[#8fe0b0]/60 bg-[#8fe0b0]/15 text-[#c8f5dc] text-xs font-semibold px-3 py-2 disabled:opacity-30"
              >
                {busy ? '…' : !reachable(sel.key) ? 'Chưa liền kề' : state.available < sel.cost ? 'Thiếu điểm' : 'Học'}
              </button>
            )}
          </div>
        </div>
      )}

      {error && <p className="text-sm text-[#e09595]">{error}</p>}

      <div className="rounded-2xl bg-white/[0.045] border border-white/[0.09] p-4">
        <p className="text-xs tracking-widest text-[#7d7a8c] mb-2">TỔNG HIỆU ỨNG</p>
        {totals.length === 0 ? (
          <p className="text-xs text-[#7d7a8c]">Chưa học ô nào.</p>
        ) : (
          <ul className="flex flex-wrap gap-1.5">
            {totals.map(([k, v]) => (
              <li
                key={k}
                className={`rounded-full border px-2.5 py-1 text-xs ${
                  v < 0 && k.endsWith('_pct')
                    ? 'border-[#e09595]/40 text-[#e09595]'
                    : 'border-[#f0c060]/40 text-[#f0d890]'
                }`}
              >
                {EFFECT_LABEL[k](v)}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}

const KIND_LABEL: Record<TalentNode['kind'], string> = {
  start: 'Tâm',
  small: 'Ô nhỏ',
  notable: 'Ô lớn',
  keystone: 'Ô trùm',
}

// Tooltip nổi cạnh ô — toạ độ SVG (-100..100) quy ra % của khung vuông
function NodeTooltip({ node, status }: { node: TalentNode; status: { text: string; cls: string } }) {
  const left = (node.x + 100) / 2
  const top = (node.y + 100) / 2
  const below = node.y < -40 // ô sát mép trên thì hiện bên dưới
  const gap = `${(RADIUS[node.kind] + 2) / 2}%`
  return (
    <div
      role="tooltip"
      className="pointer-events-none absolute z-10 w-60 max-w-[80%] rounded-xl border border-white/15 bg-[#15121d]/95 px-3.5 py-2.5 shadow-xl shadow-black/60 backdrop-blur"
      style={{
        left: `${left}%`,
        top: below ? `calc(${top}% + ${gap})` : `calc(${top}% - ${gap})`,
        // dịch ngang theo đúng tỉ lệ vị trí ô → mép tooltip không bao giờ lọt ra ngoài khung
        transform: `translate(-${left}%, ${below ? '0' : '-100%'})`,
      }}
    >
      <p className={`text-sm font-semibold ${node.kind === 'keystone' ? 'text-[#f0a060]' : 'text-white'}`}>
        {node.icon} {node.name}
      </p>
      <p className="text-xs text-[#7d7a8c] mt-0.5">
        {KIND_LABEL[node.kind]}
        {node.kind !== 'start' && ` · ${node.cost} điểm`}
      </p>
      <p className="text-sm text-[#e5e1ed] mt-1.5 leading-snug">{node.description}</p>
      {node.kind !== 'start' && <p className={`text-xs mt-1.5 ${status.cls}`}>{status.text}</p>}
    </div>
  )
}
