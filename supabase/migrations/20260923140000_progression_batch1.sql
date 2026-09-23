-- Đợt 1 (tham khảo DautoRPG): rã/ghép nguyên liệu, khóa đồ, cường hóa +1..+5,
-- bộ đếm thành tích + danh hiệu, bảng xếp hạng + lực chiến, nộm tập, nhiệm vụ
-- hằng ngày. Mọi thao tác đi qua RPC security definer (client không ghi thẳng
-- được inventory/characters sau đợt anti-cheat).

-- 1. Cột mới ---------------------------------------------------------------------
-- Level tương ứng của món đồ (≈ level vùng/dungeon rơi ra) → chọn nguyên liệu cường hóa
alter table items add column if not exists item_level int not null default 1;
-- Bậc trong chuỗi nguyên liệu (1 = thấp nhất) + level vùng có nó → rã/ghép, thưởng nhiệm vụ
alter table items add column if not exists material_tier int unique;
alter table items add column if not exists material_level int;

alter table inventory add column if not exists locked boolean not null default false;
alter table inventory add column if not exists enchant_level int not null default 0
  check (enchant_level between 0 and 5);

-- Bộ đếm thành tích (trigger guard_character_game_state dùng danh sách trắng nên
-- client tự động không sửa được các cột này)
alter table characters add column if not exists kills int not null default 0;
alter table characters add column if not exists boss_kills int not null default 0;
alter table characters add column if not exists legendary_found int not null default 0;
alter table characters add column if not exists best_enchant int not null default 0;
alter table characters add column if not exists daily_bonus_count int not null default 0;

-- 2. Chuỗi nguyên liệu --------------------------------------------------------------
update items i set material_tier = m.tier, material_level = m.lvl
from (values
  ('wolf_fang', 1, 1), ('ice_shard', 2, 8), ('sand_scarab', 3, 15), ('swamp_venom', 4, 16),
  ('magma_core', 5, 22), ('shadow_ore', 6, 25), ('shadow_essence', 7, 30), ('void_shard', 8, 35),
  ('holy_relic', 9, 40), ('void_crystal', 10, 52), ('chaos_prism', 11, 62), ('angel_feather', 12, 72)
) as m(key, tier, lvl)
where i.key = m.key;

update items i set item_level = v.lvl
from (values
  ('forest_blade', 6), ('frost_blade', 13), ('cursed_dagger', 22), ('fortress_greatsword', 32), ('voidforged_blade', 45),
  ('desert_turban', 15), ('sandstrider_boots', 15), ('pharaoh_scepter', 26),
  ('obsidian_shield', 22), ('ember_amulet', 22), ('inferno_greataxe', 33),
  ('shadow_cloak', 30), ('bone_ring', 30), ('nightfall_bow', 43),
  ('paladin_helm', 40), ('radiant_belt', 40), ('judgement_staff', 56),
  ('voidwalker_boots', 52), ('star_ring', 52), ('starfall_daggers', 66),
  ('crystal_plate', 62), ('prism_amulet', 62), ('chaos_blade', 76),
  ('seraph_crown', 72), ('celestial_shield', 72), ('genesis_staff', 81)
) as v(key, lvl)
where i.key = v.key;

-- Nguyên liệu bậc cao nhất có level ≤ p_level (null nếu chuỗi chưa có gì)
create or replace function public.material_for_level(p_level int)
returns uuid
language sql
stable
set search_path = 'public'
as $$
  select i.id from items i
  where i.material_tier is not null and i.material_level <= greatest(1, p_level)
  order by i.material_tier desc limit 1;
$$;

-- Thêm p_qty vật phẩm gộp chồng vào túi (nguyên liệu, bình…)
create or replace function public.add_stack(p_character_id uuid, p_item_id uuid, p_qty int)
returns void
language plpgsql
set search_path = 'public'
as $$
declare
  v_inventory_id uuid;
begin
  if p_qty <= 0 or p_item_id is null then return; end if;

  select inv.id into v_inventory_id
  from inventory inv where inv.character_id = p_character_id and inv.item_id = p_item_id
  limit 1 for update;

  if v_inventory_id is null then
    insert into inventory (character_id, item_id, quantity) values (p_character_id, p_item_id, p_qty);
  else
    update inventory set quantity = quantity + p_qty where id = v_inventory_id;
  end if;
