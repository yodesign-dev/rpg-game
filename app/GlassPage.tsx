import Link from 'next/link'
import { display, ui } from '@/app/fonts'
import BottomNav from './BottomNav'

// Khung chung cho mọi trang (trừ màn Nhân Vật): cùng nền, cùng header, cùng bottom nav.
// back: trang con mở từ màn Nhân Vật (danh hiệu, xếp hạng…) — tab chính thì đã có bottom nav.
// aside: góc phải tiêu đề, vd. số vàng ở Chợ. wide: trang nhiều thẻ (Túi Đồ) rộng hơn trên màn lớn.
export default function GlassPage({
  title,
  subtitle,
  back = false,
  aside,
  wide = false,
  children,
}: {
  title: string
  subtitle?: string
  back?: boolean
  aside?: React.ReactNode
  wide?: boolean
  children: React.ReactNode
}) {
  return (
    <main
      className="min-h-screen text-[#f2ede4] pb-28"
      style={{
        background:
          'radial-gradient(480px 260px at 15% 0%, rgba(107,74,122,.25), transparent 60%),' +
          'radial-gradient(480px 260px at 100% 10%, rgba(224,176,80,.1), transparent 55%),' +
          '#07070a',
      }}
    >
      <div className={`${ui.className} mx-auto ${wide ? 'max-w-6xl' : 'max-w-2xl'} px-4 pt-5`}>
        <header className="mb-5">
          {back && (
            <Link href="/" className="inline-block mb-3 text-sm text-[#a29fb3] hover:text-white">
              ← Nhân vật
            </Link>
          )}
          <div className="flex items-center justify-between gap-3">
            <h1 className={`${display.className} text-3xl text-white`}>{title}</h1>
            {aside}
          </div>
          {subtitle && <p className="text-sm text-[#a29fb3] mt-1.5">{subtitle}</p>}
        </header>
        {children}
      </div>
      <BottomNav />
    </main>
  )
}

export function GoldChip({ gold }: { gold: number }) {
  return (
    <span
      className="flex items-center gap-1 rounded-full bg-white/[0.06] border border-[#e0b050]/35 px-2.5 py-1 text-sm font-semibold text-[#f1dba0] tabular-nums"
      title="Vàng"
    >
      <span aria-hidden>🪙</span>
      {gold.toLocaleString('vi-VN')}
    </span>
  )
}
