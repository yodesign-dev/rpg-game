import { portraitSrc } from '@/lib/portraits'

// Chân dung pixel art. "full": cả người, vừa khung. "bust": phóng to nửa trên cho avatar tròn.
export default function Portrait({
  classKey,
  portrait,
  variant = 'full',
  className = '',
}: {
  classKey: string
  portrait: string | null | undefined
  variant?: 'full' | 'bust'
  className?: string
}) {
  return (
    // eslint-disable-next-line @next/next/no-img-element -- sprite 64 px, phóng bằng CSS pixelated
    <img
      src={portraitSrc(classKey, portrait)}
      alt=""
      draggable={false}
      className={`[image-rendering:pixelated] select-none ${
        variant === 'bust' ? 'h-[210%] w-full object-cover object-top' : 'h-full w-full object-contain object-bottom'
      } ${className}`}
    />
  )
}