end;
$$;

-- Trừ p_qty vật phẩm gộp chồng (có thể nằm rải nhiều dòng). Báo lỗi nếu thiếu.
create or replace function public.take_stack(p_character_id uuid, p_item_id uuid, p_qty int)
returns void
language plpgsql
set search_path = 'public'
as $$
declare
  v_have int;
  v_remaining int := p_qty;
  v_row record;
begin
  if p_qty <= 0 then return; end if;

  select coalesce(sum(inv.quantity), 0) into v_have
  from inventory inv where inv.character_id = p_character_id and inv.item_id = p_item_id and not inv.equipped;

  if v_have < p_qty then
    raise exception 'Không đủ % (cần %, có %)', (select name from items where id = p_item_id), p_qty, v_have;
  end if;

  for v_row in
    select inv.id, inv.quantity from inventory inv
    where inv.character_id = p_character_id and inv.item_id = p_item_id and not inv.equipped
    order by inv.acquired_at
    for update
  loop
    exit when v_remaining <= 0;
    if v_row.quantity <= v_remaining then
      v_remaining := v_remaining - v_row.quantity;
      delete from inventory where id = v_row.id;
    else
      update inventory set quantity = quantity - v_remaining where id = v_row.id;
      v_remaining := 0;
    end if;
  end loop;
end;
$$;

revoke execute on function public.add_stack(uuid, uuid, int) from public, anon, authenticated;
revoke execute on function public.take_stack(uuid, uuid, int) from public, anon, authenticated;

-- 3. Khóa đồ --------------------------------------------------------------------------
create or replace function public.toggle_item_lock(p_character_id uuid, p_inventory_id uuid)
returns boolean
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_locked boolean;
begin
  if (select c.user_id from characters c where c.id = p_character_id) is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  update inventory inv set locked = not inv.locked
  where inv.id = p_inventory_id and inv.character_id = p_character_id
  returning inv.locked into v_locked;

  if not found then raise exception 'Không tìm thấy vật phẩm trong túi đồ'; end if;
  return v_locked;
end;
$$;

-- 4. Rã / Ghép nguyên liệu ------------------------------------------------------------
-- combine: 3 × bậc N → 1 × bậc N+1; break: 1 × bậc N → 3 × bậc N-1.
-- Phí mỗi lần = giá bán của nguyên liệu bậc cao hơn trong cặp → ghép rồi rã
-- vòng lại luôn lỗ, không thể dùng để in vàng. Trả về số lượng nhận được.
create or replace function public.convert_material(p_character_id uuid, p_item_id uuid, p_mode text, p_times int)
returns int
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_tier int; v_target uuid; v_fee int; v_gold int;
  v_times int := greatest(1, coalesce(p_times, 1));
  v_out int;
begin
  select c.gold into v_gold from characters c
  where c.id = p_character_id and c.user_id = auth.uid() for update;
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  select i.material_tier into v_tier from items i where i.id = p_item_id;
  if v_tier is null then raise exception 'Vật phẩm này không rã/ghép được'; end if;

  if p_mode = 'combine' then
    select i.id, i.sell_price into v_target, v_fee from items i where i.material_tier = v_tier + 1;
    if v_target is null then raise exception 'Đây đã là nguyên liệu cao nhất'; end if;
    perform take_stack(p_character_id, p_item_id, 3 * v_times);
    v_out := v_times;
  elsif p_mode = 'break' then
    select i.id into v_target from items i where i.material_tier = v_tier - 1;
    if v_target is null then raise exception 'Đây đã là nguyên liệu thấp nhất'; end if;
    select i.sell_price into v_fee from items i where i.id = p_item_id;
    perform take_stack(p_character_id, p_item_id, v_times);
    v_out := 3 * v_times;
  else
    raise exception 'Chế độ không hợp lệ';
  end if;

  v_fee := v_fee * v_times;
  if v_gold < v_fee then raise exception 'Không đủ vàng (cần % vàng)', v_fee; end if;

  update characters set gold = gold - v_fee where id = p_character_id;
  perform add_stack(p_character_id, v_target, v_out);
  perform track_quest(p_character_id, 'convert', v_times);

  return v_out;
end;
$$;

