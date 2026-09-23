-- Bảng tin người chơi + hiệu ứng đặc biệt cho đồ Huyền Thoại.
--
-- Bảng tin (activity_feed): ghi khi hạ boss (explore + tầng boss dungeon) và
-- khi nhận đồ Huyền Thoại (rơi hoặc chế tạo). Mọi người chơi đăng nhập đều
-- đọc được; chỉ các RPC security definer ghi vào (qua post_activity).
--
-- Hiệu ứng Huyền Thoại (inventory.legendary_effect): mỗi món Huyền Thoại khi
-- tạo ra được random 1 trong 5 hiệu ứng. Nhiều món cùng hiệu ứng KHÔNG cộng
-- dồn — simulate_fight nhận danh sách hiệu ứng khác nhau đang mặc:
--   double_strike  Đòn Kép: 15% mỗi lượt đánh thêm 1 đòn
--   deadly_crit    Chí Mạng Chí Tử: chí mạng ×2.0 thay vì ×1.5
--   opening_strike Khai Cuộc: đòn đầu tiên mỗi trận ×2 sát thương
--   guardian       Hộ Thể: giảm 12% sát thương nhận vào
--   thorns         Phản Đòn: phản 20% sát thương nhận vào cho quái

-- 1. Bảng tin ----------------------------------------------------------------
create table if not exists activity_feed (
  id             uuid primary key default gen_random_uuid(),
  character_id   uuid references characters(id) on delete set null,
  character_name text not null,               -- chụp lại tên lúc xảy ra
  kind           text not null check (kind in ('boss_kill', 'legendary_item')),
  payload        jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now()
);

create index if not exists activity_feed_created_at_idx on activity_feed(created_at desc);

alter table activity_feed enable row level security;
drop policy if exists "authenticated read activity_feed" on activity_feed;
create policy "authenticated read activity_feed" on activity_feed
  for select to authenticated using (true);
-- Project không tự grant bảng mới (xem migration grant_select_new_tables)
grant select on table activity_feed to authenticated;

create or replace function public.post_activity(p_character_id uuid, p_kind text, p_payload jsonb)
returns void
language sql
set search_path = 'public'
as $$
  insert into activity_feed (character_id, character_name, kind, payload)
  select c.id, c.name, p_kind, p_payload from characters c where c.id = p_character_id;
$$;

revoke execute on function public.post_activity(uuid, text, jsonb) from public, anon, authenticated;

-- 2. Hiệu ứng Huyền Thoại ------------------------------------------------------
alter table inventory add column if not exists legendary_effect text
  check (legendary_effect in ('double_strike', 'deadly_crit', 'opening_strike', 'guardian', 'thorns'));

create or replace function public.roll_legendary_effect()
returns text
language sql
volatile
as $$
  select (array['double_strike', 'deadly_crit', 'opening_strike', 'guardian', 'thorns'])[1 + floor(random() * 5)::int];
$$;

-- Các hiệu ứng khác nhau trên đồ đang mặc (distinct → không cộng dồn)
create or replace function public.get_character_effects(p_character_id uuid)
returns text[]
language sql
stable
set search_path = 'public'
as $$
  select coalesce(array_agg(distinct inv.legendary_effect), '{}')
  from inventory inv
  where inv.character_id = p_character_id and inv.equipped and inv.legendary_effect is not null;
$$;

-- 3. Tạo đồ / vòng đánh / dungeon / explore dùng hiệu ứng + ghi bảng tin ------
create or replace function public.create_equipment(p_character_id uuid, p_item_id uuid, p_rarity text)
returns void
language plpgsql
set search_path = 'public'
as $$
declare
  v_slot text; v_school text; v_bonus_atk int; v_bonus_def int; v_bonus_hp int;
  v_mult numeric := rarity_multiplier(p_rarity);
  v_roll_atk int; v_roll_def int; v_roll_hp int; v_roll_crit numeric; v_roll_lifesteal numeric;
  v_effect text;
  v_item_name text; v_item_key text; v_item_icon text;
begin
  select i.slot, coalesce(i.school, 'physical'), i.bonus_atk, i.bonus_def, i.bonus_hp
    into v_slot, v_school, v_bonus_atk, v_bonus_def, v_bonus_hp
  from items i where i.id = p_item_id;

  select a.roll_atk, a.roll_def, a.roll_hp, a.roll_crit, a.roll_lifesteal
    into v_roll_atk, v_roll_def, v_roll_hp, v_roll_crit, v_roll_lifesteal
  from roll_item_affixes(v_slot, v_school, p_rarity) a;

  if p_rarity = 'legendary' then
    v_effect := roll_legendary_effect();
  end if;

  insert into inventory (character_id, item_id, quantity, rarity, legendary_effect, rolled_atk, rolled_def, rolled_hp, rolled_crit, rolled_lifesteal)
  values (
    p_character_id, p_item_id, 1, p_rarity, v_effect,
    v_roll_atk + round(v_bonus_atk * (v_mult - 1)),
    v_roll_def + round(v_bonus_def * (v_mult - 1)),
    v_roll_hp + round(v_bonus_hp * (v_mult - 1)),
    v_roll_crit, v_roll_lifesteal
  );

  -- Đồ Huyền Thoại (rơi hoặc chế tạo) lên bảng tin
  if p_rarity = 'legendary' then
    select i.name, i.key, i.icon into v_item_name, v_item_key, v_item_icon from items i where i.id = p_item_id;
    perform post_activity(p_character_id, 'legendary_item', jsonb_build_object(
      'item', v_item_name, 'item_key', v_item_key, 'icon', v_item_icon, 'effect', v_effect
    ));
  end if;
