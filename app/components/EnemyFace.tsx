import { enemyPortraitSrc } from '@/lib/portraits'

// Mặt quái hình người (ô vuông nhỏ, nửa trên sprite). Quái không có ảnh → không hiện gì.
export default function EnemyFace({ name, size = 24 }: { name: string; size?: number }) {
  const src = enemyPortraitSrc(name)
  if (!src) return null
  return (
    <span
      className="inline-flex shrink-0 overflow-hidden rounded-md border border-white/15 bg-[#16121c] align-middle"
      style={{ width: size, height: size }}
      title={name}
    >
      {/* eslint-disable-next-line @next/next/no-img-element -- sprite 64 px, phóng bằng CSS pixelated */}
      <img
        src={src}
        alt=""
        draggable={false}
        className="h-[210%] w-full object-cover object-top [image-rendering:pixelated]"
      />
    </span>
  )
}
