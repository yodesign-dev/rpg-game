-- Explore theo vùng + hồi HP theo thời gian + AP hồi nhanh hơn.
--
-- Explore: chọn vùng + số lượt (1-100). AP chỉ trừ 1 lần như vé vào vùng.
-- Mỗi lượt gặp 1 quái random theo trọng số (có tỉ lệ gặp boss), HP giữ
-- nguyên qua các trận. Dừng khi đủ lượt hoặc hết HP — chết ở lượt N thì chỉ
-- nhận thưởng từ các trận đã THẮNG trước đó (trận chết không có thưởng).
-- Dungeon theo chương vẫn giữ nguyên làm cốt truyện/boss.
--
-- Vòng đánh trước đây nằm trọn trong resolve_dungeon_floor → tách ra
-- simulate_fight + get_combat_skills để dungeon và explore đánh y hệt nhau.
--
-- Hồi phục: +2% HP tối đa mỗi phút (tối thiểu 1), AP từ 10 phút/điểm → 5
-- phút/điểm (đầy 100 AP trong ~8 tiếng thay vì ~17 tiếng). regen_character
-- được gọi ở đầu mọi RPC đọc HP/AP để combat không dùng số cũ.

-- 1. Hồi phục ------------------------------------------------------------------
alter table characters add column if not exists last_hp_update timestamptz not null default now();

alter table characters alter column ap_regen_minutes set default 5;
update characters set ap_regen_minutes = 5 where ap_regen_minutes = 10;

-- Trigger chặn client: INSERT ép ap_regen_minutes về giá trị mới (5), và
-- last_hp_update cũng là cột trạng thái game (client không được tự sửa).
create or replace function public.guard_character_game_state()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.level := 1;
      new.exp := 0;
      new.exp_to_next := 100;
      new.gold := 100;
      new.current_chapter := 1;
      new.current_hp := null;
      new.current_ap := 100;
      new.max_ap := 100;
      new.ap_regen_minutes := 5;
      new.last_ap_update := now();
      new.last_hp_update := now();
      new.created_at := now();
    elsif (to_jsonb(new) - 'name' - 'auto_allocate_stats')
          is distinct from
          (to_jsonb(old) - 'name' - 'auto_allocate_stats') then
      raise exception 'Chỉ được đổi tên và chế độ tự cộng điểm; chỉ số nhân vật chỉ thay đổi qua hành động trong game';
    end if;
  end if;
  return new;
end;
$$;

-- Hồi AP + HP kiểu lazy, không kiểm tra quyền — chỉ gọi từ bên trong các RPC
-- security definer (đã kiểm tra quyền). Gọi thẳng từ client sẽ bị trigger
-- guard_character_game_state chặn vì current_user = 'authenticated'.
-- Mốc last_*_update chỉ tiến đúng số tick đã cộng để phần phút lẻ không mất;
-- khi đang đầy thì mốc được kéo về now() để lúc bắt đầu mất HP/AP mới tính.
create or replace function public.regen_character(p_character_id uuid)
returns void
language plpgsql
set search_path = 'public'
as $$
declare
  v_current_ap int; v_max_ap int; v_regen_minutes int; v_last_ap timestamptz;
  v_current_hp int; v_last_hp timestamptz; v_max_hp int;
  v_ticks int; v_hp_per_tick int;
begin
  select c.current_ap, c.max_ap, greatest(1, c.ap_regen_minutes), c.last_ap_update,
         c.current_hp, c.last_hp_update
    into v_current_ap, v_max_ap, v_regen_minutes, v_last_ap, v_current_hp, v_last_hp
  from characters c where c.id = p_character_id for update;

  if not found then return; end if;

  -- AP
  if v_current_ap >= v_max_ap then
    update characters set last_ap_update = now() where id = p_character_id;
  else
    v_ticks := greatest(0, floor(extract(epoch from (now() - v_last_ap)) / 60))::int / v_regen_minutes;
    if v_ticks > 0 then
      update characters c
      set current_ap = least(v_max_ap, v_current_ap + v_ticks),
          last_ap_update = case when v_current_ap + v_ticks >= v_max_ap then now()
                                else c.last_ap_update + make_interval(mins => v_ticks * v_regen_minutes) end
      where c.id = p_character_id;
    end if;
  end if;

  -- HP (current_hp null = đầy)
  select gs.max_hp into v_max_hp from get_character_stats(p_character_id) gs;

  if v_current_hp is null or v_current_hp >= v_max_hp then
    update characters set last_hp_update = now() where id = p_character_id;
  else
    v_ticks := greatest(0, floor(extract(epoch from (now() - v_last_hp)) / 60))::int;
    if v_ticks > 0 then
      v_hp_per_tick := greatest(1, ceil(v_max_hp * 0.02))::int;
      update characters c
      set current_hp = least(v_max_hp, v_current_hp + v_ticks * v_hp_per_tick),
          last_hp_update = case when v_current_hp + v_ticks * v_hp_per_tick >= v_max_hp then now()
                                else c.last_hp_update + make_interval(mins => v_ticks) end
      where c.id = p_character_id;
    end if;
  end if;
