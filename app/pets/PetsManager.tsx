'use client'

import { useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { ItemIcon } from '../components/combat-ui'
import PetAvatar from '../components/PetAvatar'
import {
  NETS,
  PET_RARITY,
  RARITY_ORDER,
  catchRate,
  formatPassive,
  petCombatLine,
  releaseGold,
  type Pet,
  type PetEncounter,
  type PetPassive,
} from '@/lib/pets'

const MAX_PETS = 50

type ThrowResult = {
  caught: boolean
  fled: boolean
  tries_left: number
  pet?: Pet
}

function hoursLeft(expiresAt: string) {
  const ms = new Date(expiresAt).getTime() - Date.now()
  if (ms <= 0) return 'sắp bỏ đi'
  const h = Math.floor(ms / 3_600_000)
  return h >= 1 ? `còn ${h} giờ` : `còn ${Math.max(1, Math.floor(ms / 60_000))} phút`
}

export default function PetsManager({
  characterId,
  pets: initialPets,
  encounters: initialEncounters,
  netCounts: initialNets,
}: {
  characterId: string
  pets: Pet[]
  encounters: PetEncounter[]
  netCounts: Record<string, number>
}) {
  const router = useRouter()
  const [pets, setPets] = useState(initialPets)
  const [encounters, setEncounters] = useState(initialEncounters)
  const [nets, setNets] = useState(initialNets)
  const [busy, setBusy] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<{ text: string; tone: 'good' | 'bad' | 'info' } | null>(null)
  // Kết quả ném gần nhất theo từng pet đang chờ (hiện ngay dưới thẻ)
  const [lastThrow, setLastThrow] = useState<Record<string, string>>({})

  const active = pets.find((p) => p.active) ?? null
  const sorted = [...pets].sort(
    (a, b) =>
      Number(b.active) - Number(a.active) ||
      RARITY_ORDER[a.rarity] - RARITY_ORDER[b.rarity] ||
      b.caught_at.localeCompare(a.caught_at)
  )

  async function throwNet(enc: PetEncounter, netKey: string) {
    setError(null)
    setNotice(null)
    setBusy(enc.id)
    const { data, error: rpcError } = await createClient().rpc('throw_net', {
      p_encounter_id: enc.id,
      p_net_key: netKey,
    })
    setBusy(null)
    if (rpcError) return setError(rpcError.message)

    const res = data as ThrowResult
    setNets((n) => ({ ...n, [netKey]: Math.max(0, (n[netKey] ?? 0) - 1) }))

    if (res.caught && res.pet) {
      const pet: Pet = { ...res.pet, caught_at: new Date().toISOString() }
      setEncounters((list) => list.filter((e) => e.id !== enc.id))
      setPets((list) => [pet, ...list])
      setNotice({
        text: `🎉 Bắt được ${enc.species} (${PET_RARITY[enc.rarity].label})!${pet.active ? ' Đã mang theo.' : ''}`,
        tone: 'good',
      })
      router.refresh()
    } else if (res.fled) {
      setEncounters((list) => list.filter((e) => e.id !== enc.id))
      setNotice({ text: `💨 ${enc.species} đã thoát lưới và bỏ chạy mất…`, tone: 'bad' })
    } else {
      setEncounters((list) => list.map((e) => (e.id === enc.id ? { ...e, tries_left: res.tries_left } : e)))
      setLastThrow((m) => ({ ...m, [enc.id]: `Trượt! ${enc.species} vùng ra được — còn ${res.tries_left} lần ném.` }))
    }
  }

  async function dismiss(enc: PetEncounter) {
    setBusy(enc.id)
    const { error: rpcError } = await createClient().rpc('dismiss_pet_encounter', { p_encounter_id: enc.id })
    setBusy(null)
    if (rpcError) return setError(rpcError.message)
    setEncounters((list) => list.filter((e) => e.id !== enc.id))
  }

  async function setActive(pet: Pet | null) {
    setError(null)
    setNotice(null)
    setBusy(pet?.id ?? 'unset')
    const { error: rpcError } = await createClient().rpc('set_active_pet', {
      p_character_id: characterId,
      p_pet_id: pet?.id ?? null,
    })
    setBusy(null)
    if (rpcError) return setError(rpcError.message)
    setPets((list) => list.map((p) => ({ ...p, active: pet ? p.id === pet.id : false })))
    router.refresh()
  }

  async function release(pet: Pet) {
    if (!confirm(`Thả ${pet.species} (${PET_RARITY[pet.rarity].label})? Nhận ${releaseGold(pet).toLocaleString('vi-VN')} vàng.`))
      return
    setError(null)
    setBusy(pet.id)
    const { data, error: rpcError } = await createClient().rpc('release_pet', { p_pet_id: pet.id })
    setBusy(null)
    if (rpcError) return setError(rpcError.message)
    setPets((list) => list.filter((p) => p.id !== pet.id))
    setNotice({ text: `Đã thả ${pet.species} — nhận ${Number(data).toLocaleString('vi-VN')} vàng.`, tone: 'info' })
    router.refresh()
  }

  const totalNets = NETS.reduce((s, n) => s + (nets[n.key] ?? 0), 0)

  return (
    <div className="space-y-6">
      {error && <p className="text-center text-sm text-[#e09595]">{error}</p>}
      {notice && (
        <p
          className={`text-center text-sm ${
            notice.tone === 'good' ? 'text-[#f0c060]' : notice.tone === 'bad' ? 'text-[#e09595]' : 'text-[#8fe0b0]'
          }`}
        >
          {notice.text}
        </p>
      )}

      {/* Pet hoang dã chờ bắt */}
      <section>
        <div className="mb-2 flex items-baseline justify-between gap-2">
          <h2 className="text-xs font-semibold tracking-[2px] text-[#a29fb3]">🐾 PET HOANG DÃ ({encounters.length}/10)</h2>
          <Link href="/market" className="text-xs text-[#a29fb3] hover:text-white">
            Mua lưới →
          </Link>
        </div>
        <div className="mb-3 flex flex-wrap gap-2 text-xs">
          {NETS.map((n) => (
            <span
              key={n.key}
              className="flex items-center gap-1 rounded-full border border-white/[0.08] bg-white/[0.05] py-0.5 pl-1 pr-2 text-[#c9c4d4]"
            >
              <ItemIcon icon={n.icon} size={16} />
              {n.name} <b className="text-white">×{nets[n.key] ?? 0}</b>
            </span>
          ))}
        </div>

        {encounters.length === 0 ? (
          <p className="rounded-2xl border border-dashed border-white/15 p-4 text-center text-sm text-[#7d7a8c]">
            Chưa gặp pet nào. Thắng quái thường khi{' '}
            <Link href="/explore" className="text-[#8fe0b0] hover:underline">
              Thám Hiểm
            </Link>{' '}
            có 1,5% gặp pet hoang dã (Tinh Anh 3%, Hung Thần 5%).
          </p>
        ) : (
          <div className="grid gap-3 sm:grid-cols-2">
            {encounters.map((enc) => {
              const r = PET_RARITY[enc.rarity]
              const pending = busy === enc.id
              return (
                <div key={enc.id} className="rounded-2xl border border-white/[0.09] bg-white/[0.045] p-4">
                  <div className="flex items-center gap-3">
                    <span className={pending ? 'animate-pulse' : ''}>
                      <PetAvatar species={enc.species} rarity={enc.rarity} size={64} />
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className={`truncate ${r.text}`}>{enc.species}</p>
                      <p className="text-xs text-[#a29fb3]">
                        <span className={r.text}>{r.label}</span> · Lv{enc.level}
                      </p>
                      <p className="text-xs text-[#7d7a8c]">
                        {enc.tries_left} lần ném · {hoursLeft(enc.expires_at)}
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => dismiss(enc)}
                      disabled={pending}
                      className="self-start text-xs text-[#7d7a8c] hover:text-white disabled:opacity-30"
                      title="Bỏ qua pet này"
                    >
                      ✕
                    </button>
                  </div>
                  <div className="mt-3 grid grid-cols-3 gap-1.5">
                    {NETS.map((n) => {
                      const count = nets[n.key] ?? 0
                      return (
                        <button
                          key={n.key}
                          type="button"
                          onClick={() => throwNet(enc, n.key)}
                          disabled={pending || count === 0}
                          className="flex flex-col items-center gap-0.5 rounded-lg border border-white/15 px-1 py-1.5 text-xs
                            text-[#e5e1ed] transition-colors hover:bg-white/10 disabled:opacity-30"
                          title={`${n.name} — còn ${count}`}
                        >
                          <ItemIcon icon={n.icon} size={20} />
                          <span className="font-semibold">{Math.round(catchRate(enc.rarity, n.tier) * 100)}%</span>
                          <span className="text-[10px] text-[#7d7a8c]">×{count}</span>
                        </button>
                      )
                    })}
                  </div>
                  {lastThrow[enc.id] && <p className="mt-2 text-xs text-[#f0b070]">{lastThrow[enc.id]}</p>}
                </div>
              )
            })}
          </div>
        )}
        {encounters.length > 0 && totalNets === 0 && (
          <p className="mt-2 text-xs text-[#f0b070]">
            Bạn chưa có lưới —{' '}
            <Link href="/market" className="underline">
              mua ở Chợ
            </Link>
            . Ném trượt có 30% pet bỏ chạy.
          </p>
        )}
      </section>

      {/* Pet đang mang */}
      <section>
        <h2 className="mb-2 text-xs font-semibold tracking-[2px] text-[#a29fb3]">⭐ ĐANG MANG THEO</h2>
        {active ? (
          <div className="flex items-center gap-4 rounded-2xl border border-[#8fe0b0]/40 bg-[#8fe0b0]/[0.06] p-4">
            <PetAvatar species={active.species} rarity={active.rarity} size={80} />
            <div className="min-w-0 flex-1">
              <p className={`text-lg ${PET_RARITY[active.rarity].text}`}>{active.species}</p>
              <p className="mb-1 text-xs text-[#a29fb3]">
                {PET_RARITY[active.rarity].label} · Lv{active.level}
              </p>
              <PetCombat species={active.species} rarity={active.rarity} />
              <PassiveList passives={active.passives} />
            </div>
            <button
              type="button"
              onClick={() => setActive(null)}
              disabled={busy !== null}
              className="self-start rounded-lg border border-white/15 px-2.5 py-1.5 text-xs text-[#a29fb3] hover:bg-white/10 disabled:opacity-30"
            >
              Cất
            </button>
          </div>
        ) : (
          <p className="rounded-2xl border border-dashed border-white/15 p-4 text-center text-sm text-[#7d7a8c]">
            Chưa mang pet nào{pets.length > 0 ? ' — chọn một con bên dưới.' : '.'}
          </p>
        )}
      </section>

      {/* Bộ sưu tập */}
      <section>
        <h2 className="mb-2 text-xs font-semibold tracking-[2px] text-[#a29fb3]">
          📦 BỘ SƯU TẬP ({pets.length}/{MAX_PETS})
        </h2>
        {pets.length === 0 ? (
          <p className="text-sm text-[#7d7a8c]">Chưa có pet nào.</p>
        ) : (
          <div className="grid gap-2 sm:grid-cols-2">
            {sorted.map((pet) => {
              const r = PET_RARITY[pet.rarity]
              return (
                <div
                  key={pet.id}
                  className={`flex items-center gap-3 rounded-2xl border p-3 ${
                    pet.active ? 'border-[#8fe0b0]/40 bg-[#8fe0b0]/[0.05]' : 'border-white/[0.09] bg-white/[0.045]'
                  }`}
                >
                  <PetAvatar species={pet.species} rarity={pet.rarity} size={48} />
                  <div className="min-w-0 flex-1">
                    <p className={`truncate text-sm ${r.text}`}>
                      {pet.species} <span className="text-xs font-normal text-[#7d7a8c]">Lv{pet.level}</span>
                    </p>
                    <PetCombat species={pet.species} rarity={pet.rarity} compact />
                    <PassiveList passives={pet.passives} compact />
                  </div>
                  <div className="flex shrink-0 flex-col gap-1">
                    {pet.active ? (
                      <span className="text-center text-xs text-[#8fe0b0]">Đang mang</span>
                    ) : (
                      <>
                        <button
                          type="button"
                          onClick={() => setActive(pet)}
                          disabled={busy !== null}
                          className="rounded-lg border border-[#8fe0b0]/50 px-2 py-1 text-xs text-[#c8f5dc] hover:bg-[#8fe0b0]/15 disabled:opacity-30"
                        >
                          Mang
                        </button>
                        <button
                          type="button"
                          onClick={() => release(pet)}
                          disabled={busy !== null}
                          className="rounded-lg border border-white/10 px-2 py-1 text-[10px] text-[#7d7a8c] hover:text-[#f1dba0] disabled:opacity-30"
                          title={`Thả — nhận ${releaseGold(pet).toLocaleString('vi-VN')} vàng`}
                        >
                          Thả 🪙{releaseGold(pet).toLocaleString('vi-VN')}
                        </button>
                      </>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </section>
    </div>
  )
}

function PetCombat({ species, rarity, compact = false }: { species: string; rarity: Pet['rarity']; compact?: boolean }) {
  const line = petCombatLine(species, rarity)
  return (
    <ul className={`${compact ? 'text-[11px] leading-snug' : 'mb-1 space-y-0.5 text-xs'} text-[#f1dba0]`}>
      {!compact && <li>{line.attack}</li>}
      {line.skill && <li>{line.skill}</li>}
    </ul>
  )
}

function PassiveList({ passives, compact = false }: { passives: PetPassive[]; compact?: boolean }) {
  return (
    <ul className={compact ? 'text-[11px] leading-snug' : 'space-y-0.5 text-xs'}>
      {passives.map((p, i) => {
        const f = formatPassive(p)
        return (
          <li key={i} className="text-[#c8f5dc]">
            {f.icon} {!compact && <b className="text-[#e5e1ed]">{f.name}: </b>}
            {f.text}
          </li>
        )
      })}
    </ul>
  )
}
