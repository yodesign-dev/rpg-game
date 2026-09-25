-- Pet: bắt quái làm pet khi Thám Hiểm (kiểu Pokémon).
-- 1. Sau trận thắng quái thường có 1,5% gặp pet hoang dã (Tinh Anh 3%, Hung Thần 5%, boss không gặp).
--    Độ hiếm 60/28/10/2% (common/rare/epic/legendary); pet chờ bắt 24 giờ, tối đa 10 con chờ.
-- 2. Bắt bằng Lưới (Chợ): Thường / Tốt / Thượng Hạng. Tối đa 3 lần ném, ném trượt 30% pet bỏ chạy.
-- 3. Bắt được thì tung nội tại ngẫu nhiên: 1 dòng (common/rare), 2 dòng (epic/legendary),
--    giá trị ×1 / ×1.75 / ×2.75 / ×4 theo độ hiếm, dao động ±20%. Mang 1 pet, tối đa 50 pet.
-- 4. Nội tại chiến đấu vào get_character_stats (ATK/DEF/HP %, chí mạng, hút máu) và
--    combat_mods (hồi máu, xuyên giáp, đòn kép, giảm sát thương) qua get_bonus_totals();
--    % EXP / vàng / rơi đồ chỉ áp dụng khi Thám Hiểm.

-- Bảng pet đời đầu (schema.sql: pet_species + character_pets.species_id) chưa từng được dùng —
-- bỏ để dựng lại theo cơ chế mới. Chỉ xoá khi còn đúng cấu trúc cũ.
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'character_pets' and column_name = 'species_id') then
    drop table public.character_pets;
  end if;
end;
$$;
drop table if exists public.pet_species;

-- Loài bắt được: quái có sprite Mythic Monsters (khớp lib/enemies.ts MONSTERS), không phải boss
alter table zone_enemies add column if not exists catchable boolean not null default false;
update zone_enemies set catchable = (not is_boss and name in (
  'Slime Xanh',
  'Rắn Cỏ',
  'Sói Rừng',
  'Yêu Tinh Rừng',
  'Sâu Đồng',
  'Bù Nhìn Ma',
  'Lợn Rừng',
  'Ong Bắp Cày',
  'Vua Châu Chấu',
  'Bọ Giáp Hang',
  'Goblin Thợ Mỏ',
  'Nhện Hang',
  'Orc',
  'Ancient Golem',
  'Sói Tuyết',
  'Hồn Ma Băng',
  'Yeti',
  'Rồng Băng Non',
  'Bọ Cạp Cát',
  'Rắn Hổ Mang',
  'Xác Ướp',
  'Sâu Cát Khổng Lồ',
  'Thằn Lằn Lửa',
  'Tinh Linh Lửa',
  'Golem Dung Nham',
  'Chó Địa Ngục',
  'Rồng Lửa Cổ Đại',
  'Nhện Bóng Tối',
  'Tượng Thần Canh Gác',
  'Sư Tử Thần',
  'Mắt Hư Không',
  'Sứa Không Gian',
  'Kẻ Nuốt Sao',
  'Tinh Thể Sống',
  'Nguyên Tố Hỗn Mang',
  'Người Khổng Lồ Pha Lê',
  'Rồng Nguyên Tố',
  'Thiên Nhãn'
));

-- Lưới bắt pet: bậc 1-3
alter table items add column if not exists net_tier int;

insert into items (key, name, type, rarity, buy_price, price_per_level, daily_limit, sell_price, description, icon, net_tier) values
  ('net_basic', 'Lưới Thường', 'material', 'common', 150, 15, null, 0,
   'Ném để bắt pet hoang dã gặp khi Thám Hiểm. Bắt: common 60% · rare 35% · epic 15% · legendary 5%.', 'net_basic.png', 1),
  ('net_good', 'Lưới Tốt', 'material', 'rare', 500, 50, null, 0,
   'Ném để bắt pet hoang dã. Bắt: common 80% · rare 55% · epic 30% · legendary 12%.', 'net_good.png', 2),
  ('net_master', 'Lưới Thượng Hạng', 'material', 'epic', 1500, 150, 5, 0,
   'Ném để bắt pet hoang dã. Bắt: common 95% · rare 75% · epic 50% · legendary 25%. Mua tối đa 5 cái mỗi ngày.', 'net_master.png', 3)
on conflict (key) do nothing;

