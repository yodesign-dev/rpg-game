'use client'

import { useEffect, useState } from 'react'
import { display, ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/client'
import { portraitKeys } from '@/lib/portraits'
import Portrait from '../components/Portrait'


type ClassRow = {
  id: string
  key: string
  name: string
  description: string
  base_hp: number
  base_atk: number
  base_def: number
  base_spd: number
  icon: string | null
}

// Màu riêng cho từng class — tra theo key thay vì lưu trong DB để dễ chỉnh ở frontend
const CLASS_ACCENT: Record<string, { ring: string; text: string; bar: string }> = {
  warrior:  { ring: 'ring-[#8c3f3f]', text: 'text-[#e09595]', bar: 'bg-[#8c3f3f]' },
  mage:     { ring: 'ring-[#4a4e8c]', text: 'text-[#9ea2d6]', bar: 'bg-[#4a4e8c]' },
  archer:   { ring: 'ring-[#3d6b52]', text: 'text-[#8fc4a8]', bar: 'bg-[#3d6b52]' },
  assassin: { ring: 'ring-[#6b4a7a]', text: 'text-[#b79bc4]', bar: 'bg-[#6b4a7a]' },
}

const MAX_STAT = 24 // để vẽ thanh stat theo tỉ lệ (stat cao nhất trong 4 class dao động quanh mốc này)

export default function CreateCharacterPage() {
  const [classes, setClasses] = useState<ClassRow[]>([])
  const [selected, setSelected] = useState<ClassRow | null>(null)
  const [name, setName] = useState('')
  const [portrait, setPortrait] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const supabase = createClient()
    supabase
      .from('classes')
      .select('*')
      .order('sort_order')
      .then(({ data, error }) => {
        if (error) setError(error.message)
        else setClasses(data ?? [])
        setLoading(false)
      })
  }, [])

  async function handleCreate() {
    if (!selected || !name.trim()) return
    setSubmitting(true)
    setError(null)

    const supabase = createClient()
    const { data: userData } = await supabase.auth.getUser()

    if (!userData.user) {
      setError('Bạn cần đăng nhập trước khi tạo nhân vật.')
      setSubmitting(false)
      return
    }

    const { error: insertError } = await supabase.from('characters').insert({
      user_id: userData.user.id,
      class_id: selected.id,
      name: name.trim(),
      portrait: portrait && selected && portrait.startsWith(`${selected.key}_`) ? portrait : null,
    })

    if (insertError) {
      setError(insertError.message)
      setSubmitting(false)
      return
    }

    window.location.href = '/'
  }

  return (
    <main className="min-h-screen bg-[#07070a] text-[#f2ede4] px-6 py-16">
      <div className="mx-auto max-w-5xl">
        <header className="text-center mb-14">
          <p className={`${ui.className} text-xs tracking-widest text-[#8a8499] mb-3`}>
            Chương I — Khởi Đầu
          </p>
          <h1 className={`${display.className} text-4xl md:text-5xl font-semibold text-[#f2ede4]`}>
            Chọn Con Đường Của Bạn
          </h1>
          <p className="mt-4 text-[#a29fb3] max-w-md mx-auto">
            Mỗi lớp nhân vật dẫn tới một lối chơi khác nhau. Lựa chọn này sẽ đi cùng bạn suốt hành trình.
          </p>
        </header>

        {loading && (
          <p className="text-center text-[#8a8499]">Đang tải danh sách lớp nhân vật…</p>
        )}

        {!loading && (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
            {classes.map((c) => {
              const accent = CLASS_ACCENT[c.key] ?? CLASS_ACCENT.warrior
              const isSelected = selected?.id === c.id
              return (
                <button
                  key={c.id}
                  onClick={() => {
                    setSelected(c)
                    setPortrait(`${c.key}_1`)
                  }}
                  className={`text-left rounded-xl border border-[#2a2533] bg-[#15121d] p-5 transition
                    ${isSelected ? `ring-2 ${accent.ring}` : 'hover:border-[#3a3348]'}`}
                >
                  <div className="flex items-center justify-between mb-3">
                    <div className="h-24 w-16">
                      <Portrait
                        classKey={c.key}
                        portrait={isSelected && portrait ? portrait : `${c.key}_1`}
                      />
                    </div>
                    {isSelected && (
                      <span className={`${ui.className} text-xs tracking-wider ${accent.text}`}>
                        ĐÃ CHỌN
                      </span>
                    )}
                  </div>

                  <h2 className={`${display.className} text-xl text-[#f2ede4] mb-2`}>
                    {c.name}
                  </h2>
                  <p className="text-sm text-[#a29fb3] mb-4 leading-relaxed">
                    {c.description}
                  </p>

                  <dl className={`${ui.className} space-y-1.5 text-xs`}>
                    <StatBar label="HP" value={c.base_hp} max={MAX_STAT * 6} barClass={accent.bar} />
                    <StatBar label="ATK" value={c.base_atk} max={MAX_STAT} barClass={accent.bar} />
                    <StatBar label="DEF" value={c.base_def} max={MAX_STAT} barClass={accent.bar} />
                    <StatBar label="SPD" value={c.base_spd} max={MAX_STAT} barClass={accent.bar} />
                  </dl>
                </button>
              )
            })}
          </div>
        )}

        {selected && (
          <div className="mt-10">
            <p className={`${ui.className} text-center text-xs tracking-widest text-[#a29fb3] mb-3`}>
              CHỌN CHÂN DUNG · đổi lại được bất cứ lúc nào
            </p>
            <div className="mx-auto grid max-w-2xl grid-cols-5 gap-2">
              {portraitKeys(selected.key).map((key) => (
                <button
                  key={key}
                  type="button"
                  onClick={() => setPortrait(key)}
                  className={`h-28 rounded-xl border p-1.5 transition-colors ${
                    key === portrait
                      ? 'border-[#8fe0b0] bg-[#8fe0b0]/10'
                      : 'border-white/10 bg-white/[0.03] hover:bg-white/[0.08]'
                  }`}
                >
                  <Portrait classKey={selected.key} portrait={key} />
                </button>
              ))}
            </div>
          </div>
        )}

        <div className="mt-14 max-w-md mx-auto">
          <label className={`${ui.className} block text-xs tracking-widest text-[#8a8499] mb-2`}>
            Tên Nhân Vật
          </label>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={20}
            placeholder="Nhập tên của bạn…"
            className="w-full bg-transparent border-b border-[#3a3348] py-2 text-lg text-[#f2ede4]
              placeholder:text-[#5c5470] focus:outline-none focus:border-[#8a8499]"
          />

          {error && (
            <p className="mt-3 text-sm text-[#e09595]">{error}</p>
          )}

          <button
            onClick={handleCreate}
            disabled={!selected || !name.trim() || submitting}
            className="mt-8 w-full py-3 rounded-xl border border-[#8a8499] text-[#f2ede4]
              disabled:opacity-30 disabled:cursor-not-allowed
              enabled:hover:bg-[#8a8499] enabled:hover:text-[#07070a] transition-colors"
          >
            {submitting ? 'Đang tạo…' : 'Bắt Đầu Hành Trình'}
          </button>
        </div>
      </div>
    </main>
  )
}

function StatBar({
  label,
  value,
  max,
  barClass,
}: {
  label: string
  value: number
  max: number
  barClass: string
}) {
  const pct = Math.min(100, Math.round((value / max) * 100))
  return (
    <div className="flex items-center gap-2">
      <span className="w-8 text-[#8a8499]">{label}</span>
      <div className="flex-1 h-1.5 bg-[#2a2533] rounded-full overflow-hidden">
        <div className={`h-full ${barClass}`} style={{ width: `${pct}%` }} />
      </div>
      <span className="w-6 text-right text-[#a29fb3]">{value}</span>
    </div>
  )
}