-- 5. Cường hóa +1..+5 ------------------------------------------------------------------
-- Chi phí bước lên cấp N (1..5): (N+1) × nguyên liệu M hợp level món đồ,
-- bước 4-5 thêm 1-2 × nguyên liệu bậc trên M. Vàng = N × (20 + 5 × item_level).
-- Thành công 100/100/100/80/60%. Thất bại: mất nguyên liệu + vàng, không tụt cấp.
create or replace function public.enchant_cost(p_item_level int, p_next_level int)
returns table(out_mat uuid, out_mat_qty int, out_mat2 uuid, out_mat2_qty int, out_gold int, out_rate numeric)
language sql
stable
set search_path = 'public'
as $$
  select m.id, p_next_level + 1,
         case when p_next_level >= 4 then coalesce(m2.id, m.id) end,
         case when p_next_level >= 4 then p_next_level - 3 else 0 end,
         p_next_level * (20 + 5 * p_item_level),
         (array[1.0, 1.0, 1.0, 0.8, 0.6])[p_next_level]
  from items m
  left join items m2 on m2.material_tier = m.material_tier + 1
  where m.id = material_for_level(p_item_level);
$$;

create or replace function public.enchant_item(p_character_id uuid, p_inventory_id uuid)
returns table(out_success boolean, out_level int, out_gold int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_gold int;
  v_level int; v_rarity text; v_type text; v_item_level int;
  v_bonus_atk int; v_bonus_def int; v_bonus_hp int; v_mult numeric;
  v_next int;
  v_mat uuid; v_mat_qty int; v_mat2 uuid; v_mat2_qty int; v_cost int; v_rate numeric;
  v_success boolean;
begin
  select c.gold into v_gold from characters c
  where c.id = p_character_id and c.user_id = auth.uid() for update;
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  select inv.enchant_level, coalesce(inv.rarity, i.rarity), i.type, i.item_level, i.bonus_atk, i.bonus_def, i.bonus_hp
    into v_level, v_rarity, v_type, v_item_level, v_bonus_atk, v_bonus_def, v_bonus_hp
  from inventory inv join items i on i.id = inv.item_id
  where inv.id = p_inventory_id and inv.character_id = p_character_id
  for update of inv;

  if not found then raise exception 'Không tìm thấy vật phẩm trong túi đồ'; end if;
  if v_type not in ('weapon', 'armor') then raise exception 'Chỉ cường hóa được trang bị'; end if;
  if v_level >= 5 then raise exception 'Đã cường hóa tối đa (+5)'; end if;

  v_next := v_level + 1;
  select ec.out_mat, ec.out_mat_qty, ec.out_mat2, ec.out_mat2_qty, ec.out_gold, ec.out_rate
    into v_mat, v_mat_qty, v_mat2, v_mat2_qty, v_cost, v_rate
  from enchant_cost(v_item_level, v_next) ec;

  if v_gold < v_cost then raise exception 'Không đủ vàng (cần % vàng)', v_cost; end if;

  perform take_stack(p_character_id, v_mat, v_mat_qty);
  if v_mat2 is not null and v_mat2_qty > 0 then
    perform take_stack(p_character_id, v_mat2, v_mat2_qty);
  end if;
  update characters set gold = gold - v_cost where id = p_character_id;

  v_success := random() < v_rate;

  if v_success then
    -- Mỗi cấp +8% chỉ số gốc (đã nhân tier), tối thiểu +1 cho chỉ số món đó có
    v_mult := rarity_multiplier(v_rarity) * 0.08;
    update inventory inv
    set enchant_level = v_next,
        rolled_atk = inv.rolled_atk + case when v_bonus_atk > 0 then greatest(1, round(v_bonus_atk * v_mult))::int else 0 end,
        rolled_def = inv.rolled_def + case when v_bonus_def > 0 then greatest(1, round(v_bonus_def * v_mult))::int else 0 end,
        rolled_hp  = inv.rolled_hp  + case when v_bonus_hp  > 0 then greatest(1, round(v_bonus_hp  * v_mult))::int else 0 end
    where inv.id = p_inventory_id;

    update characters c set best_enchant = greatest(c.best_enchant, v_next) where c.id = p_character_id;
  end if;

  perform track_quest(p_character_id, 'enchant', 1);
  perform award_titles(p_character_id);

  return query select v_success, case when v_success then v_next else v_level end, v_gold - v_cost;
end;
$$;

-- 6. Danh hiệu --------------------------------------------------------------------------
create table if not exists titles (
  key         text primary key,
  name        text not null,
  emoji       text not null,
  description text not null,
  stat        text not null check (stat in ('kills', 'boss_kills', 'level', 'legendary_found', 'best_enchant', 'daily_bonus_count')),
  threshold   int not null,
  sort_order  int not null default 0
);

create table if not exists character_titles (
  character_id uuid not null references characters(id) on delete cascade,
  title_key    text not null references titles(key),
  earned_at    timestamptz not null default now(),
  primary key (character_id, title_key)
);

alter table characters add column if not exists title_key text references titles(key);

alter table titles enable row level security;
alter table character_titles enable row level security;
drop policy if exists "public read titles" on titles;
create policy "public read titles" on titles for select using (true);
drop policy if exists "own character_titles select" on character_titles;
create policy "own character_titles select" on character_titles
  for select using (exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid()));
