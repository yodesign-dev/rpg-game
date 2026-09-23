-- Allow a player to delete their own character (for the new "xoá nhân vật"
-- feature). There was previously no DELETE policy on `characters` at all,
-- so RLS silently blocked every delete — even the owner's own. All 5
-- character_id foreign keys (inventory, character_pets, dungeon_runs,
-- character_quests, character_equipped_skills) are already `on delete
-- cascade`, so deleting the character row alone is enough to wipe all of
-- its gear, gold, and progress in one transaction. No RPC needed: unlike
-- gold/HP, a player deleting their own character can't unfairly benefit
-- themselves, so a plain RLS-gated delete is safe.

create policy "own characters delete" on characters
  for delete using (auth.uid() = user_id);
