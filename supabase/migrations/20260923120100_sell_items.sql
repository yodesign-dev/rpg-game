-- Bán đồ trong túi, hỗ trợ bán nhiều món một lần (chọn theo loại/tier ở UI).

-- Giá bán 1 dòng túi đồ (cả chồng). Trang bị có tier riêng (rơi/chế tạo) bán
-- gấp đôi cho mỗi bậc tier trên tier gốc của loại đồ; đồ mua ở chợ
-- (inventory.rarity null) và vật phẩm gộp chồng bán đúng items.sell_price —
-- để không thể mua ở chợ rồi bán lại có lời.
create or replace function public.inventory_sell_price(p_sell_price int, p_item_rarity text, p_row_rarity text, p_quantity int)
returns int
language sql
immutable
as $$
  select (greatest(0, p_sell_price)
          * power(2, greatest(0, rarity_rank(coalesce(p_row_rarity, p_item_rarity)) - rarity_rank(p_item_rarity)))
          * greatest(0, p_quantity))::int;
$$;

-- Bán nhiều dòng túi đồ cùng lúc (cả chồng). Không bán đồ đang mặc — nếu có
-- id nào đang mặc/không thuộc nhân vật thì từ chối cả lượt để không bán nhầm.
create or replace function public.sell_items(p_character_id uuid, p_inventory_ids uuid[])
returns table(out_sold int, out_gold_gained int, out_new_gold int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_gold int;
  v_requested int;
  v_sold int;
  v_gained int;
begin
  select c.user_id, c.gold into v_owner_user_id, v_gold
  from characters c where c.id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  select count(distinct x) into v_requested from unnest(coalesce(p_inventory_ids, '{}')) x;
  if v_requested = 0 then raise exception 'Chưa chọn món nào để bán'; end if;

  select count(*), coalesce(sum(inventory_sell_price(i.sell_price, i.rarity, inv.rarity, inv.quantity)), 0)
    into v_sold, v_gained
  from inventory inv join items i on i.id = inv.item_id
  where inv.id = any(p_inventory_ids)
    and inv.character_id = p_character_id
    and not inv.equipped;

  if v_sold < v_requested then
    raise exception 'Có món không bán được (đang mặc hoặc không còn trong túi) — hãy tải lại trang';
  end if;

  delete from inventory inv
  where inv.id = any(p_inventory_ids) and inv.character_id = p_character_id and not inv.equipped;

  update characters c set gold = c.gold + v_gained where c.id = p_character_id;

  return query select v_sold, v_gained, v_gold + v_gained;
end;
$$;
