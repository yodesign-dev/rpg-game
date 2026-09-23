-- Tự mặc đồ tốt nhất: chấm điểm từng món theo cùng trọng số với character_power
-- (ATK×2, DEF×1.5, HP×0.25, (chí mạng + hút máu)×400, hiệu ứng Huyền Thoại +60)
-- rồi chọn bộ điểm cao nhất cho từng ô. Tay: so "vũ khí 2 tay" với "vũ khí 1
-- tay + món 1 tay tốt nhất còn lại (khiên hoặc vũ khí)".

create or replace function public.inventory_item_score(p_inventory_id uuid)
returns numeric
language sql
stable
set search_path = 'public'
as $$
  select (i.bonus_atk + inv.rolled_atk) * 2
       + (i.bonus_def + inv.rolled_def) * 1.5
       + (i.bonus_hp + inv.rolled_hp) * 0.25
       + (inv.rolled_crit + inv.rolled_lifesteal) * 400
       + case when inv.legendary_effect is not null then 60 else 0 end
  from inventory inv join items i on i.id = inv.item_id
  where inv.id = p_inventory_id;
$$;

create or replace function public.auto_equip_best(p_character_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_before int; v_after int;
  v_plan jsonb := '{}'::jsonb;   -- equip_slot → inventory id
  v_slot text;
  v_id uuid;
  v_ring record;
  v_ring_n int := 0;
  v_two uuid; v_two_score numeric := -1;
  v_main uuid; v_main_score numeric := -1;
  v_off uuid; v_off_score numeric := -1;
  v_changed int;
begin
  if (select c.user_id from characters c where c.id = p_character_id for update) is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  v_before := character_power(p_character_id);

  create temp table if not exists _ae_candidates (id uuid, slot text, hand text, is_weapon boolean, score numeric) on commit drop;
  truncate _ae_candidates;
  insert into _ae_candidates
  select inv.id, i.slot, i.hand, i.type = 'weapon', inventory_item_score(inv.id)
  from inventory inv join items i on i.id = inv.item_id
  where inv.character_id = p_character_id and i.type in ('weapon', 'armor');

  -- Ô đơn
  foreach v_slot in array array['head', 'chest', 'belt', 'amulet', 'boot'] loop
    select c.id into v_id from _ae_candidates c where c.slot = v_slot order by c.score desc limit 1;
    if v_id is not null then v_plan := v_plan || jsonb_build_object(v_slot, v_id); end if;
    v_id := null;
  end loop;

  -- 2 nhẫn tốt nhất
  for v_ring in select c.id from _ae_candidates c where c.slot = 'ring' order by c.score desc limit 2 loop
    v_ring_n := v_ring_n + 1;
    v_plan := v_plan || jsonb_build_object('ring_' || v_ring_n, v_ring.id);
  end loop;

  -- Tay
  select c.id, c.score into v_two, v_two_score from _ae_candidates c
  where c.is_weapon and c.hand = 'two_hand' order by c.score desc limit 1;
  select c.id, c.score into v_main, v_main_score from _ae_candidates c
  where c.is_weapon and coalesce(c.hand, 'one_hand') <> 'two_hand' order by c.score desc limit 1;
  if v_main is not null then
    select c.id, c.score into v_off, v_off_score from _ae_candidates c
    where c.slot in ('weapon', 'shield') and coalesce(c.hand, 'one_hand') <> 'two_hand' and c.id <> v_main
    order by c.score desc limit 1;
  end if;

  if v_two is not null and v_two_score >= coalesce(v_main_score, 0) + greatest(coalesce(v_off_score, 0), 0) then
    v_plan := v_plan || jsonb_build_object('both_arms', v_two);
  elsif v_main is not null then
    v_plan := v_plan || jsonb_build_object('r_arm', v_main);
    if v_off is not null then v_plan := v_plan || jsonb_build_object('l_arm', v_off); end if;
  end if;

  -- Số món đổi ô (so với hiện tại)
  select count(*) into v_changed from (
    select key as slot, value::text::uuid as id from jsonb_each_text(v_plan)
  ) p
  where not exists (
    select 1 from inventory inv where inv.id = p.id and inv.equipped and inv.equip_slot = p.slot
  );

  if v_changed > 0 then
    -- Gỡ các ô sẽ thay (và ô tay đối lập khi đổi kiểu 1 tay ↔ 2 tay), rồi mặc theo kế hoạch
    update inventory inv set equipped = false, equip_slot = null
    where inv.character_id = p_character_id and inv.equipped
      and (inv.equip_slot in (select jsonb_object_keys(v_plan))
           or (v_plan ? 'both_arms' and inv.equip_slot in ('l_arm', 'r_arm'))
           or ((v_plan ? 'r_arm' or v_plan ? 'l_arm') and inv.equip_slot = 'both_arms')
           or inv.id in (select value::text::uuid from jsonb_each_text(v_plan)));

    update inventory inv set equipped = true, equip_slot = p.slot
    from (select key as slot, value::text::uuid as id from jsonb_each_text(v_plan)) p
    where inv.id = p.id;
  end if;

  v_after := character_power(p_character_id);
  return jsonb_build_object('changed', v_changed, 'power_before', v_before, 'power_after', v_after);
end;
$$;
