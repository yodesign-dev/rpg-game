-- Tháp Vực Sâu: thay dungeon theo chương bằng tháp 100 tầng.
--
-- Dungeon cũ bị kẹt ở chương 1 (không có gì tăng current_chapter) nên chỉ có 5
-- tầng. Tháp: leo tự động từ điểm hồi sinh (mỗi 10 tầng), mỗi tầng tốn 5 AP,
-- HP giữ nguyên suốt lượt leo (qua mỗi tầng hồi 20%), quái trong 1 tầng đánh LẦN LƯỢT:
--   tầng thường       2 quái
--   tầng 5, 15, 25…   1 tinh anh + 1 quái
--   tầng 10, 20, 30…  ceil(tầng/20) boss (1 ở tầng 10-20 … 5 ở tầng 90-100)
-- Thành phần mỗi tầng cố định (không random) để UI xem trước được.
-- Thưởng: EXP/vàng theo quái; lần đầu qua tầng +50% vàng + nguyên liệu, tầng
-- boss lần đầu chắc chắn rơi trang bị (tier sàn tăng theo tầng), qua lại tầng
-- boss 20%. Trượt tầng nào thì không nhận thưởng của tầng đó.

-- 1. Tiến độ + danh hiệu + bảng tin ------------------------------------------------
alter table characters add column if not exists tower_best int not null default 0;

alter table titles drop constraint if exists titles_stat_check;
alter table titles add constraint titles_stat_check
  check (stat in ('kills', 'boss_kills', 'level', 'legendary_found', 'best_enchant', 'daily_bonus_count', 'tower_best'));

insert into titles (key, name, emoji, description, stat, threshold, sort_order) values
  ('tower_10',  'Người Thách Đấu',   '🗼', 'Vượt tầng 10 Tháp Vực Sâu',  'tower_best', 10,  13),
  ('tower_25',  'Kẻ Leo Tháp',       '🧗', 'Vượt tầng 25 Tháp Vực Sâu',  'tower_best', 25,  14),
  ('tower_50',  'Kẻ Chinh Phục',     '🏔️', 'Vượt tầng 50 Tháp Vực Sâu',  'tower_best', 50,  15),
  ('tower_100', 'Chúa Tể Vực Sâu',   '🌌', 'Vượt tầng 100 Tháp Vực Sâu', 'tower_best', 100, 16)
on conflict (key) do nothing;

alter table activity_feed drop constraint if exists activity_feed_kind_check;
alter table activity_feed add constraint activity_feed_kind_check
  check (kind in ('boss_kill', 'legendary_item', 'title', 'tower'));
-- now() = giờ bắt đầu transaction → mọi sự kiện trong 1 lượt leo trùng giờ,
-- bảng tin xếp lộn xộn. clock_timestamp() lấy giờ thực lúc ghi.
alter table activity_feed alter column created_at set default clock_timestamp();

create or replace function public.award_titles(p_character_id uuid)
returns int
language plpgsql
set search_path = 'public'
as $$
declare
  v_title record;
  v_count int := 0;
begin
  for v_title in
    select t.key, t.name, t.emoji
    from titles t join characters c on c.id = p_character_id
    where (case t.stat
             when 'kills' then c.kills when 'boss_kills' then c.boss_kills when 'level' then c.level
             when 'legendary_found' then c.legendary_found when 'best_enchant' then c.best_enchant
             when 'daily_bonus_count' then c.daily_bonus_count when 'tower_best' then c.tower_best
           end) >= t.threshold
      and not exists (select 1 from character_titles ct where ct.character_id = p_character_id and ct.title_key = t.key)
    order by t.sort_order
  loop
    insert into character_titles (character_id, title_key) values (p_character_id, v_title.key);
    perform post_activity(p_character_id, 'title', jsonb_build_object('title', v_title.name, 'emoji', v_title.emoji));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- 2. Thành phần mỗi tầng (cố định theo số tầng) -------------------------------------------
-- Chỉ số theo cùng công thức quái explore ở level = số tầng, nhân thêm hệ số
-- tháp (1 + 0.4% mỗi tầng → tầng 100 ×1.4) để đỉnh tháp khó hơn Thiên Đường.
create or replace function public.tower_floor_enemies(p_floor int)
returns table(out_idx int, out_name text, out_level int, out_kind text,
              out_hp int, out_atk int, out_def int, out_exp int, out_gold int)