end;
$$;

revoke execute on function public.regen_character(uuid) from public, anon, authenticated;

-- Thay apply_ap_regen bằng apply_regen (trả thêm HP) cho các trang hiển thị.
drop function if exists public.apply_ap_regen(uuid);

create or replace function public.apply_regen(p_character_id uuid)
returns table(out_current_ap int, out_max_ap int, out_next_ap_minutes int, out_current_hp int, out_max_hp int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_current_ap int; v_max_ap int; v_regen_minutes int; v_last_ap timestamptz;
  v_current_hp int; v_max_hp int;
  v_next int := null;
begin
  select c.user_id into v_owner_user_id from characters c where c.id = p_character_id;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  perform regen_character(p_character_id);

  select c.current_ap, c.max_ap, greatest(1, c.ap_regen_minutes), c.last_ap_update, c.current_hp
    into v_current_ap, v_max_ap, v_regen_minutes, v_last_ap, v_current_hp
  from characters c where c.id = p_character_id;

  select gs.max_hp into v_max_hp from get_character_stats(p_character_id) gs;

  if v_current_ap < v_max_ap then
    v_next := v_regen_minutes
      - (greatest(0, floor(extract(epoch from (now() - v_last_ap)) / 60))::int % v_regen_minutes);
  end if;

  return query select v_current_ap, v_max_ap, v_next, coalesce(v_current_hp, v_max_hp), v_max_hp;
end;
$$;

-- 2. Vòng đánh dùng chung -------------------------------------------------------

-- 2 skill chủ động (xen kẽ theo lượt) + hiệu ứng skill bị động đang trang bị.
create or replace function public.get_combat_skills(p_character_id uuid)
returns table(
  out_a1_name text, out_a1_power numeric, out_a2_name text, out_a2_power numeric,
  out_dmg_reduction numeric, out_lifesteal numeric, out_crit numeric
)
language plpgsql
stable
set search_path = 'public'
as $$
declare
  v_a1_name text; v_a1_power numeric; v_a2_name text; v_a2_power numeric;
  v_passive_type text; v_passive_value numeric;
begin
  select s.name, s.power_multiplier into v_a1_name, v_a1_power
  from character_equipped_skills ces join skills s on s.id = ces.skill_id
  where ces.character_id = p_character_id and s.skill_type = 'active'
  order by s.key limit 1 offset 0;

  select s.name, s.power_multiplier into v_a2_name, v_a2_power
  from character_equipped_skills ces join skills s on s.id = ces.skill_id
  where ces.character_id = p_character_id and s.skill_type = 'active'
  order by s.key limit 1 offset 1;

  if v_a1_name is null then v_a1_name := 'Đánh thường'; v_a1_power := 1.0; end if;
  if v_a2_name is null then v_a2_name := v_a1_name; v_a2_power := v_a1_power; end if;

  select s.effect_type, s.effect_value into v_passive_type, v_passive_value
  from character_equipped_skills ces join skills s on s.id = ces.skill_id
  where ces.character_id = p_character_id and s.skill_type = 'passive'
  limit 1;

  return query select
    v_a1_name, v_a1_power, v_a2_name, v_a2_power,
    case when v_passive_type = 'damage_reduction' then v_passive_value else 0 end,
    case when v_passive_type = 'lifesteal' then v_passive_value else 0 end,
    case when v_passive_type = 'crit_chance' then v_passive_value else 0 end;
end;
$$;

-- Mô phỏng 1 trận (tối đa 30 lượt): nhân vật đánh trước, skill 1/2 xen kẽ.
-- p_with_log = false để explore không phải dựng log từng lượt cho 100 trận.
create or replace function public.simulate_fight(
  p_char_atk int, p_char_def int, p_char_hp int, p_max_hp int,
  p_crit numeric, p_lifesteal numeric, p_dmg_reduction numeric,
  p_a1_name text, p_a1_power numeric, p_a2_name text, p_a2_power numeric,
  p_enemy_name text, p_enemy_hp int, p_enemy_atk int, p_enemy_def int,
  p_damage_multiplier numeric, p_with_log boolean
)
returns table(out_win boolean, out_timed_out boolean, out_hp_left int, out_log jsonb)
language plpgsql
volatile
as $$
declare
  v_char_hp int := p_char_hp;
  v_enemy_hp int := p_enemy_hp;
  v_turn int := 0;
  v_skill_name text; v_skill_power numeric;
  v_base_dmg numeric; v_is_crit boolean; v_dmg int;
  v_enemy_dmg numeric;
  v_log jsonb := '[]'::jsonb;
  v_win boolean;
  v_timed_out boolean := false;
begin
  while v_char_hp > 0 and v_enemy_hp > 0 and v_turn < 30 loop
    v_turn := v_turn + 1;

    if v_turn % 2 = 1 then
      v_skill_name := p_a1_name; v_skill_power := p_a1_power;
    else
      v_skill_name := p_a2_name; v_skill_power := p_a2_power;
    end if;

    v_base_dmg := greatest(1, p_char_atk * v_skill_power - p_enemy_def);
    v_is_crit := random() < p_crit;
    v_dmg := round(v_base_dmg * (case when v_is_crit then 1.5 else 1 end));
    v_enemy_hp := greatest(0, v_enemy_hp - v_dmg);

    if p_lifesteal > 0 then
      v_char_hp := least(p_max_hp, v_char_hp + round(v_dmg * p_lifesteal));
    end if;

    if p_with_log then
      v_log := v_log || jsonb_build_object(
        'turn', v_turn, 'actor', 'character', 'skill', v_skill_name,
        'damage', v_dmg, 'crit', v_is_crit, 'enemy_hp_left', v_enemy_hp
      );
    end if;

    exit when v_enemy_hp <= 0;

    v_enemy_dmg := greatest(1, p_enemy_atk - p_char_def) * p_damage_multiplier * (1 - p_dmg_reduction);
    v_char_hp := greatest(0, v_char_hp - round(v_enemy_dmg));

    if p_with_log then
      v_log := v_log || jsonb_build_object(
        'turn', v_turn, 'actor', 'enemy', 'enemy_name', p_enemy_name,
        'damage', round(v_enemy_dmg), 'character_hp_left', v_char_hp
      );
    end if;
  end loop;

  v_win := v_enemy_hp <= 0 and v_char_hp > 0;

  -- Hết 30 lượt mà cả hai còn sống: không xác định được thắng thua bằng sát
  -- thương, ghi rõ lý do vào log thay vì báo "Thất bại" mập mờ dù HP còn đầy.
  if not v_win and v_char_hp > 0 and v_enemy_hp > 0 then
    v_timed_out := true;
    if p_with_log then
      v_log := v_log || jsonb_build_object(
        'turn', v_turn, 'actor', 'system',
        'message', 'Hết giới hạn lượt đánh (30 lượt), buộc phải rút lui'
      );
    end if;
  end if;

  return query select v_win, v_timed_out, v_char_hp, v_log;
end;
$$;

-- Thêm 1 món đồ rơi vào túi: trang bị luôn tạo dòng mới kèm affix roll (giống
-- đồ rơi dungeon), vật phẩm tiêu hao/nguyên liệu thì gộp chồng.
create or replace function public.grant_drop(p_character_id uuid, p_item_id uuid)
returns void
language plpgsql
set search_path = 'public'
as $$
declare
  v_type text; v_slot text; v_school text; v_rarity text;
  v_inventory_id uuid;
  v_roll_atk int; v_roll_def int; v_roll_hp int; v_roll_crit numeric; v_roll_lifesteal numeric;
begin
  select type, slot, coalesce(school, 'physical'), rarity
    into v_type, v_slot, v_school, v_rarity
  from items where id = p_item_id;

  if v_type in ('weapon', 'armor') then
    select roll_atk, roll_def, roll_hp, roll_crit, roll_lifesteal
      into v_roll_atk, v_roll_def, v_roll_hp, v_roll_crit, v_roll_lifesteal
    from roll_item_affixes(v_slot, v_school, v_rarity);

    insert into inventory (character_id, item_id, quantity, rolled_atk, rolled_def, rolled_hp, rolled_crit, rolled_lifesteal)
    values (p_character_id, p_item_id, 1, v_roll_atk, v_roll_def, v_roll_hp, v_roll_crit, v_roll_lifesteal);
  else
    select id into v_inventory_id
    from inventory where character_id = p_character_id and item_id = p_item_id
    limit 1 for update;

    if v_inventory_id is null then
      insert into inventory (character_id, item_id, quantity) values (p_character_id, p_item_id, 1);
    else
      update inventory set quantity = quantity + 1 where id = v_inventory_id;
    end if;
  end if;
end;
$$;

revoke execute on function public.grant_drop(uuid, uuid) from public, anon, authenticated;

-- 3. Dungeon dùng vòng đánh chung ----------------------------------------------
create or replace function public.resolve_dungeon_floor(p_character_id uuid, p_dungeon_floor_id uuid)
returns table(win boolean, remaining_hp integer, exp_gained integer, gold_gained integer, item_dropped text, leveled_up boolean, new_level integer, combat_log jsonb, timed_out boolean)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  -- Nhân vật
  v_owner_user_id uuid;
  v_level int; v_current_hp int; v_current_ap int; v_max_ap int;
  v_max_hp int; v_char_atk int; v_char_def int;
  v_stat_crit_bonus numeric; v_stat_lifesteal_bonus numeric;
  -- Skill
  v_a1_name text; v_a1_power numeric; v_a2_name text; v_a2_power numeric;
  v_dmg_reduction numeric; v_lifesteal numeric; v_crit_chance numeric;
  -- Tầng / quái
  v_dungeon_id uuid; v_ap_cost int; v_enemy_name text; v_enemy_level int;
  v_enemy_hp int; v_enemy_atk int; v_enemy_def int;
  v_reward_exp int; v_reward_gold int; v_drop_item_id uuid; v_drop_rate numeric;
  v_floor_number int;
  -- Scaling
  v_exp_multiplier numeric; v_damage_multiplier numeric;
  -- Kết quả trận
  v_win boolean; v_timed_out boolean; v_hp_left int; v_log jsonb;
  v_final_hp int;
  v_was_full_ap boolean;
  v_exp_gained int := 0; v_gold_gained int := 0; v_item_dropped text := null;
  v_leveled_up boolean := false; v_new_level int;
begin
  -- 1. Quyền + hồi phục theo thời gian trước khi đọc HP/AP
  select user_id into v_owner_user_id from characters where id = p_character_id;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  perform regen_character(p_character_id);

  select level, current_hp, current_ap, max_ap
    into v_level, v_current_hp, v_current_ap, v_max_ap
  from characters where id = p_character_id for update;

  -- 2. Chỉ số tổng hợp: class + cấp + điểm chỉ số + trang bị (kể cả affix roll)
  select gs.max_hp, gs.atk, gs.def, gs.crit_bonus, gs.lifesteal_bonus
    into v_max_hp, v_char_atk, v_char_def, v_stat_crit_bonus, v_stat_lifesteal_bonus
  from get_character_stats(p_character_id) gs;

  v_current_hp := coalesce(v_current_hp, v_max_hp);

  if v_current_hp <= 0 then
    raise exception 'Nhân vật đang kiệt sức, cần hồi máu trước khi vào dungeon';
  end if;

  -- 3. Tầng dungeon đang đánh
  select df.dungeon_id, df.floor_number, df.enemy_name, df.enemy_level,
         df.enemy_hp, df.enemy_atk, df.enemy_def, df.reward_exp, df.reward_gold,
         df.drop_item_id, df.drop_rate, d.ap_cost
    into v_dungeon_id, v_floor_number, v_enemy_name, v_enemy_level,
         v_enemy_hp, v_enemy_atk, v_enemy_def, v_reward_exp, v_reward_gold,
         v_drop_item_id, v_drop_rate, v_ap_cost
  from dungeon_floors df join dungeons d on d.id = df.dungeon_id
  where df.id = p_dungeon_floor_id;

  if not found then raise exception 'Không tìm thấy tầng dungeon'; end if;

  if v_current_ap < v_ap_cost then
    raise exception 'Không đủ AP để vào tầng này (cần % AP)', v_ap_cost;
  end if;

  -- 4. Skill + bị động, cộng dồn chí mạng (AGI/DEX + affix, chặn 75%) và hút máu
  select cs.out_a1_name, cs.out_a1_power, cs.out_a2_name, cs.out_a2_power,
         cs.out_dmg_reduction, cs.out_lifesteal, cs.out_crit
    into v_a1_name, v_a1_power, v_a2_name, v_a2_power,
         v_dmg_reduction, v_lifesteal, v_crit_chance
  from get_combat_skills(p_character_id) cs;

  v_crit_chance := least(0.75, v_crit_chance + v_stat_crit_bonus);
  v_lifesteal := v_lifesteal + v_stat_lifesteal_bonus;

  -- 5. Hệ số scaling theo chênh lệch cấp độ
  select exp_multiplier, damage_multiplier into v_exp_multiplier, v_damage_multiplier
  from calculate_combat_scaling(v_level, v_enemy_level);

  -- 6. Mô phỏng trận đấu
  select f.out_win, f.out_timed_out, f.out_hp_left, f.out_log
    into v_win, v_timed_out, v_hp_left, v_log
  from simulate_fight(
    v_char_atk, v_char_def, v_current_hp, v_max_hp,
    v_crit_chance, v_lifesteal, v_dmg_reduction,
    v_a1_name, v_a1_power, v_a2_name, v_a2_power,
    v_enemy_name, v_enemy_hp, v_enemy_atk, v_enemy_def,
    v_damage_multiplier, true
  ) f;

  v_final_hp := case when v_win then v_hp_left else greatest(1, v_hp_left) end;

  -- 7. Trừ AP (luôn trừ, thắng hay thua) — reset mốc hồi AP nếu vừa tiêu từ lúc đầy
  v_was_full_ap := (v_current_ap = v_max_ap);

  if v_win then
    v_exp_gained := round(v_reward_exp * v_exp_multiplier);
    v_gold_gained := round(v_reward_gold * v_exp_multiplier);
  end if;

  update characters
  set current_hp = v_final_hp,
      current_ap = current_ap - v_ap_cost,
      gold = gold + v_gold_gained,
      last_ap_update = case when v_was_full_ap then now() else last_ap_update end
  where id = p_character_id;

  -- 8. Thưởng nếu thắng: EXP (qua hàm add_experience có sẵn), rơi đồ, ghi nhận đã qua tầng
  if v_win then
    select ae.leveled_up, ae.new_level into v_leveled_up, v_new_level
    from add_experience(p_character_id, v_exp_gained) as ae;

    if v_drop_item_id is not null and random() < v_drop_rate then
      perform grant_drop(p_character_id, v_drop_item_id);
      select key into v_item_dropped from items where id = v_drop_item_id;
    end if;

    insert into dungeon_runs (character_id, dungeon_id, current_floor, status, finished_at)
    values (p_character_id, v_dungeon_id, v_floor_number, 'cleared', now());
  end if;

  return query select
    v_win,
    v_final_hp,
    v_exp_gained,
    v_gold_gained,
    v_item_dropped,
    v_leveled_up,
    coalesce(v_new_level, v_level),
    v_log,
    v_timed_out;
end;
$$;

-- use_item: hồi phục theo thời gian trước khi uống để không phí bình máu
create or replace function public.use_item(p_character_id uuid, p_inventory_id uuid)
returns table(new_current_hp int, new_max_hp int, new_current_ap int, new_quantity int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_current_hp int; v_current_ap int; v_max_ap int;
  v_max_hp int;
  v_item_id uuid; v_quantity int; v_type text; v_heal_amount int; v_restore_ap int;
  v_new_hp int; v_new_ap int; v_new_quantity int;
begin
  select user_id into v_owner_user_id from characters where id = p_character_id;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  perform regen_character(p_character_id);

  select current_hp, current_ap, max_ap
    into v_current_hp, v_current_ap, v_max_ap
  from characters where id = p_character_id for update;

  select gs.max_hp into v_max_hp from get_character_stats(p_character_id) gs;
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

-- 4. Explore ------------------------------------------------------------------
create table if not exists zones (
  id          uuid primary key default gen_random_uuid(),
  key         text unique not null,
  name        text not null,
  icon        text not null,
  description text,
  min_level   int not null,                    -- chỉ để cảnh báo, không khóa
  max_level   int not null,
  ap_cost     int not null,                    -- vé vào vùng, trừ 1 lần mỗi lượt explore
  boss_chance numeric not null default 0.03,   -- tỉ lệ mỗi lượt gặp boss thay vì quái thường
  sort_order  int not null default 0
);

create table if not exists zone_enemies (
  id          uuid primary key default gen_random_uuid(),
  zone_id     uuid not null references zones(id) on delete cascade,
  name        text not null,
  level       int not null,
  hp          int not null,
  atk         int not null,
  def         int not null,
  reward_exp  int not null,
  reward_gold int not null,
  weight      int not null default 10,         -- trọng số random giữa quái thường
  is_boss     boolean not null default false
);

create index if not exists zone_enemies_zone_id_idx on zone_enemies(zone_id);

create table if not exists zone_drops (
  id        uuid primary key default gen_random_uuid(),
  zone_id   uuid not null references zones(id) on delete cascade,
  item_id   uuid not null references items(id),
  drop_rate numeric not null,                  -- tỉ lệ rơi mỗi trận thắng
  boss_only boolean not null default false
);

create table if not exists explore_runs (
  id              uuid primary key default gen_random_uuid(),
  character_id    uuid not null references characters(id) on delete cascade,
  zone_id         uuid not null references zones(id),
  turns_requested int not null,
  turns_completed int not null,
  wins            int not null,
  died            boolean not null,
  exp_gained      int not null,
  gold_gained     int not null,
  drops           jsonb not null default '[]'::jsonb,
  created_at      timestamptz not null default now()
);

create index if not exists explore_runs_character_id_idx on explore_runs(character_id, created_at desc);

alter table zones enable row level security;
alter table zone_enemies enable row level security;
alter table zone_drops enable row level security;
alter table explore_runs enable row level security;

create policy "public read zones" on zones for select using (true);
create policy "public read zone_enemies" on zone_enemies for select using (true);
create policy "public read zone_drops" on zone_drops for select using (true);
create policy "own explore_runs select" on explore_runs
  for select using (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );

-- Chạy toàn bộ p_turns lượt (1-100) trong 1 lần gọi. Trả về jsonb tổng kết
-- (không dùng RETURNS TABLE để tránh lỗi 42702 trùng tên cột).
create or replace function public.explore_zone(p_character_id uuid, p_zone_id uuid, p_turns int)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_level int; v_current_hp int; v_current_ap int; v_max_ap int;
  v_max_hp int; v_char_atk int; v_char_def int;
  v_stat_crit_bonus numeric; v_stat_lifesteal_bonus numeric;
  v_a1_name text; v_a1_power numeric; v_a2_name text; v_a2_power numeric;
  v_dmg_reduction numeric; v_lifesteal numeric; v_crit_chance numeric;
  v_zone zones%rowtype;
  v_enemy zone_enemies%rowtype;
  v_has_boss boolean;
  v_is_boss boolean;
  v_exp_multiplier numeric; v_damage_multiplier numeric;
  v_win boolean; v_timed_out boolean;
  v_hp int;
  v_turn int;
  v_turns_completed int := 0;
  v_wins int := 0;
  v_died boolean := false;
  v_fight_exp int; v_fight_gold int;
  v_exp_gained int := 0; v_gold_gained int := 0;
  v_drop record;
  v_fight_drops jsonb;
  v_drop_counts jsonb := '{}'::jsonb;
  v_fights jsonb := '[]'::jsonb;
  v_drops jsonb;
  v_was_full_ap boolean;
  v_leveled_up boolean := false; v_new_level int;
begin
  select user_id into v_owner_user_id from characters where id = p_character_id;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  p_turns := least(100, greatest(1, coalesce(p_turns, 100)));

  select * into v_zone from zones where id = p_zone_id;
  if not found then raise exception 'Không tìm thấy vùng explore'; end if;

  perform regen_character(p_character_id);

  select level, current_hp, current_ap, max_ap
    into v_level, v_current_hp, v_current_ap, v_max_ap
  from characters where id = p_character_id for update;

  select gs.max_hp, gs.atk, gs.def, gs.crit_bonus, gs.lifesteal_bonus
    into v_max_hp, v_char_atk, v_char_def, v_stat_crit_bonus, v_stat_lifesteal_bonus
  from get_character_stats(p_character_id) gs;

  v_hp := coalesce(v_current_hp, v_max_hp);

  if v_hp <= 1 then
    raise exception 'Nhân vật đang kiệt sức, cần hồi máu trước khi đi explore';
  end if;

  if v_current_ap < v_zone.ap_cost then
    raise exception 'Không đủ AP để vào vùng này (cần % AP)', v_zone.ap_cost;
  end if;

  select cs.out_a1_name, cs.out_a1_power, cs.out_a2_name, cs.out_a2_power,
         cs.out_dmg_reduction, cs.out_lifesteal, cs.out_crit
    into v_a1_name, v_a1_power, v_a2_name, v_a2_power,
         v_dmg_reduction, v_lifesteal, v_crit_chance
  from get_combat_skills(p_character_id) cs;

  v_crit_chance := least(0.75, v_crit_chance + v_stat_crit_bonus);
  v_lifesteal := v_lifesteal + v_stat_lifesteal_bonus;

  select exists (select 1 from zone_enemies ze where ze.zone_id = p_zone_id and ze.is_boss)
    into v_has_boss;

  for v_turn in 1..p_turns loop
    -- Chọn quái: boss theo boss_chance, còn lại random có trọng số
    -- (Efraimidis–Spirakis: sắp theo -ln(random)/weight, lấy dòng đầu).
    -- Quái cao cấp hơn nhân vật bị giảm trọng số theo (1 + chênh cấp)², nên
    -- ở đầu vùng hiếm gặp con mạnh nhất; vào vùng vượt cấp thì con nào cũng
    -- cao hơn mình nên vẫn khó.
    v_is_boss := v_has_boss and random() < v_zone.boss_chance;

    select * into v_enemy from zone_enemies ze
    where ze.zone_id = p_zone_id and ze.is_boss = v_is_boss
    order by -ln(1 - random())
             / (greatest(1, ze.weight) / power(1 + greatest(0, ze.level - v_level), 2))
    limit 1;

    if not found then raise exception 'Vùng này chưa có quái'; end if;

    select exp_multiplier, damage_multiplier into v_exp_multiplier, v_damage_multiplier
    from calculate_combat_scaling(v_level, v_enemy.level);

    select f.out_win, f.out_timed_out, f.out_hp_left
      into v_win, v_timed_out, v_hp
    from simulate_fight(
      v_char_atk, v_char_def, v_hp, v_max_hp,
      v_crit_chance, v_lifesteal, v_dmg_reduction,
      v_a1_name, v_a1_power, v_a2_name, v_a2_power,
      v_enemy.name, v_enemy.hp, v_enemy.atk, v_enemy.def,
      v_damage_multiplier, false
    ) f;

    v_fight_exp := 0; v_fight_gold := 0;
    v_fight_drops := '[]'::jsonb;

    if v_win then
      v_wins := v_wins + 1;
      v_fight_exp := round(v_enemy.reward_exp * v_exp_multiplier);
      v_fight_gold := round(v_enemy.reward_gold * v_exp_multiplier);
      v_exp_gained := v_exp_gained + v_fight_exp;
      v_gold_gained := v_gold_gained + v_fight_gold;

      for v_drop in
        select zd.item_id, zd.drop_rate, i.key
        from zone_drops zd join items i on i.id = zd.item_id
        where zd.zone_id = p_zone_id and (not zd.boss_only or v_is_boss)
      loop
        continue when random() >= v_drop.drop_rate;
        perform grant_drop(p_character_id, v_drop.item_id);
        v_fight_drops := v_fight_drops || to_jsonb(v_drop.key);
        v_drop_counts := jsonb_set(
          v_drop_counts, array[v_drop.key],
          to_jsonb(coalesce((v_drop_counts ->> v_drop.key)::int, 0) + 1)
        );
      end loop;
    end if;

    v_fights := v_fights || jsonb_build_object(
      'turn', v_turn,
      'enemy', v_enemy.name,
      'level', v_enemy.level,
      'boss', v_is_boss,
      'result', case when v_win then 'win' when v_timed_out then 'flee' else 'lose' end,
      'hp_left', v_hp,
      'exp', v_fight_exp,
      'gold', v_fight_gold,
      'drops', v_fight_drops
    );

    v_turns_completed := v_turn;

    -- Hết HP: dừng, thưởng chỉ tính các trận đã thắng trước đó
    if not v_win and not v_timed_out then
      v_died := true;
      exit;
    end if;
  end loop;

  v_was_full_ap := (v_current_ap = v_max_ap);

  update characters
  set current_hp = greatest(1, v_hp),
      current_ap = current_ap - v_zone.ap_cost,
      gold = gold + v_gold_gained,
      last_ap_update = case when v_was_full_ap then now() else last_ap_update end
  where id = p_character_id;

  if v_exp_gained > 0 then
    select ae.leveled_up, ae.new_level into v_leveled_up, v_new_level
    from add_experience(p_character_id, v_exp_gained) as ae;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'key', i.key, 'name', i.name, 'icon', i.icon, 'rarity', i.rarity,
           'quantity', (v_drop_counts ->> i.key)::int
         ) order by i.rarity desc, i.name), '[]'::jsonb)
    into v_drops
  from items i where i.key in (select jsonb_object_keys(v_drop_counts));

  insert into explore_runs (character_id, zone_id, turns_requested, turns_completed, wins, died, exp_gained, gold_gained, drops)
  values (p_character_id, p_zone_id, p_turns, v_turns_completed, v_wins, v_died, v_exp_gained, v_gold_gained, v_drops);

  return jsonb_build_object(
    'zone', v_zone.name,
    'turns_requested', p_turns,
    'turns_completed', v_turns_completed,
    'wins', v_wins,
    'died', v_died,
    'exp_gained', v_exp_gained,
    'gold_gained', v_gold_gained,
    'leveled_up', v_leveled_up,
    'new_level', coalesce(v_new_level, v_level),
    'hp_left', greatest(1, v_hp),
    'max_hp', v_max_hp,
    'ap_left', v_current_ap - v_zone.ap_cost,
    'drops', v_drops,
    'fights', v_fights
  );
