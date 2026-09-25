import { getCurrentCharacter } from '@/lib/current-character'
import type { Pet, PetEncounter } from '@/lib/pets'
import GlassPage, { GoldChip } from '../GlassPage'
import PetsManager from './PetsManager'

export default async function PetsPage() {
  const { supabase, character } = await getCurrentCharacter()

  const [{ data: pets }, { data: encounters }, { data: nets }] = await Promise.all([
    supabase
      .from('character_pets')
      .select('id, species, level, rarity, passives, active, caught_at')
      .eq('character_id', character.id)
      .order('caught_at', { ascending: false }),
    supabase
      .from('pet_encounters')
      .select('id, species, level, rarity, tries_left, expires_at')
      .eq('character_id', character.id)
      .gt('expires_at', new Date().toISOString())
      .order('created_at', { ascending: true }),
    supabase
      .from('inventory')
      .select('quantity, items!inner(key, net_tier)')
      .eq('character_id', character.id)
      .not('items.net_tier', 'is', null),
  ])

  const netCounts: Record<string, number> = {}
  for (const row of (nets ?? []) as unknown as { quantity: number; items: { key: string } }[]) {
    netCounts[row.items.key] = (netCounts[row.items.key] ?? 0) + row.quantity
  }

  return (
    <GlassPage
      back
      title="Pet"
      subtitle="Gặp pet hoang dã khi Thám Hiểm, ném lưới để bắt. Mang theo 1 pet để nhận nội tại của nó."
      aside={<GoldChip gold={character.gold} />}
    >
      <PetsManager
        characterId={character.id}
        pets={(pets ?? []) as Pet[]}
        encounters={(encounters ?? []) as PetEncounter[]}
        netCounts={netCounts}
      />
    </GlassPage>
  )
}
