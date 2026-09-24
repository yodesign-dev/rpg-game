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
    <div className="space-y-8">
      {error && (
        <p className={`${ui.className} text-xs text-[#c98787] text-center`}>{error}</p>
      )}

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
        <h2 className={`${ui.className} text-xs tracking-widest text-[#8a7f68]`}>{title}</h2>
        <span className={`${ui.className} text-xs text-[#6b6249]`}>{note}</span>
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
              className={`rounded-sm border p-4 flex items-center justify-between gap-4
                ${isEquipped ? 'border-[#3d5a45] bg-[#151d17]' : 'border-[#2c261c] bg-[#17140f]'}
                ${isLocked ? 'opacity-40' : ''}`}
            >
              <div className="flex items-start gap-3">
                <span className="text-xl leading-none mt-0.5">{skill.icon}</span>
                <div>
                  <p className="text-[#f1e6c8]">{skill.name}</p>
                  <p className={`${ui.className} text-xs text-[#8a7f68] mt-1`}>
                    {skill.description}
                  </p>
                </div>
              </div>

              {isLocked ? (
                <span className={`${ui.className} text-xs text-[#6b6249] whitespace-nowrap`}>
                  🔒 Cấp {skill.unlock_level}
                </span>
              ) : row ? (
                <button
                  onClick={() => onUnequip(skill, row)}
                  disabled={isPending}
                  className={`${ui.className} text-xs border border-[#8c3f3f] text-[#c98787] px-3 py-2 rounded-sm
                    disabled:opacity-30 hover:bg-[#8c3f3f] hover:text-[#f1e6c8] transition-colors whitespace-nowrap`}
                >
                  {isPending ? '…' : 'Gỡ'}
                </button>
              ) : (
                <button
                  onClick={() => onEquip(skill)}
                  disabled={isPending || slotFull}
                  className={`${ui.className} text-xs border border-[#8a7f68] text-[#f1e6c8] px-3 py-2 rounded-sm
                    disabled:opacity-30 hover:bg-[#8a7f68] hover:text-[#100e0c] transition-colors whitespace-nowrap`}
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
