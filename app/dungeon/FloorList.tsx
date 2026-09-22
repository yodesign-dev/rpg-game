'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/client'

const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

type Floor = {
  id: string
  floor_number: number
  is_boss_floor: boolean
  enemy_name: string
  enemy_level: number
  enemy_hp: number
}

type CombatLogEntry = {
  turn: number
  actor: 'character' | 'enemy'
  skill?: string
  enemy_name?: string
  damage: number
  crit?: boolean
  enemy_hp_left?: number
  character_hp_left?: number
}

type CombatResult = {
  win: boolean
  remaining_hp: number
  exp_gained: number
  gold_gained: number
  item_dropped: string | null
  leveled_up: boolean
  new_level: number
  combat_log: CombatLogEntry[]
}

export default function FloorList({
  characterId,
  floors,
  highestCleared,
  currentHp,
  maxHp,
  currentAp,
  apCost,
}: {
  characterId: string
  floors: Floor[]
  highestCleared: number
  currentHp: number
  maxHp: number
  currentAp: number
  apCost: number
}) {
  const router = useRouter()
  const [fightingFloor, setFightingFloor] = useState<string | null>(null)
  const [result, setResult] = useState<CombatResult | null>(null)
  const [resultFloorId, setResultFloorId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [localAp, setLocalAp] = useState(currentAp)
  const [localHighestCleared, setLocalHighestCleared] = useState(highestCleared)

  async function fight(floor: Floor) {
    setError(null)
    setResult(null)
    setFightingFloor(floor.id)

    const supabase = createClient()
    const { data, error } = await supabase.rpc('resolve_dungeon_floor', {
      p_character_id: characterId,
      p_dungeon_floor_id: floor.id,
    })

    setFightingFloor(null)

    if (error) {
      setError(error.message)
      return
    }

    const res = data as CombatResult
    setResult(res)
    setResultFloorId(floor.id)
    setLocalAp((ap) => ap - apCost)
    if (res.win && floor.floor_number > localHighestCleared) {
      setLocalHighestCleared(floor.floor_number)
    }
    router.refresh()
  }

  return (
    <div className="space-y-4">
      <div className={`${mono.className} text-center text-xs text-[#6b6249] mb-2`}>
        AP còn lại: {localAp}
      </div>

      {floors.map((floor) => {
        const isUnlocked = floor.floor_number <= localHighestCleared + 1
        const isCleared = floor.floor_number <= localHighestCleared
        const canAfford = localAp >= apCost
        const isFighting = fightingFloor === floor.id

        return (
          <div key={floor.id}>
            <div
              className={`rounded-sm border p-5 flex items-center justify-between gap-4
                ${floor.is_boss_floor ? 'border-[#8c3f3f] bg-[#1d1512]' : 'border-[#2c261c] bg-[#17140f]'}
                ${!isUnlocked ? 'opacity-40' : ''}`}
            >
              <div>
                <p className={`${mono.className} text-[10px] tracking-widest text-[#8a7f68] mb-1`}>
                  TẦNG {floor.floor_number} {floor.is_boss_floor && '· BOSS'}
                </p>
                <p className="text-[#f1e6c8]">{floor.enemy_name}</p>
                <p className={`${mono.className} text-xs text-[#6b6249] mt-1`}>
                  Cấp {floor.enemy_level} · {floor.enemy_hp} HP
                </p>
              </div>

              {!isUnlocked ? (
                <span className={`${mono.className} text-xs text-[#6b6249]`}>🔒 Khóa</span>
              ) : isCleared ? (
                <button
                  onClick={() => fight(floor)}
                  disabled={!canAfford || isFighting}
                  className={`${mono.className} text-xs border border-[#3d5a45] text-[#8fc4a8] px-3 py-2 rounded-sm
                    disabled:opacity-30 hover:bg-[#3d5a45] hover:text-[#f1e6c8] transition-colors`}
                >
                  {isFighting ? 'Đang đánh…' : 'Đánh lại'}
                </button>
              ) : (
                <button
                  onClick={() => fight(floor)}
                  disabled={!canAfford || isFighting}
                  className={`${mono.className} text-xs border border-[#8a7f68] text-[#f1e6c8] px-3 py-2 rounded-sm
                    disabled:opacity-30 hover:bg-[#8a7f68] hover:text-[#100e0c] transition-colors`}
                >
                  {isFighting ? 'Đang đánh…' : canAfford ? 'Đánh' : 'Thiếu AP'}
                </button>
              )}
            </div>

            {resultFloorId === floor.id && result && (
              <CombatResultPanel result={result} />
            )}
            {resultFloorId === floor.id && error && (
              <p className={`${mono.className} text-xs text-[#c98787] mt-2 px-2`}>{error}</p>
            )}
          </div>
        )
      })}
    </div>
  )
}

function CombatResultPanel({ result }: { result: CombatResult }) {
  return (
    <div className="mt-2 rounded-sm border border-[#2c261c] bg-[#0d0b09] p-4">
      <p className={`${mono.className} text-sm mb-3 ${result.win ? 'text-[#8fc4a8]' : 'text-[#c98787]'}`}>
        {result.win ? '✓ Chiến thắng' : '✗ Thất bại'}
      </p>

      <div className="max-h-48 overflow-y-auto space-y-1 mb-3 pr-1">
        {result.combat_log.map((entry, i) => (
          <p key={i} className={`${mono.className} text-[11px] leading-relaxed`}>
            {entry.actor === 'character' ? (
              <span className="text-[#a89b7f]">
                Lượt {entry.turn}: bạn dùng <span className="text-[#f1e6c8]">{entry.skill}</span>, gây{' '}
                <span className="text-[#c9a678]">{entry.damage}</span> sát thương
                {entry.crit && <span className="text-[#e0b050]"> (Chí mạng!)</span>}
              </span>
            ) : (
              <span className="text-[#6b6249]">
                Lượt {entry.turn}: {entry.enemy_name} phản đòn, gây{' '}
                <span className="text-[#c98787]">{entry.damage}</span> sát thương
              </span>
            )}
          </p>
        ))}
      </div>

      <div className={`${mono.className} text-xs text-[#a89b7f] space-y-0.5 border-t border-[#2c261c] pt-3`}>
        <p>HP còn lại: {result.remaining_hp}</p>
        {result.win && (
          <>
            <p>+{result.exp_gained} EXP · +{result.gold_gained} Vàng</p>
            {result.item_dropped && <p className="text-[#c9a678]">Nhặt được: {result.item_dropped}</p>}
            {result.leveled_up && (
              <p className="text-[#e0b050]">🎉 Lên cấp {result.new_level}!</p>
            )}
          </>
        )}
      </div>
    </div>
  )
}