end;
$$;

-- 5. Nội dung: 4 vùng đầu -----------------------------------------------------
-- Quái thường: hp = 16 + 6L, atk = 3 + 1.5L, def = 0.8L, exp = gold = 1 + L
-- Boss (cấp max+1): hp ×4, atk ×1.4, def ×1.3, exp/gold ×6
-- Đã mô phỏng: ở đúng vùng, mọi class sống ~16-60 trận trước khi cần hồi máu.
insert into zones (key, name, icon, description, min_level, max_level, ap_cost, boss_chance, sort_order) values
  ('rung_xanh', 'Rừng Xanh', '🌲', 'Khu rừng yên bình ở rìa làng, hợp cho người mới.', 1, 5, 5, 0.03, 1),
  ('dong_bang', 'Đồng Bằng', '🌾', 'Cánh đồng rộng lớn, quái đi thành bầy.', 3, 8, 6, 0.03, 2),
  ('hang_dong', 'Hang Động', '⛏️', 'Hầm mỏ bỏ hoang, tối tăm và đầy quặng.', 6, 12, 8, 0.03, 3),
  ('nui_tuyet', 'Núi Tuyết', '🏔️', 'Đỉnh núi băng giá, gió rét cắt da.', 10, 18, 10, 0.03, 4)
on conflict (key) do nothing;