grant select on table titles to anon, authenticated;
grant select on table character_titles to authenticated;

insert into titles (key, name, emoji, description, stat, threshold, sort_order) values
  ('hunter',        'Thợ Săn',            '🗡️', 'Hạ 100 quái',                 'kills',             100,   1),
  ('slayer',        'Đồ Tể',              '⚔️', 'Hạ 1.000 quái',               'kills',             1000,  2),
  ('exterminator',  'Kẻ Diệt Chủng',      '💀', 'Hạ 10.000 quái',              'kills',             10000, 3),
  ('boss_breaker',  'Kẻ Hạ Boss',         '👑', 'Hạ 1 boss',                   'boss_kills',        1,     4),
  ('boss_hunter',   'Sát Thủ Boss',       '🐉', 'Hạ 25 boss',                  'boss_kills',        25,    5),
  ('boss_bane',     'Khắc Tinh Boss',     '☠️', 'Hạ 100 boss',                 'boss_kills',        100,   6),
  ('veteran',       'Chiến Binh Dày Dạn', '🛡️', 'Đạt cấp 25',                  'level',             25,    7),
  ('hero',          'Anh Hùng',           '🦸', 'Đạt cấp 50',                  'level',             50,    8),
  ('living_legend', 'Huyền Thoại Sống',   '🌟', 'Đạt cấp 80',                  'level',             80,    9),
  ('chosen_one',    'Người Được Chọn',    '✨', 'Nhận 1 món Huyền Thoại',      'legendary_found',   1,     10),
  ('master_smith',  'Thợ Rèn Bậc Thầy',   '🔨', 'Cường hóa thành công lên +5', 'best_enchant',      5,     11),
  ('diligent',      'Chăm Chỉ',           '📜', 'Hoàn thành đủ nhiệm vụ ngày 7 lần', 'daily_bonus_count', 7, 12)
on conflict (key) do nothing;

-- Bảng tin: thêm loại 'title' + chụp danh hiệu đang đeo lúc đăng
alter table activity_feed drop constraint if exists activity_feed_kind_check;
alter table activity_feed add constraint activity_feed_kind_check check (kind in ('boss_kill', 'legendary_item', 'title'));
alter table activity_feed add column if not exists character_title text;

create or replace function public.post_activity(p_character_id uuid, p_kind text, p_payload jsonb)
returns void
language plpgsql
set search_path = 'public'
as $$
begin
  insert into activity_feed (character_id, character_name, character_title, kind, payload)
  select c.id, c.name, t.emoji || ' ' || t.name, p_kind, p_payload
  from characters c left join titles t on t.key = c.title_key
  where c.id = p_character_id;
end;
$$;

-- Trao các danh hiệu vừa đạt (đăng bảng tin). Trả về số danh hiệu mới.
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
             when 'daily_bonus_count' then c.daily_bonus_count
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

create or replace function public.set_title(p_character_id uuid, p_title_key text)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if (select c.user_id from characters c where c.id = p_character_id) is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  if p_title_key is not null and not exists (
    select 1 from character_titles ct where ct.character_id = p_character_id and ct.title_key = p_title_key
  ) then
    raise exception 'Chưa mở khóa danh hiệu này';
  end if;

  update characters set title_key = p_title_key where id = p_character_id;
end;
$$;

