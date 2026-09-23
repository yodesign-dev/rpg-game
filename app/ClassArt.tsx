// Minh hoạ SVG theo class — 2 biến thể mỗi class, chọn ổn định theo seed
// (id nhân vật) để không đổi ngẫu nhiên mỗi lần render lại, chỉ khác nhau
// giữa các nhân vật khác nhau. Không dùng ảnh ngoài (không có công cụ tạo
// ảnh/nguồn art đã duyệt) — vẽ dạng "phù hiệu" hình học nhiều lớp, chi tiết
// hơn 1 icon nét đơn, tránh rủi ro bản quyền và không cần tải asset.

import type { ReactElement } from 'react'

function pickVariant(seed: string, count: number) {
  let hash = 0
  for (let i = 0; i < seed.length; i++) hash = (hash * 31 + seed.charCodeAt(i)) >>> 0
  return hash % count
}

function WarriorShield({ accent, accentLight }: { accent: string; accentLight: string }) {
  return (
    <>
      <path
        d="M48 12 L78 24 L78 50 Q78 74 48 88 Q18 74 18 50 L18 24 Z"
        fill={`${accent}33`}
        stroke={accent}
        strokeWidth="2.5"
        strokeLinejoin="round"
      />
      <line x1="48" y1="22" x2="48" y2="72" stroke={accentLight} strokeWidth="3.5" strokeLinecap="round" />
      <line x1="36" y1="34" x2="60" y2="34" stroke={accentLight} strokeWidth="3.5" strokeLinecap="round" />
      <circle cx="48" cy="22" r="3.5" fill={accentLight} />
    </>
  )
}

function WarriorCrossedSwords({ accent, accentLight }: { accent: string; accentLight: string }) {
  return (
    <>
      <line x1="22" y1="22" x2="74" y2="74" stroke={accentLight} strokeWidth="3.5" strokeLinecap="round" />
      <line x1="74" y1="22" x2="22" y2="74" stroke={accentLight} strokeWidth="3.5" strokeLinecap="round" />
      <line x1="30" y1="30" x2="38" y2="22" stroke={accent} strokeWidth="3" strokeLinecap="round" />
      <line x1="66" y1="30" x2="58" y2="22" stroke={accent} strokeWidth="3" strokeLinecap="round" />
      <circle cx="48" cy="48" r="5" fill="#0d0b09" stroke={accent} strokeWidth="2.5" />
    </>
  )
}

function MageCrystal({ accent, accentLight }: { accent: string; accentLight: string }) {
  return (
    <>
      <polygon
        points="48,14 66,32 61,66 48,82 35,66 30,32"
        fill={`${accent}33`}
        stroke={accent}
        strokeWidth="2.5"
        strokeLinejoin="round"
      />
      <line x1="48" y1="14" x2="48" y2="82" stroke={accentLight} strokeWidth="1.5" opacity="0.6" />
      <line x1="30" y1="32" x2="66" y2="32" stroke={accentLight} strokeWidth="1.5" opacity="0.6" />
      <line x1="48" y1="4" x2="48" y2="12" stroke={accentLight} strokeWidth="2.5" strokeLinecap="round" />
      <line x1="40" y1="6" x2="44" y2="13" stroke={accentLight} strokeWidth="2" strokeLinecap="round" />
      <line x1="56" y1="6" x2="52" y2="13" stroke={accentLight} strokeWidth="2" strokeLinecap="round" />
    </>
  )
}

function MageTome({ accent, accentLight }: { accent: string; accentLight: string }) {
  return (
    <>
      <path
        d="M16 58 Q48 48 80 58 L80 70 Q48 60 16 70 Z"
        fill={`${accent}33`}
        stroke={accent}
        strokeWidth="2.5"
        strokeLinejoin="round"
      />
      <line x1="48" y1="53" x2="48" y2="65" stroke={accent} strokeWidth="2" />
      <path
        d="M48 16 L52 26 L62 27 L54 34 L57 44 L48 38 L39 44 L42 34 L34 27 L44 26 Z"
        fill={accentLight}
        opacity="0.9"
      />
    </>
  )
}