-- Danh mục nội tại pet: key = khoá trong mods (get_talent_totals / combat_mods), base = giá trị common
create table if not exists pet_passives (
  key         text primary key,
  name        text not null,
  base        numeric not null,
  sort_order  int not null default 0
);
alter table pet_passives enable row level security;
drop policy if exists "pet_passives read" on pet_passives;
create policy "pet_passives read" on pet_passives for select using (true);
grant select on table pet_passives to anon, authenticated;

insert into pet_passives (key, name, base, sort_order) values
  ('atk_pct', 'Sức Mạnh', 0.02, 1),
  ('def_pct', 'Vững Chãi', 0.02, 2),
  ('hp_pct', 'Sinh Lực', 0.02, 3),
  ('crit', 'Nhãn Lực', 0.01, 4),
  ('lifesteal', 'Hút Huyết', 0.0075, 5),
  ('regen', 'Tái Tạo', 0.002, 6),
  ('pierce', 'Xuyên Giáp', 0.02, 7),
  ('double', 'Liên Kích', 0.01, 8),
  ('pet_dmg_red', 'Hộ Vệ', 0.01, 9),
  ('exp_pct', 'Thông Tuệ', 0.03, 10),
  ('gold_pct', 'Tài Lộc', 0.03, 11),
  ('drop_pct', 'May Mắn', 0.03, 12)
on conflict (key) do update set name = excluded.name, base = excluded.base, sort_order = excluded.sort_order;

-- Pet đã bắt
create table if not exists character_pets (
  id           uuid primary key default gen_random_uuid(),
  character_id uuid not null references characters(id) on delete cascade,
  species      text not null,             -- tên loài quái (zone_enemies.name)
  level        int not null default 1,    -- cấp quái lúc bắt (quyết định vàng khi thả)
  rarity       text not null check (rarity in ('common', 'rare', 'epic', 'legendary')),
  passives     jsonb not null default '[]'::jsonb,  -- [{key, value}]
  zone_id      uuid references zones(id) on delete set null,
  active       boolean not null default false,
  caught_at    timestamptz not null default now()
);
create index if not exists character_pets_character_idx on character_pets (character_id);
create unique index if not exists character_pets_one_active on character_pets (character_id) where active;
alter table character_pets enable row level security;
drop policy if exists "own pets select" on character_pets;
create policy "own pets select" on character_pets
  for select using (exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid()));
grant select on table character_pets to authenticated;

-- Pet hoang dã đang chờ bắt
create table if not exists pet_encounters (
  id           uuid primary key default gen_random_uuid(),
  character_id uuid not null references characters(id) on delete cascade,
  zone_id      uuid references zones(id) on delete set null,
  species      text not null,
  level        int not null default 1,
  rarity       text not null check (rarity in ('common', 'rare', 'epic', 'legendary')),
  tries_left   int not null default 3,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '24 hours'
);
create index if not exists pet_encounters_character_idx on pet_encounters (character_id);
alter table pet_encounters enable row level security;
drop policy if exists "own pet_encounters select" on pet_encounters;
create policy "own pet_encounters select" on pet_encounters
  for select using (exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid()));
grant select on table pet_encounters to authenticated;

alter table activity_feed drop constraint if exists activity_feed_kind_check;
alter table activity_feed add constraint activity_feed_kind_check
  check (kind in ('boss_kill', 'legendary_item', 'title', 'tower', 'gacha_jackpot', 'pet_catch'));

create or replace function public.pet_rarity_mult(p_rarity text)
returns numeric
language sql
immutable
as $$
  select case p_rarity when 'legendary' then 4 when 'epic' then 2.75 when 'rare' then 1.75 else 1 end::numeric;
$$;

-- Tỉ lệ bắt theo độ hiếm × bậc lưới
create or replace function public.pet_catch_rate(p_rarity text, p_net_tier int)
returns numeric
language sql
immutable
as $$
  select (case p_rarity
    when 'legendary' then array[0.05, 0.12, 0.25]
    when 'epic' then array[0.15, 0.30, 0.50]
    when 'rare' then array[0.35, 0.55, 0.75]
    else array[0.60, 0.80, 0.95] end)[least(3, greatest(1, p_net_tier))]::numeric;
$$;

