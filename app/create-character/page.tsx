'use client'

import { useEffect, useState } from 'react'
import { Cinzel, JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/client'

const display = Cinzel({ subsets: ['latin'], weight: ['500', '700'] })
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

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
  warrior:  { ring: 'ring-[#8c3f3f]', text: 'text-[#c98787]', bar: 'bg-[#8c3f3f]' },
  mage:     { ring: 'ring-[#4a4e8c]', text: 'text-[#9ea2d6]', bar: 'bg-[#4a4e8c]' },
  archer:   { ring: 'ring-[#3d6b52]', text: 'text-[#8fc4a8]', bar: 'bg-[#3d6b52]' },
  assassin: { ring: 'ring-[#6b4a7a]', text: 'text-[#b79bc4]', bar: 'bg-[#6b4a7a]' },
}

const MAX_STAT = 24 // để vẽ thanh stat theo tỉ lệ (stat cao nhất trong 4 class dao động quanh mốc này)

export default function CreateCharacterPage() {
  const [classes, setClasses] = useState<ClassRow[]>([])
  const [selected, setSelected] = useState<ClassRow | null>(null)
  const [name, setName] = useState('')
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
    })

    if (insertError) {
      setError(insertError.message)
      setSubmitting(false)
      return
    }

    window.location.href = '/'
  }

  return (
    <main className="min-h-screen bg-[#100e0c] text-[#ece3d0] px-6 py-16">
      <div className="mx-auto max-w-5xl">
        <header className="text-center mb-14">
          <p className={`${mono.className} text-xs tracking-widest text-[#8a7f68] mb-3`}>
            Chương I — Khởi Đầu
          </p>
          <h1 className={`${display.className} text-4xl md:text-5xl font-semibold text-[#f1e6c8]`}>
            Chọn Con Đường Của Bạn
          </h1>
          <p className="mt-4 text-[#a89b7f] max-w-md mx-auto">
            Mỗi lớp nhân vật dẫn tới một lối chơi khác nhau. Lựa chọn này sẽ đi cùng bạn suốt hành trình.
          </p>
        </header>

        {loading && (
          <p className="text-center text-[#8a7f68]">Đang tải danh sách lớp nhân vật…</p>
        )}

        {!loading && (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
            {classes.map((c) => {
              const accent = CLASS_ACCENT[c.key] ?? CLASS_ACCENT.warrior
              const isSelected = selected?.id === c.id
              return (
                <button
                  key={c.id}
                  onClick={() => setSelected(c)}
                  className={`text-left rounded-sm border border-[#2c261c] bg-[#17140f] p-5 transition
                    ${isSelected ? `ring-2 ${accent.ring}` : 'hover:border-[#4a4230]'}`}
                >
                  <div className="flex items-center justify-between mb-3">
                    <span className="text-3xl">{c.icon}</span>
                    {isSelected && (
                      <span className={`${mono.className} text-[10px] tracking-wider ${accent.text}`}>
                        ĐÃ CHỌN
                      </span>
                    )}
                  </div>

                  <h2 className={`${display.className} text-xl text-[#f1e6c8] mb-2`}>
                    {c.name}
                  </h2>
                  <p className="text-sm text-[#a89b7f] mb-4 leading-relaxed">
                    {c.description}
                  </p>

                  <dl className={`${mono.className} space-y-1.5 text-xs`}>
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

        <div className="mt-14 max-w-md mx-auto">
          <label className={`${mono.className} block text-xs tracking-widest text-[#8a7f68] mb-2`}>
            Tên Nhân Vật
          </label>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={20}
            placeholder="Nhập tên của bạn…"
            className="w-full bg-transparent border-b border-[#4a4230] py-2 text-lg text-[#f1e6c8]
              placeholder:text-[#5c5340] focus:outline-none focus:border-[#8a7f68]"
          />

          {error && (
            <p className="mt-3 text-sm text-[#c98787]">{error}</p>
          )}

          <button
            onClick={handleCreate}
            disabled={!selected || !name.trim() || submitting}
            className="mt-8 w-full py-3 rounded-sm border border-[#8a7f68] text-[#f1e6c8]
              disabled:opacity-30 disabled:cursor-not-allowed
              enabled:hover:bg-[#8a7f68] enabled:hover:text-[#100e0c] transition-colors"
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
      <span className="w-8 text-[#8a7f68]">{label}</span>
      <div className="flex-1 h-1.5 bg-[#2c261c] rounded-full overflow-hidden">
        <div className={`h-full ${barClass}`} style={{ width: `${pct}%` }} />
      </div>
      <span className="w-6 text-right text-[#a89b7f]">{value}</span>
    </div>
  )
}
