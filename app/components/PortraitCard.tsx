import { frameSrc } from '@/lib/frames'
import Portrait from './Portrait'

// Chân dung trong khung 64x96 (tỉ lệ 2:3). Kích thước do className quyết định (vd. "w-24").
export default function PortraitCard({
  classKey,
  portrait,
  frame,
  className = '',
}: {
  classKey: string
  portrait: string | null | undefined
  frame: string | null | undefined
  className?: string
}) {
  return (
    <div className={`relative aspect-[2/3] shrink-0 ${className}`}>
      <div className="absolute inset-[9%] rounded-[6%] bg-[#16121c]" />
      <div className="absolute inset-x-[12%] top-[10%] bottom-[9%]">
        <Portrait classKey={classKey} portrait={portrait} />
      </div>
      {/* eslint-disable-next-line @next/next/no-img-element -- khung 64 px, phóng bằng CSS pixelated */}
      <img
        src={frameSrc(frame)}
        alt=""
        draggable={false}
        className="absolute inset-0 h-full w-full select-none [image-rendering:pixelated]"
      />
    </div>
  )
}