-- Tung nội tại lúc bắt: 1 dòng (common/rare) hoặc 2 dòng khác nhau (epic/legendary), ±20%
create or replace function public.roll_pet_passives(p_rarity text)
returns jsonb
language sql
volatile
set search_path = 'public'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'key', p.key,
           'value', round(p.base * pet_rarity_mult(p_rarity) * (0.8 + random() * 0.4)::numeric, 4)
         )), '[]'::jsonb)
  from (
    select pp.key, pp.base from pet_passives pp
    order by random()
    limit case when p_rarity in ('epic', 'legendary') then 2 else 1 end
  ) p;
$$;

-- Tổng nội tại của pet đang mang: {key: value}
create or replace function public.pet_mods(p_character_id uuid)
returns jsonb
language sql
stable
set search_path = 'public'
as $$
  select coalesce(jsonb_object_agg(s.k, s.total), '{}'::jsonb)
  from (
    select x->>'key' as k, sum((x->>'value')::numeric) as total
    from character_pets cp cross join lateral jsonb_array_elements(cp.passives) x
    where cp.character_id = p_character_id and cp.active
    group by x->>'key'
  ) s;
$$;

-- Thiên phú + nội tại chiến đấu của pet (không gồm % EXP / vàng / rơi đồ — chỉ Thám Hiểm đọc)
create or replace function public.get_bonus_totals(p_character_id uuid)
returns jsonb
language plpgsql
stable
set search_path = 'public'
as $$
declare
  v jsonb := get_talent_totals(p_character_id);
  p jsonb := pet_mods(p_character_id);
  k text;
begin
  for k in select jsonb_object_keys(p) loop
    continue when k in ('exp_pct', 'gold_pct', 'drop_pct');
    v := v || jsonb_build_object(k, coalesce((v->>k)::numeric, 0) + (p->>k)::numeric);
  end loop;
  return v;
end;
$$;

create or replace function public.combat_mods(p_character_id uuid)
returns jsonb
language plpgsql
stable
set search_path = 'public'
as $$
declare
  v jsonb := get_bonus_totals(p_character_id);
  g jsonb := get_gear_mods(p_character_id);
  k text;
begin
  for k in select jsonb_object_keys(g) loop
    if k = 'dmg_red' then
      v := v || jsonb_build_object('gear_dmg_red', coalesce((v->>'gear_dmg_red')::numeric, 0) + (g->>k)::numeric);
    else
      v := v || jsonb_build_object(k, coalesce((v->>k)::numeric, 0) + (g->>k)::numeric);
    end if;
  end loop;
  -- Hộ Vệ của pet cộng chung trần giảm sát thương với trang bị (simulate_fight: tối đa 25%)
  if v ? 'pet_dmg_red' then
    v := v || jsonb_build_object('gear_dmg_red', coalesce((v->>'gear_dmg_red')::numeric, 0) + (v->>'pet_dmg_red')::numeric);
  end if;
  return v || jsonb_build_object('kit', get_skill_kit(p_character_id));
end;
$$;