language plpgsql
stable
set search_path = 'public'
as $$
declare
  v_lvl int := greatest(1, least(100, p_floor));
  v_tm numeric := 1 + v_lvl * 0.004;
  v_hp numeric := 16 + 6 * v_lvl;
  v_atk numeric := case when v_lvl < 15 then 3 + 1.5 * v_lvl else 8 + 1.2 * v_lvl end;
  v_def numeric := 0.8 * v_lvl;
  v_name text;
  v_idx int := 0;
  k int;
begin
  if v_lvl % 10 = 0 then
    -- Tầng boss: các boss explore gần level nhất, mạnh dần về cuối
    for v_name in
      select b.name from (
        select ze.name, ze.level from zone_enemies ze where ze.is_boss
        order by abs(ze.level - v_lvl), ze.level desc
        limit ceil(v_lvl / 20.0)::int
      ) b order by b.level
    loop
      v_idx := v_idx + 1;
      return query select v_idx, v_name, v_lvl, 'boss',
        round(v_hp * 2.5 * v_tm)::int, round(v_atk * 1.2 * v_tm)::int, round(v_def * 1.2)::int,
        (1 + v_lvl) * 6, (1 + v_lvl) * 6;
    end loop;
    return;
  end if;

  if v_lvl % 5 = 0 then
    select ze.name into v_name from zone_enemies ze where not ze.is_boss
    order by abs(ze.level - v_lvl), ze.level desc limit 1;
    v_idx := 1;
    return query select 1, 'Tinh Anh ' || v_name, v_lvl + 1, 'elite',
      round(v_hp * 2 * v_tm)::int, round(v_atk * 1.15 * v_tm)::int, round(v_def * 1.15)::int,
      (2 + v_lvl) * 3, (2 + v_lvl) * 3;
  end if;

  for k in (v_idx + 1)..2 loop
    select ze.name into v_name from zone_enemies ze where not ze.is_boss
    order by abs(ze.level - v_lvl), ze.name limit 1 offset ((v_lvl + k) % 3);
    return query select k, v_name, v_lvl, 'normal',
      round(v_hp * v_tm)::int, round(v_atk * v_tm)::int, round(v_def)::int,
      1 + v_lvl, 1 + v_lvl;
  end loop;
end;
$$;

-- 3. Leo tháp -------------------------------------------------------------------------------
-- p_start_floor phải là điểm hồi sinh: 1, 11, 21… và ≤ tầng cao nhất đã qua + 1.
-- Leo tối đa p_max_floors tầng (1-20); dừng khi gục, bỏ chạy (hết 30 lượt),
-- hết AP cho tầng kế, đủ số tầng, hoặc qua tầng 100.
create or replace function public.climb_tower(p_character_id uuid, p_start_floor int, p_max_floors int)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  c_ap_per_floor constant int := 5;
  v_owner_user_id uuid;
  v_level int; v_current_hp int; v_current_ap int; v_max_ap int; v_best int;
  v_max_hp int; v_char_atk int; v_char_def int;
  v_stat_crit_bonus numeric; v_stat_lifesteal_bonus numeric;
  v_a1_name text; v_a1_power numeric; v_a2_name text; v_a2_power numeric;
  v_dmg_reduction numeric; v_lifesteal numeric; v_crit_chance numeric;
  v_effects text[];
  v_hp int; v_ap int;
  v_max int := least(20, greatest(1, coalesce(p_max_floors, 10)));
  v_floor int := p_start_floor;
  v_done int := 0;
  v_stop text := null;
  v_enemy record;
  v_exp_mult numeric; v_dmg_mult numeric;
  v_win boolean; v_timed_out boolean; v_dmg_taken int; v_fight_log jsonb;
  v_last_fight jsonb := null;
  v_enemies jsonb; v_cleared boolean;
  v_floor_exp int; v_floor_gold int; v_floor_kills int; v_floor_bosses int;
  v_first boolean; v_drops jsonb;
  v_mat uuid; v_equip uuid; v_equip_rarity text; v_equip_base text;
  v_floors jsonb := '[]'::jsonb;
  v_exp_total int := 0; v_gold_total int := 0; v_kills int := 0; v_bosses int := 0; v_cleared_count int := 0;
  v_was_full_ap boolean;
  v_leveled_up boolean := false; v_new_level int;
