-- AP potion — a real gold sink. AP currently only regenerates for free over
-- time (lib/ap-regen.ts); with no way to spend gold to skip the wait, gold
-- has nowhere to go once a player has enough for the shop's other items,
-- which just sits unused ("lạm phát" the user flagged). Priced the same as
-- potion_large (100 vàng) so it competes directly with "just wait" instead
-- of being a trivially-cheap no-brainer.
--
-- items.restore_ap parallels heal_amount but for AP; use_item is rewritten
-- to branch on whichever of the two the item actually has (an item is
-- expected to have exactly one, never both) instead of assuming HP.

alter table items add column if not exists restore_ap int not null default 0;

insert into items (key, name, type, rarity, restore_ap, buy_price, sell_price, description, icon) values
  ('potion_ap_large', 'Bình Hồi AP Lớn', 'consumable', 'epic', 40, 100, 30, 'Hồi ngay 40 AP', 'potion_ap_large.png')
on conflict (key) do nothing;

drop function if exists public.use_item(uuid, uuid);

create or replace function public.use_item(p_character_id uuid, p_inventory_id uuid)
returns table(new_current_hp int, new_max_hp int, new_current_ap int, new_quantity int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_level int; v_current_hp int; v_current_ap int; v_max_ap int; v_class_id uuid;
  v_base_hp int; v_hp_per_level int; v_max_hp int; v_item_hp_bonus int;
  v_item_id uuid; v_quantity int; v_type text; v_heal_amount int; v_restore_ap int;
  v_new_hp int; v_new_ap int; v_new_quantity int;
begin
  select user_id, level, current_hp, current_ap, max_ap, class_id
    into v_owner_user_id, v_level, v_current_hp, v_current_ap, v_max_ap, v_class_id
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  select base_hp, hp_per_level into v_base_hp, v_hp_per_level
  from classes where id = v_class_id;

  select coalesce(sum(i.bonus_hp + inv.rolled_hp), 0) into v_item_hp_bonus
  from inventory inv join items i on i.id = inv.item_id
  where inv.character_id = p_character_id and inv.equipped = true;

  v_max_hp := v_base_hp + (v_level - 1) * v_hp_per_level + v_item_hp_bonus;
  v_current_hp := coalesce(v_current_hp, v_max_hp);

  select item_id, quantity into v_item_id, v_quantity
  from inventory where id = p_inventory_id and character_id = p_character_id
  for update;

  if not found then
    raise exception 'Không tìm thấy vật phẩm trong túi đồ';
  end if;

  select type, heal_amount, restore_ap into v_type, v_heal_amount, v_restore_ap
  from items where id = v_item_id;

  if v_type is distinct from 'consumable'
     or (coalesce(v_heal_amount, 0) <= 0 and coalesce(v_restore_ap, 0) <= 0) then
    raise exception 'Vật phẩm này không thể sử dụng';
  end if;

  v_new_hp := v_current_hp;
  v_new_ap := v_current_ap;

  if coalesce(v_heal_amount, 0) > 0 then
    if v_current_hp >= v_max_hp then
      raise exception 'HP đã đầy';
    end if;
    v_new_hp := least(v_max_hp, v_current_hp + v_heal_amount);
  end if;

  if coalesce(v_restore_ap, 0) > 0 then
    if v_current_ap >= v_max_ap then
      raise exception 'AP đã đầy';
    end if;
    v_new_ap := least(v_max_ap, v_current_ap + v_restore_ap);
  end if;

  update characters set current_hp = v_new_hp, current_ap = v_new_ap where id = p_character_id;

  v_new_quantity := v_quantity - 1;

  if v_new_quantity <= 0 then
    delete from inventory where id = p_inventory_id;
  else
    update inventory set quantity = v_new_quantity where id = p_inventory_id;
  end if;

  return query select v_new_hp, v_max_hp, v_new_ap, v_new_quantity;
end;
$$;