create or replace function public.get_character_stats(p_character_id uuid)
returns table(
  base_max_hp int, base_atk int, base_def int, base_spd int, attr_crit numeric,
  max_hp int, atk int, def int, crit_bonus numeric, lifesteal_bonus numeric
)
language sql
stable
set search_path = 'public'
as $$
  select
    b.base_max_hp, b.base_atk, b.base_def, b.base_spd, b.attr_crit,
    b.base_max_hp + e.hp, b.base_atk + e.atk, b.base_def + e.def,
    b.attr_crit + b.talent_crit + e.crit, b.talent_lifesteal + e.lifesteal
  from (
    -- Thiên phú + pet đang mang: % nhân vào chỉ số gốc (không nhân trang bị), chí mạng/hút máu cộng thẳng
    select
      round((cl.base_hp + (ch.level - 1) * cl.hp_per_level + ab.attr_hp)
            * greatest(0.1, 1 + coalesce((t.j->>'hp_pct')::numeric, 0)))::int as base_max_hp,
      round((cl.base_atk + (ch.level - 1) * cl.atk_per_level + ab.attr_atk)
            * greatest(0.1, 1 + coalesce((t.j->>'atk_pct')::numeric, 0)))::int as base_atk,
      round((cl.base_def + (ch.level - 1) * cl.def_per_level + ab.attr_def)
            * greatest(0.1, 1 + coalesce((t.j->>'def_pct')::numeric, 0)))::int as base_def,
      cl.base_spd + (ch.level - 1) * cl.spd_per_level as base_spd,
      ab.attr_crit + cl.base_crit as attr_crit,   -- chí mạng khởi điểm theo class + AGI/DEX
      coalesce((t.j->>'crit')::numeric, 0) as talent_crit,
      coalesce((t.j->>'lifesteal')::numeric, 0) as talent_lifesteal
    from characters ch
    join classes cl on cl.id = ch.class_id
    cross join lateral attribute_bonuses(
      cl.main_stat, ch.stat_str, ch.stat_int, ch.stat_agi, ch.stat_dex, ch.stat_vit
    ) ab
    cross join lateral (select get_bonus_totals(ch.id) as j) t
    where ch.id = p_character_id
  ) b
  cross join lateral (
    select
      coalesce(sum(i.bonus_hp + inv.rolled_hp), 0)::int as hp,
      coalesce(sum(i.bonus_atk + inv.rolled_atk), 0)::int as atk,
      coalesce(sum(i.bonus_def + inv.rolled_def), 0)::int as def,
      coalesce(sum(inv.rolled_crit), 0) as crit,
      coalesce(sum(inv.rolled_lifesteal), 0) as lifesteal
    from inventory inv join items i on i.id = inv.item_id
    where inv.character_id = p_character_id and inv.equipped = true
  ) e;
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
  -- Cấp quái thường: Tinh Anh / Hung Thần (boss không tung cấp)
  v_tier text; v_tier_roll numeric; v_name text; v_traits text[];
  v_e_hp int; v_e_atk int; v_e_def int;
  v_reward_mult numeric; v_drop_mult numeric;
  v_exp_multiplier numeric; v_damage_multiplier numeric;
  v_win boolean; v_timed_out boolean;
  v_dmg_taken int; v_fight_log jsonb;
  v_effects text[];
  v_last_fight jsonb := null;
  v_hp int;
  v_turn int;
  v_turns_completed int := 0;
  v_wins int := 0;
  v_boss_wins int := 0;
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
  v_mods jsonb; v_revived boolean;
  -- Tiếp tế: bình tự uống (tối đa 3/chuyến) + cuộn / bùa đang chờ
  v_auto_potion boolean; v_potions_left int := 0; v_potions_used int := 0; v_drink record;
  v_buff_exp boolean := false; v_buff_luck boolean := false; v_buff_guard boolean := false; v_guard_used boolean := false;
  v_ap_spent int; v_pen_gold int := 0; v_pen_exp int := 0;
  -- Pet: nội tại % EXP/vàng/rơi đồ của pet đang mang + gặp pet hoang dã sau trận thắng
  v_pet jsonb; v_pet_exp numeric; v_pet_gold numeric; v_pet_drop numeric;
  v_pending_pets int; v_pet_chance numeric; v_pet_roll numeric; v_pet_rarity text; v_fight_pet text;
  v_pets_found jsonb := '[]'::jsonb;
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

  select level, current_hp, current_ap, max_ap, auto_potion
    into v_level, v_current_hp, v_current_ap, v_max_ap, v_auto_potion
  from characters where id = p_character_id for update;

  select gs.max_hp, gs.atk, gs.def, gs.crit_bonus, gs.lifesteal_bonus
    into v_max_hp, v_char_atk, v_char_def, v_stat_crit_bonus, v_stat_lifesteal_bonus
  from get_character_stats(p_character_id) gs;

  v_hp := coalesce(v_current_hp, v_max_hp);

  if v_hp <= 1 then
    raise exception 'Nhân vật đang kiệt sức, cần hồi máu trước khi đi explore';
  end if;

  if v_current_ap < v_zone.ap_cost then
    raise exception 'Không đủ AP để vào vùng này (cần % AP cho 10 trận)', v_zone.ap_cost;
  end if;
  -- Vé AP tính cho mỗi 10 trận: số trận tối đa theo AP đang có
  p_turns := least(p_turns, (v_current_ap / v_zone.ap_cost) * 10);

  select cs.out_a1_name, cs.out_a1_power, cs.out_a2_name, cs.out_a2_power,
         cs.out_dmg_reduction, cs.out_lifesteal, cs.out_crit
    into v_a1_name, v_a1_power, v_a2_name, v_a2_power,
         v_dmg_reduction, v_lifesteal, v_crit_chance
  from get_combat_skills(p_character_id) cs;

  v_crit_chance := least(0.5, v_crit_chance + v_stat_crit_bonus);
  v_lifesteal := v_lifesteal + v_stat_lifesteal_bonus;
  v_effects := get_character_effects(p_character_id);
  v_mods := combat_mods(p_character_id);
  v_pet := pet_mods(p_character_id);
  v_pet_exp := 1 + coalesce((v_pet->>'exp_pct')::numeric, 0);
  v_pet_gold := 1 + coalesce((v_pet->>'gold_pct')::numeric, 0);
  v_pet_drop := 1 + coalesce((v_pet->>'drop_pct')::numeric, 0);
  delete from pet_encounters pe where pe.character_id = p_character_id and pe.expires_at < now();
  select count(*) into v_pending_pets from pet_encounters pe where pe.character_id = p_character_id;

  select coalesce(bool_or(b.buff_key = 'exp'), false), coalesce(bool_or(b.buff_key = 'luck'), false),
         coalesce(bool_or(b.buff_key = 'guard'), false)
    into v_buff_exp, v_buff_luck, v_buff_guard
  from character_buffs b where b.character_id = p_character_id;
  delete from character_buffs b where b.character_id = p_character_id;
  v_potions_left := case when v_auto_potion then 2 else 0 end;

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

    -- Tung cấp: 2% Hung Thần, 10% Tinh Anh. Tên hiển thị mang tiền tố cấp (web tra ảnh theo tên).
    v_tier := 'normal';
    if not v_is_boss then
      v_tier_roll := random();
      if v_tier_roll < 0.02 then v_tier := 'champion';
      elsif v_tier_roll < 0.12 then v_tier := 'elite';
      end if;
    end if;

    v_name := case v_tier when 'elite' then 'Tinh Anh ' when 'champion' then 'Hung Thần ' else '' end || v_enemy.name;
    v_e_hp := round(v_enemy.hp * case v_tier when 'elite' then 2 when 'champion' then 3 else 1 end);
    v_e_atk := round(v_enemy.atk * case v_tier when 'elite' then 1.15 when 'champion' then 1.3 else 1 end);
    v_e_def := round(v_enemy.def * case v_tier when 'elite' then 1.15 when 'champion' then 1.25 else 1 end);
    v_reward_mult := case v_tier when 'elite' then 2.5 when 'champion' then 4 else 1 end;
    v_drop_mult := case v_tier when 'elite' then 1.5 when 'champion' then 2 else 1 end;
    -- Đặc tính: của vùng + Tinh Anh thêm 1, Hung Thần thêm 2 (ngẫu nhiên), boss luôn Cuồng Nộ
    v_traits := v_zone.traits || case
      when v_is_boss then array['enrage']
      when v_tier = 'elite' then enemy_extra_traits(1, v_zone.traits)
      when v_tier = 'champion' then enemy_extra_traits(2, v_zone.traits)
      else '{}'::text[] end;

    select exp_multiplier, damage_multiplier into v_exp_multiplier, v_damage_multiplier
    from calculate_combat_scaling(v_level, v_enemy.level);

    select f.out_win, f.out_timed_out, f.out_hp_left, f.out_dmg_taken, f.out_log, f.out_revived
      into v_win, v_timed_out, v_hp, v_dmg_taken, v_fight_log, v_revived
    from simulate_fight(
      v_char_atk, v_char_def, v_hp, v_max_hp,
      v_crit_chance, v_lifesteal, v_dmg_reduction,
      v_a1_name, v_a1_power, v_a2_name, v_a2_power,
      v_name, v_e_hp, v_e_atk, v_e_def,
      v_damage_multiplier, true, v_effects, v_mods,
      v_enemy.level - v_level, v_traits, v_enemy.level
    ) f;

    -- Chỉ giữ log từng đòn của trận cuối (nút "Xem trận cuối" trên web)
    -- Giả Chết chỉ 1 lần mỗi chuyến
    if v_revived then v_mods := v_mods - 'revive'; end if;

    v_last_fight := jsonb_build_object(
      'turn', v_turn, 'enemy', v_name, 'level', v_enemy.level, 'boss', v_is_boss, 'log', v_fight_log
    );

    v_fight_exp := 0; v_fight_gold := 0;
    v_fight_drops := '[]'::jsonb;
    v_fight_pet := null;

    if v_win then
      v_wins := v_wins + 1;
      if v_is_boss then v_boss_wins := v_boss_wins + 1; end if;

      if v_is_boss then
        perform post_activity(p_character_id, 'boss_kill', jsonb_build_object(
          'boss', v_enemy.name, 'where', v_zone.icon || ' ' || v_zone.name, 'source', 'explore'
        ));
      end if;
      v_fight_exp := round(v_enemy.reward_exp * v_reward_mult * v_exp_multiplier * case when v_buff_exp then 1.25 else 1 end * v_pet_exp);
      v_fight_gold := round(v_enemy.reward_gold * v_reward_mult * v_exp_multiplier * v_pet_gold);
      v_exp_gained := v_exp_gained + v_fight_exp;
      v_gold_gained := v_gold_gained + v_fight_gold;

      for v_drop in
        select zd.item_id, zd.drop_rate, i.key
        from zone_drops zd join items i on i.id = zd.item_id
        where zd.zone_id = p_zone_id and (not zd.boss_only or v_is_boss)
      loop
        continue when random() >= v_drop.drop_rate * v_drop_mult * case when v_buff_luck then 1.3 else 1 end * v_pet_drop;
        -- Hung Thần tung độ hiếm trang bị như boss
        v_drop_rarity := grant_drop(p_character_id, v_drop.item_id, v_is_boss or v_tier = 'champion');
        v_fight_drops := v_fight_drops || jsonb_build_object('key', v_drop.key, 'rarity', v_drop_rarity);
        -- Gộp theo cặp item|tier (cùng 1 món có thể rơi ra nhiều tier khác nhau)
        v_drop_counts := jsonb_set(
          v_drop_counts, array[v_drop.key || '|' || v_drop_rarity],
          to_jsonb(coalesce((v_drop_counts ->> (v_drop.key || '|' || v_drop_rarity))::int, 0) + 1)
        );
      end loop;

      -- Pet hoang dã: 1,5% sau trận thắng quái thường (Tinh Anh 3%, Hung Thần 5%), không gặp ở boss.
      -- Độ hiếm 60/28/10/2%; Tinh Anh / Hung Thần nghiêng về hiếm hơn. Tối đa 10 pet chờ bắt.
      v_pet_chance := case v_tier when 'champion' then 0.05 when 'elite' then 0.03 else 0.015 end;
      if not v_is_boss and v_enemy.catchable and v_pending_pets < 10 and random() < v_pet_chance then
        v_pet_roll := random() * case v_tier when 'champion' then 0.5 when 'elite' then 0.75 else 1 end;
        v_pet_rarity := case when v_pet_roll < 0.02 then 'legendary' when v_pet_roll < 0.12 then 'epic'
                             when v_pet_roll < 0.40 then 'rare' else 'common' end;
        insert into pet_encounters (character_id, zone_id, species, level, rarity)
        values (p_character_id, p_zone_id, v_enemy.name, v_enemy.level, v_pet_rarity);
        v_pending_pets := v_pending_pets + 1;
        v_fight_pet := v_pet_rarity;
        v_pets_found := v_pets_found || jsonb_build_object(
          'species', v_enemy.name, 'rarity', v_pet_rarity, 'level', v_enemy.level);
      end if;
    end if;

    v_fights := v_fights || jsonb_build_object(
      'turn', v_turn,
      'enemy', v_name,
      'level', v_enemy.level,
      'boss', v_is_boss,
      'tier', v_tier,
      'traits', to_jsonb(v_traits),
      'log', v_fight_log,
      'result', case when v_win then 'win' when v_timed_out then 'flee' else 'lose' end,
      'hp_left', v_hp,
      'dmg_taken', v_dmg_taken,
      'exp', v_fight_exp,
      'gold', v_fight_gold,
      'drops', v_fight_drops,
      'pet', v_fight_pet
    );

    v_turns_completed := v_turn;

    -- Hết HP: dừng, thưởng chỉ tính các trận đã thắng trước đó
    if not v_win and not v_timed_out then
      if not v_buff_guard then
        v_died := true;
        exit;
      end if;
      -- Bùa Hộ Mệnh: đứng dậy với 50% HP, đánh tiếp chuyến
      v_buff_guard := false;
      v_guard_used := true;
      v_hp := greatest(1, round(v_max_hp * 0.5)::int);
      v_fights := jsonb_set(v_fights, array[(jsonb_array_length(v_fights) - 1)::text, 'guard'], 'true'::jsonb);
    end if;

    -- Tự uống bình khi HP dưới 35%
    if v_potions_left > 0 and v_hp < v_max_hp * 0.35 then
      select d.out_hp, d.out_name into v_drink from drink_best_potion(p_character_id, v_hp, v_max_hp) d;
      if v_drink.out_name is not null then
        v_hp := v_drink.out_hp;
        v_potions_left := v_potions_left - 1;
        v_potions_used := v_potions_used + 1;
        v_fights := jsonb_set(v_fights, array[(jsonb_array_length(v_fights) - 1)::text, 'potion'], to_jsonb(v_drink.out_name));
      else
        v_potions_left := 0;
      end if;
    end if;
  end loop;

  v_was_full_ap := (v_current_ap = v_max_ap);
  v_ap_spent := v_zone.ap_cost * ceil(v_turns_completed / 10.0)::int;

  update characters
  set current_hp = greatest(1, v_hp),
      current_ap = current_ap - v_ap_spent,
      gold = gold + v_gold_gained,
      last_ap_update = case when v_was_full_ap then now() else last_ap_update end
  where id = p_character_id;

  if v_exp_gained > 0 then
    select ae.leveled_up, ae.new_level into v_leveled_up, v_new_level
    from add_experience(p_character_id, v_exp_gained) as ae;
  end if;

  -- Phạt khi gục: mất 10% vàng đang cầm và 15% EXP của cấp hiện tại (không tụt cấp)
  if v_died then
    select floor(c.gold * 0.10)::int, least(c.exp, round(c.exp_to_next * 0.15)::int)
      into v_pen_gold, v_pen_exp
    from characters c where c.id = p_character_id;
    update characters c set gold = c.gold - v_pen_gold, exp = c.exp - v_pen_exp where c.id = p_character_id;
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

  -- Bộ đếm thành tích + nhiệm vụ ngày + danh hiệu
  update characters c
  set kills = c.kills + v_wins, boss_kills = c.boss_kills + v_boss_wins
  where c.id = p_character_id;
  perform track_quest(p_character_id, 'kills', v_wins);
  perform track_quest(p_character_id, 'boss', v_boss_wins);
  perform track_quest(p_character_id, 'explore', 1);
  perform award_titles(p_character_id);

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
    'ap_left', v_current_ap - v_ap_spent,
    'ap_spent', v_ap_spent,
    'penalty', jsonb_build_object('gold', v_pen_gold, 'exp', v_pen_exp),
    'drops', v_drops,
    'fights', v_fights,
    'last_fight', v_last_fight,
    'potions_used', v_potions_used,
    'guard_used', v_guard_used,
    'buffs', jsonb_build_object('exp', v_buff_exp, 'luck', v_buff_luck),
    'pets', v_pets_found
  );
