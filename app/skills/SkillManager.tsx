'use client'

import { useState } from 'react'
import { ui } from '@/app/fonts'
import { createClient } from '@/lib/supabase/client'


const ACTIVE_MAX = 2
const PASSIVE_MAX = 1

type Skill = {
  id: string
  key: string
  name: string
  description: string
  skill_type: 'active' | 'passive'
  unlock_level: number
  icon: string | null
}

type EquippedRow = {
  id: string
  skill_id: string
}

export default function SkillManager({
  characterId,
  characterLevel,
  skills,
  initialEquipped,
}: {
  characterId: string
  characterLevel: number
  skills: Skill[]
  initialEquipped: EquippedRow[]
}) {
  const [equipped, setEquipped] = useState<EquippedRow[]>(initialEquipped)
  const [pendingSkillId, setPendingSkillId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const activeSkills = skills.filter((s) => s.skill_type === 'active')
  const passiveSkills = skills.filter((s) => s.skill_type === 'passive')
  const activeCount = equipped.filter((e) => activeSkills.some((s) => s.id === e.skill_id)).length
  const passiveCount = equipped.filter((e) => passiveSkills.some((s) => s.id === e.skill_id)).length
  const equippedOf = (list: Skill[]) => list.filter((s) => equipped.some((e) => e.skill_id === s.id))

  async function equip(skill: Skill) {
    setError(null)
    setPendingSkillId(skill.id)

    const supabase = createClient()
    const { data, error: insertError } = await supabase
      .from('character_equipped_skills')
      .insert({ character_id: characterId, skill_id: skill.id })
      .select('id, skill_id')
      .single()

    setPendingSkillId(null)

    if (insertError) {
      setError(insertError.message)
      return
    }

    setEquipped((prev) => [...prev, data])
  }

  async function unequip(skill: Skill, row: EquippedRow) {
    setError(null)
    setPendingSkillId(skill.id)

    const supabase = createClient()
    const { error: deleteError } = await supabase
      .from('character_equipped_skills')
      .delete()
      .eq('id', row.id)

    setPendingSkillId(null)

    if (deleteError) {
      setError(deleteError.message)
      return
    }

    setEquipped((prev) => prev.filter((e) => e.id !== row.id))
  }

  return (
    <div className="space-y-6">
      {error && (
        <p className={`${ui.className} text-xs text-[#e09595] text-center`}>{error}</p>
      )}

      {/* Bộ kỹ năng đang dùng — nhìn là biết còn trống ô nào */}
      <section className="rounded-2xl bg-white/[0.045] border border-white/[0.09] p-4">
        <h2 className={`${ui.className} text-xs font-semibold tracking-[2px] text-[#a29fb3] mb-3`}>ĐANG TRANG BỊ</h2>
        <div className="grid grid-cols-3 gap-2">
          {[
            ...Array.from({ length: ACTIVE_MAX }, (_, i) => ({ kind: 'Chủ động', skill: equippedOf(activeSkills)[i] })),
            ...Array.from({ length: PASSIVE_MAX }, (_, i) => ({ kind: 'Bị động', skill: equippedOf(passiveSkills)[i] })),
          ].map((slot, i) => (
            <div
              key={i}
              className={`rounded-xl border px-2 py-3 text-center ${
                slot.skill ? 'border-[#8fe0b0]/40 bg-[#8fe0b0]/[0.07]' : 'border-dashed border-white/15'
              }`}
            >
              <div className="text-2xl leading-none h-7">{slot.skill?.icon ?? '＋'}</div>
              <div className={`${ui.className} text-xs mt-1.5 truncate ${slot.skill ? 'text-white' : 'text-[#7d7a8c]'}`}>
                {slot.skill?.name ?? 'Trống'}
              </div>
              <div className={`${ui.className} text-[11px] text-[#7d7a8c]`}>{slot.kind}</div>
            </div>
          ))}
        </div>
      </section>

      <SkillGroup
        title="CHỦ ĐỘNG"
        note={`${activeCount} / ${ACTIVE_MAX} đã trang bị`}
        skills={activeSkills}
        equipped={equipped}
        characterLevel={characterLevel}
        pendingSkillId={pendingSkillId}
        slotFull={activeCount >= ACTIVE_MAX}
        onEquip={equip}
        onUnequip={unequip}
      />

      <SkillGroup
        title="BỊ ĐỘNG"
        note={`${passiveCount} / ${PASSIVE_MAX} đã trang bị`}
        skills={passiveSkills}
        equipped={equipped}
        characterLevel={characterLevel}
        pendingSkillId={pendingSkillId}
        slotFull={passiveCount >= PASSIVE_MAX}
        onEquip={equip}
        onUnequip={unequip}
      />
    </div>
  )
}

function SkillGroup({
  title,
  note,
  skills,
  equipped,
  characterLevel,
  pendingSkillId,
  slotFull,
  onEquip,
  onUnequip,
}: {
  title: string
  note: string
  skills: Skill[]
  equipped: EquippedRow[]
  characterLevel: number
  pendingSkillId: string | null
  slotFull: boolean
  onEquip: (skill: Skill) => void
  onUnequip: (skill: Skill, row: EquippedRow) => void
}) {
  return (
    <section>
      <div className="flex items-center justify-between mb-3">
        <h2 className={`${ui.className} text-xs font-semibold tracking-[2px] text-[#a29fb3]`}>{title}</h2>
        <span className={`${ui.className} text-xs text-[#7d7a8c]`}>{note}</span>
      </div>

      <div className="space-y-3">
        {skills.map((skill) => {
          const row = equipped.find((e) => e.skill_id === skill.id)
          const isEquipped = !!row
          const isLocked = characterLevel < skill.unlock_level
          const isPending = pendingSkillId === skill.id

          return (
            <div
              key={skill.id}
              className={`rounded-2xl border p-4 flex items-center justify-between gap-4
                ${isEquipped ? 'border-[#8fe0b0]/40 bg-[#8fe0b0]/[0.07]' : 'border-white/[0.09] bg-white/[0.045]'}
                ${isLocked ? 'opacity-40' : ''}`}
            >
              <div className="flex items-start gap-3">
                <span className="text-xl leading-none mt-0.5">{skill.icon}</span>
                <div>
                  <p className="font-semibold text-white">{skill.name}</p>
                  <p className={`${ui.className} text-xs text-[#8a8499] mt-1`}>
                    {skill.description}
                  </p>
                </div>
              </div>

              {isLocked ? (
                <span className={`${ui.className} text-xs text-[#5c5470] whitespace-nowrap`}>
                  🔒 Cấp {skill.unlock_level}
                </span>
              ) : row ? (
                <button
                  onClick={() => onUnequip(skill, row)}
                  disabled={isPending}
                  className={`${ui.className} text-xs border border-[#8c3f3f] text-[#e09595] px-3 py-2 rounded-lg
                    disabled:opacity-30 hover:bg-[#8c3f3f] hover:text-[#f2ede4] transition-colors whitespace-nowrap`}
                >
                  {isPending ? '…' : 'Gỡ'}
                </button>
              ) : (
                <button
                  onClick={() => onEquip(skill)}
                  disabled={isPending || slotFull}
                  className={`${ui.className} text-xs border border-[#8a8499] text-[#f2ede4] px-3 py-2 rounded-lg
                    disabled:opacity-30 hover:bg-[#8a8499] hover:text-[#0e0c13] transition-colors whitespace-nowrap`}
                >
                  {isPending ? '…' : slotFull ? 'Đầy' : 'Trang bị'}
                </button>
              )}
            </div>
          )
        })}
      </div>
    </section>
  )
}
