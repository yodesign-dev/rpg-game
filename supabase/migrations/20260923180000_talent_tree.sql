-- Cây Thiên Phú (passive tree) hình sao, dùng chung mọi class, xuất phát từ tâm.
--
-- 6 nhánh (Sinh Lực, Cuồng Chiến, Chí Mạng, Huyết, Tốc Chiến, Thép), mỗi nhánh
-- 4 ô nhỏ + 1 ô lớn + 1 ô trùm (đánh đổi), cộng 6 ô cầu nối giữa các nhánh →
-- 43 ô, tổng chi phí 60 điểm (nhỏ 1, lớn 2, trùm 3). Chỉ học được ô kề ô đã
-- học. Điểm: 1 mỗi 2 cấp + 1 mỗi tầng boss Tháp đã qua (tối đa ~50) → không
-- học hết được, phải chọn build.
--
-- Hiệu ứng (talent_nodes.effects, cộng dồn giữa các ô):
--   hp_pct/atk_pct/def_pct  nhân vào chỉ số GỐC (class + cấp + điểm chỉ số),
--                           không nhân trang bị → số ở UI và trong trận luôn khớp
--   crit, lifesteal         cộng vào chí mạng / hút máu tổng
--   dmg_red                 cộng vào giảm sát thương (cùng skill bị động, tối đa 60%)
--   double                  cộng vào tỉ lệ Đòn Kép (cùng hiệu ứng Huyền Thoại, tối đa 50%)
--   crit_mult, opening, low_hp_ls  lấy giá trị lớn nhất (hệ số chí mạng, hệ số
--                           đòn đầu, hệ số hút máu khi HP < 30%)

-- 1. Dữ liệu cây -------------------------------------------------------------------
create table if not exists talent_nodes (
  key         text primary key,
  name        text not null,
  icon        text not null,
  branch      text not null,
  kind        text not null check (kind in ('start', 'small', 'notable', 'keystone')),
  cost        int not null,
  x           numeric not null,     -- toạ độ SVG, tâm (0,0)
  y           numeric not null,
  effects     jsonb not null default '{}'::jsonb,
  description text not null
);

create table if not exists talent_edges (
  a text not null references talent_nodes(key) on delete cascade,
  b text not null references talent_nodes(key) on delete cascade,
  primary key (a, b)
);

create table if not exists character_talents (
  character_id uuid not null references characters(id) on delete cascade,
  node_key     text not null references talent_nodes(key),
  learned_at   timestamptz not null default now(),
  primary key (character_id, node_key)
);

alter table talent_nodes enable row level security;
alter table talent_edges enable row level security;
alter table character_talents enable row level security;
drop policy if exists "public read talent_nodes" on talent_nodes;
create policy "public read talent_nodes" on talent_nodes for select using (true);
drop policy if exists "public read talent_edges" on talent_edges;
create policy "public read talent_edges" on talent_edges for select using (true);
drop policy if exists "own character_talents select" on character_talents;
create policy "own character_talents select" on character_talents
  for select using (exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid()));
grant select on table talent_nodes, talent_edges to anon, authenticated;
grant select on table character_talents to authenticated;

