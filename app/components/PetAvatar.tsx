import { enemySprite } from '@/lib/enemies'
import { PET_RARITY, petSpriteName, type PetRarity } from '@/lib/pets'

// Ảnh pet trong ô vuông, viền theo độ hiếm
export default function PetAvatar({ species, rarity, size = 48 }: { species: string; rarity: PetRarity; size?: number }) {
  const sprite = enemySprite(petSpriteName(species, rarity))
  return (
    <span
      className={`inline-flex shrink-0 overflow-hidden rounded-lg border bg-[#16121c] align-middle ${PET_RARITY[rarity].frame}`}
      style={{ width: size, height: size }}
      title={`${species} · ${PET_RARITY[rarity].label}`}
    >
      {sprite && (
        // eslint-disable-next-line @next/next/no-img-element -- sprite pixel art, phóng bằng CSS pixelated
        <img
          src={sprite.src}
          alt=""
          draggable={false}
          className="h-full w-full select-none object-contain object-bottom p-px [image-rendering:pixelated]"
        />
      )}
    </span>
  )
}
