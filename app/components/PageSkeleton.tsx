import GlassPage from '../GlassPage'
import BottomNav from '../BottomNav'

// Khung chờ cho loading.tsx: hiện ngay khi bấm chuyển trang (Next prefetch sẵn file này),
// giữ nguyên tiêu đề + bottom nav để người chơi thấy đã chuyển, dữ liệu stream vào sau.
function Block({ className = '' }: { className?: string }) {
  return <div className={`rounded-2xl bg-white/[0.05] border border-white/[0.06] animate-pulse ${className}`} />
}

export default function PageSkeleton({
  title,
  back = false,
  wide = false,
  variant = 'list',
}: {
  title: string
  back?: boolean
  wide?: boolean
  variant?: 'list' | 'grid'
}) {
  return (
    <GlassPage title={title} back={back} wide={wide}>
      <div aria-busy="true" aria-label="Đang tải">
        {variant === 'grid' ? (
          <div className="grid grid-cols-4 sm:grid-cols-6 gap-2">
            {Array.from({ length: 18 }, (_, i) => (
              <Block key={i} className="aspect-square" />
            ))}
          </div>
        ) : (
          <div className="space-y-3">
            <Block className="h-24" />
            <Block className="h-16" />
            <Block className="h-16" />
            <Block className="h-16" />
          </div>
        )}
      </div>
    </GlassPage>
  )
}

// Khung chờ riêng cho màn Nhân Vật (không dùng GlassPage)
export function HubSkeleton() {
  return (
    <main className="min-h-screen pb-28" style={{ background: '#07070a' }}>
      <div className="mx-auto max-w-2xl px-4 pt-4" aria-busy="true" aria-label="Đang tải">
        <div className="flex items-center gap-3">
          <Block className="w-12 aspect-[2/3] rounded-lg" />
          <div className="flex-grow space-y-2">
            <Block className="h-5 w-40 rounded-md" />
            <Block className="h-4 w-28 rounded-md" />
          </div>
        </div>
        <div className="grid grid-cols-3 gap-3 mt-3">
          <Block className="h-6 rounded-md" />
          <Block className="h-6 rounded-md" />
          <Block className="h-6 rounded-md" />
        </div>
        <Block className="h-11 mt-4 mb-4 rounded-none" />
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Block className="h-24" />
            <Block className="h-24" />
          </div>
          <Block className="h-16" />
          <Block className="h-40" />
        </div>
      </div>
      <BottomNav />
    </main>
  )
}