-- Các ô (toạ độ tính sẵn theo vòng tròn) và đường nối
insert into talent_nodes (key, name, icon, branch, kind, cost, x, y, effects, description) values
  ('origin', 'Khởi Nguyên', '✦', 'origin', 'start', 0, 0, 0, '{}'::jsonb, 'Điểm xuất phát'),
  ('hp_1', 'Sinh Lực', '❤️', 'hp', 'small', 1, 0.0, -17.0, '{"hp_pct": 0.04}'::jsonb, '+4% HP tối đa'),
  ('hp_2', 'Sinh Lực II', '❤️', 'hp', 'small', 1, 0.0, -34.0, '{"hp_pct": 0.04}'::jsonb, '+4% HP tối đa'),
  ('hp_n', 'Sinh Lực Dồi Dào', '❤️', 'hp', 'notable', 2, 0.0, -51.0, '{"hp_pct": 0.08, "def_pct": 0.03}'::jsonb, '+8% HP, +3% DEF'),
  ('hp_side', 'Da Thịt Rắn Chắc', '❤️', 'hp', 'small', 1, 19.8, -54.3, '{"hp_pct": 0.05}'::jsonb, '+5% HP'),
  ('hp_3', 'Sinh Lực III', '❤️', 'hp', 'small', 1, -7.1, -67.6, '{"hp_pct": 0.04}'::jsonb, '+4% HP tối đa'),
  ('hp_k', 'Thành Trì Sống', '❤️', 'hp', 'keystone', 3, 0.0, -86.7, '{"hp_pct": 0.25, "atk_pct": -0.1}'::jsonb, '+25% HP tối đa, −10% ATK'),
  ('atk_1', 'Sức Mạnh', '⚔️', 'atk', 'small', 1, 14.7, -8.5, '{"atk_pct": 0.03}'::jsonb, '+3% ATK'),
  ('atk_2', 'Sức Mạnh II', '⚔️', 'atk', 'small', 1, 29.4, -17.0, '{"atk_pct": 0.03}'::jsonb, '+3% ATK'),
  ('atk_n', 'Khát Chiến', '⚔️', 'atk', 'notable', 2, 44.2, -25.5, '{"atk_pct": 0.06, "crit": 0.02}'::jsonb, '+6% ATK, +2% chí mạng'),
  ('atk_side', 'Đồ Tể', '⚔️', 'atk', 'small', 1, 56.9, -10.0, '{"atk_pct": 0.04}'::jsonb, '+4% ATK'),
  ('atk_3', 'Sức Mạnh III', '⚔️', 'atk', 'small', 1, 55.0, -40.0, '{"atk_pct": 0.03}'::jsonb, '+3% ATK'),
  ('atk_k', 'Cuồng Nộ Vô Độ', '⚔️', 'atk', 'keystone', 3, 75.1, -43.4, '{"atk_pct": 0.3, "def_pct": -0.2}'::jsonb, '+30% ATK, −20% DEF'),
  ('crit_1', 'Nhãn Lực', '🎯', 'crit', 'small', 1, 14.7, 8.5, '{"crit": 0.015}'::jsonb, '+1.5% chí mạng'),
  ('crit_2', 'Nhãn Lực II', '🎯', 'crit', 'small', 1, 29.4, 17.0, '{"crit": 0.015}'::jsonb, '+1.5% chí mạng'),
  ('crit_n', 'Điểm Yếu', '🎯', 'crit', 'notable', 2, 44.2, 25.5, '{"crit": 0.03, "atk_pct": 0.02}'::jsonb, '+3% chí mạng, +2% ATK'),
  ('crit_side', 'Tâm Nhãn', '🎯', 'crit', 'small', 1, 37.2, 44.3, '{"crit": 0.02}'::jsonb, '+2% chí mạng'),
  ('crit_3', 'Nhãn Lực III', '🎯', 'crit', 'small', 1, 62.1, 27.7, '{"crit": 0.015}'::jsonb, '+1.5% chí mạng'),
  ('crit_k', 'Mắt Tử Thần', '🎯', 'crit', 'keystone', 3, 75.1, 43.3, '{"crit_mult": 2.2, "hp_pct": -0.1}'::jsonb, 'Chí mạng gây ×2.2 (thay ×1.5), −10% HP'),
  ('ls_1', 'Huyết Mạch', '🩸', 'ls', 'small', 1, 0.0, 17.0, '{"lifesteal": 0.01}'::jsonb, '+1% hút máu'),
  ('ls_2', 'Huyết Mạch II', '🩸', 'ls', 'small', 1, 0.0, 34.0, '{"lifesteal": 0.01}'::jsonb, '+1% hút máu'),
  ('ls_n', 'Hiến Tế Huyết Ma', '🩸', 'ls', 'notable', 2, 0.0, 51.0, '{"lifesteal": 0.02, "hp_pct": 0.03}'::jsonb, '+2% hút máu, +3% HP'),
  ('ls_side', 'Huyết Khí', '🩸', 'ls', 'small', 1, -19.8, 54.3, '{"lifesteal": 0.015}'::jsonb, '+1.5% hút máu'),
  ('ls_3', 'Huyết Mạch III', '🩸', 'ls', 'small', 1, 7.1, 67.6, '{"lifesteal": 0.01}'::jsonb, '+1% hút máu'),
  ('ls_k', 'Khát Máu Vô Tận', '🩸', 'ls', 'keystone', 3, 0.0, 86.7, '{"lifesteal": 0.03, "low_hp_ls": 2, "def_pct": -0.1}'::jsonb, '+3% hút máu; HP dưới 30% thì hút máu ×2; −10% DEF'),
  ('spd_1', 'Nhanh Nhẹn', '⚡', 'spd', 'small', 1, -14.7, 8.5, '{"double": 0.02}'::jsonb, '+2% Đòn Kép'),
  ('spd_2', 'Nhanh Nhẹn II', '⚡', 'spd', 'small', 1, -29.4, 17.0, '{"double": 0.02}'::jsonb, '+2% Đòn Kép'),
  ('spd_n', 'Khai Cuộc Thần Tốc', '⚡', 'spd', 'notable', 2, -44.2, 25.5, '{"opening": 1.5, "double": 0.02}'::jsonb, 'Đòn đầu mỗi trận ×1.5, +2% Đòn Kép'),
  ('spd_side', 'Lướt Gió', '⚡', 'spd', 'small', 1, -56.9, 10.0, '{"double": 0.02}'::jsonb, '+2% Đòn Kép'),
  ('spd_3', 'Nhanh Nhẹn III', '⚡', 'spd', 'small', 1, -55.0, 40.0, '{"double": 0.02}'::jsonb, '+2% Đòn Kép'),
  ('spd_k', 'Lưỡi Dao Thủy Tinh', '⚡', 'spd', 'keystone', 3, -75.1, 43.4, '{"double": 0.12, "opening": 2.0, "hp_pct": -0.15}'::jsonb, '+12% Đòn Kép, đòn đầu ×2, −15% HP'),
  ('def_1', 'Giáp Trụ', '🛡️', 'def', 'small', 1, -14.7, -8.5, '{"def_pct": 0.04}'::jsonb, '+4% DEF'),
  ('def_2', 'Giáp Trụ II', '🛡️', 'def', 'small', 1, -29.4, -17.0, '{"def_pct": 0.04}'::jsonb, '+4% DEF'),
  ('def_n', 'Lũy Thép', '🛡️', 'def', 'notable', 2, -44.2, -25.5, '{"def_pct": 0.08, "dmg_red": 0.03}'::jsonb, '+8% DEF, giảm 3% sát thương nhận'),
  ('def_side', 'Bất Khả Xâm', '🛡️', 'def', 'small', 1, -37.2, -44.3, '{"def_pct": 0.05}'::jsonb, '+5% DEF'),
  ('def_3', 'Giáp Trụ III', '🛡️', 'def', 'small', 1, -62.1, -27.7, '{"def_pct": 0.04}'::jsonb, '+4% DEF'),
  ('def_k', 'Pháo Đài Bất Động', '🛡️', 'def', 'keystone', 3, -75.1, -43.4, '{"dmg_red": 0.15, "atk_pct": -0.15}'::jsonb, 'Giảm 15% sát thương nhận, −15% ATK'),
  ('bridge_hp_atk', 'Chiến Binh Bền Bỉ', '💠', 'bridge', 'small', 1, 19.5, -33.9, '{"hp_pct": 0.02, "atk_pct": 0.02}'::jsonb, '+2% HP, +2% ATK'),
  ('bridge_atk_crit', 'Sát Khí', '💠', 'bridge', 'small', 1, 39.1, -0.0, '{"atk_pct": 0.02, "crit": 0.01}'::jsonb, '+2% ATK, +1% chí mạng'),
  ('bridge_crit_ls', 'Vết Cắt Sâu', '💠', 'bridge', 'small', 1, 19.5, 33.9, '{"crit": 0.01, "lifesteal": 0.005}'::jsonb, '+1% chí mạng, +0.5% hút máu'),
  ('bridge_ls_spd', 'Huyết Tốc', '💠', 'bridge', 'small', 1, -19.6, 33.9, '{"lifesteal": 0.005, "double": 0.01}'::jsonb, '+0.5% hút máu, +1% Đòn Kép'),
  ('bridge_spd_def', 'Linh Hoạt', '💠', 'bridge', 'small', 1, -39.1, 0.0, '{"double": 0.01, "def_pct": 0.02}'::jsonb, '+1% Đòn Kép, +2% DEF'),
  ('bridge_def_hp', 'Hộ Thân', '💠', 'bridge', 'small', 1, -19.6, -33.9, '{"def_pct": 0.02, "hp_pct": 0.02}'::jsonb, '+2% DEF, +2% HP')
