// Chân dung nhân vật: public/portraits/<class>_<1..10>.png — pixel art 64 px đã tách nền
// (pack "500+ Free Pixel-art Fantasy Character Pack" của Batareya). characters.portrait
// null = mẫu 1 của class.
export const PORTRAITS_PER_CLASS = 10

export function portraitKeys(classKey: string) {
  return Array.from({ length: PORTRAITS_PER_CLASS }, (_, i) => `${classKey}_${i + 1}`)
}

export function portraitSrc(classKey: string, portrait: string | null | undefined) {
  const key = portrait && portrait.startsWith(`${classKey}_`) ? portrait : `${classKey}_1`
  return `/portraits/${key}.png`
}
