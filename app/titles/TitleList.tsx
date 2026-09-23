'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

export type TitleRow = {
  key: string
  name: string
  emoji: string
  description: string
  stat: string
  threshold: number
  owned: boolean
  progress: number
}

export default function TitleList({
  characterId,
  rows,
  equipped,
}: {
  characterId: string
  rows: TitleRow[]
  equipped: string | null
}) {
  const router = useRouter()
  const [current, setCurrent] = useState(equipped)
  const [busy, setBusy] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function wear(key: string | null) {
    setBusy(key ?? 'none')
    setError(null)
    const { error: rpcError } = await createClient().rpc('set_title', { p_character_id: characterId, p_title_key: key })
    setBusy(null)
    if (rpcError) return setError(rpcError.message)
    setCurrent(key)
    router.refresh()
  }

  const ownedCount = rows.filter((r) => r.owned).length

  return (
    <div className="space-y-2">
      <p className="text-xs text-[#a29fb3] mb-3">
        Đã mở khóa {ownedCount}/{rows.length}
        {current && (
          <button onClick={() => wear(null)} disabled={busy !== null} className="ml-3 underline hover:text-white">
            Tháo danh hiệu
          </button>
        )}
      </p>
      {error && <p className="text-sm text-[#e09595]">{error}</p>}
      {rows.map((t) => {
        const wearing = current === t.key
        const pct = Math.round((t.progress / t.threshold) * 100)
        return (
          <div
            key={t.key}
            className={`rounded-2xl border p-4 flex items-center gap-3 ${
              wearing
                ? 'border-[#f0c060]/60 bg-[#f0c060]/10'
                : t.owned
                  ? 'border-white/[0.09] bg-white/[0.045]'
                  : 'border-white/[0.05] bg-white/[0.02] opacity-60'
            }`}
          >
            <span className={`text-2xl shrink-0 ${t.owned ? '' : 'grayscale'}`}>{t.emoji}</span>
            <div className="flex-grow min-w-0">
              <p className="text-sm font-semibold text-white">{t.name}</p>
              <p className="text-[11px] text-[#a29fb3]">{t.description}</p>
              {!t.owned && (
                <div className="mt-1.5 flex items-center gap-2">
                  <div className="flex-grow h-1 rounded-full bg-white/[0.07] overflow-hidden">
                    <div className="h-full bg-[#b06fd8]" style={{ width: `${pct}%` }} />
                  </div>
                  <span className="text-[10px] text-[#7d7a8c] tabular-nums">
                    {t.progress}/{t.threshold}
                  </span>
                </div>
              )}
            </div>
            {t.owned &&
              (wearing ? (
                <span className="text-xs text-[#f0c060] shrink-0">Đang đeo</span>
              ) : (
                <button
                  onClick={() => wear(t.key)}
                  disabled={busy !== null}
                  className="shrink-0 rounded-xl border border-white/20 text-xs text-white px-3 py-2 hover:bg-white/10 disabled:opacity-40"
                >
                  {busy === t.key ? '…' : 'Đeo'}
                </button>
              ))}
          </div>
        )
      })}
    </div>
  )
}
