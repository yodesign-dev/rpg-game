import { redirect } from 'next/navigation'
import Link from 'next/link'
import { Cinzel, JetBrains_Mono } from 'next/font/google'
import { createClient } from '@/lib/supabase/server'
import InventoryManager from './InventoryManager'

const display = Cinzel({ subsets: ['latin'], weight: ['500', '700'] })
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400', '600'] })

export default async function InventoryPage() {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: character } = await supabase
    .from('characters')
    .select('*, classes(*)')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (!character) redirect('/create-character')

  const { data: inventory, error: inventoryError } = await supabase
    .from('inventory')
    .select('id, quantity, equipped, equip_slot, items(*)')
    .eq('character_id', character.id)

  const cls = character.classes as {
    icon: string | null
    base_hp: number; hp_per_level: number
    base_atk: number; atk_per_level: number
    base_def: number; def_per_level: number
    base_spd: number; spd_per_level: number
  }
  const maxHp = cls.base_hp + (character.level - 1) * cls.hp_per_level
  const currentHp = character.current_hp ?? maxHp
  const baseAtk = cls.base_atk + (character.level - 1) * cls.atk_per_level
  const baseDef = cls.base_def + (character.level - 1) * cls.def_per_level
  const baseSpd = cls.base_spd + (character.level - 1) * cls.spd_per_level

  return (
    <main className="min-h-screen bg-[#100e0c] text-[#ece3d0] px-6 py-16">
      <div className="mx-auto max-w-2xl">
        <div className="mb-8">
          <Link href="/" className={`${mono.className} text-xs text-[#8a7f68] hover:text-[#a89b7f]`}>
            ← Về nhân vật
          </Link>
        </div>

        <header className="text-center mb-10">
          <h1 className={`${display.className} text-3xl text-[#f1e6c8]`}>Túi Đồ</h1>
          <p className={`${mono.className} text-xs text-[#8a7f68] mt-2`}>
            {character.gold} vàng · HP {currentHp} / {maxHp}
          </p>
        </header>

        {inventoryError && (
          <p className={`${mono.className} text-xs text-[#c98787] text-center mb-6`}>
            Không tải được túi đồ: {inventoryError.message}
          </p>
        )}

        <InventoryManager
          characterId={character.id}
          characterName={character.name}
          classIcon={cls.icon}
          items={(inventory as any) ?? []}
          currentHp={currentHp}
          maxHp={maxHp}
          baseAtk={baseAtk}
          baseDef={baseDef}
          baseSpd={baseSpd}
        />
      </div>
    </main>
  )
}