-- 7. Lực chiến + Bảng xếp hạng -------------------------------------------------------------
create or replace function public.character_power(p_character_id uuid)
returns int
language sql
stable
set search_path = 'public'
as $$
  select round(gs.atk * 2 + gs.def * 1.5 + gs.max_hp * 0.25
               + (gs.crit_bonus + gs.lifesteal_bonus) * 400
               + coalesce(array_length(get_character_effects(p_character_id), 1), 0) * 60)::int
  from get_character_stats(p_character_id) gs;
$$;

-- Top 50 theo p_sort ('level' | 'power' | 'boss_kills'). security definer vì RLS
-- chỉ cho đọc nhân vật của mình — chỉ trả các cột công khai.
create or replace function public.get_leaderboard(p_sort text)
returns table(
  out_rank int, out_character_id uuid, out_name text, out_class_key text, out_class_name text,
  out_level int, out_power int, out_boss_kills int, out_kills int, out_title text
)
language sql
stable
security definer
set search_path = 'public'
as $$
  with base as (
    select c.id, c.name, cl.key as class_key, cl.name as class_name, c.level, c.exp,
           character_power(c.id) as power, c.boss_kills, c.kills,
           t.emoji || ' ' || t.name as title
    from characters c
    join classes cl on cl.id = c.class_id
    left join titles t on t.key = c.title_key
  )
  select (row_number() over (order by
            case p_sort when 'power' then b.power when 'boss_kills' then b.boss_kills else b.level end desc,
            case p_sort when 'level' then b.exp else b.level end desc,
            b.name))::int,
         b.id, b.name, b.class_key, b.class_name, b.level, b.power, b.boss_kills, b.kills, b.title
  from base b
  order by 1
  limit 50;
$$;

-- 8. Nộm tập -----------------------------------------------------------------------------------
-- 30 lượt đánh vào nộm máu vô hạn, không tốn AP/HP, không đổi gì trong DB.
-- p_armored: nộm bọc giáp có DEF như quái cùng cấp ×1.3.
create or replace function public.training_dummy(p_character_id uuid, p_armored boolean)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_level int;
  v_atk int; v_crit numeric; v_lifesteal numeric;
  v_a1_name text; v_a1_power numeric; v_a2_name text; v_a2_power numeric;
  v_dmg_reduction numeric; v_skill_lifesteal numeric; v_skill_crit numeric;
  v_effects text[];
  v_def int;
  v_log jsonb;
  v_hits jsonb;
begin
  select c.level into v_level from characters c where c.id = p_character_id and c.user_id = auth.uid();
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  select gs.atk, gs.crit_bonus, gs.lifesteal_bonus into v_atk, v_crit, v_lifesteal
  from get_character_stats(p_character_id) gs;

  select cs.out_a1_name, cs.out_a1_power, cs.out_a2_name, cs.out_a2_power,
         cs.out_dmg_reduction, cs.out_lifesteal, cs.out_crit
    into v_a1_name, v_a1_power, v_a2_name, v_a2_power,
         v_dmg_reduction, v_skill_lifesteal, v_skill_crit
  from get_combat_skills(p_character_id) cs;

  v_effects := get_character_effects(p_character_id);
  v_def := case when p_armored then round(0.8 * v_level * 1.3)::int else 0 end;

  select f.out_log into v_log
  from simulate_fight(
    v_atk, 0, 1000000000, 1000000000,
    least(0.75, v_crit + v_skill_crit), 0, 0,
    v_a1_name, v_a1_power, v_a2_name, v_a2_power,
    'Nộm Tập', 2000000000, 0, v_def,
    1, true, v_effects
  ) f;

  select coalesce(jsonb_agg(e), '[]'::jsonb) into v_hits
  from jsonb_array_elements(v_log) e where e->>'actor' = 'character';

  return jsonb_build_object(
    'turns', 30,
    'dummy_def', v_def,
    'total', (select coalesce(sum((e->>'damage')::int), 0) from jsonb_array_elements(v_hits) e),
    'hits', jsonb_array_length(v_hits),
    'max_hit', (select coalesce(max((e->>'damage')::int), 0) from jsonb_array_elements(v_hits) e),
    'crits', (select count(*) from jsonb_array_elements(v_hits) e where (e->>'crit')::boolean),
    'doubles', (select count(*) from jsonb_array_elements(v_hits) e where (e->>'double')::boolean),
    'atk', v_atk,
    'crit_chance', least(0.75, v_crit + v_skill_crit),
    'effects', to_jsonb(v_effects),
    'log', v_hits
  );