on conflict (key) do nothing;

insert into talent_edges (a, b) values
  ('origin', 'hp_1'),
  ('hp_1', 'hp_2'),
  ('hp_2', 'hp_n'),
  ('hp_n', 'hp_side'),
  ('hp_n', 'hp_3'),
  ('hp_3', 'hp_k'),
  ('origin', 'atk_1'),
  ('atk_1', 'atk_2'),
  ('atk_2', 'atk_n'),
  ('atk_n', 'atk_side'),
  ('atk_n', 'atk_3'),
  ('atk_3', 'atk_k'),
  ('origin', 'crit_1'),
  ('crit_1', 'crit_2'),
  ('crit_2', 'crit_n'),
  ('crit_n', 'crit_side'),
  ('crit_n', 'crit_3'),
  ('crit_3', 'crit_k'),
  ('origin', 'ls_1'),
  ('ls_1', 'ls_2'),
  ('ls_2', 'ls_n'),
  ('ls_n', 'ls_side'),
  ('ls_n', 'ls_3'),
  ('ls_3', 'ls_k'),
  ('origin', 'spd_1'),
  ('spd_1', 'spd_2'),
  ('spd_2', 'spd_n'),
  ('spd_n', 'spd_side'),
  ('spd_n', 'spd_3'),
  ('spd_3', 'spd_k'),
  ('origin', 'def_1'),
  ('def_1', 'def_2'),
  ('def_2', 'def_n'),
  ('def_n', 'def_side'),
  ('def_n', 'def_3'),
  ('def_3', 'def_k'),
  ('hp_2', 'bridge_hp_atk'),
  ('bridge_hp_atk', 'atk_2'),
  ('atk_2', 'bridge_atk_crit'),
  ('bridge_atk_crit', 'crit_2'),
  ('crit_2', 'bridge_crit_ls'),
  ('bridge_crit_ls', 'ls_2'),
  ('ls_2', 'bridge_ls_spd'),
  ('bridge_ls_spd', 'spd_2'),
  ('spd_2', 'bridge_spd_def'),
  ('bridge_spd_def', 'def_2'),
  ('def_2', 'bridge_def_hp'),
  ('bridge_def_hp', 'hp_2')
