-- Hồi nhanh: uống bình liên tục tới khi HP (hoặc AP) đầy hoặc hết bình, thay cho bấm từng bình.
-- Mỗi lượt chọn bình nhỏ nhất đủ lấp phần thiếu (đỡ phí); không bình nào đủ thì uống bình lớn nhất.
-- Trả {hp, max_hp, ap, max_ap, full, used: [{name, qty}]}.

create or replace function public.quick_refill(p_character_id uuid, p_kind text)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_hp int; v_max_hp int; v_ap int; v_max_ap int;
  v_cur int; v_max int; v_missing int;
  v_pick record;
  v_used jsonb := '{}'::jsonb;
  v_i int := 0;
begin
  if p_kind not in ('hp', 'ap') then raise exception 'Loại hồi phục không hợp lệ'; end if;

  select c.user_id into v_owner_user_id from characters c where c.id = p_character_id;
  if not found then raise exception 'Không tìm thấy nhân vật'; end if;
  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  perform regen_character(p_character_id);

  select c.current_hp, c.current_ap, c.max_ap into v_hp, v_ap, v_max_ap
  from characters c where c.id = p_character_id for update;
  select gs.max_hp into v_max_hp from get_character_stats(p_character_id) gs;
  v_hp := least(v_max_hp, coalesce(v_hp, v_max_hp));

  v_cur := case p_kind when 'hp' then v_hp else v_ap end;
  v_max := case p_kind when 'hp' then v_max_hp else v_max_ap end;
  if v_cur >= v_max then
    raise exception '% đã đầy', upper(p_kind);
  end if;

  loop
    v_missing := v_max - v_cur;
    exit when v_missing <= 0 or v_i >= 500;
    v_i := v_i + 1;

    select inv.id as inv_id, inv.quantity as qty, i.name as item_name, x.amount
      into v_pick
    from inventory inv
    join items i on i.id = inv.item_id
    cross join lateral (
      select case p_kind
               when 'hp' then greatest(coalesce(i.heal_amount, 0), round(v_max_hp * coalesce(i.heal_pct, 0))::int)
               else coalesce(i.restore_ap, 0)
             end as amount
    ) x
    where inv.character_id = p_character_id and inv.quantity > 0 and not inv.equipped
      and i.type = 'consumable' and i.buff_key is null and x.amount > 0
    order by (x.amount >= v_missing) desc,
             case when x.amount >= v_missing then x.amount else -x.amount end
    limit 1;

    exit when not found;

    v_cur := least(v_max, v_cur + v_pick.amount);
    if v_pick.qty <= 1 then
      delete from inventory inv where inv.id = v_pick.inv_id;
    else
      update inventory inv set quantity = inv.quantity - 1 where inv.id = v_pick.inv_id;
    end if;
    v_used := jsonb_set(v_used, array[v_pick.item_name],
                        to_jsonb(coalesce((v_used->>v_pick.item_name)::int, 0) + 1));
  end loop;

  if v_used = '{}'::jsonb then
    raise exception 'Không còn bình % trong túi — mua thêm ở Chợ', upper(p_kind);
  end if;

  if p_kind = 'hp' then
    v_hp := v_cur;
    update characters c set current_hp = v_hp where c.id = p_character_id;
  else
    v_ap := v_cur;
    update characters c set current_ap = v_ap where c.id = p_character_id;
  end if;

  return jsonb_build_object(
    'hp', v_hp, 'max_hp', v_max_hp, 'ap', v_ap, 'max_ap', v_max_ap,
    'full', v_cur >= v_max,
    'used', (select coalesce(jsonb_agg(jsonb_build_object('name', e.key, 'qty', e.value::int)), '[]'::jsonb)
             from jsonb_each_text(v_used) e)
  );
end;
$$;

revoke execute on function public.quick_refill(uuid, text) from public, anon;
grant execute on function public.quick_refill(uuid, text) to authenticated;