end;
$$;

-- 9. Nhiệm vụ hằng ngày -----------------------------------------------------------------------
-- 3 nhiệm vụ khác loại mỗi ngày (theo giờ Việt Nam), tạo lười khi cần.
create table if not exists daily_quests (
  character_id  uuid not null references characters(id) on delete cascade,
  quest_date    date not null,
  quests        jsonb not null,           -- [{type, target, label, progress, claimed}]
  bonus_claimed boolean not null default false,
  primary key (character_id, quest_date)
);

alter table daily_quests enable row level security;
drop policy if exists "own daily_quests select" on daily_quests;
create policy "own daily_quests select" on daily_quests
  for select using (exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid()));
grant select on table daily_quests to authenticated;

create or replace function public.vn_today()
returns date
language sql
stable
as $$ select (now() at time zone 'Asia/Ho_Chi_Minh')::date; $$;

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
        ('dungeon', 1, 'Thắng 1 tầng dungeon'), ('dungeon', 3, 'Thắng 3 tầng dungeon'),
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

create or replace function public.track_quest(p_character_id uuid, p_type text, p_amount int)
returns void
language plpgsql
set search_path = 'public'
as $$
begin
  if coalesce(p_amount, 0) <= 0 then return; end if;
  perform ensure_daily_quests(p_character_id);

  update daily_quests dq
  set quests = (
    select jsonb_agg(case when q->>'type' = p_type
                          then jsonb_set(q, '{progress}', to_jsonb(least((q->>'target')::int, (q->>'progress')::int + p_amount)))
                          else q end order by ord)
    from jsonb_array_elements(dq.quests) with ordinality as a(q, ord)
  )
  where dq.character_id = p_character_id and dq.quest_date = vn_today();
end;
$$;

revoke execute on function public.ensure_daily_quests(uuid) from public, anon, authenticated;
revoke execute on function public.track_quest(uuid, text, int) from public, anon, authenticated;
revoke execute on function public.award_titles(uuid) from public, anon, authenticated;