begin
  select c.user_id into v_owner_user_id from characters c where c.id = p_character_id;
  if not found then raise exception 'Không tìm thấy nhân vật'; end if;
  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  perform regen_character(p_character_id);

  select c.level, c.current_hp, c.current_ap, c.max_ap, c.tower_best
    into v_level, v_current_hp, v_current_ap, v_max_ap, v_best
  from characters c where c.id = p_character_id for update;

  if p_start_floor is null or p_start_floor < 1 or p_start_floor > 100
     or (p_start_floor - 1) % 10 <> 0 or p_start_floor - 1 > v_best then
    raise exception 'Chỉ được bắt đầu từ điểm hồi sinh đã mở (tầng 1, 11, 21… tới tầng % )',
      (least(v_best, 99) / 10) * 10 + 1;
  end if;

  select gs.max_hp, gs.atk, gs.def, gs.crit_bonus, gs.lifesteal_bonus
    into v_max_hp, v_char_atk, v_char_def, v_stat_crit_bonus, v_stat_lifesteal_bonus
  from get_character_stats(p_character_id) gs;

  v_hp := coalesce(v_current_hp, v_max_hp);
  if v_hp <= 1 then raise exception 'Nhân vật đang kiệt sức, cần hồi máu trước khi leo tháp'; end if;
  if v_current_ap < c_ap_per_floor then
    raise exception 'Không đủ AP (mỗi tầng cần % AP)', c_ap_per_floor;
  end if;

  select cs.out_a1_name, cs.out_a1_power, cs.out_a2_name, cs.out_a2_power,
         cs.out_dmg_reduction, cs.out_lifesteal, cs.out_crit
    into v_a1_name, v_a1_power, v_a2_name, v_a2_power, v_dmg_reduction, v_lifesteal, v_crit_chance
  from get_combat_skills(p_character_id) cs;
  v_crit_chance := least(0.75, v_crit_chance + v_stat_crit_bonus);
  v_lifesteal := v_lifesteal + v_stat_lifesteal_bonus;
  v_effects := get_character_effects(p_character_id);

  v_ap := v_current_ap;
  v_was_full_ap := (v_current_ap >= v_max_ap);

  loop
    if v_floor > 100 then v_stop := 'top'; exit; end if;
    if v_done >= v_max then v_stop := 'max_floors'; exit; end if;
    if v_ap < c_ap_per_floor then v_stop := 'no_ap'; exit; end if;

    v_ap := v_ap - c_ap_per_floor;
    v_enemies := '[]'::jsonb;
    v_cleared := true;
    v_floor_exp := 0; v_floor_gold := 0; v_floor_kills := 0; v_floor_bosses := 0;

    for v_enemy in select * from tower_floor_enemies(v_floor) order by out_idx loop
      select sc.exp_multiplier, sc.damage_multiplier into v_exp_mult, v_dmg_mult
      from calculate_combat_scaling(v_level, v_enemy.out_level) sc;

      select f.out_win, f.out_timed_out, f.out_hp_left, f.out_dmg_taken, f.out_log
        into v_win, v_timed_out, v_hp, v_dmg_taken, v_fight_log
      from simulate_fight(
        v_char_atk, v_char_def, v_hp, v_max_hp,
        v_crit_chance, v_lifesteal, v_dmg_reduction,
        v_a1_name, v_a1_power, v_a2_name, v_a2_power,
        v_enemy.out_name, v_enemy.out_hp, v_enemy.out_atk, v_enemy.out_def,
        v_dmg_mult, true, v_effects
      ) f;

      v_last_fight := jsonb_build_object('floor', v_floor, 'enemy', v_enemy.out_name, 'log', v_fight_log);
      v_enemies := v_enemies || jsonb_build_object(
        'name', v_enemy.out_name, 'level', v_enemy.out_level, 'kind', v_enemy.out_kind,
        'result', case when v_win then 'win' when v_timed_out then 'flee' else 'lose' end,
        'hp_left', v_hp, 'dmg_taken', v_dmg_taken
      );

      if not v_win then
        v_cleared := false;
        v_stop := case when v_timed_out then 'fled' else 'died' end;
        exit;
      end if;

      v_floor_kills := v_floor_kills + 1;
      if v_enemy.out_kind = 'boss' then v_floor_bosses := v_floor_bosses + 1; end if;
      v_floor_exp := v_floor_exp + round(v_enemy.out_exp * v_exp_mult);
      v_floor_gold := v_floor_gold + round(v_enemy.out_gold * v_exp_mult);
    end loop;

    -- Quái đã hạ vẫn tính vào thành tích dù tầng trượt; thưởng thì không
    v_kills := v_kills + v_floor_kills;
    v_bosses := v_bosses + v_floor_bosses;
    v_done := v_done + 1;

    if not v_cleared then
      v_floors := v_floors || jsonb_build_object('floor', v_floor, 'cleared', false, 'enemies', v_enemies);
      exit;
    end if;

    v_first := v_floor > v_best;
    v_drops := '[]'::jsonb;

    if v_first then
      v_floor_gold := v_floor_gold + v_floor_gold / 2;
      v_mat := material_for_level(v_floor);
      if v_mat is not null then
        perform add_stack(p_character_id, v_mat, 2);
        v_drops := v_drops || (select jsonb_build_object('key', i.key, 'name', i.name, 'icon', i.icon, 'rarity', i.rarity, 'qty', 2)
                               from items i where i.id = v_mat);
      end if;
    end if;

    -- Tầng boss: lần đầu chắc chắn rơi trang bị, qua lại 20%
    if v_floor % 10 = 0 and (v_first or random() < 0.2) then
      select i.id, i.rarity into v_equip, v_equip_base from items i
      where i.type in ('weapon', 'armor') and i.buy_price is null
        and i.item_level between v_floor - 12 and v_floor + 3
      order by random() limit 1;
      if v_equip is null then
        select i.id, i.rarity into v_equip, v_equip_base from items i
        where i.type in ('weapon', 'armor') and i.buy_price is null
        order by abs(i.item_level - v_floor), random() limit 1;
      end if;
      if v_equip is not null then
        v_equip_rarity := roll_rarity(v_equip_base, 'boss');
        -- tier sàn theo tầng: 30+ ≥ Hiếm, 60+ ≥ Sử Thi, tầng 100 lần đầu = Huyền Thoại
        if v_floor >= 30 and rarity_rank(v_equip_rarity) < 1 then v_equip_rarity := 'rare'; end if;
        if v_floor >= 60 and rarity_rank(v_equip_rarity) < 2 then v_equip_rarity := 'epic'; end if;
        if v_floor = 100 and v_first then v_equip_rarity := 'legendary'; end if;
        perform create_equipment(p_character_id, v_equip, v_equip_rarity);
        v_drops := v_drops || (select jsonb_build_object('key', i.key, 'name', i.name, 'icon', i.icon, 'rarity', v_equip_rarity, 'qty', 1)
                               from items i where i.id = v_equip);
      end if;
      v_equip := null;
    end if;

    if v_first then
      v_best := v_floor;
      if v_floor % 10 = 0 then
        perform post_activity(p_character_id, 'tower', jsonb_build_object('floor', v_floor));
      end if;
    end if;

    v_exp_total := v_exp_total + v_floor_exp;
    v_gold_total := v_gold_total + v_floor_gold;
    v_cleared_count := v_cleared_count + 1;

    v_floors := v_floors || jsonb_build_object(
      'floor', v_floor, 'cleared', true, 'first_clear', v_first,
      'exp', v_floor_exp, 'gold', v_floor_gold, 'drops', v_drops, 'enemies', v_enemies
    );

    -- Nghỉ chân giữa các tầng: hồi 20% HP tối đa
    v_hp := least(v_max_hp, v_hp + ceil(v_max_hp * 0.2)::int);
    v_floor := v_floor + 1;
  end loop;

  update characters c
  set current_hp = greatest(1, v_hp),
      current_ap = v_ap,
      gold = c.gold + v_gold_total,
      tower_best = v_best,
      kills = c.kills + v_kills,
      boss_kills = c.boss_kills + v_bosses,
      last_ap_update = case when v_was_full_ap then now() else c.last_ap_update end
  where c.id = p_character_id;

  if v_exp_total > 0 then
    select ae.leveled_up, ae.new_level into v_leveled_up, v_new_level
    from add_experience(p_character_id, v_exp_total) ae;
  end if;

  perform track_quest(p_character_id, 'kills', v_kills);
  perform track_quest(p_character_id, 'boss', v_bosses);
  perform track_quest(p_character_id, 'dungeon', v_cleared_count);
  perform award_titles(p_character_id);

  return jsonb_build_object(
    'start_floor', p_start_floor,
    'floors_attempted', v_done,
    'floors_cleared', v_cleared_count,
    'stop', v_stop,
    'tower_best', v_best,
    'exp_gained', v_exp_total,
    'gold_gained', v_gold_total,
    'leveled_up', v_leveled_up,
    'new_level', coalesce(v_new_level, v_level),
    'hp_left', greatest(1, v_hp),
    'max_hp', v_max_hp,
    'ap_left', v_ap,
    'ap_per_floor', c_ap_per_floor,
    'floors', v_floors,
    'last_fight', v_last_fight
  );