end;
$$;


-- simulate_fight thêm tham số p_effects → drop bản cũ (17 tham số) trước
drop function if exists public.simulate_fight(int, int, int, int, numeric, numeric, numeric, text, numeric, text, numeric, text, int, int, int, numeric, boolean);

create or replace function public.simulate_fight(
  p_char_atk int, p_char_def int, p_char_hp int, p_max_hp int,
  p_crit numeric, p_lifesteal numeric, p_dmg_reduction numeric,
  p_a1_name text, p_a1_power numeric, p_a2_name text, p_a2_power numeric,
  p_enemy_name text, p_enemy_hp int, p_enemy_atk int, p_enemy_def int,
  p_damage_multiplier numeric, p_with_log boolean,
  p_effects text[] default '{}'
)
returns table(out_win boolean, out_timed_out boolean, out_hp_left int, out_dmg_taken int, out_log jsonb)
language plpgsql
volatile
as $$
declare
  v_char_hp int := p_char_hp;
  v_enemy_hp int := p_enemy_hp;
  v_turn int := 0;
  v_skill_name text; v_skill_power numeric;
  v_base_dmg numeric; v_is_crit boolean; v_dmg int;
  v_enemy_dmg numeric; v_enemy_hit int; v_thorns int;
  v_log jsonb := '[]'::jsonb;
  v_win boolean;
  v_timed_out boolean := false;
  v_dmg_taken int := 0;
  v_hits int; v_hit int;
  -- Hiệu ứng Huyền Thoại (đã distinct ở get_character_effects)
  v_double boolean := 'double_strike' = any(p_effects);
  v_crit_mult numeric := case when 'deadly_crit' = any(p_effects) then 2.0 else 1.5 end;
  v_opening boolean := 'opening_strike' = any(p_effects);
  v_guardian numeric := case when 'guardian' = any(p_effects) then 0.88 else 1 end;
  v_thorns_on boolean := 'thorns' = any(p_effects);