end;
$$;


-- Ném lưới vào pet đang chờ. Trả {caught, fled, tries_left, rate, pet}
create or replace function public.throw_net(p_encounter_id uuid, p_net_key text)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_enc pet_encounters%rowtype;
  v_owner uuid;
  v_inv_id uuid; v_qty int; v_tier int;
  v_rate numeric; v_caught boolean; v_fled boolean := false;
  v_pet_id uuid; v_passives jsonb; v_active boolean := false;
begin
  select * into v_enc from pet_encounters pe where pe.id = p_encounter_id for update;
  if not found then raise exception 'Pet này đã bỏ đi'; end if;

  select c.user_id into v_owner from characters c where c.id = v_enc.character_id;
  if v_owner is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  if v_enc.expires_at < now() then
    delete from pet_encounters pe where pe.id = p_encounter_id;
    raise exception 'Pet đã bỏ chạy mất (quá 24 giờ)';
  end if;

  if (select count(*) from character_pets cp where cp.character_id = v_enc.character_id) >= 50 then
    raise exception 'Chuồng pet đã đầy (50) — thả bớt pet trước';
  end if;

  select inv.id, inv.quantity, i.net_tier into v_inv_id, v_qty, v_tier
  from inventory inv join items i on i.id = inv.item_id
  where inv.character_id = v_enc.character_id and i.key = p_net_key and i.net_tier is not null and inv.quantity > 0
  limit 1
  for update of inv;
  if not found then raise exception 'Bạn không còn lưới này — mua thêm ở Chợ'; end if;

  if v_qty <= 1 then
    delete from inventory inv where inv.id = v_inv_id;
  else
    update inventory inv set quantity = inv.quantity - 1 where inv.id = v_inv_id;
  end if;

  v_rate := pet_catch_rate(v_enc.rarity, v_tier);
  v_caught := random() < v_rate;

  if v_caught then
    v_passives := roll_pet_passives(v_enc.rarity);
    -- Chưa mang pet nào thì mang luôn con vừa bắt
    v_active := not exists (select 1 from character_pets cp where cp.character_id = v_enc.character_id and cp.active);
    insert into character_pets (character_id, species, level, rarity, passives, zone_id, active)
    values (v_enc.character_id, v_enc.species, v_enc.level, v_enc.rarity, v_passives, v_enc.zone_id, v_active)
    returning id into v_pet_id;
    delete from pet_encounters pe where pe.id = p_encounter_id;
    if v_enc.rarity = 'legendary' then
      perform post_activity(v_enc.character_id, 'pet_catch', jsonb_build_object('pet', v_enc.species, 'rarity', v_enc.rarity));
    end if;
    return jsonb_build_object(
      'caught', true, 'fled', false, 'tries_left', 0, 'rate', v_rate,
      'pet', jsonb_build_object('id', v_pet_id, 'species', v_enc.species, 'level', v_enc.level,
                                'rarity', v_enc.rarity, 'passives', v_passives, 'active', v_active)
    );
  end if;

  -- Trượt: hết lượt hoặc 30% bỏ chạy
  v_fled := v_enc.tries_left <= 1 or random() < 0.3;
  if v_fled then
    delete from pet_encounters pe where pe.id = p_encounter_id;
  else
    update pet_encounters pe set tries_left = pe.tries_left - 1 where pe.id = p_encounter_id;
  end if;
  return jsonb_build_object(
    'caught', false, 'fled', v_fled,
    'tries_left', case when v_fled then 0 else v_enc.tries_left - 1 end, 'rate', v_rate
  );