function ArcherBow({ accent, accentLight }: { accent: string; accentLight: string }) {
  return (
    <>
      <path d="M30 14 Q56 48 30 82" fill="none" stroke={accent} strokeWidth="3" strokeLinecap="round" />
      <line x1="30" y1="14" x2="30" y2="82" stroke={accentLight} strokeWidth="1.5" opacity="0.7" />
      <line x1="18" y1="48" x2="72" y2="48" stroke={accentLight} strokeWidth="3" strokeLinecap="round" />
      <path d="M72 48 L62 43 L62 53 Z" fill={accentLight} />
      <line x1="18" y1="48" x2="26" y2="42" stroke={accent} strokeWidth="2" strokeLinecap="round" />
      <line x1="18" y1="48" x2="26" y2="54" stroke={accent} strokeWidth="2" strokeLinecap="round" />
    </>
  )
}

function ArcherCrossedArrows({ accent, accentLight }: { accent: string; accentLight: string }) {
  return (
    <>
      <circle cx="48" cy="48" r="30" fill="none" stroke={accent} strokeWidth="1.5" opacity="0.35" />
      <line x1="22" y1="22" x2="74" y2="74" stroke={accentLight} strokeWidth="3" strokeLinecap="round" />
      <path d="M74 74 L64 70 L70 64 Z" fill={accentLight} />
      <line x1="22" y1="22" x2="30" y2="22" stroke={accent} strokeWidth="2" strokeLinecap="round" />
      <line x1="22" y1="22" x2="22" y2="30" stroke={accent} strokeWidth="2" strokeLinecap="round" />
      <line x1="74" y1="22" x2="22" y2="74" stroke={accentLight} strokeWidth="3" strokeLinecap="round" />
      <path d="M22 74 L32 70 L26 64 Z" fill={accentLight} />
      <line x1="74" y1="22" x2="66" y2="22" stroke={accent} strokeWidth="2" strokeLinecap="round" />
      <line x1="74" y1="22" x2="74" y2="30" stroke={accent} strokeWidth="2" strokeLinecap="round" />
    </>
  )
}

function AssassinTwinDaggers({ accent, accentLight }: { accent: string; accentLight: string }) {
  return (
    <>
      <line x1="22" y1="22" x2="74" y2="74" stroke={accentLight} strokeWidth="3" strokeLinecap="round" />
      <path d="M30 30 L22 22 L18 26 L26 34" fill="none" stroke={accent} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
      <line x1="74" y1="22" x2="22" y2="74" stroke={accentLight} strokeWidth="3" strokeLinecap="round" />
      <path d="M66 30 L74 22 L78 26 L70 34" fill="none" stroke={accent} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
    </>
  )
}

function AssassinCrescent({ accent, accentLight }: { accent: string; accentLight: string }) {
  return (
    <>
      <path
        d="M62 18 A26 26 0 1 0 62 78 A21 21 0 1 1 62 18 Z"
        fill={`${accent}33`}
        stroke={accent}
        strokeWidth="2"
      />
      <line x1="24" y1="72" x2="60" y2="36" stroke={accentLight} strokeWidth="3.5" strokeLinecap="round" />
      <path d="M60 36 L68 30 L72 34 L64 42" fill="none" stroke={accentLight} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
    </>
  )
}

type ArtComponent = (p: { accent: string; accentLight: string }) => ReactElement

const CLASS_ART: Record<string, ArtComponent[]> = {
  warrior: [WarriorShield, WarriorCrossedSwords],
  mage: [MageCrystal, MageTome],
  archer: [ArcherBow, ArcherCrossedArrows],
  assassin: [AssassinTwinDaggers, AssassinCrescent],
}

const CLASS_TONE: Record<string, { accent: string; accentLight: string }> = {
  warrior: { accent: '#8c3f3f', accentLight: '#e0a3a3' },
  mage: { accent: '#4a4e8c', accentLight: '#b3b7e8' },
  archer: { accent: '#3d6b52', accentLight: '#9fd8b8' },
  assassin: { accent: '#6b4a7a', accentLight: '#d9c3ee' },
}

export default function ClassArt({
  classKey,
  seed,
  size = 96,
}: {
  classKey: string
  seed: string
  size?: number
}) {
  const variants = CLASS_ART[classKey] ?? CLASS_ART.warrior
  const tone = CLASS_TONE[classKey] ?? CLASS_TONE.warrior
  const Variant = variants[pickVariant(seed, variants.length)]

  return (
    <svg width={size} height={size} viewBox="0 0 96 96" fill="none">
      <Variant accent={tone.accent} accentLight={tone.accentLight} />
    </svg>
  )
}