on conflict do nothing;

-- 2. Tính điểm + tổng hiệu ứng -------------------------------------------------------
create or replace function public.talent_points_total(p_level int, p_tower_best int)
returns int
language sql
immutable
as $$ select (greatest(1, p_level) / 2) + (least(100, greatest(0, p_tower_best)) / 10); $$;

-- plpgsql (không phải sql) để get_character_stats tạo trước bảng cây vẫn được
create or replace function public.get_talent_totals(p_character_id uuid)
returns jsonb
language plpgsql
stable
set search_path = 'public'
as $$
declare
  v jsonb;
begin
  select coalesce(jsonb_object_agg(s.k, s.val), '{}'::jsonb) into v
  from (
    select e.key as k,
           case when e.key in ('crit_mult', 'opening', 'low_hp_ls')
                then max(e.value::text::numeric) else sum(e.value::text::numeric) end as val
    from character_talents ct
    join talent_nodes n on n.key = ct.node_key
    cross join lateral jsonb_each(n.effects) e
    where ct.character_id = p_character_id
    group by e.key
  ) s;
  return v;
end;
$$;

create or replace function public.get_talent_state(p_character_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_level int; v_tower int; v_total int; v_spent int;
begin
  select c.level, c.tower_best into v_level, v_tower
  from characters c where c.id = p_character_id and c.user_id = auth.uid();
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  v_total := talent_points_total(v_level, v_tower);
  select coalesce(sum(n.cost), 0) into v_spent
  from character_talents ct join talent_nodes n on n.key = ct.node_key where ct.character_id = p_character_id;

  return jsonb_build_object(
    'total', v_total, 'spent', v_spent, 'available', v_total - v_spent,
    'learned', (select coalesce(jsonb_agg(ct.node_key), '[]'::jsonb) from character_talents ct where ct.character_id = p_character_id),
    'totals', get_talent_totals(p_character_id),
    'reset_cost', 30 * v_level
  );
end;
$$;

create or replace function public.learn_talent(p_character_id uuid, p_node_key text)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_level int; v_tower int; v_cost int; v_kind text; v_spent int;
begin
  select c.level, c.tower_best into v_level, v_tower
  from characters c where c.id = p_character_id and c.user_id = auth.uid() for update;
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  select n.cost, n.kind into v_cost, v_kind from talent_nodes n where n.key = p_node_key;
  if not found or v_kind = 'start' then raise exception 'Không tìm thấy ô thiên phú này'; end if;

  if exists (select 1 from character_talents ct where ct.character_id = p_character_id and ct.node_key = p_node_key) then
    raise exception 'Đã học ô này rồi';
  end if;

  -- Phải kề ô đã học (hoặc kề tâm)
  if not exists (
    select 1 from talent_edges e
    where (e.a = p_node_key or e.b = p_node_key)
      and (case when e.a = p_node_key then e.b else e.a end) in (
        select 'origin' union all
        select ct.node_key from character_talents ct where ct.character_id = p_character_id)
  ) then
    raise exception 'Phải học ô liền kề trước';
  end if;

  select coalesce(sum(n.cost), 0) into v_spent
  from character_talents ct join talent_nodes n on n.key = ct.node_key where ct.character_id = p_character_id;
  if talent_points_total(v_level, v_tower) - v_spent < v_cost then
    raise exception 'Không đủ điểm thiên phú (cần % điểm)', v_cost;
  end if;

  insert into character_talents (character_id, node_key) values (p_character_id, p_node_key);
  return get_talent_state(p_character_id);
end;
$$;

-- Tẩy toàn bộ cây: 30 × cấp vàng. HP hiện tại bị kẹp lại nếu vượt HP tối đa mới.
create or replace function public.reset_talents(p_character_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_level int; v_gold int; v_cost int; v_max_hp int;
begin
  select c.level, c.gold into v_level, v_gold
  from characters c where c.id = p_character_id and c.user_id = auth.uid() for update;
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  if not exists (select 1 from character_talents ct where ct.character_id = p_character_id) then
    raise exception 'Chưa học ô thiên phú nào';
  end if;

  v_cost := 30 * v_level;
  if v_gold < v_cost then raise exception 'Không đủ vàng (cần % vàng)', v_cost; end if;

  delete from character_talents where character_id = p_character_id;
  update characters set gold = gold - v_cost where id = p_character_id;

  select gs.max_hp into v_max_hp from get_character_stats(p_character_id) gs;
  update characters set current_hp = least(current_hp, v_max_hp)
  where id = p_character_id and current_hp is not null;

  return get_talent_state(p_character_id);
end;
$$;

-- 3. Áp thiên phú vào chỉ số + combat ------------------------------------------------
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
    -- Thiên phú: % nhân vào chỉ số gốc (không nhân trang bị), chí mạng/hút máu cộng thẳng
    select
      round((cl.base_hp + (ch.level - 1) * cl.hp_per_level + ab.attr_hp)
            * greatest(0.1, 1 + coalesce((t.j->>'hp_pct')::numeric, 0)))::int as base_max_hp,
      round((cl.base_atk + (ch.level - 1) * cl.atk_per_level + ab.attr_atk)
            * greatest(0.1, 1 + coalesce((t.j->>'atk_pct')::numeric, 0)))::int as base_atk,
      round((cl.base_def + (ch.level - 1) * cl.def_per_level + ab.attr_def)
            * greatest(0.1, 1 + coalesce((t.j->>'def_pct')::numeric, 0)))::int as base_def,
      cl.base_spd + (ch.level - 1) * cl.spd_per_level as base_spd,
      ab.attr_crit,
      coalesce((t.j->>'crit')::numeric, 0) as talent_crit,
      coalesce((t.j->>'lifesteal')::numeric, 0) as talent_lifesteal
    from characters ch
    join classes cl on cl.id = ch.class_id
    cross join lateral attribute_bonuses(
      cl.main_stat, ch.stat_str, ch.stat_int, ch.stat_agi, ch.stat_dex, ch.stat_vit
    ) ab
    cross join lateral (select get_talent_totals(ch.id) as j) t
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
    -- skill bị động + thiên phú, tối đa 60%
    least(0.6, case when v_passive_type = 'damage_reduction' then v_passive_value else 0 end
               + coalesce((get_talent_totals(p_character_id)->>'dmg_red')::numeric, 0)),
    case when v_passive_type = 'lifesteal' then v_passive_value else 0 end,
    case when v_passive_type = 'crit_chance' then v_passive_value else 0 end;
end;
$$;


-- simulate_fight thêm p_mods → drop bản cũ (18 tham số) trước
drop function if exists public.simulate_fight(int, int, int, int, numeric, numeric, numeric, text, numeric, text, numeric, text, int, int, int, numeric, boolean, text[]);

create or replace function public.simulate_fight(
  p_char_atk int, p_char_def int, p_char_hp int, p_max_hp int,
  p_crit numeric, p_lifesteal numeric, p_dmg_reduction numeric,
  p_a1_name text, p_a1_power numeric, p_a2_name text, p_a2_power numeric,
  p_enemy_name text, p_enemy_hp int, p_enemy_atk int, p_enemy_def int,
  p_damage_multiplier numeric, p_with_log boolean,
  p_effects text[] default '{}',
  p_mods jsonb default '{}'       -- tổng thiên phú (get_talent_totals)
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
  -- Hiệu ứng Huyền Thoại (đã distinct ở get_character_effects) + thiên phú (p_mods)
  v_double_chance numeric := least(0.5,
    case when 'double_strike' = any(p_effects) then 0.15 else 0 end + coalesce((p_mods->>'double')::numeric, 0));
  v_crit_mult numeric := greatest(case when 'deadly_crit' = any(p_effects) then 2.0 else 1.5 end,
                                  coalesce((p_mods->>'crit_mult')::numeric, 0));
  v_opening_mult numeric := greatest(case when 'opening_strike' = any(p_effects) then 2 else 1 end,
                                     coalesce((p_mods->>'opening')::numeric, 1));
  v_low_hp_ls numeric := greatest(1, coalesce((p_mods->>'low_hp_ls')::numeric, 1));
  v_opening boolean;
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

    -- Đòn Kép: đánh thêm 1 đòn trong lượt
    v_hits := case when random() < v_double_chance then 2 else 1 end;

    for v_hit in 1..v_hits loop
      exit when v_enemy_hp <= 0;

      v_base_dmg := greatest(1, p_char_atk * v_skill_power - p_enemy_def);
      v_opening := v_opening_mult > 1 and v_turn = 1 and v_hit = 1;
      if v_opening then
        v_base_dmg := v_base_dmg * v_opening_mult;   -- Khai Cuộc
      end if;
      v_is_crit := random() < p_crit;
      v_dmg := round(v_base_dmg * (case when v_is_crit then v_crit_mult else 1 end));
      v_enemy_hp := greatest(0, v_enemy_hp - v_dmg);

      if p_lifesteal > 0 then
        -- Khát Máu Vô Tận: HP dưới 30% thì hút máu nhân thêm
        v_char_hp := least(p_max_hp, v_char_hp + round(v_dmg * p_lifesteal
          * case when v_char_hp < p_max_hp * 0.3 then v_low_hp_ls else 1 end));
      end if;

      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'character', 'skill', v_skill_name,
          'damage', v_dmg, 'crit', v_is_crit, 'enemy_hp_left', v_enemy_hp,
          'double', v_hit = 2, 'opening', v_opening
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
      v_damage_multiplier, true, v_effects, get_talent_totals(p_character_id)
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
        v_dmg_mult, true, v_effects, get_talent_totals(p_character_id)
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
    1, true, v_effects, get_talent_totals(p_character_id)
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