end;
$$;

-- Bỏ qua pet đang chờ
create or replace function public.dismiss_pet_encounter(p_encounter_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  delete from pet_encounters pe
  using characters c
  where pe.id = p_encounter_id and c.id = pe.character_id and c.user_id = auth.uid();
end;
$$;

-- Mang pet (p_pet_id null = cất pet đang mang)
create or replace function public.set_active_pet(p_character_id uuid, p_pet_id uuid default null)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not exists (select 1 from characters c where c.id = p_character_id and c.user_id = auth.uid()) then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;
  if p_pet_id is not null and not exists (
    select 1 from character_pets cp where cp.id = p_pet_id and cp.character_id = p_character_id
  ) then
    raise exception 'Không tìm thấy pet';
  end if;

  update character_pets cp set active = false where cp.character_id = p_character_id and cp.active;
  if p_pet_id is not null then
    update character_pets cp set active = true where cp.id = p_pet_id;
  end if;
end;
$$;

-- Thả pet: nhận vàng theo độ hiếm × cấp (không thả được pet đang mang)
create or replace function public.release_pet(p_pet_id uuid)
returns int
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_pet character_pets%rowtype;
  v_gold int;
begin
  select cp.* into v_pet
  from character_pets cp join characters c on c.id = cp.character_id
  where cp.id = p_pet_id and c.user_id = auth.uid()
  for update of cp;
  if not found then raise exception 'Không tìm thấy pet'; end if;
  if v_pet.active then raise exception 'Cất pet trước khi thả'; end if;

  v_gold := (case v_pet.rarity when 'legendary' then 300 when 'epic' then 100 when 'rare' then 30 else 10 end)
            * greatest(1, v_pet.level);
  delete from character_pets cp where cp.id = p_pet_id;
  update characters c set gold = c.gold + v_gold where c.id = v_pet.character_id;
  return v_gold;
end;
$$;

revoke execute on function public.roll_pet_passives(text) from public, anon, authenticated;
revoke execute on function public.throw_net(uuid, text) from public, anon;
grant execute on function public.throw_net(uuid, text) to authenticated;
revoke execute on function public.dismiss_pet_encounter(uuid) from public, anon;
grant execute on function public.dismiss_pet_encounter(uuid) to authenticated;
revoke execute on function public.set_active_pet(uuid, uuid) from public, anon;
grant execute on function public.set_active_pet(uuid, uuid) to authenticated;
revoke execute on function public.release_pet(uuid) from public, anon;
grant execute on function public.release_pet(uuid) to authenticated;