begin
  while v_char_hp > 0 and v_enemy_hp > 0 and v_turn < 30 loop
    v_turn := v_turn + 1;

    if v_turn % 2 = 1 then
      v_skill_name := p_a1_name; v_skill_power := p_a1_power;
    else
      v_skill_name := p_a2_name; v_skill_power := p_a2_power;
    end if;

    -- Đòn Kép: 15% đánh thêm 1 đòn trong lượt
    v_hits := case when v_double and random() < 0.15 then 2 else 1 end;

    for v_hit in 1..v_hits loop
      exit when v_enemy_hp <= 0;

      v_base_dmg := greatest(1, p_char_atk * v_skill_power - p_enemy_def);
      if v_opening and v_turn = 1 and v_hit = 1 then
        v_base_dmg := v_base_dmg * 2;   -- Khai Cuộc
      end if;
      v_is_crit := random() < p_crit;
      v_dmg := round(v_base_dmg * (case when v_is_crit then v_crit_mult else 1 end));
      v_enemy_hp := greatest(0, v_enemy_hp - v_dmg);

      if p_lifesteal > 0 then
        v_char_hp := least(p_max_hp, v_char_hp + round(v_dmg * p_lifesteal));
      end if;

      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'character', 'skill', v_skill_name,
          'damage', v_dmg, 'crit', v_is_crit, 'enemy_hp_left', v_enemy_hp,
          'double', v_hit = 2, 'opening', v_opening and v_turn = 1 and v_hit = 1
        );
      end if;
    end loop;

    exit when v_enemy_hp <= 0;

    v_enemy_dmg := greatest(1, p_enemy_atk - p_char_def) * p_damage_multiplier * (1 - p_dmg_reduction) * v_guardian;
    v_enemy_hit := round(v_enemy_dmg);
    v_char_hp := greatest(0, v_char_hp - v_enemy_hit);
    v_dmg_taken := v_dmg_taken + v_enemy_hit;

    -- Phản Đòn: 20% sát thương nhận vào dội lại quái
    v_thorns := case when v_thorns_on then round(v_enemy_hit * 0.2) else 0 end;
    if v_thorns > 0 then
      v_enemy_hp := greatest(0, v_enemy_hp - v_thorns);
    end if;

    if p_with_log then
      v_log := v_log || jsonb_build_object(
        'turn', v_turn, 'actor', 'enemy', 'enemy_name', p_enemy_name,
        'damage', v_enemy_hit, 'character_hp_left', v_char_hp,
        'thorns', v_thorns, 'enemy_hp_left', v_enemy_hp
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

  return query select v_win, v_timed_out, v_char_hp, v_dmg_taken, v_log;
end;
$$;

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
  v_floor_number int; v_is_boss_floor boolean;
  v_effects text[];
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
         df.drop_item_id, df.drop_rate, d.ap_cost, df.is_boss_floor
    into v_dungeon_id, v_floor_number, v_enemy_name, v_enemy_level,
         v_enemy_hp, v_enemy_atk, v_enemy_def, v_reward_exp, v_reward_gold,
         v_drop_item_id, v_drop_rate, v_ap_cost, v_is_boss_floor
  from dungeon_floors df join dungeons d on d.id = df.dungeon_id
  where df.id = p_dungeon_floor_id;

  if not found then raise exception 'Không tìm thấy tầng dungeon'; end if;

  -- Chỉ được đánh tầng đã mở khóa: tầng 1, hoặc đã qua tầng ngay trước đó.
  -- (Trước đây chỉ UI khóa → gọi RPC thẳng là đánh được boss tầng cuối.)
  if v_floor_number > 1 and not exists (
    select 1 from dungeon_runs dr
    where dr.character_id = p_character_id and dr.dungeon_id = v_dungeon_id
      and dr.status = 'cleared' and dr.current_floor >= v_floor_number - 1
  ) then
    raise exception 'Tầng này chưa mở khóa (cần qua tầng % trước)', v_floor_number - 1;
  end if;

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
  v_effects := get_character_effects(p_character_id);

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
    v_damage_multiplier, true, v_effects
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

    if v_is_boss_floor then
      perform post_activity(p_character_id, 'boss_kill', jsonb_build_object(
        'boss', v_enemy_name, 'where', (select d.name from dungeons d where d.id = v_dungeon_id), 'source', 'dungeon'
      ));
    end if;
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
  v_dmg_taken int; v_fight_log jsonb;
  v_effects text[];
  v_last_fight jsonb := null;
  v_hp int;
  v_turn int;
  v_turns_completed int := 0;
  v_wins int := 0;
  v_died boolean := false;
  v_fight_exp int; v_fight_gold int;
  v_exp_gained int := 0; v_gold_gained int := 0;
  v_drop record;
  v_drop_rarity text;
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
  v_effects := get_character_effects(p_character_id);

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

    select f.out_win, f.out_timed_out, f.out_hp_left, f.out_dmg_taken, f.out_log
      into v_win, v_timed_out, v_hp, v_dmg_taken, v_fight_log
    from simulate_fight(
      v_char_atk, v_char_def, v_hp, v_max_hp,
      v_crit_chance, v_lifesteal, v_dmg_reduction,
      v_a1_name, v_a1_power, v_a2_name, v_a2_power,
      v_enemy.name, v_enemy.hp, v_enemy.atk, v_enemy.def,
      v_damage_multiplier, true, v_effects
    ) f;

    -- Chỉ giữ log từng đòn của trận cuối (nút "Xem trận cuối" trên web)
    v_last_fight := jsonb_build_object(
      'turn', v_turn, 'enemy', v_enemy.name, 'level', v_enemy.level, 'boss', v_is_boss, 'log', v_fight_log
    );

    v_fight_exp := 0; v_fight_gold := 0;
    v_fight_drops := '[]'::jsonb;

    if v_win then
      v_wins := v_wins + 1;

      if v_is_boss then
        perform post_activity(p_character_id, 'boss_kill', jsonb_build_object(
          'boss', v_enemy.name, 'where', v_zone.icon || ' ' || v_zone.name, 'source', 'explore'
        ));
      end if;
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
        v_drop_rarity := grant_drop(p_character_id, v_drop.item_id, v_is_boss);
        v_fight_drops := v_fight_drops || jsonb_build_object('key', v_drop.key, 'rarity', v_drop_rarity);
        -- Gộp theo cặp item|tier (cùng 1 món có thể rơi ra nhiều tier khác nhau)
        v_drop_counts := jsonb_set(
          v_drop_counts, array[v_drop.key || '|' || v_drop_rarity],
          to_jsonb(coalesce((v_drop_counts ->> (v_drop.key || '|' || v_drop_rarity))::int, 0) + 1)
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
      'dmg_taken', v_dmg_taken,
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
           'key', i.key, 'name', i.name, 'icon', i.icon, 'rarity', dc.drop_rarity,
           'quantity', dc.qty
         ) order by rarity_rank(dc.drop_rarity) desc, i.name), '[]'::jsonb)
    into v_drops
  from (
    select split_part(e.key, '|', 1) as item_key, split_part(e.key, '|', 2) as drop_rarity, e.value::int as qty
    from jsonb_each_text(v_drop_counts) e
  ) dc
  join items i on i.key = dc.item_key;

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
    'fights', v_fights,
    'last_fight', v_last_fight
  );
end;
$$;


-- 4. Đồ Huyền Thoại đang có: random hiệu ứng (không lên bảng tin)
update inventory set legendary_effect = roll_legendary_effect()
where rarity = 'legendary' and legendary_effect is null;