insert into zone_enemies (zone_id, name, level, hp, atk, def, reward_exp, reward_gold, weight, is_boss)
select z.id, e.name, e.lvl,
       round((16 + 6 * e.lvl) * case when e.boss then 4 else 1 end),
       round((3 + 1.5 * e.lvl) * case when e.boss then 1.4 else 1 end),
       round((0.8 * e.lvl) * case when e.boss then 1.3 else 1 end),
       (1 + e.lvl) * case when e.boss then 6 else 1 end,
       (1 + e.lvl) * case when e.boss then 6 else 1 end,
       e.weight, e.boss
from (values
  ('rung_xanh', 'Slime Xanh', 1, 40, false),
  ('rung_xanh', 'Thỏ Hoang', 2, 30, false),
  ('rung_xanh', 'Sói Rừng', 4, 20, false),
  ('rung_xanh', 'Nấm Độc', 5, 10, false),
  ('rung_xanh', 'Tinh Linh Cổ Thụ', 6, 1, true),
  ('dong_bang', 'Chuột Đồng', 3, 40, false),
  ('dong_bang', 'Bù Nhìn Ma', 5, 30, false),
  ('dong_bang', 'Lợn Rừng', 7, 20, false),
  ('dong_bang', 'Ong Bắp Cày', 8, 10, false),
  ('dong_bang', 'Vua Châu Chấu', 9, 1, true),
  ('hang_dong', 'Dơi Hang', 6, 40, false),
  ('hang_dong', 'Goblin Thợ Mỏ', 8, 30, false),
  ('hang_dong', 'Nhện Hang', 10, 20, false),
  ('hang_dong', 'Orc', 12, 10, false),
  ('hang_dong', 'Ancient Golem', 13, 1, true),
  ('nui_tuyet', 'Sói Tuyết', 10, 40, false),
  ('nui_tuyet', 'Người Tuyết', 13, 30, false),
  ('nui_tuyet', 'Yeti', 15, 20, false),
  ('nui_tuyet', 'Pháp Sư Băng', 18, 10, false),
  ('nui_tuyet', 'Rồng Băng Non', 19, 1, true)
) as e(zone_key, name, lvl, weight, boss)
join zones z on z.key = e.zone_key
where not exists (select 1 from zone_enemies ze where ze.zone_id = z.id);