end;
$$;

-- 4. Dungeon cũ ngừng dùng (UI thay bằng tháp) ---------------------------------------------
revoke execute on function public.resolve_dungeon_floor(uuid, uuid) from public, anon, authenticated;

-- Nhiệm vụ ngày loại 'dungeon' giờ là vượt tầng tháp
create or replace function public.ensure_daily_quests(p_character_id uuid)
returns void
language plpgsql
set search_path = 'public'
as $$
begin
  insert into daily_quests (character_id, quest_date, quests)
  select p_character_id, vn_today(), jsonb_agg(jsonb_build_object(
           'type', q.type, 'target', q.target, 'label', q.label, 'progress', 0, 'claimed', false))
  from (
    -- mỗi loại lấy 1 mức ngẫu nhiên, rồi chọn ngẫu nhiên 3 loại khác nhau
    select per_type.* from (
      select distinct on (p.type) p.type, p.target, p.label
      from (values
        ('kills', 30, 'Hạ 30 quái'), ('kills', 60, 'Hạ 60 quái'), ('kills', 100, 'Hạ 100 quái'),
        ('boss', 1, 'Hạ 1 boss'), ('boss', 3, 'Hạ 3 boss'),
        ('explore', 2, 'Đi thám hiểm 2 lần'), ('explore', 4, 'Đi thám hiểm 4 lần'),
        ('dungeon', 2, 'Vượt 2 tầng Tháp'), ('dungeon', 5, 'Vượt 5 tầng Tháp'),
        ('enchant', 1, 'Cường hóa trang bị 1 lần'),
        ('convert', 1, 'Rã hoặc ghép nguyên liệu 1 lần')
      ) as p(type, target, label)
      order by p.type, random()
    ) per_type
    order by random()
    limit 3
  ) q
  on conflict (character_id, quest_date) do nothing;
end;
$$;

-- 5. Bảng xếp hạng thêm tầng tháp -------------------------------------------------------------
drop function if exists public.get_leaderboard(text);

create or replace function public.get_leaderboard(p_sort text)
returns table(
  out_rank int, out_character_id uuid, out_name text, out_class_key text, out_class_name text,
  out_level int, out_power int, out_boss_kills int, out_kills int, out_tower_best int, out_title text
)
language sql
stable
security definer
set search_path = 'public'
as $$
  with base as (
    select c.id, c.name, cl.key as class_key, cl.name as class_name, c.level, c.exp,
           character_power(c.id) as power, c.boss_kills, c.kills, c.tower_best,
           t.emoji || ' ' || t.name as title
    from characters c
    join classes cl on cl.id = c.class_id
    left join titles t on t.key = c.title_key
  )
  select (row_number() over (order by
            case p_sort when 'power' then b.power when 'boss_kills' then b.boss_kills
                        when 'tower' then b.tower_best else b.level end desc,
            case p_sort when 'level' then b.exp else b.level end desc,
            b.name))::int,
         b.id, b.name, b.class_key, b.class_name, b.level, b.power, b.boss_kills, b.kills, b.tower_best, b.title
  from base b
  order by 1
  limit 50;
$$;
