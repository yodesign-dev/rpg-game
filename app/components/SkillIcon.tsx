// Icon kỹ năng: ảnh pixel (skills.icon = "/skills/<key>.png") trong khung bo tròn màu class;
// dữ liệu cũ còn emoji thì hiện emoji. locked → xám và mờ.
const CLASS_RING: Record<string, string> = {
  warrior: 'border-[#e0b050]/70 bg-[#e0b050]/10',
  mage: 'border-[#5b8fd8]/70 bg-[#5b8fd8]/10',
  archer: 'border-[#8fe0b0]/70 bg-[#8fe0b0]/10',
  assassin: 'border-[#b06fd8]/70 bg-[#b06fd8]/10',
}

export function skillClassKey(skillKey: string) {
  return skillKey.split('_')[0]
}

export default function SkillIcon({
  icon,
  classKey,
  size = 44,
  locked = false,
}: {
  icon: string | null
  classKey: string
  size?: number
  locked?: boolean
}) {
  return (
    <span
      className={`inline-flex shrink-0 items-center justify-center rounded-xl border-2 ${
        CLASS_RING[classKey] ?? CLASS_RING.mage
      } ${locked ? 'grayscale opacity-45' : ''}`}
      style={{ width: size, height: size }}
    >
      {icon?.startsWith('/') ? (
        // eslint-disable-next-line @next/next/no-img-element -- icon 64 px, phóng bằng CSS pixelated
        <img src={icon} alt="" draggable={false} className="h-[78%] w-[78%] [image-rendering:pixelated]" />
      ) : (
        <span style={{ fontSize: size * 0.5 }}>{icon ?? '✦'}</span>
      )}
    </span>
  )
}