-- Thưởng 1 nhiệm vụ theo level: vàng 40 + 8×level, 2-4 nguyên liệu hợp level
create or replace function public.get_daily_quests(p_character_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_level int;
  v_row daily_quests%rowtype;
begin
  select c.level into v_level from characters c where c.id = p_character_id and c.user_id = auth.uid();
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  perform ensure_daily_quests(p_character_id);
  select * into v_row from daily_quests dq where dq.character_id = p_character_id and dq.quest_date = vn_today();

  return jsonb_build_object(
    'date', v_row.quest_date,
    'quests', v_row.quests,
    'bonus_claimed', v_row.bonus_claimed,
    'reward_gold', 40 + 8 * v_level,
    'reward_material', (select jsonb_build_object('key', i.key, 'name', i.name, 'icon', i.icon)
                        from items i where i.id = material_for_level(v_level)),
    'bonus_gold', 100 + 10 * v_level,
    'bonus_item', (select jsonb_build_object('key', i.key, 'name', i.name, 'icon', i.icon)
                   from items i where i.key = 'potion_ap_large')
  );
end;
$$;

create or replace function public.claim_daily_quest(p_character_id uuid, p_index int)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_level int;
  v_quests jsonb;
  v_q jsonb;
begin
  select c.level into v_level from characters c
  where c.id = p_character_id and c.user_id = auth.uid() for update;
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  select dq.quests into v_quests from daily_quests dq
  where dq.character_id = p_character_id and dq.quest_date = vn_today() for update;

  v_q := v_quests -> p_index;
  if v_q is null then raise exception 'Không tìm thấy nhiệm vụ'; end if;
  if (v_q->>'claimed')::boolean then raise exception 'Đã nhận thưởng nhiệm vụ này'; end if;
  if (v_q->>'progress')::int < (v_q->>'target')::int then raise exception 'Chưa hoàn thành nhiệm vụ'; end if;

  update daily_quests dq set quests = jsonb_set(dq.quests, array[p_index::text, 'claimed'], 'true'::jsonb)
  where dq.character_id = p_character_id and dq.quest_date = vn_today();

  update characters set gold = gold + 40 + 8 * v_level where id = p_character_id;
  perform add_stack(p_character_id, material_for_level(v_level), 2 + floor(random() * 3)::int);
end;
$$;

create or replace function public.claim_daily_bonus(p_character_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_level int;
  v_row daily_quests%rowtype;
begin
  select c.level into v_level from characters c
  where c.id = p_character_id and c.user_id = auth.uid() for update;
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  select * into v_row from daily_quests dq
  where dq.character_id = p_character_id and dq.quest_date = vn_today() for update;

  if v_row.bonus_claimed then raise exception 'Đã nhận quà hoàn thành hôm nay'; end if;
  if exists (select 1 from jsonb_array_elements(v_row.quests) q where not (q->>'claimed')::boolean) then
    raise exception 'Cần nhận thưởng đủ 3 nhiệm vụ trước';
  end if;

  update daily_quests dq set bonus_claimed = true
  where dq.character_id = p_character_id and dq.quest_date = vn_today();

  update characters c
  set gold = c.gold + 100 + 10 * v_level, daily_bonus_count = c.daily_bonus_count + 1
  where c.id = p_character_id;

  perform add_stack(p_character_id, (select i.id from items i where i.key = 'potion_ap_large'), 1);
  perform award_titles(p_character_id);
end;
$$;

-- 10. Gắn bộ đếm / nhiệm vụ / danh hiệu vào các hàm có sẵn ---------------------------------
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

  -- Đồ Huyền Thoại (rơi hoặc chế tạo) lên bảng tin + đếm cho danh hiệu
  if p_rarity = 'legendary' then
    update characters c set legendary_found = c.legendary_found + 1 where c.id = p_character_id;
    select i.name, i.key, i.icon into v_item_name, v_item_key, v_item_icon from items i where i.id = p_item_id;
    perform post_activity(p_character_id, 'legendary_item', jsonb_build_object(
      'item', v_item_name, 'item_key', v_item_key, 'icon', v_item_icon, 'effect', v_effect
    ));
    perform award_titles(p_character_id);
  end if;
end;
$$;


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
    and not inv.equipped
    and not inv.locked;

  if v_sold < v_requested then
    raise exception 'Có món không bán được (đang mặc, đã khóa 🔒 hoặc không còn trong túi) — hãy tải lại trang';
  end if;

  delete from inventory inv
  where inv.id = any(p_inventory_ids) and inv.character_id = p_character_id and not inv.equipped and not inv.locked;

  update characters c set gold = c.gold + v_gained where c.id = p_character_id;

  return query select v_sold, v_gained, v_gold + v_gained;
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

    -- Bộ đếm thành tích + nhiệm vụ ngày
    update characters c
    set kills = c.kills + 1, boss_kills = c.boss_kills + case when v_is_boss_floor then 1 else 0 end
    where c.id = p_character_id;
    perform track_quest(p_character_id, 'kills', 1);
    perform track_quest(p_character_id, 'dungeon', 1);
    if v_is_boss_floor then perform track_quest(p_character_id, 'boss', 1); end if;

    if v_is_boss_floor then
      perform post_activity(p_character_id, 'boss_kill', jsonb_build_object(
        'boss', v_enemy_name, 'where', (select d.name from dungeons d where d.id = v_dungeon_id), 'source', 'dungeon'
      ));
    end if;

    perform award_titles(p_character_id);
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
      if v_is_boss then v_boss_wins := v_boss_wins + 1; end if;

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
    'ap_left', v_current_ap - v_zone.ap_cost,
    'drops', v_drops,
    'fights', v_fights,
    'last_fight', v_last_fight
  );
end;
$$;


-- 11. Bù dữ liệu cho người chơi hiện có (không đăng bảng tin) ----------------------------
update characters c set boss_kills = f.n
from (select character_id, count(*)::int n from activity_feed where kind = 'boss_kill' and character_id is not null group by 1) f
where f.character_id = c.id;

update characters c set legendary_found = l.n
from (select character_id, count(*)::int n from inventory where rarity = 'legendary' group by 1) l
where l.character_id = c.id;

insert into character_titles (character_id, title_key)
select c.id, t.key
from characters c cross join titles t
where (case t.stat
         when 'kills' then c.kills when 'boss_kills' then c.boss_kills when 'level' then c.level
         when 'legendary_found' then c.legendary_found when 'best_enchant' then c.best_enchant
         when 'daily_bonus_count' then c.daily_bonus_count
       end) >= t.threshold
on conflict do nothing;
