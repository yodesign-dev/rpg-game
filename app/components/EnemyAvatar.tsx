import { ENEMY_TRAITS, enemySprite, parseEnemyName, type EnemyTier } from '@/lib/enemies'

// Viền theo cấp — giống nhau cho mọi loài, vì màu sprite đổi theo từng họ quái nên không tự nói
// lên độ mạnh.
const TIER_FRAME: Record<EnemyTier, string> = {
  normal: 'border-white/15',
  elite: 'border-[#8fc4e0]/80 shadow-[0_0_6px_rgba(143,196,224,0.45)]',
  champion: 'border-[#f0c060] shadow-[0_0_8px_rgba(240,192,96,0.6)]',
  boss: 'border-[#e07070] shadow-[0_0_8px_rgba(224,112,112,0.6)]',
}

export const ENEMY_TIER_TEXT: Record<EnemyTier, string> = {
  normal: 'text-[#e5e1ed]',
  elite: 'text-[#8fc4e0]',
  champion: 'text-[#f0c060] font-semibold',
  boss: 'text-[#f0a8a8] font-semibold',
}

export function enemyTier(name: string, boss?: boolean): EnemyTier {
  return boss ? 'boss' : parseEnemyName(name).tier
}

// Ảnh quái trong ô vuông. Quái vật: cả con, canh đáy. Quái hình người: nửa trên sprite.
// Không có ảnh → ô trống (vẫn giữ viền cấp để dòng log thẳng hàng).
export default function EnemyAvatar({ name, size = 24, boss }: { name: string; size?: number; boss?: boolean }) {
  const sprite = enemySprite(name)
  return (
    <span
      className={`inline-flex shrink-0 overflow-hidden rounded-md border bg-[#16121c] align-middle ${TIER_FRAME[enemyTier(name, boss)]}`}
      style={{ width: size, height: size }}
      title={name}
    >
      {sprite && (
        // eslint-disable-next-line @next/next/no-img-element -- sprite pixel art, phóng bằng CSS pixelated
        <img
          src={sprite.src}
          alt=""
          draggable={false}
          className={`[image-rendering:pixelated] select-none ${
            sprite.kind === 'monster' ? 'h-full w-full object-contain object-bottom p-px' : 'h-[210%] w-full object-cover object-top'
          }`}
        />
      )}
    </span>
  )
}

// Biểu tượng đặc tính quái, di chuột / giữ để xem mô tả
export function EnemyTraits({ traits, className = '' }: { traits?: string[] | null; className?: string }) {
  const known = [...new Set(traits ?? [])].filter((t) => ENEMY_TRAITS[t])
  if (known.length === 0) return null
  return (
    <span className={`inline-flex gap-0.5 ${className}`}>
      {known.map((t) => (
        <span key={t} title={`${ENEMY_TRAITS[t].name}: ${ENEMY_TRAITS[t].desc}`} className="cursor-help">
          {ENEMY_TRAITS[t].icon}
        </span>
      ))}
    </span>
  )
}
