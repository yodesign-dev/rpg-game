// Dòng tổng kết tiếp tế sau một chuyến: bình đã uống, bùa hộ mệnh, cuộn đã áp
export default function SupplyResult({
  potionsUsed,
  guardUsed,
  buffs,
}: {
  potionsUsed?: number
  guardUsed?: boolean
  buffs?: { exp?: boolean; luck?: boolean }
}) {
  const parts = [
    potionsUsed ? `🧪 uống ${potionsUsed} bình` : null,
    guardUsed ? '🛡️ Bùa Hộ Mệnh đã cứu bạn' : null,
    buffs?.exp ? '📜 +25% EXP' : null,
    buffs?.luck ? '🍀 +30% rơi đồ' : null,
  ].filter(Boolean)
  if (parts.length === 0) return null
  return <p className="text-[#c8f5dc]">{parts.join(' · ')}</p>
}