-- Chỉ thêm đồ đã có trong bảng items (join bỏ qua key không tồn tại)
insert into zone_drops (zone_id, item_id, drop_rate, boss_only)
select z.id, i.id, d.rate, d.boss_only
from (values
  ('rung_xanh', 'wolf_fang', 0.12, false),
  ('rung_xanh', 'potion_minor', 0.06, false),
  ('rung_xanh', 'leather_armor', 0.015, false),
  ('rung_xanh', 'traveler_boots', 0.015, false),
  ('rung_xanh', 'forest_blade', 0.15, true),
  ('dong_bang', 'wolf_fang', 0.08, false),
  ('dong_bang', 'potion_minor', 0.08, false),
  ('dong_bang', 'iron_helmet', 0.02, false),
  ('dong_bang', 'ring_ruby', 0.015, false),
  ('dong_bang', 'guardian_amulet', 0.2, true),
  ('hang_dong', 'shadow_ore', 0.1, false),
  ('hang_dong', 'potion_medium', 0.05, false),
  ('hang_dong', 'iron_shield', 0.02, false),
  ('hang_dong', 'fortress_greatsword', 0.1, true),
  ('nui_tuyet', 'ice_shard', 0.12, false),
  ('nui_tuyet', 'potion_medium', 0.06, false),
  ('nui_tuyet', 'frost_blade', 0.12, true)
) as d(zone_key, item_key, rate, boss_only)
join zones z on z.key = d.zone_key
join items i on i.key = d.item_key
where not exists (select 1 from zone_drops zd where zd.zone_id = z.id);
