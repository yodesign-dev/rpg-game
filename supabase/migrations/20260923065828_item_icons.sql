-- Real pixel-art icons for items (Raven Fantasy Icons pack, /public/items/*.png),
-- replacing the icon-less text-only item rows in the shop/inventory lists.
-- icon stores just the filename under /public/items/ — the frontend prefixes
-- the path itself, so this stays a plain filename, not a full URL.

alter table items add column if not exists icon text;

update items set icon = 'sword_starter.png' where key = 'sword_starter';
update items set icon = 'bow_starter.png' where key = 'bow_starter';
update items set icon = 'daggers_starter.png' where key = 'daggers_starter';
update items set icon = 'staff_starter.png' where key = 'staff_starter';
update items set icon = 'forest_blade.png' where key = 'forest_blade';
update items set icon = 'frost_blade.png' where key = 'frost_blade';
update items set icon = 'cursed_dagger.png' where key = 'cursed_dagger';
update items set icon = 'fortress_greatsword.png' where key = 'fortress_greatsword';
update items set icon = 'voidforged_blade.png' where key = 'voidforged_blade';
update items set icon = 'leather_armor.png' where key = 'leather_armor';
update items set icon = 'potion_minor.png' where key = 'potion_minor';
update items set icon = 'potion_medium.png' where key = 'potion_medium';
update items set icon = 'potion_large.png' where key = 'potion_large';
update items set icon = 'wolf_fang.png' where key = 'wolf_fang';
update items set icon = 'ice_shard.png' where key = 'ice_shard';
update items set icon = 'swamp_venom.png' where key = 'swamp_venom';
update items set icon = 'shadow_ore.png' where key = 'shadow_ore';
update items set icon = 'void_shard.png' where key = 'void_shard';
