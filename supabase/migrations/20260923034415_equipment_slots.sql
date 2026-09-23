-- Expand equipment from a flat weapon/body/accessory model to full paper-doll
-- slots: head, chest, belt, amulet, boot, plus two independent arm sockets
-- (l_arm / r_arm) for weapons and shields. A two-handed weapon (e.g. a mage's
-- staff) occupies both arms at once and blocks equipping anything else into
-- either arm until it's unequipped — a one-handed weapon or shield only
-- takes the specific arm it's equipped into.
--
-- items.hand ('one_hand' | 'two_hand') is only meaningful for slot in
-- ('weapon', 'shield'); null for everything else.
-- inventory.equip_slot records exactly which physical socket an equipped
-- row occupies ('head' | 'chest' | 'belt' | 'amulet' | 'boot' | 'l_arm' |
-- 'r_arm' | 'both_arms'), replacing the old "compare items.slot" approach
-- that couldn't tell l_arm from r_arm. Equip/unequip stay plain client
-- .update() calls under the existing "own inventory update" RLS policy —
-- no gold/HP is involved, so no security-definer RPC is needed here.

alter table items add column if not exists hand text;
alter table inventory add column if not exists equip_slot text;

-- Old slot value 'body' -> 'chest' to match the new naming.
update items set slot = 'chest' where slot = 'body';

-- All existing weapons default to one-handed except the mage's staff, which
-- the game design calls out explicitly as two-handed.
update items set hand = 'one_hand' where type = 'weapon' and hand is null;
update items set hand = 'two_hand' where key = 'staff_starter';

-- Backfill equip_slot for anything already equipped so gear already on a
-- character doesn't silently fall off the paper doll after this migration.
-- Weapons default into the left arm (no per-character handedness data to
-- infer from); everything else maps 1:1 from its item slot.
update inventory inv
set equip_slot = case
  when it.slot = 'weapon' then 'l_arm'
  else it.slot
end
from items it
where inv.item_id = it.id and inv.equipped = true and inv.equip_slot is null;
