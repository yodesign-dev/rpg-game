-- Fix "column reference is ambiguous" (Postgres 42702) in buy_item/use_item.
--
-- RETURNS TABLE(gold int, quantity int) / (current_hp int, ...) implicitly
-- declares OUT parameters named gold/quantity/current_hp that are in scope
-- as plain identifiers for the whole function body. Every bare reference to
-- characters.gold, inventory.quantity, or characters.current_hp inside the
-- function collided with those OUT params, so every buy/use attempt failed
-- with a 42702 error before touching any data (confirmed live: gold was
-- never deducted and no item was granted).
--
-- Fix: rename the output columns so they can't collide with any real
-- column name. Values are still returned positionally, so this only
-- affects the field names on the returned row (buy_item: gold -> new_gold,
-- quantity -> new_quantity; use_item: current_hp -> new_current_hp,
-- max_hp -> new_max_hp, quantity_left -> new_quantity).

drop function if exists public.buy_item(uuid, uuid, int);
drop function if exists public.use_item(uuid, uuid);

create or replace function public.buy_item(p_character_id uuid, p_item_id uuid, p_quantity int default 1)
returns table(new_gold int, new_quantity int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_gold int;
  v_buy_price int;
  v_total_cost int;
  v_inventory_id uuid;
  v_new_quantity int;
begin
  if p_quantity <= 0 then
    raise exception 'Số lượng không hợp lệ';
  end if;

  select user_id, gold into v_owner_user_id, v_gold
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  select buy_price into v_buy_price from items where id = p_item_id;

  if v_buy_price is null then
    raise exception 'Vật phẩm này không bán trong chợ';
  end if;

  v_total_cost := v_buy_price * p_quantity;

  if v_gold < v_total_cost then
    raise exception 'Không đủ vàng (cần % vàng)', v_total_cost;
  end if;

  update characters set gold = gold - v_total_cost where id = p_character_id;

  select id, quantity into v_inventory_id, v_new_quantity
  from inventory where character_id = p_character_id and item_id = p_item_id
  for update;

  if v_inventory_id is null then
    insert into inventory (character_id, item_id, quantity)
    values (p_character_id, p_item_id, p_quantity)
    returning quantity into v_new_quantity;
  else
    update inventory set quantity = quantity + p_quantity
    where id = v_inventory_id
    returning quantity into v_new_quantity;
  end if;

  return query select (v_gold - v_total_cost), v_new_quantity;
end;
$$;

create or replace function public.use_item(p_character_id uuid, p_inventory_id uuid)
returns table(new_current_hp int, new_max_hp int, new_quantity int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_level int; v_current_hp int; v_class_id uuid;
  v_base_hp int; v_hp_per_level int; v_max_hp int;
  v_item_id uuid; v_quantity int; v_type text; v_heal_amount int;
  v_new_hp int; v_new_quantity int;
begin
  select user_id, level, current_hp, class_id
    into v_owner_user_id, v_level, v_current_hp, v_class_id
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  select base_hp, hp_per_level into v_base_hp, v_hp_per_level
  from classes where id = v_class_id;

  v_max_hp := v_base_hp + (v_level - 1) * v_hp_per_level;
  v_current_hp := coalesce(v_current_hp, v_max_hp);

  select item_id, quantity into v_item_id, v_quantity
  from inventory where id = p_inventory_id and character_id = p_character_id
  for update;

  if not found then
    raise exception 'Không tìm thấy vật phẩm trong túi đồ';
  end if;

  select type, heal_amount into v_type, v_heal_amount from items where id = v_item_id;

  if v_type is distinct from 'consumable' or coalesce(v_heal_amount, 0) <= 0 then
    raise exception 'Vật phẩm này không thể sử dụng để hồi máu';
  end if;

  if v_current_hp >= v_max_hp then
    raise exception 'HP đã đầy';
  end if;

  v_new_hp := least(v_max_hp, v_current_hp + v_heal_amount);
  update characters set current_hp = v_new_hp where id = p_character_id;

  v_new_quantity := v_quantity - 1;

  if v_new_quantity <= 0 then
    delete from inventory where id = p_inventory_id;
  else
    update inventory set quantity = v_new_quantity where id = p_inventory_id;
  end if;

  return query select v_new_hp, v_max_hp, v_new_quantity;
end;
$$;
