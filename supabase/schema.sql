-- ============================================================================
-- RPG GAME SCHEMA
-- Chạy toàn bộ file này trong Supabase Dashboard → SQL Editor → New query
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. CLASSES (4 class cố định — dữ liệu tĩnh, admin quản lý, người chơi chỉ đọc)
-- ----------------------------------------------------------------------------
create table classes (
  id            uuid primary key default gen_random_uuid(),
  key           text unique not null,        -- 'warrior' | 'mage' | 'archer' | 'assassin'
  name          text not null,                -- 'Chiến Binh'
  description   text not null,
  base_hp       int not null,
  base_atk      int not null,
  base_crit     numeric not null default 0.05,  -- chí mạng khởi điểm theo class
  base_def      int not null,
  base_spd      int not null,
  -- Tăng trưởng tự động mỗi cấp (thấp hơn trước khi có điểm chỉ số — phần
  -- còn lại người chơi tự cộng qua STR/INT/AGI/DEX/VIT, xem attribute_bonuses)
  hp_per_level  int not null default 6,
  atk_per_level int not null default 1,
  def_per_level int not null default 1,
  spd_per_level int not null default 1,
  -- Chỉ số gốc duy nhất cộng ATK cho class này: 'str'|'int'|'agi'|'dex'
  main_stat     text not null check (main_stat in ('str', 'int', 'agi', 'dex')),
  -- Tỉ lệ nút "Tự cộng" chia điểm, vd. {"str":2,"vit":1}
  auto_preset   jsonb not null,
  icon          text,                         -- emoji hoặc tên icon dùng ở frontend
  sort_order    int not null default 0
);

insert into classes (key, name, description, base_hp, base_atk, base_def, base_spd, main_stat, auto_preset, icon, sort_order) values
  ('warrior',  'Chiến Binh', 'Máu trâu, phòng thủ cao, đánh cận chiến ổn định. Dễ chơi cho người mới.', 120, 14, 12, 8,  'str', '{"str":2,"vit":1}', '⚔️', 1),
  ('mage',     'Pháp Sư',    'Sát thương phép cực cao nhưng máu giấy, cần né đòn khéo léo.',           80,  20, 6,  9,  'int', '{"int":3}',         '🔮', 2),
  ('archer',   'Xạ Thủ',     'Tốc độ và sát thương ổn định, ra đòn liên tục, khắc chế boss đơn.',       95,  16, 8,  13, 'dex', '{"dex":2,"agi":1}', '🏹', 3),
  ('assassin', 'Sát Thủ',    'Chí mạng cao, đánh nhanh kết liễu sớm, nhưng dễ chết nếu bị dồn.',       85,  18, 7,  15, 'agi', '{"agi":2,"dex":1}', '🗡️', 4);

-- ----------------------------------------------------------------------------
-- 2. CHARACTERS (nhân vật của người chơi — 1 user có thể có nhiều nhân vật)
-- ----------------------------------------------------------------------------
create table characters (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  class_id          uuid not null references classes(id),
  name              text not null,
  level             int not null default 1,
  exp               int not null default 0,
  exp_to_next       int not null default 100,
  gold              int not null default 100,
  current_chapter   int not null default 1,
  current_hp        int,                        -- null = đầy máu (tính theo class + level)
  -- Hệ thống AP (giới hạn hành động chống nghiện)
  current_ap        int not null default 100,
  max_ap            int not null default 100,
  ap_regen_minutes  int not null default 1,    -- +1 AP mỗi X phút
  last_ap_update    timestamptz not null default now(),
  last_hp_update    timestamptz not null default now(),  -- mốc hồi HP (+2% HP tối đa mỗi phút)
  -- Điểm chỉ số: +3 mỗi cấp. Chỉ đổi được qua allocate_stats /
  -- auto_allocate_stats / reset_stats / add_experience (trigger
  -- guard_character_attributes chặn client tự sửa thẳng qua REST).
  stat_points       int not null default 0 check (stat_points >= 0),
  stat_str          int not null default 0 check (stat_str >= 0),
  stat_int          int not null default 0 check (stat_int >= 0),
  stat_agi          int not null default 0 check (stat_agi >= 0),
  stat_dex          int not null default 0 check (stat_dex >= 0),
  stat_vit          int not null default 0 check (stat_vit >= 0),
  auto_allocate_stats  boolean not null default false,  -- tự chia điểm theo preset khi lên cấp
  free_stat_reset_used boolean not null default false,  -- lần tẩy điểm đầu tiên miễn phí
  -- Bộ đếm thành tích (danh hiệu, xếp hạng) + tầng cao nhất Tháp Vực Sâu
  kills             int not null default 0,
  boss_kills        int not null default 0,
  legendary_found   int not null default 0,
  best_enchant      int not null default 0,
  daily_bonus_count int not null default 0,
  tower_best        int not null default 0,
  gacha_pity        int not null default 0,   -- số lượt gacha liên tiếp chưa ra Huyền Thoại
  gacha_free_date   date,                     -- ngày (giờ VN) đã dùng lượt gacha miễn phí
  created_at        timestamptz not null default now()
);

create index characters_user_id_idx on characters(user_id);

-- ----------------------------------------------------------------------------
-- 3. PET SPECIES (danh mục loài pet có thể bắt) + PET của từng nhân vật
-- ----------------------------------------------------------------------------
create table pet_species (
  id           uuid primary key default gen_random_uuid(),
  key          text unique not null,
  name         text not null,
  description  text,
  base_hp      int not null,
  base_atk     int not null,
  base_def     int not null,
  catch_rate   numeric not null default 0.3,   -- tỉ lệ bắt cơ bản (0..1)
  rarity       text not null default 'common', -- common | rare | epic | legendary
  icon         text
);

create table character_pets (
  id            uuid primary key default gen_random_uuid(),
  character_id  uuid not null references characters(id) on delete cascade,
  species_id    uuid not null references pet_species(id),
  nickname      text,
  level         int not null default 1,
  exp           int not null default 0,
  is_companion  boolean not null default false, -- pet đang đi theo hỗ trợ chiến đấu
  caught_at     timestamptz not null default now()
);

create index character_pets_character_id_idx on character_pets(character_id);

-- ----------------------------------------------------------------------------
-- 4. ITEMS (vũ khí, giáp, đồ tiêu hao, nguyên liệu) + INVENTORY
-- ----------------------------------------------------------------------------
create table items (
  id           uuid primary key default gen_random_uuid(),
  key          text unique not null,
  name         text not null,
  type         text not null,                 -- weapon | armor | consumable | material
  slot         text,                           -- weapon | shield | head | chest | belt | amulet | boot | null
  hand         text,                           -- one_hand | two_hand — chỉ có ý nghĩa khi slot là weapon/shield
  school       text,                           -- physical | magic — chỉ có ý nghĩa khi slot = weapon, quyết định affix pool khi rơi
  rarity       text not null default 'common', -- common | rare | epic | legendary
  bonus_atk    int not null default 0,
  bonus_def    int not null default 0,
  bonus_hp     int not null default 0,
  heal_amount  int not null default 0,         -- dùng cho potion hồi HP
  restore_ap   int not null default 0,         -- dùng cho potion hồi AP — 1 item chỉ nên có 1 trong 2, không cả hai
  buy_price    int,                            -- null = không bán trong shop
  sell_price   int not null default 0,
  description  text,
  icon         text                            -- tên file dưới /public/items/, null = chưa có art
);

create table inventory (
  id            uuid primary key default gen_random_uuid(),
  character_id  uuid not null references characters(id) on delete cascade,
  item_id       uuid not null references items(id),
  quantity      int not null default 1,
  equipped      boolean not null default false,
  equip_slot    text,                           -- head|chest|belt|amulet|boot|l_arm|r_arm|both_arms|ring_1|ring_2, null khi chưa mặc
  -- Affix roll riêng cho lần rơi này (không dùng chung khuôn với items) — 0 nếu mua ở chợ hoặc chế tạo.
  rolled_atk       int not null default 0,
  rolled_def       int not null default 0,
  rolled_hp        int not null default 0,
  rolled_crit      numeric not null default 0,
  rolled_lifesteal numeric not null default 0,
  -- Tier riêng của món trang bị này (null = đồ mua ở chợ / vật phẩm gộp chồng → dùng items.rarity)
  rarity        text check (rarity in ('common', 'rare', 'epic', 'legendary')),
  locked        boolean not null default false,          -- 🔒 không bán được
  enchant_level int not null default 0 check (enchant_level between 0 and 5),
  -- Hiệu ứng đặc biệt của món Huyền Thoại (random lúc tạo), null nếu không có
  legendary_effect text check (legendary_effect in ('double_strike', 'deadly_crit', 'opening_strike', 'guardian', 'thorns')),
  acquired_at   timestamptz not null default now()
);

create index inventory_character_id_idx on inventory(character_id);

-- ----------------------------------------------------------------------------
-- 5. DUNGEONS (theo tầng, có boss elite ở tầng cuối)
-- ----------------------------------------------------------------------------
create table dungeons (
  id             uuid primary key default gen_random_uuid(),
  key            text unique not null,
  name           text not null,
  min_level      int not null default 1,
  ap_cost        int not null default 10,
  floor_count    int not null default 5,
  description    text,
  chapter_number int unique                     -- chương cốt truyện dungeon này mở khóa
);

create table dungeon_floors (
  id            uuid primary key default gen_random_uuid(),
  dungeon_id    uuid not null references dungeons(id) on delete cascade,
  floor_number  int not null,
  is_boss_floor boolean not null default false,
  enemy_name    text not null,
  enemy_level   int not null default 1,
  enemy_hp      int not null,
  enemy_atk     int not null,
  enemy_def     int not null,
  reward_exp    int not null default 0,
  reward_gold   int not null default 0,
  drop_item_id  uuid references items(id),
  drop_rate     numeric not null default 0.1,
  unique (dungeon_id, floor_number)
);

create table dungeon_runs (
  id             uuid primary key default gen_random_uuid(),
  character_id   uuid not null references characters(id) on delete cascade,
  dungeon_id     uuid not null references dungeons(id),
  current_floor  int not null default 1,
  status         text not null default 'in_progress', -- in_progress | cleared | failed
  started_at     timestamptz not null default now(),
  finished_at    timestamptz
);

create index dungeon_runs_character_id_idx on dungeon_runs(character_id);

-- ----------------------------------------------------------------------------
-- 6. SKILLS (kỹ năng theo class — dữ liệu tĩnh) + kỹ năng đang trang bị
-- ----------------------------------------------------------------------------
create table skills (
  id               uuid primary key default gen_random_uuid(),
  class_id         uuid not null references classes(id),
  key              text unique not null,
  name             text not null,
  description      text not null,
  skill_type       text not null,                 -- active | passive
  power_multiplier numeric,                        -- dùng cho skill active (nhân vào atk)
  effect_type      text,                           -- damage_reduction | lifesteal | crit_chance | crit_damage (passive)
  effect_value     numeric,                        -- 0..1
  unlock_level     int not null default 1,
  icon             text
);

create table character_equipped_skills (
  id            uuid primary key default gen_random_uuid(),
  character_id  uuid not null references characters(id) on delete cascade,
  skill_id      uuid not null references skills(id)
);

create index character_equipped_skills_character_id_idx on character_equipped_skills(character_id);

-- ----------------------------------------------------------------------------
-- 7. STORY (nội dung cốt truyện mở dần theo level)
-- ----------------------------------------------------------------------------
create table story_chapters (
  id             uuid primary key default gen_random_uuid(),
  chapter_number int unique not null,
  title          text not null,
  content        text not null,
  level_required int not null default 1
);

-- ----------------------------------------------------------------------------
-- 8. QUESTS (nhiệm vụ chính + phụ) + tiến trình của từng nhân vật
-- ----------------------------------------------------------------------------
create table quests (
  id                uuid primary key default gen_random_uuid(),
  key               text unique not null,
  title             text not null,
  description       text not null,
  type              text not null default 'side', -- main | side | daily
  chapter_required  int not null default 1,
  target_type       text not null,                 -- kill_monster | reach_level | clear_dungeon | collect_item
  target_key        text,                           -- vd: dungeon key hoặc item key liên quan
  target_amount     int not null default 1,
  reward_exp        int not null default 0,
  reward_gold       int not null default 0,
  reward_item_id    uuid references items(id)
);

create table character_quests (
  id            uuid primary key default gen_random_uuid(),
  character_id  uuid not null references characters(id) on delete cascade,
  quest_id      uuid not null references quests(id),
  status        text not null default 'active', -- active | completed | claimed
  progress      int not null default 0,
  updated_at    timestamptz not null default now(),
  unique (character_id, quest_id)
);

create index character_quests_character_id_idx on character_quests(character_id);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

-- Bảng dữ liệu tĩnh (đọc công khai, không ai sửa được từ client)
alter table classes enable row level security;
alter table pet_species enable row level security;
alter table items enable row level security;
alter table dungeons enable row level security;
alter table dungeon_floors enable row level security;
alter table story_chapters enable row level security;
alter table quests enable row level security;
alter table skills enable row level security;

create policy "public read classes" on classes for select using (true);
create policy "public read pet_species" on pet_species for select using (true);
create policy "public read items" on items for select using (true);
create policy "public read dungeons" on dungeons for select using (true);
create policy "public read dungeon_floors" on dungeon_floors for select using (true);
create policy "public read story_chapters" on story_chapters for select using (true);
create policy "public read quests" on quests for select using (true);
create policy "public read skills" on skills for select using (true);

-- Bảng dữ liệu người chơi (chỉ chủ sở hữu mới đọc/ghi được)
alter table characters enable row level security;
alter table character_pets enable row level security;
alter table inventory enable row level security;
alter table dungeon_runs enable row level security;
alter table character_quests enable row level security;
alter table character_equipped_skills enable row level security;

create policy "own characters select" on characters
  for select using (auth.uid() = user_id);
create policy "own characters insert" on characters
  for insert with check (auth.uid() = user_id);
create policy "own characters update" on characters
  for update using (auth.uid() = user_id);
create policy "own characters delete" on characters
  for delete using (auth.uid() = user_id);

create policy "own pets select" on character_pets
  for select using (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );

create policy "own inventory select" on inventory
  for select using (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );

create policy "own dungeon_runs select" on dungeon_runs
  for select using (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );

create policy "own character_quests select" on character_quests
  for select using (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );

create policy "own equipped skills select" on character_equipped_skills
  for select using (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );
create policy "own equipped skills insert" on character_equipped_skills
  for insert with check (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );
create policy "own equipped skills delete" on character_equipped_skills
  for delete using (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );

-- ============================================================================
-- COMBAT FUNCTIONS (chạy trên server qua SECURITY DEFINER — client gọi qua
-- supabase.rpc(), không tự trừ AP/cộng gold/exp trực tiếp từ browser)
-- ============================================================================

-- Hệ số scale EXP/damage theo chênh lệch cấp độ nhân vật vs quái.
create or replace function public.calculate_combat_scaling(p_character_level integer, p_enemy_level integer)
returns table(exp_multiplier numeric, damage_multiplier numeric, level_diff integer)
language sql
immutable
as $$
  select
    -- Mỗi cấp quái cao hơn nhân vật: +15% EXP. Mỗi cấp thấp hơn: -15% EXP.
    -- Chặn trong khoảng [0.2x, 1.5x] — trần cũ 3.0x thưởng quá lớn cho việc vượt cấp.
    greatest(0.2, least(1.5, 1 + (p_enemy_level - p_character_level) * 0.15)) as exp_multiplier,
    -- Mỗi cấp quái cao hơn: +12% sát thương gây ra. Thấp hơn: -12%.
    -- Chặn trong khoảng [0.5x, 2.5x].
    greatest(0.5, least(2.5, 1 + (p_enemy_level - p_character_level) * 0.12)) as damage_multiplier,
    (p_enemy_level - p_character_level) as level_diff;
$$;

-- ============================================================================
-- ĐIỂM CHỈ SỐ (STR / INT / AGI / DEX / VIT)
-- Mỗi class chỉ có 1 chỉ số chính cộng ATK (classes.main_stat) — vd. Pháp Sư
-- cộng STR không được thêm ATK, nên tự khắc phải dồn INT. VIT là chỉ số phòng
-- thủ dùng chung. Công thức hiệu ứng nằm DUY NHẤT ở attribute_bonuses; bản
-- sao phía client (lib/character-stats.ts) chỉ dùng để xem trước khi cộng.
-- ============================================================================

create or replace function public.attribute_bonuses(
  p_main_stat text, p_str int, p_int int, p_agi int, p_dex int, p_vit int
)
returns table(attr_atk int, attr_def int, attr_hp int, attr_crit numeric)
language sql
immutable
as $$
  select
    -- Chỉ số chính: +1 ATK mỗi điểm
    case p_main_stat
      when 'str' then p_str when 'int' then p_int
      when 'agi' then p_agi when 'dex' then p_dex
      else 0
    end,
    -- VIT: +1 DEF mỗi 2 điểm, +5 HP mỗi điểm
    p_vit / 2,
    p_vit * 5,
    -- AGI 0.5 / DEX 0.3 "điểm chí mạng", giảm dần: 0.3 × r / (r + 0.5), tối đa ~30%
    -- (trước cộng thẳng, Sát Thủ dồn AGI lên >100% chí mạng)
    0.3 * (p_agi * 0.005 + p_dex * 0.003) / (p_agi * 0.005 + p_dex * 0.003 + 0.5);
$$;

-- Chỉ số tổng hợp của nhân vật: base_* = class + cấp + điểm chỉ số (chưa có
-- trang bị), còn max_hp/atk/def/crit_bonus/lifesteal_bonus = đã cộng trang bị.
-- Dùng chung cho combat, use_item, reset_stats và các trang hiển thị để số
-- trên UI không lệch với số trong trận. security invoker: RLS vẫn áp dụng khi
-- client gọi trực tiếp (chỉ đọc được nhân vật của chính mình).
-- Tổng hiệu ứng Cây Thiên Phú (bảng ở phần CÂY THIÊN PHÚ cuối file; plpgsql nên
-- tạo trước bảng vẫn được)
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
           case when e.key in ('crit_mult', 'opening', 'low_hp_ls', 'parry_mult', 'echo_pct')
                then max(e.value::text::numeric) else sum(e.value::text::numeric) end as val
    from character_talents ct
    join talent_nodes n on n.key = ct.node_key
    cross join lateral jsonb_each(n.effects) e
    where ct.character_id = p_character_id
    group by e.key
  ) s;

  -- Giáp Hoàng Gia: +x% ATK/DEF gốc cho mỗi món đang mặc
  if v ? 'equip_bonus' then
    select v
           || jsonb_build_object(
                'atk_pct', coalesce((v->>'atk_pct')::numeric, 0) + (v->>'equip_bonus')::numeric * count(*),
                'def_pct', coalesce((v->>'def_pct')::numeric, 0) + (v->>'equip_bonus')::numeric * count(*))
      into v
    from inventory inv where inv.character_id = p_character_id and inv.equipped;
  end if;
  return v;
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
    -- Thiên phú: % nhân vào chỉ số gốc (không nhân trang bị), chí mạng/hút máu cộng thẳng
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

-- Chia p_points điểm theo tỉ lệ preset (vd. {"str":2,"vit":1} → str, str,
-- vit, str, str, vit, ...). Preset rỗng thì dồn hết vào VIT.
create or replace function public.split_stat_points(p_points int, p_preset jsonb)
returns table(add_str int, add_int int, add_agi int, add_dex int, add_vit int)
language plpgsql
immutable
as $$
declare
  v_seq text[] := '{}';
  v_key text; v_len int; i int;
  s int := 0; n int := 0; a int := 0; d int := 0; v int := 0;
begin
  foreach v_key in array array['str', 'int', 'agi', 'dex', 'vit'] loop
    for i in 1..coalesce((p_preset ->> v_key)::int, 0) loop
      v_seq := v_seq || v_key;
    end loop;
  end loop;

  v_len := coalesce(array_length(v_seq, 1), 0);
  if v_len = 0 then v_seq := array['vit']; v_len := 1; end if;

  for i in 0..coalesce(p_points, 0) - 1 loop
    case v_seq[(i % v_len) + 1]
      when 'str' then s := s + 1;
      when 'int' then n := n + 1;
      when 'agi' then a := a + 1;
      when 'dex' then d := d + 1;
      else v := v + 1;
    end case;
  end loop;

  return query select s, n, a, d, v;
end;
$$;

-- Người chơi tự cộng điểm (từ panel +/- ở trang nhân vật). Trả về số điểm còn lại.
create or replace function public.allocate_stats(
  p_character_id uuid, p_str int, p_int int, p_agi int, p_dex int, p_vit int
)
returns int
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_points int;
  v_total int;
begin
  select user_id, stat_points into v_owner_user_id, v_points
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  p_str := coalesce(p_str, 0); p_int := coalesce(p_int, 0); p_agi := coalesce(p_agi, 0);
  p_dex := coalesce(p_dex, 0); p_vit := coalesce(p_vit, 0);

  if least(p_str, p_int, p_agi, p_dex, p_vit) < 0 then
    raise exception 'Số điểm không hợp lệ';
  end if;

  v_total := p_str + p_int + p_agi + p_dex + p_vit;

  if v_total = 0 then raise exception 'Chưa chọn điểm nào để cộng'; end if;
  if v_total > v_points then
    raise exception 'Không đủ điểm chỉ số (còn % điểm)', v_points;
  end if;

  update characters
  set stat_points = stat_points - v_total,
      stat_str = stat_str + p_str, stat_int = stat_int + p_int, stat_agi = stat_agi + p_agi,
      stat_dex = stat_dex + p_dex, stat_vit = stat_vit + p_vit
  where id = p_character_id;

  return v_points - v_total;
end;
$$;

-- Nút "Tự cộng": chia toàn bộ điểm còn lại theo preset của class.
-- Trả về số điểm đã cộng.
create or replace function public.auto_allocate_stats(p_character_id uuid)
returns int
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_points int;
  v_preset jsonb;
begin
  select c.user_id, c.stat_points, cl.auto_preset into v_owner_user_id, v_points, v_preset
  from characters c join classes cl on cl.id = c.class_id
  where c.id = p_character_id for update of c;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  if v_points <= 0 then raise exception 'Không còn điểm chỉ số để cộng'; end if;

  update characters c
  set stat_points = 0,
      stat_str = c.stat_str + sp.add_str, stat_int = c.stat_int + sp.add_int,
      stat_agi = c.stat_agi + sp.add_agi, stat_dex = c.stat_dex + sp.add_dex,
      stat_vit = c.stat_vit + sp.add_vit
  from split_stat_points(v_points, v_preset) sp
  where c.id = p_character_id;

  return v_points;
end;
$$;

-- Tẩy điểm: trả toàn bộ điểm đã cộng về stat_points. Lần đầu miễn phí, sau đó
-- tốn level × 50 vàng (thêm một chỗ tiêu vàng). HP hiện tại bị kẹp lại nếu
-- vượt HP tối đa mới (vd. vừa tẩy hết VIT). Trả về số vàng đã tốn.
create or replace function public.reset_stats(p_character_id uuid)
returns int
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_level int; v_gold int; v_free_used boolean;
  v_spent int; v_cost int;
  v_new_max_hp int;
begin
  select user_id, level, gold, free_stat_reset_used,
         stat_str + stat_int + stat_agi + stat_dex + stat_vit
    into v_owner_user_id, v_level, v_gold, v_free_used, v_spent
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  if v_spent = 0 then raise exception 'Chưa cộng điểm nào để tẩy'; end if;

  v_cost := case when v_free_used then v_level * 50 else 0 end;

  if v_gold < v_cost then
    raise exception 'Không đủ vàng để tẩy điểm (cần % vàng)', v_cost;
  end if;

  update characters
  set gold = gold - v_cost,
      free_stat_reset_used = true,
      stat_points = stat_points + v_spent,
      stat_str = 0, stat_int = 0, stat_agi = 0, stat_dex = 0, stat_vit = 0
  where id = p_character_id;

  select gs.max_hp into v_new_max_hp from get_character_stats(p_character_id) gs;

  update characters
  set current_hp = least(current_hp, v_new_max_hp)
  where id = p_character_id and current_hp is not null;

  return v_cost;
end;
$$;

-- Chặn client tự sửa điểm chỉ số qua REST (RLS "own characters update" cho
-- phép update cả dòng). Các RPC security definer ở trên chạy dưới quyền owner
-- nên current_user không phải 'authenticated' và không bị chặn.
create or replace function public.guard_character_attributes()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.stat_points := 0;
      new.stat_str := 0; new.stat_int := 0; new.stat_agi := 0; new.stat_dex := 0; new.stat_vit := 0;
      new.free_stat_reset_used := false;
    elsif (new.stat_points, new.stat_str, new.stat_int, new.stat_agi, new.stat_dex, new.stat_vit, new.free_stat_reset_used)
          is distinct from
          (old.stat_points, old.stat_str, old.stat_int, old.stat_agi, old.stat_dex, old.stat_vit, old.free_stat_reset_used) then
      raise exception 'Điểm chỉ số chỉ được thay đổi qua cộng/tẩy điểm trong game';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_character_attributes on characters;
create trigger guard_character_attributes
  before insert or update on characters
  for each row execute function public.guard_character_attributes();

-- Cộng EXP cho nhân vật, tự động lên cấp (có thể lên nhiều cấp cùng lúc).
-- Mỗi cấp lên được +3 điểm chỉ số; nếu bật auto_allocate_stats thì chia luôn
-- theo preset của class thay vì dồn vào stat_points.
create or replace function public.add_experience(p_character_id uuid, p_exp_gained int)
returns table(leveled_up boolean, new_level int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_level int; v_exp int; v_exp_to_next int;
  v_auto_allocate boolean; v_preset jsonb;
  v_levels_gained int := 0;
begin
  select c.user_id, c.level, c.exp, c.exp_to_next, c.auto_allocate_stats, cl.auto_preset
    into v_owner_user_id, v_level, v_exp, v_exp_to_next, v_auto_allocate, v_preset
  from characters c join classes cl on cl.id = c.class_id
  where c.id = p_character_id for update of c;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  v_exp := v_exp + greatest(0, p_exp_gained);

  while v_exp >= v_exp_to_next loop
    v_exp := v_exp - v_exp_to_next;
    v_level := v_level + 1;
    v_exp_to_next := round(2.5 * (100 + (v_level - 1) * 50));
    v_levels_gained := v_levels_gained + 1;
  end loop;

  update characters
  set level = v_level, exp = v_exp, exp_to_next = v_exp_to_next
  where id = p_character_id;

  if v_levels_gained > 0 then
    if v_auto_allocate then
      update characters c
      set stat_str = c.stat_str + sp.add_str, stat_int = c.stat_int + sp.add_int,
          stat_agi = c.stat_agi + sp.add_agi, stat_dex = c.stat_dex + sp.add_dex,
          stat_vit = c.stat_vit + sp.add_vit
      from split_stat_points(v_levels_gained * 3, v_preset) sp
      where c.id = p_character_id;
    else
      update characters
      set stat_points = stat_points + v_levels_gained * 3
      where id = p_character_id;
    end if;
  end if;

  return query select v_levels_gained > 0, v_level;
end;
$$;

-- Roll ngẫu nhiên affix cho 1 món đồ khi rơi, giới hạn theo slot/school của
-- item (vd. kiếm không bao giờ roll được 'mag atk' vì đó là pool riêng của
-- weapon school='magic'). Số lượng roll và biên độ tăng theo rarity.
create or replace function public.roll_item_affixes(p_slot text, p_school text, p_rarity text)
returns table(roll_atk int, roll_def int, roll_hp int, roll_crit numeric, roll_lifesteal numeric, roll_extra jsonb)
language plpgsql
as $$
declare
  v_roll_count int;
  v_flat_min int; v_flat_max int;
  v_pct_min numeric; v_pct_max numeric;
  v_pool text[];
  v_stat text;
  v_atk int := 0; v_def int := 0; v_hp int := 0;
  v_crit numeric := 0; v_lifesteal numeric := 0;
  v_extra jsonb := '{}'::jsonb;
  v_pct numeric;
  i int;
begin
  case p_rarity
    when 'legendary' then v_roll_count := 4; v_flat_min := 7; v_flat_max := 12; v_pct_min := 0.05; v_pct_max := 0.10;
    when 'epic'      then v_roll_count := 3; v_flat_min := 4; v_flat_max := 8;  v_pct_min := 0.03; v_pct_max := 0.06;
    when 'rare'      then v_roll_count := 2; v_flat_min := 2; v_flat_max := 5;  v_pct_min := 0.02; v_pct_max := 0.04;
    else                  v_roll_count := 1; v_flat_min := 1; v_flat_max := 3;  v_pct_min := 0.01; v_pct_max := 0.02;
  end case;

  -- Dòng tiện ích (pierce, double, dmg_red, regen, skill_dmg) chiếm ~1/3 pool; chỉ số thô
  -- lặp 2 lần để vẫn là dòng hay gặp nhất
  v_pool := case
    when p_slot = 'weapon' and p_school = 'magic' then
      array['atk', 'atk', 'lifesteal', 'pierce', 'skill_dmg']
    when p_slot = 'weapon' then
      array['atk', 'atk', 'crit', 'crit', 'lifesteal', 'pierce', 'double', 'skill_dmg']
    when p_slot in ('amulet', 'ring') then
      array['atk', 'def', 'hp', 'crit', 'lifesteal', 'atk', 'hp', 'crit', 'double', 'skill_dmg', 'regen']
    when p_slot in ('shield', 'head', 'chest', 'belt', 'boot') then
      array['def', 'hp', 'def', 'hp', 'dmg_red', 'regen']
    else null
  end;

  if v_pool is null then
    return query select 0, 0, 0, 0::numeric, 0::numeric, '{}'::jsonb;
    return;
  end if;

  for i in 1..v_roll_count loop
    v_stat := v_pool[1 + floor(random() * array_length(v_pool, 1))::int];
    -- Mỗi dòng tiện ích tối đa 1 lần / món; trùng thì thành chỉ số thô đầu pool
    if v_extra ? v_stat then v_stat := v_pool[1]; end if;
    v_pct := v_pct_min + random() * (v_pct_max - v_pct_min);
    if v_stat = 'atk' then
      v_atk := v_atk + (v_flat_min + floor(random() * (v_flat_max - v_flat_min + 1)))::int;
    elsif v_stat = 'def' then
      v_def := v_def + (v_flat_min + floor(random() * (v_flat_max - v_flat_min + 1)))::int;
    elsif v_stat = 'hp' then
      v_hp := v_hp + ((v_flat_min + floor(random() * (v_flat_max - v_flat_min + 1))) * 3)::int;
    elsif v_stat = 'crit' then
      v_crit := v_crit + round(v_pct::numeric, 4);
    elsif v_stat = 'lifesteal' then
      v_lifesteal := v_lifesteal + round(v_pct::numeric, 4);
    else
      -- Tiện ích: pierce/skill_dmg ×2, double/dmg_red ×0.8, regen ×0.15 so với dải % của tier
      v_pct := round((v_pct * case v_stat when 'pierce' then 2 when 'skill_dmg' then 2
                                          when 'regen' then 0.15 else 0.8 end)::numeric, 4);
      v_extra := jsonb_set(v_extra, array[v_stat],
        to_jsonb(coalesce((v_extra->>v_stat)::numeric, 0) + v_pct));
    end if;
  end loop;

  return query select v_atk, v_def, v_hp, v_crit, v_lifesteal, v_extra;
end;
$$;

-- ============================================================================
-- VÒNG ĐÁNH DÙNG CHUNG (dungeon + explore)
-- ============================================================================

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
    -- skill bị động + thiên phú, tối đa 60%
    least(0.6, case when v_passive_type = 'damage_reduction' then v_passive_value else 0 end
               + coalesce((get_talent_totals(p_character_id)->>'dmg_red')::numeric, 0)),
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
  p_damage_multiplier numeric, p_with_log boolean,
  p_effects text[] default '{}',
  p_mods jsonb default '{}',      -- tổng thiên phú (get_talent_totals) + 'kit' (get_skill_kit)
  p_level_gap int default 0,      -- cấp quái − cấp nhân vật (> 0: đánh vượt cấp)
  p_enemy_traits text[] default '{}', -- đặc tính quái (mô tả: ENEMY_TRAITS, lib/enemies.ts)
  p_enemy_level int default 0     -- cấp quái: hằng số DEF theo tỉ lệ
)
returns table(out_win boolean, out_timed_out boolean, out_hp_left int, out_dmg_taken int, out_log jsonb,
              out_revived boolean)
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
  -- Đánh quái cao cấp hơn: −2% sát thương mỗi cấp chênh, thấp nhất còn 30%
  v_gap_mult numeric := greatest(0.3, 1 - greatest(0, p_level_gap) * 0.02);
  -- Ô thiên phú lấy cảm hứng từ DautoRPG
  v_rage numeric := coalesce((p_mods->>'rage')::numeric, 0);              -- Cuồng Huyết
  v_guard_step numeric := coalesce((p_mods->>'guard_stack')::numeric, 0); -- Trụ Cột
  v_guard_hits int := 0;
  v_prestige numeric := coalesce((p_mods->>'prestige')::numeric, 0);      -- Phong Hầu
  v_parry numeric := least(0.5, coalesce((p_mods->>'parry')::numeric, 0)); -- Phản Kích
  v_parry_mult numeric := coalesce((p_mods->>'parry_mult')::numeric, 1.5);
  v_echo numeric := least(0.5, coalesce((p_mods->>'echo')::numeric, 0));  -- Dư Âm
  v_echo_pct numeric := coalesce((p_mods->>'echo_pct')::numeric, 0.6);
  v_pierce numeric := least(1, coalesce((p_mods->>'pierce')::numeric, 0)); -- Xuyên Giáp
  v_crit_pierce boolean := coalesce((p_mods->>'crit_pierce')::numeric, 0) > 0; -- Mắt Tử Thần
  v_revive numeric := coalesce((p_mods->>'revive')::numeric, 0);          -- Giả Chết (caller bỏ key khi đã dùng)
  v_revived boolean := false;
  v_atk_now numeric; v_def_now numeric; v_stack numeric;
  v_parried boolean; v_counter int; v_echo_dmg int;
  -- Bộ kỹ năng có hồi chiêu (get_skill_kit). Không có 'kit' → luân phiên a1/a2 như cũ.
  v_kit jsonb := p_mods->'kit';
  v_n int := coalesce(jsonb_array_length(p_mods->'kit'->'actives'), 0);
  v_cds int[] := array_fill(0, array[greatest(1, coalesce(jsonb_array_length(p_mods->'kit'->'actives'), 0))]);
  v_i int; v_best int; v_best_score numeric; v_score numeric; v_sk jsonb;
  v_eff jsonb := '{}'::jsonb;
  v_bonus numeric; v_multi int; v_hit_pierce numeric; v_stun_now boolean;
  v_dot_dmg int := 0; v_dot_left int := 0; v_dot_name text; v_tick int;
  v_stunned boolean := false;   -- quái bị đóng băng: mất lượt đánh kế
  v_chill boolean := false;     -- quái vừa mất lượt vì đóng băng (Băng Vỡ đánh mạnh hơn)
  v_stun_count int := 0;        -- đóng băng giảm dần: lần 2 tỉ lệ ×0.5, tối đa 2 lần/trận
  -- Dòng tiện ích trang bị (combat_mods)
  v_regen numeric := least(0.03, coalesce((p_mods->>'regen')::numeric, 0));
  v_skill_dmg numeric := least(0.5, coalesce((p_mods->>'skill_dmg')::numeric, 0));
  v_gear_red numeric := least(0.25, coalesce((p_mods->>'gear_dmg_red')::numeric, 0));
  -- Đặc tính quái
  v_t_armored boolean := 'armored' = any(p_enemy_traits);  -- Giáp Cứng: chí mạng yếu, không xuyên giáp
  v_t_evasive boolean := 'evasive' = any(p_enemy_traits);  -- Né Tránh: 15% đòn trượt
  v_t_savage boolean := 'savage' = any(p_enemy_traits);    -- Hung Bạo: quái chí mạng 15% ×1.5
  v_t_enrage boolean := 'enrage' = any(p_enemy_traits);    -- Cuồng Nộ: dưới 50% HP ATK ×1.3
  v_t_venom boolean := 'venom' = any(p_enemy_traits);      -- Độc: trúng đòn bị độc 2% HP/lượt
  v_t_regen boolean := 'regen' = any(p_enemy_traits);      -- Tái Sinh: hồi 4% HP mỗi lượt
  v_t_thorny boolean := 'thorny' = any(p_enemy_traits);    -- Gai: phản 4% sát thương nhận
  v_ls_mult numeric := case when 'unholy' = any(p_enemy_traits) then 0.5 else 1 end; -- Ô Uế: hút máu −50%
  v_miss boolean; v_real int; v_reflect int; v_poison int := 0; v_poison_tick int; v_regen_e int;
  v_enemy_crit boolean; v_enraged boolean; v_enrage_logged boolean := false;
  -- Sát thương quái: DEF giảm theo tỉ lệ DEF/(DEF+K) thay vì trừ thẳng (DEF cao không vô hiệu
  -- hoá quái). Hoà dần từ Lv30 (công thức cũ) tới Lv60 (công thức mới) để giữ cân bằng cấp thấp.
  v_k numeric := 20 + 6 * greatest(1, p_enemy_level);
  v_blend numeric := least(1, greatest(0, (p_enemy_level - 30) / 30.0));
  v_old_dmg numeric; v_ratio_dmg numeric;
begin
  -- Trần chung: chí mạng 50%, hút máu (chỉ số + bị động) 10%
  p_crit := least(0.5, p_crit);
  p_lifesteal := least(0.10, p_lifesteal);
  -- Bị động "Sát Thương Chí Mạng" cộng thẳng vào hệ số chí mạng
  v_crit_mult := v_crit_mult + coalesce((v_kit->>'crit_damage')::numeric, 0);
  if v_t_armored then
    v_crit_mult := 1 + (v_crit_mult - 1) * 0.5;
    v_crit_pierce := false;
  end if;

  while v_char_hp > 0 and v_enemy_hp > 0 and v_turn < 30 loop
    v_turn := v_turn + 1;

    if v_kit is null then
      if v_turn % 2 = 1 then
        v_skill_name := p_a1_name; v_skill_power := p_a1_power;
      else
        v_skill_name := p_a2_name; v_skill_power := p_a2_power;
      end if;
    else
      -- Hồi chiêu: dùng skill sẵn sàng có sức mạnh hiệu dụng cao nhất, không có thì đánh thường
      for v_i in 1..v_n loop
        v_cds[v_i] := greatest(0, v_cds[v_i] - 1);
      end loop;
      v_best := 0; v_best_score := 1;
      for v_i in 1..v_n loop
        v_sk := v_kit->'actives'->(v_i - 1);
        continue when v_cds[v_i] > 0;
        continue when v_char_hp < p_max_hp * coalesce((v_sk->'effect'->>'min_hp')::numeric, 0);
        v_score := (v_sk->>'power')::numeric
          * (1 + case when v_turn >= 3 then coalesce((v_sk->'effect'->>'streak')::numeric, 0) else 0 end
               + case when v_chill then coalesce((v_sk->'effect'->>'bonus_stunned')::numeric, 0) else 0 end
               + case when v_enemy_hp < p_enemy_hp * 0.3 then coalesce((v_sk->'effect'->>'execute')::numeric, 0) else 0 end)
          * coalesce((v_sk->'effect'->>'hits')::numeric, 1);
        if v_score > v_best_score then v_best := v_i; v_best_score := v_score; end if;
      end loop;

      if v_best > 0 then
        v_sk := v_kit->'actives'->(v_best - 1);
        v_eff := coalesce(v_sk->'effect', '{}'::jsonb);
        v_skill_name := v_sk->>'name';
        v_skill_power := v_best_score / coalesce((v_eff->>'hits')::numeric, 1) * (1 + v_skill_dmg);
        v_cds[v_best] := coalesce((v_sk->>'cooldown')::int, 0);
      else
        v_eff := '{}'::jsonb;
        v_skill_name := 'Đánh thường'; v_skill_power := 1;
      end if;
      v_chill := false;

      -- Chém Tuyệt Vọng: tự mất % HP hiện tại
      if coalesce((v_eff->>'hp_cost')::numeric, 0) > 0 then
        v_char_hp := greatest(1, v_char_hp - greatest(1, round(v_char_hp * (v_eff->>'hp_cost')::numeric))::int);
      end if;
    end if;

    -- Phong Hầu: +x% ATK/DEF mỗi lượt đã qua (tối đa 10); Cuồng Huyết: ATK tăng dần khi HP
    -- tụt từ 100% xuống 40%
    -- Hồi HP mỗi lượt (dòng tiện ích trang bị)
    if v_regen > 0 and v_turn > 1 then
      v_char_hp := least(p_max_hp, v_char_hp + greatest(1, round(p_max_hp * v_regen))::int);
    end if;

    v_stack := least(10, v_turn - 1) * v_prestige;
    v_atk_now := p_char_atk * (1 + v_stack
      + v_rage * least(1, greatest(0, (1 - v_char_hp::numeric / greatest(1, p_max_hp)) / 0.6)));
    v_def_now := p_char_def * (1 + v_stack);

    -- Đòn Kép: đánh thêm 1 đòn trong lượt
    v_multi := coalesce((v_eff->>'hits')::int, 1);
    v_hits := v_multi + case when random() < v_double_chance then 1 else 0 end;
    v_hit_pierce := 1 - (1 - v_pierce) * (1 - least(1, coalesce((v_eff->>'pierce')::numeric, 0)));

    for v_hit in 1..v_hits loop
      exit when v_enemy_hp <= 0;

      v_miss := v_t_evasive and random() < 0.15;
      if v_miss then
        if p_with_log then
          v_log := v_log || jsonb_build_object(
            'turn', v_turn, 'actor', 'character', 'skill', v_skill_name,
            'damage', 0, 'miss', true, 'enemy_hp_left', v_enemy_hp
          );
        end if;
        continue;
      end if;

      v_is_crit := random() < p_crit;
      v_base_dmg := greatest(1, (v_atk_now * v_skill_power
        - case when v_is_crit and v_crit_pierce then 0 else p_enemy_def * (1 - v_hit_pierce) end) * v_gap_mult);
      v_opening := v_opening_mult > 1 and v_turn = 1 and v_hit = 1;
      if v_opening then
        v_base_dmg := v_base_dmg * v_opening_mult;   -- Khai Cuộc
      end if;
      v_dmg := round(v_base_dmg * (case when v_is_crit then v_crit_mult else 1 end));
      -- Hút máu / phản gai chỉ tính phần sát thương thật (không tính phần tràn khi quái đã hết máu)
      v_real := least(v_dmg, v_enemy_hp);
      v_enemy_hp := greatest(0, v_enemy_hp - v_dmg);

      if p_lifesteal + coalesce((v_eff->>'lifesteal')::numeric, 0) > 0 then
        -- Khát Máu Vô Tận: HP dưới 30% thì hút máu nhân thêm
        v_char_hp := least(p_max_hp, v_char_hp + round(v_real * (p_lifesteal + coalesce((v_eff->>'lifesteal')::numeric, 0))
          * v_ls_mult * case when v_char_hp < p_max_hp * 0.3 then v_low_hp_ls else 1 end));
      end if;

      v_reflect := case when v_t_thorny then round(v_real * 0.04)::int else 0 end;
      if v_reflect > 0 then
        v_char_hp := greatest(1, v_char_hp - v_reflect);
        v_dmg_taken := v_dmg_taken + v_reflect;
      end if;

      -- Hiệu ứng chỉ áp ở đòn đầu của skill: đóng băng, độc/thiêu
      v_stun_now := v_hit = 1 and coalesce((v_eff->>'stun')::numeric, 0) > 0 and v_stun_count < 2
                    and random() < (v_eff->>'stun')::numeric * power(0.5, v_stun_count);
      if v_stun_now then v_stunned := true; v_stun_count := v_stun_count + 1; end if;
      if v_hit = 1 and coalesce((v_eff->>'dot')::numeric, 0) > 0 then
        v_dot_dmg := greatest(1, round(v_atk_now * (v_eff->>'dot')::numeric))::int;
        v_dot_left := coalesce((v_eff->>'dot_turns')::int, 2);
        v_dot_name := coalesce(v_eff->>'dot_name', 'Độc');
      end if;

      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'character', 'skill', v_skill_name,
          'damage', v_dmg, 'crit', v_is_crit, 'enemy_hp_left', v_enemy_hp,
          'double', v_hit > v_multi, 'opening', v_opening, 'stun', v_stun_now, 'reflect', v_reflect
        );
      end if;
    end loop;

    -- Dư Âm: cơ hội đánh thêm 1 đòn yếu cuối lượt
    if v_echo > 0 and v_enemy_hp > 0 and random() < v_echo then
      v_echo_dmg := round(greatest(1, (v_atk_now * v_echo_pct - p_enemy_def * (1 - v_pierce)) * v_gap_mult));
      v_enemy_hp := greatest(0, v_enemy_hp - v_echo_dmg);
      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'character', 'skill', 'Dư Âm',
          'damage', v_echo_dmg, 'crit', false, 'enemy_hp_left', v_enemy_hp, 'echo', true
        );
      end if;
    end if;

    -- Độc / thiêu: trừ máu quái cuối mỗi lượt của mình
    if v_dot_left > 0 and v_enemy_hp > 0 then
      v_tick := v_dot_dmg;
      v_enemy_hp := greatest(0, v_enemy_hp - v_tick);
      v_dot_left := v_dot_left - 1;
      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'character', 'skill', v_dot_name,
          'damage', v_tick, 'crit', false, 'enemy_hp_left', v_enemy_hp, 'dot', true
        );
      end if;
    end if;

    exit when v_enemy_hp <= 0;

    -- Tái Sinh: quái hồi máu đầu lượt của nó
    v_regen_e := 0;
    if v_t_regen then
      v_regen_e := least(p_enemy_hp - v_enemy_hp, round(p_enemy_hp * 0.04)::int);
      v_enemy_hp := v_enemy_hp + v_regen_e;
    end if;

    -- Đóng băng: quái mất lượt này
    if v_stunned then
      v_stunned := false;
      v_chill := true;
      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'enemy', 'enemy_name', p_enemy_name,
          'damage', 0, 'character_hp_left', v_char_hp, 'stunned', true, 'enemy_hp_left', v_enemy_hp
        );
      end if;
      continue;
    end if;

    -- Phản Kích: đỡ trọn đòn quái và đánh trả
    v_parried := v_parry > 0 and random() < v_parry;
    if v_parried then
      v_counter := round(greatest(1, (v_atk_now * v_parry_mult - p_enemy_def) * v_gap_mult));
      v_enemy_hp := greatest(0, v_enemy_hp - v_counter);
      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'enemy', 'enemy_name', p_enemy_name,
          'damage', 0, 'character_hp_left', v_char_hp, 'parry', v_counter, 'enemy_hp_left', v_enemy_hp
        );
      end if;
      continue;
    end if;

    -- DEF trừ thẳng nhưng quái luôn gây ít nhất 15% ATK của nó — trước đây sàn là 1,
    -- DEF nhân vật (cấp + VIT + đồ) vượt ATK quái nên quái gần như không gây sát thương
    -- Trụ Cột: mỗi lần trúng đòn trước đó +x% giảm sát thương (tối đa 3), chung trần 60%
    v_old_dmg := greatest(1, p_enemy_atk - v_def_now, p_enemy_atk * 0.15);
    v_ratio_dmg := p_enemy_atk * v_k / (v_k + greatest(0, v_def_now));
    v_enraged := v_t_enrage and v_enemy_hp < p_enemy_hp * 0.5;
    v_enemy_crit := v_t_savage and random() < 0.15;
    v_enemy_dmg := (v_old_dmg * (1 - v_blend) + greatest(v_old_dmg, v_ratio_dmg) * v_blend)
                   * case when v_enraged then 1.3 else 1 end
                   * case when v_enemy_crit then 1.5 else 1 end
                   * p_damage_multiplier
                   * (1 - least(0.6, p_dmg_reduction + v_gear_red + least(3, v_guard_hits) * v_guard_step)) * v_guardian;
    v_enemy_hit := round(v_enemy_dmg);
    v_char_hp := greatest(0, v_char_hp - v_enemy_hit);
    v_dmg_taken := v_dmg_taken + v_enemy_hit;
    v_guard_hits := v_guard_hits + 1;

    -- Độc: ngấm từ đòn trước, trúng đòn thì (lại) bị độc
    v_poison_tick := 0;
    if v_poison > 0 and v_char_hp > 0 then
      v_poison_tick := v_poison;
      v_char_hp := greatest(0, v_char_hp - v_poison_tick);
      v_dmg_taken := v_dmg_taken + v_poison_tick;
    end if;
    if v_t_venom then v_poison := greatest(1, round(p_max_hp * 0.02)::int); end if;

    -- Phản Đòn: 20% sát thương nhận vào dội lại quái
    v_thorns := case when v_thorns_on then round(v_enemy_hit * 0.2) else 0 end;
    if v_thorns > 0 then
      v_enemy_hp := greatest(0, v_enemy_hp - v_thorns);
    end if;

    if p_with_log then
      v_log := v_log || jsonb_build_object(
        'turn', v_turn, 'actor', 'enemy', 'enemy_name', p_enemy_name,
        'damage', v_enemy_hit, 'character_hp_left', v_char_hp,
        'thorns', v_thorns, 'enemy_hp_left', v_enemy_hp,
        'enemy_crit', v_enemy_crit, 'enraged', v_enraged and not v_enrage_logged,
        'poison', v_poison_tick, 'regen', v_regen_e
      );
      v_enrage_logged := v_enrage_logged or v_enraged;
    end if;

    -- Giả Chết: đòn chí tử đầu tiên để lại x% HP
    if v_char_hp <= 0 and v_revive > 0 and not v_revived then
      v_revived := true;
      v_char_hp := greatest(1, round(p_max_hp * v_revive));
      if p_with_log then
        v_log := v_log || jsonb_build_object(
          'turn', v_turn, 'actor', 'system', 'revive', true,
          'message', 'Giả Chết! Gượng dậy với ' || v_char_hp || ' HP'
        );
      end if;
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

  return query select v_win, v_timed_out, v_char_hp, v_dmg_taken, v_log, v_revived;
end;
$$;
-- ============================================================================
-- BẢNG TIN + HIỆU ỨNG HUYỀN THOẠI
-- ============================================================================

-- 1. Bảng tin ----------------------------------------------------------------
create table if not exists activity_feed (
  id             uuid primary key default gen_random_uuid(),
  character_id   uuid references characters(id) on delete set null,
  character_name text not null,               -- chụp lại tên lúc xảy ra
  kind           text not null check (kind in ('boss_kill', 'legendary_item', 'title', 'tower', 'gacha_jackpot')),
  character_title text,                       -- danh hiệu đang đeo lúc đăng
  payload        jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default clock_timestamp()  -- giờ thực, không phải giờ bắt đầu transaction
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

revoke execute on function public.post_activity(uuid, text, jsonb) from public, anon, authenticated;

-- 2. Hiệu ứng Huyền Thoại ------------------------------------------------------
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

-- Thứ tự tier: common < rare < epic < legendary
create or replace function public.rarity_rank(p_rarity text)
returns int
language sql
immutable
as $$
  select case p_rarity when 'legendary' then 3 when 'epic' then 2 when 'rare' then 1 else 0 end;
$$;

-- Hệ số nhân chỉ số gốc (bonus_atk/def/hp của items) theo tier của từng món
create or replace function public.rarity_multiplier(p_rarity text)
returns numeric
language sql
immutable
as $$
  select case p_rarity when 'legendary' then 1.8 when 'epic' then 1.6 when 'rare' then 1.25 else 1.0 end;
$$;

-- Quay tier cho 1 món trang bị. p_table: 'normal' (quái thường), 'boss',
-- 'craft', 'craft_boost' (bỏ gấp đôi vàng). Không bao giờ thấp hơn tier gốc
-- của loại đồ (p_floor = items.rarity), vd. đồ boss rare không ra common.
create or replace function public.roll_rarity(p_floor text, p_table text)
returns text
language plpgsql
volatile
as $$
declare
  v_roll numeric := random();
  v_rarity text;
begin
  -- Ngưỡng cộng dồn [legendary, epic, rare] — phần còn lại là common
  v_rarity := case p_table
    when 'boss' then        case when v_roll < 0.05 then 'legendary' when v_roll < 0.25 then 'epic' when v_roll < 0.60 then 'rare' else 'common' end
    when 'craft' then       case when v_roll < 0.02 then 'legendary' when v_roll < 0.12 then 'epic' when v_roll < 0.40 then 'rare' else 'common' end
    when 'craft_boost' then case when v_roll < 0.05 then 'legendary' when v_roll < 0.25 then 'epic' when v_roll < 0.65 then 'rare' else 'common' end
    else                    case when v_roll < 0.01 then 'legendary' when v_roll < 0.08 then 'epic' when v_roll < 0.30 then 'rare' else 'common' end
  end;

  if rarity_rank(v_rarity) < rarity_rank(coalesce(p_floor, 'common')) then
    v_rarity := p_floor;
  end if;

  return v_rarity;
end;
$$;

-- Tạo 1 món trang bị với tier cho trước: affix roll theo tier + phần chỉ số
-- gốc được nhân theo tier cộng thẳng vào rolled_* — nhờ vậy mọi chỗ đang
-- tính "bonus_* + rolled_*" (get_character_stats, combat, túi đồ) tự đúng.
create or replace function public.create_equipment(p_character_id uuid, p_item_id uuid, p_rarity text)
returns void
language plpgsql
set search_path = 'public'
as $$
declare
  v_slot text; v_school text; v_bonus_atk int; v_bonus_def int; v_bonus_hp int;
  v_mult numeric := rarity_multiplier(p_rarity);
  v_roll_atk int; v_roll_def int; v_roll_hp int; v_roll_crit numeric; v_roll_lifesteal numeric;
  v_roll_extra jsonb; v_utility int;
  v_effect text;
  v_item_name text; v_item_key text; v_item_icon text;
begin
  select i.slot, coalesce(i.school, 'physical'), i.bonus_atk, i.bonus_def, i.bonus_hp
    into v_slot, v_school, v_bonus_atk, v_bonus_def, v_bonus_hp
  from items i where i.id = p_item_id;

  select a.roll_atk, a.roll_def, a.roll_hp, a.roll_crit, a.roll_lifesteal, a.roll_extra
    into v_roll_atk, v_roll_def, v_roll_hp, v_roll_crit, v_roll_lifesteal, v_roll_extra
  from roll_item_affixes(v_slot, v_school, p_rarity) a;

  -- Ngân sách sức mạnh: mỗi dòng tiện ích trừ 8% chỉ số gốc của món
  select count(*) into v_utility from jsonb_object_keys(v_roll_extra);
  v_mult := v_mult - 0.08 * v_utility;

  if p_rarity = 'legendary' then
    v_effect := roll_legendary_effect();
  end if;

  insert into inventory (character_id, item_id, quantity, rarity, legendary_effect, rolled_atk, rolled_def, rolled_hp, rolled_crit, rolled_lifesteal, rolled_extra)
  values (
    p_character_id, p_item_id, 1, p_rarity, v_effect,
    v_roll_atk + round(v_bonus_atk * (v_mult - 1)),
    v_roll_def + round(v_bonus_def * (v_mult - 1)),
    v_roll_hp + round(v_bonus_hp * (v_mult - 1)),
    v_roll_crit, v_roll_lifesteal, v_roll_extra
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

revoke execute on function public.create_equipment(uuid, uuid, text) from public, anon, authenticated;

-- Thêm 1 món đồ rơi vào túi. Trang bị: quay tier (bảng boss nếu p_is_boss)
-- rồi tạo dòng mới. Vật phẩm tiêu hao/nguyên liệu: gộp chồng, giữ tier gốc.
-- Trả về tier thực tế của món vừa nhận.
create or replace function public.grant_drop(p_character_id uuid, p_item_id uuid, p_is_boss boolean default false)
returns text
language plpgsql
set search_path = 'public'
as $$
declare
  v_type text; v_base_rarity text; v_rarity text;
  v_inventory_id uuid;
begin
  select i.type, i.rarity into v_type, v_base_rarity from items i where i.id = p_item_id;

  if v_type in ('weapon', 'armor') then
    v_rarity := roll_rarity(v_base_rarity, case when p_is_boss then 'boss' else 'normal' end);
    perform create_equipment(p_character_id, p_item_id, v_rarity);
    return v_rarity;
  end if;

  select inv.id into v_inventory_id
  from inventory inv where inv.character_id = p_character_id and inv.item_id = p_item_id
  limit 1 for update;

  if v_inventory_id is null then
    insert into inventory (character_id, item_id, quantity) values (p_character_id, p_item_id, 1);
  else
    update inventory set quantity = quantity + 1 where id = v_inventory_id;
  end if;

  return v_base_rarity;
end;
$$;
revoke execute on function public.grant_drop(uuid, uuid, boolean) from public, anon, authenticated;

-- Mô phỏng một lượt đánh dungeon: khóa nhân vật, tính sát thương theo lượt,
-- trừ AP, cộng thưởng nếu thắng, ghi nhận dungeon_runs. Trả về log trận đấu.
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

-- ============================================================================
-- Market (mua bình máu bằng vàng) + dùng vật phẩm hồi máu
-- HP hiện chỉ thay đổi như tác dụng phụ của resolve_dungeon_floor — không có
-- cách nào khác để hồi máu ngoài dungeon. buy_item/use_item đi qua RPC
-- security definer, theo đúng khuyến nghị ở phần "Ghi chú" bên dưới, để
-- tránh người chơi tự sửa gold/HP qua console trình duyệt.
-- ============================================================================

insert into items (key, name, type, rarity, heal_amount, buy_price, sell_price, description) values
  ('potion_minor', 'Bình Máu Nhỏ', 'consumable', 'common', 50, 20, 5, 'Hồi ngay 50 HP'),
  ('potion_medium', 'Bình Máu Vừa', 'consumable', 'rare', 120, 45, 12, 'Hồi ngay 120 HP'),
  ('potion_large', 'Bình Máu Lớn', 'consumable', 'epic', 300, 100, 30, 'Hồi ngay 300 HP')
on conflict (key) do nothing;

-- Bình hồi AP — gold sink thật: cùng giá potion_large (100 vàng) để người
-- chơi cân nhắc dùng vàng thay vì chỉ đợi AP tự hồi, tránh vàng ứ đọng.
insert into items (key, name, type, rarity, restore_ap, buy_price, sell_price, description, icon) values
  ('potion_ap_large', 'Bình Hồi AP Lớn', 'consumable', 'epic', 40, 100, 30, 'Hồi ngay 40 AP', 'potion_ap_large.png')
on conflict (key) do nothing;

-- Icon pixel-art (Raven Fantasy Icons pack, /public/items/*.png) cho toàn bộ
-- item hiện có — trước đó danh sách item chỉ hiện text, không có ảnh.
update items set icon = 'sword_starter.png' where key = 'sword_starter';
update items set icon = 'bow_starter.png' where key = 'bow_starter';
update items set icon = 'daggers_starter.png' where key = 'daggers_starter';
update items set icon = 'staff_starter.png' where key = 'staff_starter';
update items set icon = 'forest_blade.png' where key = 'forest_blade';
update items set icon = 'frost_blade.png' where key = 'frost_blade';
update items set icon = 'cursed_dagger.png' where key = 'cursed_dagger';
update items set icon = 'fortress_greatsword.png' where key = 'fortress_greatsword';
update items set icon = 'voidforged_blade.png' where key = 'voidforged_blade';
update items set icon = 'leather_armor.png' where key = 'leather_armor';
update items set icon = 'potion_minor.png' where key = 'potion_minor';
update items set icon = 'potion_medium.png' where key = 'potion_medium';
update items set icon = 'potion_large.png' where key = 'potion_large';
update items set icon = 'wolf_fang.png' where key = 'wolf_fang';
update items set icon = 'ice_shard.png' where key = 'ice_shard';
update items set icon = 'swamp_venom.png' where key = 'swamp_venom';
update items set icon = 'shadow_ore.png' where key = 'shadow_ore';
update items set icon = 'void_shard.png' where key = 'void_shard';

-- Item đầu tiên cho 5/6 khớp trang bị mới (head/boot/ring/amulet/shield) —
-- Thắt lưng vẫn chưa có icon phù hợp trong pack, để trống thay vì gán tạm.
insert into items (key, name, type, slot, hand, rarity, bonus_atk, bonus_def, bonus_hp, buy_price, sell_price, description, icon) values
  ('iron_helmet', 'Nón Sắt Cũ', 'armor', 'head', null, 'common', 0, 2, 5, 30, 10, 'Mũ sắt cơ bản, bảo vệ phần đầu.', 'iron_helmet.png'),
  ('traveler_boots', 'Giày Da Lữ Hành', 'armor', 'boot', null, 'common', 0, 1, 5, 25, 8, 'Đôi giày bền bỉ cho hành trình dài.', 'traveler_boots.png'),
  ('ring_ruby', 'Nhẫn Bạc Đá Đỏ', 'armor', 'ring', null, 'common', 2, 0, 0, 35, 10, 'Chiếc nhẫn bạc khảm đá đỏ, tăng nhẹ sức mạnh.', 'ring_ruby.png'),
  ('guardian_amulet', 'Bùa Hộ Mệnh', 'armor', 'amulet', null, 'common', 0, 0, 15, 40, 12, 'Bùa chú cổ xưa, gia tăng sinh lực.', 'guardian_amulet.png'),
  ('iron_shield', 'Khiên Gỗ Bọc Sắt', 'armor', 'shield', 'one_hand', 'common', 0, 4, 0, 45, 15, 'Khiên gỗ chắc chắn, bọc viền sắt.', 'iron_shield.png')
on conflict (key) do nothing;

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
  v_item_type text;
  v_level int; v_per_level int; v_limit int; v_listed boolean; v_bought int;
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

  select buy_price, type, price_per_level, daily_limit, shop_listed
    into v_buy_price, v_item_type, v_per_level, v_limit, v_listed
  from items where id = p_item_id;
  select c.level into v_level from characters c where c.id = p_character_id;

  if v_buy_price is null or not v_listed then
    raise exception 'Vật phẩm này không bán trong chợ';
  end if;

  -- Giá tăng theo cấp; món có giới hạn ngày thì đếm theo ngày giờ VN
  v_buy_price := v_buy_price + v_per_level * v_level;
  if v_limit is not null then
    select coalesce(sum(sd.qty), 0) into v_bought from shop_daily sd
    where sd.character_id = p_character_id and sd.item_id = p_item_id and sd.day = vn_today();
    if v_bought + p_quantity > v_limit then
      raise exception 'Hôm nay chỉ được mua tối đa % món này (đã mua %)', v_limit, v_bought;
    end if;
    insert into shop_daily (character_id, item_id, day, qty) values (p_character_id, p_item_id, vn_today(), p_quantity)
    on conflict (character_id, item_id, day) do update set qty = shop_daily.qty + excluded.qty;
  end if;

  v_total_cost := v_buy_price * p_quantity;

  if v_gold < v_total_cost then
    raise exception 'Không đủ vàng (cần % vàng)', v_total_cost;
  end if;

  update characters set gold = gold - v_total_cost where id = p_character_id;

  -- Vũ khí/giáp không gộp chồng khi mua (mỗi món 1 dòng riêng), nhất quán
  -- với đồ rơi (luôn tạo dòng mới) — tránh mua thêm 1 bản "vanilla" đè gộp
  -- số lượng lên dòng đã có affix roll từ trước, và giữ đúng equip_slot
  -- theo từng dòng khi mặc nhiều bản cùng key vào các khớp khác nhau.
  if v_item_type in ('weapon', 'armor') then
    insert into inventory (character_id, item_id, quantity)
    values (p_character_id, p_item_id, p_quantity)
    returning quantity into v_new_quantity;
  else
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
  end if;

  return query select (v_gold - v_total_cost), v_new_quantity;
end;
$$;

-- ============================================================================
-- BÁN ĐỒ
-- ============================================================================

-- Giá bán 1 dòng túi đồ (cả chồng). Trang bị có tier riêng (rơi/chế tạo/gacha)
-- bán ×1.5 cho mỗi bậc tier trên tier gốc của loại đồ; đồ mua ở chợ
-- (inventory.rarity null) và vật phẩm gộp chồng bán đúng items.sell_price —
-- để không thể mua ở chợ rồi bán lại có lời.
create or replace function public.inventory_sell_price(p_sell_price int, p_item_rarity text, p_row_rarity text, p_quantity int)
returns int
language sql
immutable
as $$
  select round(greatest(0, p_sell_price)
          * power(1.5, greatest(0, rarity_rank(coalesce(p_row_rarity, p_item_rarity)) - rarity_rank(p_item_rarity)))
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
  v_heal_pct numeric; v_buff text;
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

  select type, heal_amount, restore_ap, heal_pct, buff_key into v_type, v_heal_amount, v_restore_ap, v_heal_pct, v_buff
  from items where id = v_item_id;

  -- Bình theo % HP: lấy mức lớn hơn giữa số cố định và % HP tối đa
  v_heal_amount := greatest(coalesce(v_heal_amount, 0), round(v_max_hp * coalesce(v_heal_pct, 0))::int);

  if v_type is distinct from 'consumable'
     or (v_heal_amount <= 0 and coalesce(v_restore_ap, 0) <= 0 and v_buff is null) then
    raise exception 'Vật phẩm này không thể sử dụng';
  end if;

  -- Cuộn / bùa: chờ áp vào chuyến khám phá hoặc lần leo tháp kế tiếp
  if v_buff is not null then
    if exists (select 1 from character_buffs b where b.character_id = p_character_id and b.buff_key = v_buff) then
      raise exception 'Đã có một cuộn/bùa loại này đang chờ dùng';
    end if;
    insert into character_buffs (character_id, buff_key) values (p_character_id, v_buff);
  end if;

  v_new_hp := v_current_hp;
  v_new_ap := v_current_ap;

  if v_buff is null and v_heal_amount > 0 then
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

-- ============================================================================
-- Crafting: chế tạo từ nguyên liệu, có % thất bại (mất hết nguyên liệu đã bỏ
-- vào nếu thất bại). Nguyên liệu (wolf_fang, ice_shard, swamp_venom,
-- shadow_ore, void_shard) vốn đã rơi từ dungeon tương ứng nhưng chưa có tác
-- dụng gì — các recipe dưới đây cho phép chế các vũ khí boss-drop đã có sẵn
-- (forest_blade, frost_blade, cursed_dagger, fortress_greatsword,
-- voidforged_blade) như một con đường thay thế ngoài may rủi drop_rate của
-- boss. Kết quả chế tạo luôn ra đúng stat gốc của item (không roll affix) —
-- chỉ đồ rơi từ combat mới roll ngẫu nhiên.
-- ============================================================================

create table recipes (
  id             uuid primary key default gen_random_uuid(),
  key            text unique not null,
  name           text not null,
  result_item_id uuid not null references items(id),
  result_quantity int not null default 1,
  gold_cost      int not null default 0,
  success_rate   numeric not null default 0.5,  -- 0..1
  description    text
);

create table recipe_ingredients (
  id         uuid primary key default gen_random_uuid(),
  recipe_id  uuid not null references recipes(id) on delete cascade,
  item_id    uuid not null references items(id),
  quantity   int not null default 1,
  unique (recipe_id, item_id)
);

alter table recipes enable row level security;
alter table recipe_ingredients enable row level security;
grant select on table recipes, recipe_ingredients to anon, authenticated;
create policy "public read recipes" on recipes for select using (true);
create policy "public read recipe_ingredients" on recipe_ingredients for select using (true);

insert into recipes (key, name, result_item_id, gold_cost, success_rate, description) values
  ('craft_forest_blade', 'Chế Kiếm Rừng Cổ', (select id from items where key = 'forest_blade'), 0, 0.7, 'Cần 5 Nanh Sói'),
  ('craft_frost_blade', 'Chế Kiếm Băng Giá', (select id from items where key = 'frost_blade'), 0, 0.65, 'Cần 5 Mảnh Băng Vĩnh Cửu'),
  ('craft_cursed_dagger', 'Chế Đoản Đao Nguyền Rủa', (select id from items where key = 'cursed_dagger'), 0, 0.5, 'Cần 5 Nọc Độc Đầm Lầy'),
  ('craft_fortress_greatsword', 'Chế Đại Kiếm Pháo Đài', (select id from items where key = 'fortress_greatsword'), 0, 0.4, 'Cần 5 Quặng Bóng Tối'),
  ('craft_voidforged_blade', 'Chế Thần Kiếm Hư Không', (select id from items where key = 'voidforged_blade'), 100, 0.2, 'Cần 5 Mảnh Vỡ Hư Không + 3 Quặng Bóng Tối')
on conflict (key) do nothing;

insert into recipe_ingredients (recipe_id, item_id, quantity)
select r.id, i.id, ing.qty
from (values
  ('craft_forest_blade', 'wolf_fang', 5),
  ('craft_frost_blade', 'ice_shard', 5),
  ('craft_cursed_dagger', 'swamp_venom', 5),
  ('craft_fortress_greatsword', 'shadow_ore', 5),
  ('craft_voidforged_blade', 'void_shard', 5),
  ('craft_voidforged_blade', 'shadow_ore', 3)
) as ing(recipe_key, item_key, qty)
join recipes r on r.key = ing.recipe_key
join items i on i.key = ing.item_key
on conflict (recipe_id, item_id) do nothing;

create or replace function public.craft_item(p_character_id uuid, p_recipe_id uuid, p_boost boolean default false)
returns table(success boolean, result_name text, new_gold int, result_rarity text)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_gold int;
  v_result_item_id uuid; v_result_qty int; v_gold_cost int; v_success_rate numeric;
  v_result_type text;
  v_ing record;
  v_have int;
  v_success boolean;
  v_result_name text;
  v_existing_id uuid; v_existing_qty int;
  v_result_rarity text;
begin
  select user_id, gold into v_owner_user_id, v_gold
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  select result_item_id, result_quantity, gold_cost, success_rate
    into v_result_item_id, v_result_qty, v_gold_cost, v_success_rate
  from recipes where id = p_recipe_id;

  if not found then raise exception 'Không tìm thấy công thức'; end if;

  -- Tăng tỉ lệ tier cao: tốn gấp đôi vàng (tối thiểu 50 nếu công thức miễn phí)
  if p_boost then
    v_gold_cost := greatest(50, v_gold_cost * 2);
  end if;

  if v_gold < v_gold_cost then
    raise exception 'Không đủ vàng (cần % vàng)', v_gold_cost;
  end if;

  -- Kiểm tra đủ nguyên liệu trước khi trừ bất cứ gì
  for v_ing in
    select ri.item_id, ri.quantity as needed from recipe_ingredients ri where ri.recipe_id = p_recipe_id
  loop
    select coalesce(sum(quantity), 0) into v_have
    from inventory where character_id = p_character_id and item_id = v_ing.item_id;

    if v_have < v_ing.needed then
      raise exception 'Thiếu nguyên liệu để chế tạo';
    end if;
  end loop;

  -- Trừ nguyên liệu — luôn trừ dù thành công hay thất bại (rủi ro thật)
  for v_ing in
    select ri.item_id, ri.quantity as needed from recipe_ingredients ri where ri.recipe_id = p_recipe_id
  loop
    declare
      v_remaining int := v_ing.needed;
      v_row record;
    begin
      for v_row in
        select id, quantity from inventory
        where character_id = p_character_id and item_id = v_ing.item_id
        order by acquired_at
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
  end loop;

  update characters set gold = gold - v_gold_cost where id = p_character_id;

  v_success := random() < v_success_rate;

  if v_success then
    select type into v_result_type from items where id = v_result_item_id;

    if v_result_type in ('weapon', 'armor') then
      select i.rarity into v_result_rarity from items i where i.id = v_result_item_id;
      v_result_rarity := roll_rarity(v_result_rarity, case when p_boost then 'craft_boost' else 'craft' end);
      for v_n in 1..v_result_qty loop
        perform create_equipment(p_character_id, v_result_item_id, v_result_rarity);
      end loop;
    else
      select id, quantity into v_existing_id, v_existing_qty
      from inventory where character_id = p_character_id and item_id = v_result_item_id
      for update;

      if v_existing_id is null then
        insert into inventory (character_id, item_id, quantity) values (p_character_id, v_result_item_id, v_result_qty);
      else
        update inventory set quantity = quantity + v_result_qty where id = v_existing_id;
      end if;
    end if;

    select name into v_result_name from items where id = v_result_item_id;
  end if;

  return query select v_success, v_result_name, (v_gold - v_gold_cost), v_result_rarity;
end;
$$;

-- ============================================================================
-- Trang bị đầy đủ: head/chest/belt/amulet/boot + 2 khớp tay riêng (l_arm/
-- r_arm) cho vũ khí/khiên. Vũ khí 2 tay (ví dụ trượng của pháp sư) chiếm cả
-- hai khớp tay cùng lúc và không thể mặc thêm khiên/vũ khí khác cho đến khi
-- gỡ ra. Trang bị/gỡ đi qua RPC equip_item / unequip_item (xem phần CHỐNG
-- CHEAT) — server kiểm tra khớp hợp lệ.
-- ============================================================================

update items set slot = 'chest' where slot = 'body';
update items set hand = 'one_hand' where type = 'weapon' and hand is null;
update items set hand = 'two_hand' where key = 'staff_starter';

update inventory inv
set equip_slot = case
  when it.slot = 'weapon' then 'l_arm'
  else it.slot
end
from items it
where inv.item_id = it.id and inv.equipped = true and inv.equip_slot is null;

-- ============================================================================
-- CHẶN CLIENT SỬA TRẠNG THÁI GAME (gold / level / exp / HP / AP ...)
-- RLS "own characters update" cho phép update cả dòng; trigger này chỉ cho
-- 'authenticated'/'anon' đổi name + auto_allocate_stats, và ép mặc định khi
-- INSERT. RPC security definer chạy dưới quyền owner nên không bị chặn.
-- ============================================================================

create or replace function public.guard_character_game_state()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.level := 1;
      new.exp := 0;
      new.exp_to_next := 250;
      new.gold := 100;
      new.current_chapter := 1;
      new.current_hp := null;
      new.current_ap := 100;
      new.max_ap := 100;
      new.ap_regen_minutes := 1;
      new.last_ap_update := now();
      new.last_hp_update := now();
      new.created_at := now();
    elsif (to_jsonb(new) - 'name' - 'auto_allocate_stats' - 'portrait' - 'frame' - 'auto_potion')
          is distinct from
          (to_jsonb(old) - 'name' - 'auto_allocate_stats' - 'portrait' - 'frame' - 'auto_potion') then
      raise exception 'Chỉ được đổi tên, chân dung, khung và chế độ tự cộng điểm; chỉ số nhân vật chỉ thay đổi qua hành động trong game';
    elsif new.frame is distinct from old.frame and new.frame is not null
          and not frame_unlocked(new.frame, new.level, new.tower_best, new.legendary_found, new.boss_kills) then
      raise exception 'Chưa mở khóa khung này';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_character_game_state on characters;
create trigger guard_character_game_state
  before insert or update on characters
  for each row execute function public.guard_character_game_state();

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

-- Trả AP/HP sau khi hồi cho các trang hiển thị.
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

-- ============================================================================
-- CHỐNG CHEAT: client chỉ ghi trực tiếp được characters (tên / auto_allocate_stats,
-- xem guard_character_game_state) và character_equipped_skills (có trigger kiểm).
-- Mọi thay đổi inventory / dungeon_runs / pets / quests đi qua RPC security definer.
-- resolve_dungeon_floor kiểm tra tầng đã mở khóa.
-- ============================================================================

-- 1. add_experience ------------------------------------------------------------
revoke execute on function public.add_experience(uuid, int) from public, anon, authenticated;

-- 2 + 3. Bỏ quyền ghi trực tiếp -------------------------------------------------

revoke insert, update, delete on table inventory, dungeon_runs, character_pets, character_quests
  from anon, authenticated;

-- Khớp trang bị hợp lệ cho từng loại item (dùng chung cho equip_item và dọn dữ liệu).
create or replace function public.equip_slot_allowed(p_item_slot text, p_hand text, p_equip_slot text)
returns boolean
language sql
immutable
as $$
  select case
    when p_item_slot in ('weapon', 'shield') then
      case when p_hand = 'two_hand' then p_equip_slot = 'both_arms'
           else p_equip_slot in ('l_arm', 'r_arm') end
    when p_item_slot = 'ring' then p_equip_slot in ('ring_1', 'ring_2')
    when p_item_slot in ('head', 'chest', 'belt', 'amulet', 'boot') then p_equip_slot = p_item_slot
    else false
  end;
$$;

-- Mặc 1 món vào khớp p_slot, tự gỡ món đang chiếm khớp đó (vũ khí 2 tay chiếm
-- cả l_arm lẫn r_arm). Trả về id các dòng vừa bị gỡ để client cập nhật UI.
create or replace function public.equip_item(p_character_id uuid, p_inventory_id uuid, p_slot text)
returns uuid[]
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_item_slot text; v_item_hand text; v_item_type text;
  v_clear text[];
  v_unequipped uuid[];
begin
  select c.user_id into v_owner_user_id
  from characters c where c.id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  select i.slot, i.hand, i.type into v_item_slot, v_item_hand, v_item_type
  from inventory inv join items i on i.id = inv.item_id
  where inv.id = p_inventory_id and inv.character_id = p_character_id
  for update of inv;

  if not found then raise exception 'Không tìm thấy vật phẩm trong túi đồ'; end if;

  if v_item_type not in ('weapon', 'armor')
     or not equip_slot_allowed(v_item_slot, v_item_hand, p_slot) then
    raise exception 'Không thể mặc vật phẩm này vào vị trí đó';
  end if;

  v_clear := case
    when p_slot = 'both_arms' then array['l_arm', 'r_arm', 'both_arms']
    when p_slot in ('l_arm', 'r_arm') then array[p_slot, 'both_arms']
    else array[p_slot]
  end;

  with cleared as (
    update inventory inv
    set equipped = false, equip_slot = null
    where inv.character_id = p_character_id and inv.equipped
      and inv.equip_slot = any(v_clear) and inv.id <> p_inventory_id
    returning inv.id
  )
  select coalesce(array_agg(cleared.id), '{}') into v_unequipped from cleared;

  update inventory inv
  set equipped = true, equip_slot = p_slot
  where inv.id = p_inventory_id;

  return v_unequipped;
end;
$$;

create or replace function public.unequip_item(p_character_id uuid, p_inventory_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
begin
  select c.user_id into v_owner_user_id from characters c where c.id = p_character_id;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  update inventory inv
  set equipped = false, equip_slot = null
  where inv.id = p_inventory_id and inv.character_id = p_character_id;

  if not found then raise exception 'Không tìm thấy vật phẩm trong túi đồ'; end if;
end;
$$;

-- 5. Skill trang bị: đúng class, đủ cấp, không trùng, tối đa 2 chủ động + 1 bị động.
-- security definer để khóa được dòng characters (tránh 2 request song song cùng
-- vượt giới hạn); quyền sở hữu nhân vật đã do RLS "own equipped skills insert" kiểm.
create or replace function public.guard_equipped_skill()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_class_id uuid; v_level int;
  v_skill_class_id uuid; v_unlock_level int; v_skill_type text;
  v_count int; v_limit int;
begin
  select c.class_id, c.level into v_class_id, v_level
  from characters c where c.id = new.character_id for update;

  select s.class_id, s.unlock_level, s.skill_type into v_skill_class_id, v_unlock_level, v_skill_type
  from skills s where s.id = new.skill_id;

  if v_skill_class_id is distinct from v_class_id then
    raise exception 'Kỹ năng này không thuộc class của bạn';
  end if;

  if v_level < v_unlock_level then
    raise exception 'Cần đạt cấp % để dùng kỹ năng này', v_unlock_level;
  end if;

  if exists (
    select 1 from character_equipped_skills ces
    where ces.character_id = new.character_id and ces.skill_id = new.skill_id
  ) then
    raise exception 'Kỹ năng đã được trang bị';
  end if;

  select count(*) into v_count
  from character_equipped_skills ces join skills s on s.id = ces.skill_id
  where ces.character_id = new.character_id and s.skill_type = v_skill_type;

  -- Ô chủ động thứ 2 mở ở cấp 8 (ô bị động mở cùng skill bị động đầu tiên, cấp 5)
  v_limit := case when v_skill_type = 'passive' then 1 when v_level >= 8 then 2 else 1 end;

  if v_count >= v_limit then
    raise exception 'Đã đủ số kỹ năng % được trang bị', v_skill_type;
  end if;

  return new;
end;
$$;

drop trigger if exists guard_equipped_skill on character_equipped_skills;
create trigger guard_equipped_skill
  before insert on character_equipped_skills
  for each row execute function public.guard_equipped_skill();

revoke update on table character_equipped_skills from anon, authenticated;

-- Tên nhân vật: 1-20 ký tự như form tạo nhân vật (not valid: không kiểm dữ liệu cũ).
alter table characters drop constraint if exists characters_name_length;
alter table characters
  add constraint characters_name_length check (char_length(btrim(name)) between 1 and 20) not valid;

-- ============================================================================
-- Ghi chú:
-- - Các thao tác nhạy cảm (trừ AP, mua bán, nhận thưởng dungeon/quest) đi qua
--   RPC security definer; trigger guard_character_game_state chặn client tự
--   sửa gold/exp/level/HP/AP của characters qua console trình duyệt.
-- - RLS ở trên chỉ chặn việc đọc/ghi TRỰC TIẾP từ client bằng anon key.
-- ============================================================================

-- ============================================================================
-- EXPLORE THEO VÙNG
-- Chọn vùng + số lượt (1-100). AP trừ 1 lần như vé vào vùng; HP giữ nguyên
-- qua các trận, dừng khi đủ lượt hoặc hết HP (chỉ nhận thưởng các trận đã
-- thắng trước đó). Level vùng chỉ để cảnh báo, không khóa.
-- ============================================================================

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
  sort_order  int not null default 0,
  traits      text[] not null default '{}'     -- đặc tính quái của vùng (ENEMY_TRAITS, lib/enemies.ts)
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

-- Project không tự cấp quyền cho bảng mới → phải grant tường minh, nếu không
-- PostgREST không đọc được dù RLS policy đúng.
grant select on table zones, zone_enemies, zone_drops to anon, authenticated;
grant select on table explore_runs to authenticated;

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

    if v_win then
      v_wins := v_wins + 1;
      if v_is_boss then v_boss_wins := v_boss_wins + 1; end if;

      if v_is_boss then
        perform post_activity(p_character_id, 'boss_kill', jsonb_build_object(
          'boss', v_enemy.name, 'where', v_zone.icon || ' ' || v_zone.name, 'source', 'explore'
        ));
      end if;
      v_fight_exp := round(v_enemy.reward_exp * v_reward_mult * v_exp_multiplier * case when v_buff_exp then 1.25 else 1 end);
      v_fight_gold := round(v_enemy.reward_gold * v_reward_mult * v_exp_multiplier);
      v_exp_gained := v_exp_gained + v_fight_exp;
      v_gold_gained := v_gold_gained + v_fight_gold;

      for v_drop in
        select zd.item_id, zd.drop_rate, i.key
        from zone_drops zd join items i on i.id = zd.item_id
        where zd.zone_id = p_zone_id and (not zd.boss_only or v_is_boss)
      loop
        continue when random() >= v_drop.drop_rate * v_drop_mult * case when v_buff_luck then 1.3 else 1 end;
        -- Hung Thần tung độ hiếm trang bị như boss
        v_drop_rarity := grant_drop(p_character_id, v_drop.item_id, v_is_boss or v_tier = 'champion');
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
      'drops', v_fight_drops
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
    'buffs', jsonb_build_object('exp', v_buff_exp, 'luck', v_buff_luck)
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
  ('rung_xanh', 'Rắn Cỏ', 2, 30, false),
  ('rung_xanh', 'Sói Rừng', 4, 20, false),
  ('rung_xanh', 'Yêu Tinh Rừng', 5, 10, false),
  ('rung_xanh', 'Tinh Linh Cổ Thụ', 6, 1, true),
  ('dong_bang', 'Sâu Đồng', 3, 40, false),
  ('dong_bang', 'Bù Nhìn Ma', 5, 30, false),
  ('dong_bang', 'Lợn Rừng', 7, 20, false),
  ('dong_bang', 'Ong Bắp Cày', 8, 10, false),
  ('dong_bang', 'Vua Châu Chấu', 9, 1, true),
  ('hang_dong', 'Bọ Giáp Hang', 6, 40, false),
  ('hang_dong', 'Goblin Thợ Mỏ', 8, 30, false),
  ('hang_dong', 'Nhện Hang', 10, 20, false),
  ('hang_dong', 'Orc', 12, 10, false),
  ('hang_dong', 'Ancient Golem', 13, 1, true),
  ('nui_tuyet', 'Sói Tuyết', 10, 40, false),
  ('nui_tuyet', 'Hồn Ma Băng', 13, 30, false),
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

-- ============================================================================
-- EXPLORE: 7 VÙNG LV 15-80 + TRANG BỊ MỚI
-- ============================================================================

-- 1. Trang bị + nguyên liệu mới --------------------------------------------------
insert into items (key, name, type, slot, hand, school, rarity, bonus_atk, bonus_def, bonus_hp, heal_amount, buy_price, sell_price, description, icon) values
  -- Sa Mạc (Lv 15-25)
  ('sand_scarab',       'Bọ Hung Cát',           'material', null,     null,       null,       'common',     0,  0,   0,   0, null,  35, 'Vỏ bọ hung vàng óng từ sa mạc.', 'sand_scarab.png'),
  ('desert_turban',     'Khăn Quấn Sa Mạc',      'armor',    'head',   null,       null,       'common',     0,  7,  40,   0, null,  40, 'Che nắng gió cát, bền bỉ.', 'desert_turban.png'),
  ('sandstrider_boots', 'Giày Lướt Cát',         'armor',    'boot',   null,       null,       'common',     0,  5,  30,   0, null,  40, 'Không lún dù đi trên cát lún.', 'sandstrider_boots.png'),
  ('pharaoh_scepter',   'Quyền Trượng Pharaoh',  'weapon',   'weapon', 'two_hand', 'magic',    'rare',      24,  0,   0,   0, null, 150, 'Quyền trượng của vị vua bất tử.', 'pharaoh_scepter.png'),
  -- Núi Lửa (Lv 22-32)
  ('magma_core',        'Lõi Dung Nham',         'material', null,     null,       null,       'common',     0,  0,   0,   0, null,  45, 'Vẫn còn nóng bỏng tay.', 'magma_core.png'),
  ('obsidian_shield',   'Khiên Hắc Diện Thạch',  'armor',    'shield', 'one_hand', null,       'common',     0, 14,  20,   0, null,  50, 'Đá núi lửa nguội, cứng như thép.', 'obsidian_shield.png'),
  ('ember_amulet',      'Bùa Than Hồng',         'armor',    'amulet', null,       null,       'common',     6,  0,  60,   0, null,  50, 'Ngọn lửa nhỏ không bao giờ tắt.', 'ember_amulet.png'),
  ('inferno_greataxe',  'Rìu Luyện Ngục',        'weapon',   'weapon', 'two_hand', 'physical', 'rare',      36,  0,   0,   0, null, 220, 'Rèn trong miệng núi lửa.', 'inferno_greataxe.png'),
  -- Vực Tối (Lv 30-42)
  ('shadow_essence',    'Tinh Chất Bóng Đêm',    'material', null,     null,       null,       'common',     0,  0,   0,   0, null,  60, 'Bóng tối cô đặc thành tinh thể.', 'shadow_essence.png'),
  ('shadow_cloak',      'Áo Choàng Bóng Đêm',    'armor',    'chest',  null,       null,       'common',     0, 16,  90,   0, null,  70, 'Hòa lẫn vào bóng tối.', 'shadow_cloak.png'),
  ('bone_ring',         'Nhẫn Xương',            'armor',    'ring',   null,       null,       'common',     9,  0,  20,   0, null,  70, 'Tạc từ xương của hiệp sĩ cổ.', 'bone_ring.png'),
  ('nightfall_bow',     'Cung Hoàng Hôn',        'weapon',   'weapon', 'one_hand', 'physical', 'epic',      40,  0,   0,   0, null, 320, 'Mũi tên bắn ra như màn đêm buông xuống.', 'nightfall_bow.png'),
  -- Thánh Địa (Lv 40-55)
  ('holy_relic',        'Thánh Tích',            'material', null,     null,       null,       'common',     0,  0,   0,   0, null,  80, 'Mảnh vỡ từ đền thờ cổ.', 'holy_relic.png'),
  ('paladin_helm',      'Mũ Hiệp Sĩ Thánh',      'armor',    'head',   null,       null,       'common',     0, 20, 120,   0, null,  90, 'Được ban phước bởi ánh sáng.', 'paladin_helm.png'),
  ('radiant_belt',      'Đai Rạng Ngời',         'armor',    'belt',   null,       null,       'common',     0, 14, 140,   0, null,  90, 'Tỏa sáng dịu nhẹ trong bóng tối.', 'radiant_belt.png'),
  ('judgement_staff',   'Trượng Phán Xét',       'weapon',   'weapon', 'two_hand', 'magic',    'epic',      55,  0,   0,   0, null, 450, 'Phán xét kẻ có tội bằng ánh sáng.', 'judgement_staff.png'),
  -- Hư Không (Lv 52-65)
  ('void_crystal',      'Pha Lê Hư Không',       'material', null,     null,       null,       'common',     0,  0,   0,   0, null, 100, 'Phản chiếu một vũ trụ khác.', 'void_crystal.png'),
  ('voidwalker_boots',  'Giày Lữ Khách Hư Không', 'armor',   'boot',   null,       null,       'common',     0, 22, 150,   0, null, 120, 'Bước đi giữa các vì sao.', 'voidwalker_boots.png'),
  ('star_ring',         'Nhẫn Tinh Tú',          'armor',    'ring',   null,       null,       'common',    16,  0,  60,   0, null, 120, 'Chứa một ngôi sao nhỏ.', 'star_ring.png'),
  ('starfall_daggers',  'Dao Găm Sao Rơi',       'weapon',   'weapon', 'one_hand', 'physical', 'epic',      65,  0,   0,   0, null, 600, 'Nhanh như sao băng.', 'starfall_daggers.png'),
  -- Cõi Hỗn Nguồn (Lv 62-75)
  ('chaos_prism',       'Lăng Kính Hỗn Mang',    'material', null,     null,       null,       'common',     0,  0,   0,   0, null, 130, 'Bẻ cong cả ánh sáng lẫn thực tại.', 'chaos_prism.png'),
  ('crystal_plate',     'Giáp Pha Lê',           'armor',    'chest',  null,       null,       'common',     0, 34, 230,   0, null, 150, 'Trong suốt nhưng không gì xuyên thủng.', 'crystal_plate.png'),
  ('prism_amulet',      'Bùa Lăng Kính',         'armor',    'amulet', null,       null,       'common',    18,  0, 160,   0, null, 150, 'Tách ánh sáng thành sức mạnh.', 'prism_amulet.png'),
  ('chaos_blade',       'Kiếm Hỗn Nguồn',        'weapon',   'weapon', 'one_hand', 'physical', 'legendary', 80,  0,   0,   0, null, 900, 'Lưỡi kiếm sinh ra từ hỗn mang nguyên thủy.', 'chaos_blade.png'),
  -- Thiên Đường (Lv 72-80)
  ('angel_feather',     'Lông Thiên Sứ',         'material', null,     null,       null,       'common',     0,  0,   0,   0, null, 160, 'Nhẹ tênh, tỏa hơi ấm.', 'angel_feather.png'),
  ('seraph_crown',      'Vương Miện Thiên Sứ',   'armor',    'head',   null,       null,       'common',     0, 34, 250,   0, null, 190, 'Vầng hào quang được rèn thành vàng.', 'seraph_crown.png'),
  ('celestial_shield',  'Khiên Thiên Giới',      'armor',    'shield', 'one_hand', null,       'common',     0, 40, 120,   0, null, 190, 'Chưa từng bị phá vỡ.', 'celestial_shield.png'),
  ('genesis_staff',     'Trượng Sáng Thế',       'weapon',   'weapon', 'two_hand', 'magic',    'legendary', 95,  0,   0,   0, null,1200, 'Thứ đã tạo ra thế giới này.', 'genesis_staff.png'),
  -- Bình máu cho vùng cao (cũng bán ở chợ)
  ('potion_supreme',    'Bình Máu Thượng Hạng',  'consumable', null,   null,       null,       'rare',       0,  0,   0, 800,  250,  70, 'Hồi ngay 800 HP', 'potion_supreme.png')
on conflict (key) do nothing;

-- 2. Vùng -------------------------------------------------------------------------
insert into zones (key, name, icon, description, min_level, max_level, ap_cost, boss_chance, sort_order) values
  ('sa_mac',     'Sa Mạc',        '🏜️', 'Biển cát vô tận, lăng mộ vua chúa bị chôn vùi.', 15, 25, 12, 0.03, 5),
  ('nui_lua',    'Núi Lửa',       '🌋', 'Dung nham chảy tràn, không khí bỏng rát.',       22, 32, 14, 0.03, 6),
  ('vuc_toi',    'Vực Tối',       '🌑', 'Nơi ánh sáng không bao giờ chạm tới.',           30, 42, 16, 0.03, 7),
  ('thanh_dia',  'Thánh Địa',     '🏛️', 'Đền thờ cổ được canh giữ bởi thần linh.',        40, 55, 18, 0.03, 8),
  ('hu_khong',   'Hư Không',      '🌀', 'Khoảng trống giữa các vì sao.',                  52, 65, 20, 0.03, 9),
  ('hon_nguyen', 'Cõi Hỗn Nguồn', '💠', 'Nơi mọi thứ bắt đầu — và kết thúc.',            62, 75, 22, 0.03, 10),
  ('thien_duong','Thiên Đường',   '🌤️', 'Vương quốc trên mây của các thiên sứ.',         72, 80, 25, 0.03, 11)
on conflict (key) do nothing;

-- 3. Quái -------------------------------------------------------------------------
-- Quái thường: hp = 16 + 6L, atk = 8 + 1.2L, def = 0.8L, exp = gold = 1 + L
-- Boss (cấp max+1): hp ×4, atk ×1.4, def ×1.3, exp/gold ×6
-- ATK khác 4 vùng đầu (3 + 1.5L): với 1.5L, phòng thủ tự nhiên của class
-- mỏng máu không theo kịp nên ở Lv 50+ chỉ sống ~9 trận. 8 + 1.2L bằng đúng
-- công thức cũ ở Lv 15 và mô phỏng cho ~15-75 trận ở mọi vùng (chưa mặc đồ).
insert into zone_enemies (zone_id, name, level, hp, atk, def, reward_exp, reward_gold, weight, is_boss)
select z.id, e.name, e.lvl,
       round((16 + 6 * e.lvl) * case when e.boss then 4 else 1 end),
       round((8 + 1.2 * e.lvl) * case when e.boss then 1.4 else 1 end),
       round((0.8 * e.lvl) * case when e.boss then 1.3 else 1 end),
       (1 + e.lvl) * case when e.boss then 6 else 1 end,
       (1 + e.lvl) * case when e.boss then 6 else 1 end,
       e.weight, e.boss
from (values
  ('sa_mac', 'Bọ Cạp Cát', 15, 40, false),
  ('sa_mac', 'Rắn Hổ Mang', 18, 30, false),
  ('sa_mac', 'Xác Ướp', 21, 20, false),
  ('sa_mac', 'Sâu Cát Khổng Lồ', 24, 10, false),
  ('sa_mac', 'Pharaoh Bất Tử', 26, 1, true),
  ('nui_lua', 'Thằn Lằn Lửa', 22, 40, false),
  ('nui_lua', 'Tinh Linh Lửa', 25, 30, false),
  ('nui_lua', 'Golem Dung Nham', 28, 20, false),
  ('nui_lua', 'Chó Địa Ngục', 31, 10, false),
  ('nui_lua', 'Rồng Lửa Cổ Đại', 33, 1, true),
  ('vuc_toi', 'Bóng Ma', 30, 40, false),
  ('vuc_toi', 'Nhện Bóng Tối', 34, 30, false),
  ('vuc_toi', 'Hiệp Sĩ Xương', 38, 20, false),
  ('vuc_toi', 'Ác Quỷ Vực Sâu', 41, 10, false),
  ('vuc_toi', 'Chúa Tể Bóng Đêm', 43, 1, true),
  ('thanh_dia', 'Tượng Thần Canh Gác', 40, 40, false),
  ('thanh_dia', 'Thiên Thần Sa Ngã', 45, 30, false),
  ('thanh_dia', 'Hiệp Sĩ Thánh Điện', 50, 20, false),
  ('thanh_dia', 'Sư Tử Thần', 54, 10, false),
  ('thanh_dia', 'Thẩm Phán Thánh Quang', 56, 1, true),
  ('hu_khong', 'Mắt Hư Không', 52, 40, false),
  ('hu_khong', 'Sứa Không Gian', 56, 30, false),
  ('hu_khong', 'Kẻ Nuốt Sao', 60, 20, false),
  ('hu_khong', 'Thợ Săn Hư Vô', 64, 10, false),
  ('hu_khong', 'Hư Vương', 66, 1, true),
  ('hon_nguyen', 'Tinh Thể Sống', 62, 40, false),
  ('hon_nguyen', 'Nguyên Tố Hỗn Mang', 66, 30, false),
  ('hon_nguyen', 'Người Khổng Lồ Pha Lê', 70, 20, false),
  ('hon_nguyen', 'Rồng Nguyên Tố', 74, 10, false),
  ('hon_nguyen', 'Mẹ Hỗn Nguồn', 76, 1, true),
  ('thien_duong', 'Thiên Sứ Hộ Vệ', 72, 40, false),
  ('thien_duong', 'Thiên Nhãn', 75, 30, false),
  ('thien_duong', 'Kỵ Sĩ Mây', 78, 20, false),
  ('thien_duong', 'Tổng Lãnh Thiên Thần', 80, 10, false),
  ('thien_duong', 'Đấng Sáng Thế', 81, 1, true)
) as e(zone_key, name, lvl, weight, boss)
join zones z on z.key = e.zone_key
where not exists (select 1 from zone_enemies ze where ze.zone_id = z.id);

-- 4. Đồ rơi -----------------------------------------------------------------------
insert into zone_drops (zone_id, item_id, drop_rate, boss_only)
select z.id, i.id, d.rate, d.boss_only
from (values
  ('sa_mac', 'sand_scarab', 0.12, false),
  ('sa_mac', 'potion_medium', 0.06, false),
  ('sa_mac', 'desert_turban', 0.02, false),
  ('sa_mac', 'sandstrider_boots', 0.02, false),
  ('sa_mac', 'pharaoh_scepter', 0.12, true),
  ('nui_lua', 'magma_core', 0.12, false),
  ('nui_lua', 'potion_large', 0.05, false),
  ('nui_lua', 'obsidian_shield', 0.02, false),
  ('nui_lua', 'ember_amulet', 0.015, false),
  ('nui_lua', 'inferno_greataxe', 0.12, true),
  ('vuc_toi', 'shadow_essence', 0.12, false),
  ('vuc_toi', 'potion_large', 0.06, false),
  ('vuc_toi', 'shadow_cloak', 0.02, false),
  ('vuc_toi', 'bone_ring', 0.015, false),
  ('vuc_toi', 'nightfall_bow', 0.12, true),
  ('thanh_dia', 'holy_relic', 0.12, false),
  ('thanh_dia', 'potion_supreme', 0.04, false),
  ('thanh_dia', 'paladin_helm', 0.02, false),
  ('thanh_dia', 'radiant_belt', 0.02, false),
  ('thanh_dia', 'judgement_staff', 0.12, true),
  ('hu_khong', 'void_crystal', 0.12, false),
  ('hu_khong', 'potion_supreme', 0.05, false),
  ('hu_khong', 'voidwalker_boots', 0.02, false),
  ('hu_khong', 'star_ring', 0.015, false),
  ('hu_khong', 'starfall_daggers', 0.12, true),
  ('hon_nguyen', 'chaos_prism', 0.12, false),
  ('hon_nguyen', 'potion_supreme', 0.05, false),
  ('hon_nguyen', 'crystal_plate', 0.02, false),
  ('hon_nguyen', 'prism_amulet', 0.015, false),
  ('hon_nguyen', 'chaos_blade', 0.1, true),
  ('thien_duong', 'angel_feather', 0.12, false),
  ('thien_duong', 'potion_supreme', 0.06, false),
  ('thien_duong', 'seraph_crown', 0.02, false),
  ('thien_duong', 'celestial_shield', 0.02, false),
  ('thien_duong', 'genesis_staff', 0.1, true)
) as d(zone_key, item_key, rate, boss_only)
join zones z on z.key = d.zone_key
join items i on i.key = d.item_key
where not exists (select 1 from zone_drops zd where zd.zone_id = z.id);

-- ============================================================================
-- ĐỢT 1: NGUYÊN LIỆU, CƯỜNG HÓA, KHÓA ĐỒ, DANH HIỆU, XẾP HẠNG, NỘM TẬP, NHIỆM VỤ NGÀY
-- ============================================================================

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
  stat        text not null check (stat in ('kills', 'boss_kills', 'level', 'legendary_found', 'best_enchant', 'daily_bonus_count', 'tower_best')),
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

-- (post_activity: xem phần BẢNG TIN phía trên)
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
  out_level int, out_power int, out_boss_kills int, out_kills int, out_tower_best int, out_title text,
  out_portrait text, out_frame text
)
language sql
stable
security definer
set search_path = 'public'
as $$
  with base as (
    select c.id, c.name, cl.key as class_key, cl.name as class_name, c.level, c.exp,
           character_power(c.id) as power, c.boss_kills, c.kills, c.tower_best,
           t.emoji || ' ' || t.name as title, c.portrait, c.frame
    from characters c
    join classes cl on cl.id = c.class_id
    left join titles t on t.key = c.title_key
  )
  select (row_number() over (order by
            case p_sort when 'power' then b.power when 'boss_kills' then b.boss_kills
                        when 'tower' then b.tower_best else b.level end desc,
            case p_sort when 'level' then b.exp else b.level end desc,
            b.name))::int,
         b.id, b.name, b.class_key, b.class_name, b.level, b.power, b.boss_kills, b.kills, b.tower_best, b.title,
         b.portrait, b.frame
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
    least(0.5, v_crit + v_skill_crit), 0, 0,
    v_a1_name, v_a1_power, v_a2_name, v_a2_power,
    'Nộm Tập', 2000000000, 0, v_def,
    1, true, v_effects, combat_mods(p_character_id)
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
    'crit_chance', least(0.5, v_crit + v_skill_crit),
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

-- ============================================================================
-- THÁP VỰC SÂU (thay dungeon theo chương)
-- ============================================================================

-- 1. Tiến độ + danh hiệu + bảng tin ------------------------------------------------
alter table characters add column if not exists tower_best int not null default 0;


insert into titles (key, name, emoji, description, stat, threshold, sort_order) values
  ('tower_10',  'Người Thách Đấu',   '🗼', 'Vượt tầng 10 Tháp Vực Sâu',  'tower_best', 10,  13),
  ('tower_25',  'Kẻ Leo Tháp',       '🧗', 'Vượt tầng 25 Tháp Vực Sâu',  'tower_best', 25,  14),
  ('tower_50',  'Kẻ Chinh Phục',     '🏔️', 'Vượt tầng 50 Tháp Vực Sâu',  'tower_best', 50,  15),
  ('tower_100', 'Chúa Tể Vực Sâu',   '🌌', 'Vượt tầng 100 Tháp Vực Sâu', 'tower_best', 100, 16)
on conflict (key) do nothing;


-- (award_titles: xem phần ĐỢT 1)
-- 2. Thành phần mỗi tầng (cố định theo số tầng) -------------------------------------------
-- Chỉ số theo cùng công thức quái explore ở level = số tầng, nhân thêm hệ số
-- tháp (1 + 0.4% mỗi tầng → tầng 100 ×1.4) để đỉnh tháp khó hơn Thiên Đường.
create or replace function public.tower_floor_enemies(p_floor int)
returns table(out_idx int, out_name text, out_level int, out_kind text,
              out_hp int, out_atk int, out_def int, out_exp int, out_gold int, out_traits text[])
language plpgsql
stable
set search_path = 'public'
as $$
declare
  v_lvl int := greatest(1, least(100, p_floor));
  -- Khó hơn: HP ×(2 + 0.025 × tầng), ATK ×1.15, mỗi tầng +1% (trước 0.4%)
  -- Mỗi tầng +1%, từ tầng 30 quái mạnh thêm (khớp enemy_level_mult)
  v_tm numeric := 1 + v_lvl * 0.01;
  -- Đặc tính cố định theo tầng (xem trước = lúc đánh): từ tầng 11, đổi mỗi 5 tầng
  v_pool text[] := array['evasive','armored','venom','enrage','unholy','regen','thorny','savage'];
  v_base int := (p_floor / 5) % 8;
  v_trait text[] := case when v_lvl > 10 then array[v_pool[1 + v_base]] else '{}'::text[] end;
  v_hp numeric := (16 + 6 * v_lvl) * (2 + 0.025 * v_lvl) * enemy_level_mult(v_lvl);
  -- Tháp đã có +1%/tầng nên ATK chỉ theo đường cong HP (nhẹ hơn quái vùng)
  v_atk numeric := (case when v_lvl < 15 then 3 + 1.5 * v_lvl else 8 + 1.2 * v_lvl end) * 1.15
                   * enemy_level_mult(v_lvl);
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
        round(v_hp * 3 * v_tm)::int, round(v_atk * 1.25 * v_tm)::int, round(v_def * 1.2)::int,
        (1 + v_lvl) * 6, (1 + v_lvl) * 6,
        v_trait || array[v_pool[1 + (v_base + 1) % 8], v_pool[1 + (v_base + 3 + v_idx) % 8]];
    end loop;
    return;
  end if;

  if v_lvl % 5 = 0 then
    select ze.name into v_name from zone_enemies ze where not ze.is_boss
    order by abs(ze.level - v_lvl), ze.level desc limit 1;
    v_idx := 1;
    return query select 1, 'Tinh Anh ' || v_name, v_lvl + 1, 'elite',
      round(v_hp * 2 * v_tm)::int, round(v_atk * 1.15 * v_tm)::int, round(v_def * 1.15)::int,
      (2 + v_lvl) * 3, (2 + v_lvl) * 3,
      v_trait || array[v_pool[1 + (v_base + 2) % 8]];
  end if;

  for k in (v_idx + 1)..2 loop
    select ze.name into v_name from zone_enemies ze where not ze.is_boss
    order by abs(ze.level - v_lvl), ze.name limit 1 offset ((v_lvl + k) % 3);
    return query select k, v_name, v_lvl, 'normal',
      round(v_hp * v_tm)::int, round(v_atk * v_tm)::int, round(v_def)::int,
      1 + v_lvl, 1 + v_lvl, v_trait;
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
  v_mods jsonb; v_revived boolean;
  v_auto_potion boolean; v_potions_left int := 0; v_potions_used int := 0; v_drink record;
  v_buff_exp boolean := false; v_buff_luck boolean := false; v_buff_guard boolean := false; v_guard_used boolean := false;
  v_pen_gold int := 0; v_pen_exp int := 0;
begin
  select c.user_id into v_owner_user_id from characters c where c.id = p_character_id;
  if not found then raise exception 'Không tìm thấy nhân vật'; end if;
  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  perform regen_character(p_character_id);

  select c.level, c.current_hp, c.current_ap, c.max_ap, c.tower_best, c.auto_potion
    into v_level, v_current_hp, v_current_ap, v_max_ap, v_best, v_auto_potion
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
  v_crit_chance := least(0.5, v_crit_chance + v_stat_crit_bonus);
  v_lifesteal := v_lifesteal + v_stat_lifesteal_bonus;
  v_effects := get_character_effects(p_character_id);
  v_mods := combat_mods(p_character_id);

  select coalesce(bool_or(b.buff_key = 'exp'), false), coalesce(bool_or(b.buff_key = 'luck'), false),
         coalesce(bool_or(b.buff_key = 'guard'), false)
    into v_buff_exp, v_buff_luck, v_buff_guard
  from character_buffs b where b.character_id = p_character_id;
  delete from character_buffs b where b.character_id = p_character_id;
  v_potions_left := case when v_auto_potion then 2 else 0 end;

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

      -- Bùa Hộ Mệnh: gục thì đứng dậy với 50% HP và đánh lại quái này (1 lần mỗi lần leo)
      loop
        select f.out_win, f.out_timed_out, f.out_hp_left, f.out_dmg_taken, f.out_log, f.out_revived
          into v_win, v_timed_out, v_hp, v_dmg_taken, v_fight_log, v_revived
        from simulate_fight(
          v_char_atk, v_char_def, v_hp, v_max_hp,
          v_crit_chance, v_lifesteal, v_dmg_reduction,
          v_a1_name, v_a1_power, v_a2_name, v_a2_power,
          v_enemy.out_name, v_enemy.out_hp, v_enemy.out_atk, v_enemy.out_def,
          v_dmg_mult, true, v_effects, v_mods,
          v_enemy.out_level - v_level, v_enemy.out_traits, v_enemy.out_level
        ) f;

        -- Giả Chết chỉ 1 lần mỗi lần leo
        if v_revived then v_mods := v_mods - 'revive'; end if;

        exit when v_win or v_timed_out or not v_buff_guard;
        v_buff_guard := false;
        v_guard_used := true;
        v_hp := greatest(1, round(v_max_hp * 0.5)::int);
      end loop;

      v_last_fight := jsonb_build_object('floor', v_floor, 'enemy', v_enemy.out_name, 'log', v_fight_log);
      v_enemies := v_enemies || jsonb_build_object(
        'name', v_enemy.out_name, 'level', v_enemy.out_level, 'kind', v_enemy.out_kind,
        'result', case when v_win then 'win' when v_timed_out then 'flee' else 'lose' end,
        'hp_left', v_hp, 'dmg_taken', v_dmg_taken, 'log', v_fight_log,
        'traits', to_jsonb(v_enemy.out_traits)
      );

      if not v_win then
        v_cleared := false;
        v_stop := case when v_timed_out then 'fled' else 'died' end;
        exit;
      end if;

      v_floor_kills := v_floor_kills + 1;
      if v_enemy.out_kind = 'boss' then v_floor_bosses := v_floor_bosses + 1; end if;
      v_floor_exp := v_floor_exp + round(v_enemy.out_exp * v_exp_mult * case when v_buff_exp then 1.25 else 1 end);
      v_floor_gold := v_floor_gold + round(v_enemy.out_gold * v_exp_mult);

      -- Tự uống bình khi HP dưới 35%
      if v_potions_left > 0 and v_hp < v_max_hp * 0.35 then
        select d.out_hp, d.out_name into v_drink from drink_best_potion(p_character_id, v_hp, v_max_hp) d;
        if v_drink.out_name is not null then
          v_hp := v_drink.out_hp;
          v_potions_left := v_potions_left - 1;
          v_potions_used := v_potions_used + 1;
        else
          v_potions_left := 0;
        end if;
      end if;
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
    if v_floor % 10 = 0 and (v_first or random() < case when v_buff_luck then 0.26 else 0.2 end) then
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

  -- Phạt khi gục: mất 10% vàng đang cầm và 15% EXP của cấp hiện tại (không tụt cấp)
  if v_stop = 'died' then
    select floor(c.gold * 0.10)::int, least(c.exp, round(c.exp_to_next * 0.15)::int)
      into v_pen_gold, v_pen_exp
    from characters c where c.id = p_character_id;
    update characters c set gold = c.gold - v_pen_gold, exp = c.exp - v_pen_exp where c.id = p_character_id;
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
    'penalty', jsonb_build_object('gold', v_pen_gold, 'exp', v_pen_exp),
    'floors', v_floors,
    'last_fight', v_last_fight,
    'potions_used', v_potions_used,
    'guard_used', v_guard_used,
    'buffs', jsonb_build_object('exp', v_buff_exp, 'luck', v_buff_luck)
  );
end;
$$;

-- 4. Dungeon cũ ngừng dùng (UI thay bằng tháp) ---------------------------------------------
revoke execute on function public.resolve_dungeon_floor(uuid, uuid) from public, anon, authenticated;

-- Nhiệm vụ ngày loại 'dungeon' giờ là vượt tầng tháp
-- (ensure_daily_quests: xem phần ĐỢT 1)
-- 5. Bảng xếp hạng thêm tầng tháp -------------------------------------------------------------

-- (get_leaderboard: xem phần ĐỢT 1)

-- ============================================================================
-- THƯƠNG NHÂN BÍ ẨN (gacha tiêu vàng)
-- ============================================================================

create table if not exists gacha_log (
  id           uuid primary key default gen_random_uuid(),
  character_id uuid not null references characters(id) on delete cascade,
  tier         text not null check (tier in ('common', 'rare', 'epic', 'legendary', 'jackpot')),
  item_id      uuid not null references items(id),
  rarity       text not null,
  quantity     int not null,
  created_at   timestamptz not null default clock_timestamp()
);

create index if not exists gacha_log_character_idx on gacha_log(character_id, created_at desc);

alter table gacha_log enable row level security;
drop policy if exists "own gacha_log select" on gacha_log;
create policy "own gacha_log select" on gacha_log
  for select using (exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid()));
grant select on table gacha_log to authenticated;


-- Trang bị ngẫu nhiên hợp level (item_level trong [L-8, L+2]; không có thì gần nhất).
-- p_weapons_only + p_boss_only: Jackpot chỉ lấy vũ khí boss (không bán ở chợ, tier gốc ≥ Hiếm).
create or replace function public.pick_equipment_for_level(p_level int, p_boss_only boolean)
returns uuid
language sql
volatile
set search_path = 'public'
as $$
  select coalesce(
    (select i.id from items i
     where i.type in ('weapon', 'armor')
       and (not p_boss_only or (i.type = 'weapon' and i.buy_price is null and rarity_rank(i.rarity) >= 1))
       and i.item_level between p_level - 8 and p_level + 2
     order by random() limit 1),
    (select i.id from items i
     where i.type in ('weapon', 'armor')
       and (not p_boss_only or (i.type = 'weapon' and i.buy_price is null and rarity_rank(i.rarity) >= 1))
     order by abs(i.item_level - p_level), random() limit 1)
  );
$$;

create or replace function public.gacha_pull(p_character_id uuid, p_count int, p_free boolean)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_level int; v_gold int; v_pity int; v_free_date date;
  v_count int := case when p_count = 10 then 10 else 1 end;
  v_cost int;
  v_results jsonb := '[]'::jsonb;
  v_has_epic boolean := false;
  v_roll numeric; v_tier text;
  v_item uuid; v_qty int; v_rarity text; v_item2 uuid;
  v_mat uuid; v_mat_price int;
  i int;
begin
  select c.level, c.gold, c.gacha_pity, c.gacha_free_date
    into v_level, v_gold, v_pity, v_free_date
  from characters c where c.id = p_character_id and c.user_id = auth.uid() for update;
  if not found then raise exception 'Không có quyền điều khiển nhân vật này'; end if;

  if p_free then
    if v_count <> 1 then raise exception 'Lượt miễn phí chỉ mở 1 rương'; end if;
    if v_free_date = vn_today() then raise exception 'Hôm nay đã dùng lượt miễn phí'; end if;
    v_cost := 0;
  else
    v_cost := case when v_count = 10 then 3600 else 400 end;
    if v_gold < v_cost then raise exception 'Không đủ vàng (cần % vàng)', v_cost; end if;
  end if;

  v_mat := material_for_level(v_level);
  select i2.sell_price into v_mat_price from items i2 where i2.id = v_mat;

  for i in 1..v_count loop
    v_pity := v_pity + 1;
    v_roll := random();
    v_tier := case
      when v_roll < 0.005 then 'jackpot'
      when v_roll < 0.05 then 'legendary'
      when v_roll < 0.17 then 'epic'
      when v_roll < 0.45 then 'rare'
      else 'common' end;

    -- Pity: lượt thứ 50 không có Huyền Thoại → ép Huyền Thoại
    if v_pity >= 50 and v_tier not in ('legendary', 'jackpot') then v_tier := 'legendary'; end if;
    -- x10: lượt cuối chưa có Sử Thi nào → ép Sử Thi
    if v_count = 10 and i = 10 and not v_has_epic and v_tier in ('common', 'rare') then v_tier := 'epic'; end if;

    if v_tier in ('epic', 'legendary', 'jackpot') then v_has_epic := true; end if;
    if v_tier in ('legendary', 'jackpot') then v_pity := 0; end if;

    v_item := null; v_item2 := null; v_qty := 1; v_rarity := null;

    if v_tier = 'common' then
      if random() < 0.7 and v_mat is not null then
        v_item := v_mat; v_qty := greatest(1, round(100.0 / greatest(1, v_mat_price))::int);
      else
        select id into v_item from items where key = case
          when v_level < 20 then 'potion_medium' when v_level < 45 then 'potion_large' else 'potion_supreme' end;
        v_qty := case when v_level < 45 then 2 else 1 end;
      end if;
    elsif v_tier = 'rare' then
      if random() < 0.6 and v_mat is not null then
        v_item := v_mat; v_qty := greatest(1, round(150.0 / greatest(1, v_mat_price))::int);
        select id into v_item2 from items where material_tier = (select material_tier + 1 from items where id = v_mat);
      else
        v_item := pick_equipment_for_level(v_level, false); v_rarity := 'rare';
      end if;
    elsif v_tier = 'epic' then
      if random() < 0.75 then
        v_item := pick_equipment_for_level(v_level, false); v_rarity := 'epic';
      else
        select id into v_item from items where key = 'potion_ap_large'; v_qty := 2;
      end if;
    elsif v_tier = 'legendary' then
      v_item := pick_equipment_for_level(v_level, false); v_rarity := 'legendary';
    else
      v_item := pick_equipment_for_level(v_level, true); v_rarity := 'legendary';
    end if;

    if v_item is null then  -- dữ liệu thiếu (vd. chưa có bình) → quy về nguyên liệu
      v_item := v_mat; v_qty := greatest(1, round(100.0 / greatest(1, v_mat_price))::int); v_rarity := null;
    end if;

    -- Trao thưởng: trang bị tạo qua create_equipment (affix + hiệu ứng Huyền
    -- Thoại + bảng tin), vật phẩm gộp chồng qua add_stack
    if v_rarity is not null then
      perform create_equipment(p_character_id, v_item, v_rarity);
    else
      perform add_stack(p_character_id, v_item, v_qty);
    end if;

    insert into gacha_log (character_id, tier, item_id, rarity, quantity)
    values (p_character_id, v_tier, v_item, coalesce(v_rarity, (select rarity from items where id = v_item)), v_qty);

    v_results := v_results || (select jsonb_build_object(
      'tier', v_tier, 'key', it.key, 'name', it.name, 'icon', it.icon,
      'rarity', coalesce(v_rarity, it.rarity), 'qty', v_qty,
      'effect', case when v_rarity = 'legendary' then (
        select inv.legendary_effect from inventory inv
        where inv.character_id = p_character_id and inv.item_id = v_item
        order by inv.acquired_at desc limit 1) end
    ) from items it where it.id = v_item);

    if v_item2 is not null then
      perform add_stack(p_character_id, v_item2, 1);
      v_results := v_results || (select jsonb_build_object(
        'tier', v_tier, 'key', it.key, 'name', it.name, 'icon', it.icon, 'rarity', it.rarity, 'qty', 1
      ) from items it where it.id = v_item2);
    end if;

    if v_tier = 'jackpot' then
      perform post_activity(p_character_id, 'gacha_jackpot', jsonb_build_object(
        'item', (select name from items where id = v_item), 'icon', (select icon from items where id = v_item)
      ));
    end if;
  end loop;

  update characters c
  set gold = c.gold - v_cost,
      gacha_pity = v_pity,
      gacha_free_date = case when p_free then vn_today() else c.gacha_free_date end
  where c.id = p_character_id;

  return jsonb_build_object(
    'results', v_results,
    'gold_left', v_gold - v_cost,
    'pity', v_pity,
    'free_used', p_free
  );
end;
$$;

-- ============================================================================
-- TỰ MẶC ĐỒ TỐT NHẤT
-- ============================================================================

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
       + coalesce((inv.rolled_extra->>'pierce')::numeric, 0) * 150
       + coalesce((inv.rolled_extra->>'double')::numeric, 0) * 300
       + coalesce((inv.rolled_extra->>'dmg_red')::numeric, 0) * 500
       + coalesce((inv.rolled_extra->>'regen')::numeric, 0) * 800
       + coalesce((inv.rolled_extra->>'skill_dmg')::numeric, 0) * 200
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

-- ============================================================================
-- CÂY THIÊN PHÚ
-- ============================================================================

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
  ('hp_n', 'Giáp Hoàng Gia', '❤️', 'hp', 'notable', 2, 0.0, -51.0, '{"hp_pct": 0.05, "equip_bonus": 0.01}'::jsonb, '+5% HP; +1% ATK và DEF gốc cho mỗi món đang mặc'),
  ('hp_side', 'Da Thịt Rắn Chắc', '❤️', 'hp', 'small', 1, 19.8, -54.3, '{"hp_pct": 0.05}'::jsonb, '+5% HP'),
  ('hp_3', 'Sinh Lực III', '❤️', 'hp', 'small', 1, -7.1, -67.6, '{"hp_pct": 0.04}'::jsonb, '+4% HP tối đa'),
  ('hp_k', 'Trụ Cột', '❤️', 'hp', 'keystone', 2, 0.0, -86.7, '{"hp_pct": 0.10, "guard_stack": 0.05}'::jsonb, '+10% HP; mỗi lần trúng đòn +5% giảm sát thương (tối đa 3 lần mỗi trận)'),
  ('atk_1', 'Sức Mạnh', '⚔️', 'atk', 'small', 1, 14.7, -8.5, '{"atk_pct": 0.03}'::jsonb, '+3% ATK'),
  ('atk_2', 'Sức Mạnh II', '⚔️', 'atk', 'small', 1, 29.4, -17.0, '{"atk_pct": 0.03}'::jsonb, '+3% ATK'),
  ('atk_n', 'Khát Chiến', '⚔️', 'atk', 'notable', 2, 44.2, -25.5, '{"atk_pct": 0.06, "crit": 0.02}'::jsonb, '+6% ATK, +2% chí mạng'),
  ('atk_side', 'Đồ Tể', '⚔️', 'atk', 'small', 1, 56.9, -10.0, '{"atk_pct": 0.04}'::jsonb, '+4% ATK'),
  ('atk_3', 'Sức Mạnh III', '⚔️', 'atk', 'small', 1, 55.0, -40.0, '{"atk_pct": 0.03}'::jsonb, '+3% ATK'),
  ('atk_k', 'Cuồng Huyết', '⚔️', 'atk', 'keystone', 2, 75.1, -43.4, '{"rage": 0.40, "def_pct": -0.15}'::jsonb, 'ATK tăng theo máu đã mất, tới +40% khi HP ≤ 40%; −15% DEF'),
  ('crit_1', 'Nhãn Lực', '🎯', 'crit', 'small', 1, 14.7, 8.5, '{"crit": 0.015}'::jsonb, '+1.5% chí mạng'),
  ('crit_2', 'Nhãn Lực II', '🎯', 'crit', 'small', 1, 29.4, 17.0, '{"crit": 0.015}'::jsonb, '+1.5% chí mạng'),
  ('crit_n', 'Xuyên Giáp', '🎯', 'crit', 'notable', 2, 44.2, 25.5, '{"pierce": 0.30, "crit": 0.02}'::jsonb, 'Bỏ qua 30% DEF quái, +2% chí mạng'),
  ('crit_side', 'Tâm Nhãn', '🎯', 'crit', 'small', 1, 37.2, 44.3, '{"crit": 0.02}'::jsonb, '+2% chí mạng'),
  ('crit_3', 'Nhãn Lực III', '🎯', 'crit', 'small', 1, 62.1, 27.7, '{"crit": 0.015}'::jsonb, '+1.5% chí mạng'),
  ('crit_k', 'Mắt Tử Thần', '🎯', 'crit', 'keystone', 2, 75.1, 43.3, '{"crit_mult": 2.2, "crit_pierce": 1, "hp_pct": -0.1}'::jsonb, 'Chí mạng gây ×2.2 (thay ×1.5) và xuyên toàn bộ DEF; −10% HP'),
  ('ls_1', 'Huyết Mạch', '🩸', 'ls', 'small', 1, 0.0, 17.0, '{"lifesteal": 0.01}'::jsonb, '+1% hút máu'),
  ('ls_2', 'Huyết Mạch II', '🩸', 'ls', 'small', 1, 0.0, 34.0, '{"lifesteal": 0.01}'::jsonb, '+1% hút máu'),
  ('ls_n', 'Hiến Tế Huyết Ma', '🩸', 'ls', 'notable', 2, 0.0, 51.0, '{"lifesteal": 0.02, "hp_pct": 0.03}'::jsonb, '+2% hút máu, +3% HP'),
  ('ls_side', 'Huyết Khí', '🩸', 'ls', 'small', 1, -19.8, 54.3, '{"lifesteal": 0.015}'::jsonb, '+1.5% hút máu'),
  ('ls_3', 'Huyết Mạch III', '🩸', 'ls', 'small', 1, 7.1, 67.6, '{"lifesteal": 0.01}'::jsonb, '+1% hút máu'),
  ('ls_k', 'Khát Máu Vô Tận', '🩸', 'ls', 'keystone', 2, 0.0, 86.7, '{"lifesteal": 0.03, "low_hp_ls": 2, "def_pct": -0.1}'::jsonb, '+3% hút máu; HP dưới 30% thì hút máu ×2; −10% DEF'),
  ('spd_1', 'Nhanh Nhẹn', '⚡', 'spd', 'small', 1, -14.7, 8.5, '{"double": 0.02}'::jsonb, '+2% Đòn Kép'),
  ('spd_2', 'Nhanh Nhẹn II', '⚡', 'spd', 'small', 1, -29.4, 17.0, '{"double": 0.02}'::jsonb, '+2% Đòn Kép'),
  ('spd_n', 'Khai Cuộc Thần Tốc', '⚡', 'spd', 'notable', 2, -44.2, 25.5, '{"opening": 1.5, "double": 0.02}'::jsonb, 'Đòn đầu mỗi trận ×1.5, +2% Đòn Kép'),
  ('spd_side', 'Dư Âm', '⚡', 'spd', 'small', 1, -56.9, 10.0, '{"echo": 0.15, "echo_pct": 0.6}'::jsonb, '15% mỗi lượt đánh thêm 1 đòn 60% ATK'),
  ('spd_3', 'Nhanh Nhẹn III', '⚡', 'spd', 'small', 1, -55.0, 40.0, '{"double": 0.02}'::jsonb, '+2% Đòn Kép'),
  ('spd_k', 'Giả Chết', '⚡', 'spd', 'keystone', 2, -75.1, 43.4, '{"revive": 0.30, "double": 0.08, "opening": 2.0, "hp_pct": -0.10}'::jsonb, '1 lần mỗi chuyến khám phá / lần leo tháp: đòn chí tử để lại 30% HP; đòn đầu ×2, +8% Đòn Kép; −10% HP'),
  ('def_1', 'Giáp Trụ', '🛡️', 'def', 'small', 1, -14.7, -8.5, '{"def_pct": 0.04}'::jsonb, '+4% DEF'),
  ('def_2', 'Giáp Trụ II', '🛡️', 'def', 'small', 1, -29.4, -17.0, '{"def_pct": 0.04}'::jsonb, '+4% DEF'),
  ('def_n', 'Phong Hầu', '🛡️', 'def', 'notable', 2, -44.2, -25.5, '{"prestige": 0.02, "def_pct": 0.03}'::jsonb, 'Mỗi lượt trong trận +2% ATK và DEF (tối đa +20%); +3% DEF'),
  ('def_side', 'Bất Khả Xâm', '🛡️', 'def', 'small', 1, -37.2, -44.3, '{"def_pct": 0.05}'::jsonb, '+5% DEF'),
  ('def_3', 'Giáp Trụ III', '🛡️', 'def', 'small', 1, -62.1, -27.7, '{"def_pct": 0.04}'::jsonb, '+4% DEF'),
  ('def_k', 'Phản Kích', '🛡️', 'def', 'keystone', 2, -75.1, -43.4, '{"parry": 0.20, "parry_mult": 1.5, "atk_pct": -0.10}'::jsonb, '20% đỡ trọn đòn quái và phản 150% ATK; −10% ATK'),
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
as $$
  -- 1 điểm ở mỗi mốc cấp 6/14/22/30/50/65/75 + 1 điểm mỗi 25 tầng Tháp, tối đa 7
  select least(7,
    (select count(*)::int from unnest(array[6, 14, 22, 30, 50, 65, 75]) m where m <= p_level)
    + least(100, greatest(0, p_tower_best)) / 25);
$$;

-- plpgsql (không phải sql) để get_character_stats tạo trước bảng cây vẫn được
-- (get_talent_totals: xem gần get_character_stats)
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
    'reset_cost', 30 * v_level,
    'level', v_level, 'notable_level', 20, 'keystone_level', 40
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

  -- Tầng ô mở theo cấp: ô lớn từ cấp 20, ô trùm từ cấp 40
  if v_kind = 'notable' and v_level < 20 then raise exception 'Ô lớn mở từ cấp 20'; end if;
  if v_kind = 'keystone' and v_level < 40 then raise exception 'Ô trùm mở từ cấp 40'; end if;

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

-- ============================================================================
-- KỸ NĂNG CLASS: HỒI CHIÊU + HIỆU ỨNG (dữ liệu skill nằm ở đây)
-- ============================================================================

alter table skills add column if not exists cooldown int not null default 0;
alter table skills add column if not exists effect jsonb not null default '{}'::jsonb;
comment on column skills.effect is
  'Hiệu ứng skill chủ động: pierce, lifesteal, hp_cost, min_hp, stun, bonus_stunned, dot/dot_turns/dot_name, streak, execute, hits';
comment on column skills.effect_type is 'Bị động: damage_reduction | lifesteal | crit_chance | crit_damage';

-- Bộ kỹ năng cũ chỉ có trên DB live (không nằm trong repo) → thay toàn bộ bằng bộ mới
delete from character_equipped_skills;
delete from skills;

insert into skills (class_id, key, name, description, skill_type, power_multiplier, cooldown, effect, effect_type, effect_value, unlock_level, icon)
select cl.id, v.key, v.name, v.description, v.skill_type, v.power, v.cooldown, v.effect, v.effect_type, v.effect_value, v.unlock_level, v.icon
from (values
  ('warrior', 'warrior_slash', 'Chém Mạnh', '150% ATK', 'active', 1.5, 3, '{}'::jsonb, null, null, 1, '⚔️'),
  ('warrior', 'warrior_knight', 'Kiếm Hiệp Sĩ', '160% ATK, xuyên 25% DEF', 'active', 1.6, 3, '{"pierce": 0.25}'::jsonb, null, null, 12, '🗡️'),
  ('warrior', 'warrior_drain', 'Hút Máu', '140% ATK, hồi HP bằng 20% sát thương gây ra', 'active', 1.4, 3, '{"lifesteal": 0.2}'::jsonb, null, null, 25, '🩸'),
  ('warrior', 'warrior_despair', 'Chém Tuyệt Vọng', 'Tốn 15% HP hiện tại, 240% ATK xuyên giáp hoàn toàn. Chỉ dùng khi HP ≥ 50%', 'active', 2.4, 5, '{"hp_cost": 0.15, "pierce": 1, "min_hp": 0.5}'::jsonb, null, null, 45, '💥'),
  ('warrior', 'warrior_holy', 'Thánh Kích', '140% ATK xuyên giáp, hồi HP bằng 15% sát thương', 'active', 1.4, 3, '{"pierce": 1, "lifesteal": 0.15}'::jsonb, null, null, 60, '✨'),
  ('warrior', 'warrior_armor', 'Giáp Dày', 'Giảm 10% sát thương nhận vào', 'passive', null, 0, '{}'::jsonb, 'damage_reduction', 0.1, 5, '🛡️'),
  ('warrior', 'warrior_will', 'Ý Chí Thép', 'Hút máu 5% mọi đòn đánh', 'passive', null, 0, '{}'::jsonb, 'lifesteal', 0.05, 35, '❤️'),
  ('mage', 'mage_fireball', 'Cầu Lửa', '160% ATK phép, xuyên giáp', 'active', 1.6, 4, '{"pierce": 1}'::jsonb, null, null, 1, '🔥'),
  ('mage', 'mage_frost', 'Băng Tiễn', '140% ATK phép xuyên giáp, 20% đóng băng quái 1 lượt', 'active', 1.4, 3, '{"pierce": 1, "stun": 0.2}'::jsonb, null, null, 12, '❄️'),
  ('mage', 'mage_shatter', 'Băng Vỡ', '200% ATK phép xuyên giáp; +40% nếu quái vừa bị đóng băng', 'active', 2.0, 5, '{"pierce": 1, "bonus_stunned": 0.4}'::jsonb, null, null, 25, '🧊'),
  ('mage', 'mage_inferno', 'Hỏa Ngục', '220% ATK phép xuyên giáp', 'active', 2.2, 5, '{"pierce": 1}'::jsonb, null, null, 45, '🌋'),
  ('mage', 'mage_meteor', 'Thiên Thạch', '130% ATK phép xuyên giáp + thiêu 10% ATK mỗi lượt trong 3 lượt', 'active', 1.3, 4, '{"pierce": 1, "dot": 0.1, "dot_turns": 3, "dot_name": "Thiêu đốt"}'::jsonb, null, null, 60, '☄️'),
  ('mage', 'mage_shield', 'Khiên Mana', 'Giảm 12% sát thương nhận vào', 'passive', null, 0, '{}'::jsonb, 'damage_reduction', 0.12, 5, '🔮'),
  ('mage', 'mage_focus', 'Tập Trung', '+8% tỉ lệ chí mạng', 'passive', null, 0, '{}'::jsonb, 'crit_chance', 0.08, 35, '🎯'),
  ('assassin', 'assassin_stab', 'Đâm Hiểm', '180% ATK', 'active', 1.8, 4, '{}'::jsonb, null, null, 1, '🗡️'),
  ('assassin', 'assassin_venom', 'Đòn Độc', '120% ATK + độc 15% ATK mỗi lượt trong 2 lượt', 'active', 1.2, 3, '{"dot": 0.15, "dot_turns": 2, "dot_name": "Độc"}'::jsonb, null, null, 12, '🐍'),
  ('assassin', 'assassin_iai', 'Iaijutsu', '190% ATK, xuyên 30% DEF', 'active', 1.9, 4, '{"pierce": 0.3}'::jsonb, null, null, 25, '⚔️'),
  ('assassin', 'assassin_divine', 'Kiếm Thần', '160% ATK xuyên giáp hoàn toàn', 'active', 1.6, 4, '{"pierce": 1}'::jsonb, null, null, 45, '🌙'),
  ('assassin', 'assassin_execute', 'Kết Liễu', '160% ATK; +60% nếu quái còn dưới 30% HP', 'active', 1.6, 5, '{"execute": 0.6}'::jsonb, null, null, 60, '💀'),
  ('assassin', 'assassin_critdmg', 'Sát Thương Chí Mạng', 'Đòn chí mạng gây thêm 30% sát thương', 'passive', null, 0, '{}'::jsonb, 'crit_damage', 0.3, 5, '💢'),
  ('assassin', 'assassin_shadow', 'Bóng Tối', '+10% tỉ lệ chí mạng', 'passive', null, 0, '{}'::jsonb, 'crit_chance', 0.1, 35, '🌑'),
  ('archer', 'archer_shot', 'Mũi Tên Đánh Dấu', '150% ATK', 'active', 1.5, 3, '{}'::jsonb, null, null, 1, '🏹'),
  ('archer', 'archer_pierce', 'Xuyên Tâm Tiễn', '140% ATK, xuyên 50% DEF', 'active', 1.4, 3, '{"pierce": 0.5}'::jsonb, null, null, 12, '🎯'),
  ('archer', 'archer_aimed', 'Nhắm Bắn', '180% ATK; +30% từ lượt thứ 3 trở đi', 'active', 1.8, 5, '{"streak": 0.3}'::jsonb, null, null, 25, '🦅'),
  ('archer', 'archer_fire', 'Tên Lửa', '130% ATK + thiêu 15% ATK mỗi lượt trong 2 lượt', 'active', 1.3, 4, '{"dot": 0.15, "dot_turns": 2, "dot_name": "Thiêu đốt"}'::jsonb, null, null, 45, '🔥'),
  ('archer', 'archer_volley', 'Liên Xạ', 'Bắn 3 mũi, mỗi mũi 70% ATK', 'active', 0.7, 5, '{"hits": 3}'::jsonb, null, null, 60, '🌧️'),
  ('archer', 'archer_eagle', 'Mắt Đại Bàng', '+10% tỉ lệ chí mạng', 'passive', null, 0, '{}'::jsonb, 'crit_chance', 0.1, 5, '👁️'),
  ('archer', 'archer_reflex', 'Phản Xạ', 'Giảm 8% sát thương nhận vào', 'passive', null, 0, '{}'::jsonb, 'damage_reduction', 0.08, 35, '🍃')
) as v(class_key, key, name, description, skill_type, power, cooldown, effect, effect_type, effect_value, unlock_level, icon)
join classes cl on cl.key = v.class_key;

-- Trang bị lại cho mọi nhân vật: 2 skill chủ động + 1 bị động mạnh nhất đã mở
insert into character_equipped_skills (character_id, skill_id)
select c.id, s.id
from characters c
cross join lateral (
  select sk.id from skills sk
  where sk.class_id = c.class_id and sk.skill_type = 'active' and sk.unlock_level <= c.level
  order by sk.unlock_level desc limit 2
) s
union all
select c.id, s.id
from characters c
cross join lateral (
  select sk.id from skills sk
  where sk.class_id = c.class_id and sk.skill_type = 'passive' and sk.unlock_level <= c.level
  order by sk.unlock_level desc limit 1
) s;

create or replace function public.get_skill_kit(p_character_id uuid)
returns jsonb
language sql
stable
set search_path = 'public'
as $$
  select jsonb_build_object(
    'actives', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', s.name, 'power', s.power_multiplier, 'cooldown', s.cooldown, 'effect', s.effect
             ) order by s.unlock_level)
      from character_equipped_skills ces join skills s on s.id = ces.skill_id
      where ces.character_id = p_character_id and s.skill_type = 'active'), '[]'::jsonb),
    'crit_damage', coalesce((
      select sum(s.effect_value)
      from character_equipped_skills ces join skills s on s.id = ces.skill_id
      where ces.character_id = p_character_id and s.skill_type = 'passive' and s.effect_type = 'crit_damage'), 0)
  );
$$;

-- Nhân vật mới: tự trang bị skill chủ động + bị động cấp 1 (trước đây chỉ đánh thường)
-- Lấp ô kỹ năng còn trống bằng skill mạnh nhất đã mở (cấp mở cao nhất). Gọi khi tạo
-- nhân vật và khi lên cấp — lên cấp 5/8/12… tự có skill mới thay vì ô trống.
create or replace function public.fill_skill_slots(p_character_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_class_id uuid; v_level int; v_type text; v_free int;
begin
  select c.class_id, c.level into v_class_id, v_level from characters c where c.id = p_character_id;
  if not found then return; end if;

  foreach v_type in array array['active', 'passive'] loop
    v_free := case when v_type = 'passive' then 1 when v_level >= 8 then 2 else 1 end
      - (select count(*) from character_equipped_skills ces join skills s on s.id = ces.skill_id
         where ces.character_id = p_character_id and s.skill_type = v_type);
    continue when v_free <= 0;

    insert into character_equipped_skills (character_id, skill_id)
    select p_character_id, s.id from skills s
    where s.class_id = v_class_id and s.skill_type = v_type and s.unlock_level <= v_level
      and not exists (select 1 from character_equipped_skills ces
                      where ces.character_id = p_character_id and ces.skill_id = s.id)
    order by s.unlock_level desc
    limit v_free;
  end loop;
end;
$$;

revoke execute on function public.fill_skill_slots(uuid) from public, anon, authenticated;

create or replace function public.equip_starter_skills()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  perform fill_skill_slots(new.id);
  return new;
end;
$$;

drop trigger if exists equip_starter_skills on characters;
create trigger equip_starter_skills
  after insert on characters
  for each row execute function public.equip_starter_skills();

-- Lên cấp: tự lấp ô kỹ năng mới mở
create or replace function public.fill_skill_slots_on_level_up()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  perform fill_skill_slots(new.id);
  return new;
end;
$$;

drop trigger if exists fill_skill_slots_on_level_up on characters;
create trigger fill_skill_slots_on_level_up
  after update of level on characters
  for each row when (new.level > old.level)
  execute function public.fill_skill_slots_on_level_up();

-- ============================================================================
-- CHẾ TẠO MỞ RỘNG: giáp / phụ kiện mọi vùng + bình máu
-- ============================================================================

insert into recipes (key, name, result_item_id, gold_cost, success_rate, result_quantity, description)
select v.key, v.name, i.id, v.gold, v.rate, v.qty, v.description
from (values
  ('craft_iron_helmet', 'Chế Nón Sắt', 'iron_helmet', 20, 0.8, 1, 'Cần 4 Nanh Sói'),
  ('craft_traveler_boots', 'Chế Giày Lữ Hành', 'traveler_boots', 20, 0.8, 1, 'Cần 4 Nanh Sói'),
  ('craft_leather_armor', 'Chế Áo Da', 'leather_armor', 30, 0.75, 1, 'Cần 5 Nanh Sói'),
  ('craft_iron_shield', 'Chế Khiên Bọc Sắt', 'iron_shield', 30, 0.75, 1, 'Cần 5 Nanh Sói'),
  ('craft_ring_ruby', 'Chế Nhẫn Đá Đỏ', 'ring_ruby', 40, 0.7, 1, 'Cần 6 Nanh Sói'),
  ('craft_guardian_amulet', 'Chế Bùa Hộ Mệnh', 'guardian_amulet', 40, 0.7, 1, 'Cần 6 Nanh Sói'),
  ('craft_desert_turban', 'Chế Khăn Sa Mạc', 'desert_turban', 80, 0.6, 1, 'Cần 6 Bọ Hung Cát'),
  ('craft_sandstrider_boots', 'Chế Giày Lướt Cát', 'sandstrider_boots', 80, 0.6, 1, 'Cần 6 Bọ Hung Cát'),
  ('craft_obsidian_shield', 'Chế Khiên Hắc Diện Thạch', 'obsidian_shield', 120, 0.55, 1, 'Cần 6 Lõi Dung Nham'),
  ('craft_ember_amulet', 'Chế Bùa Than Hồng', 'ember_amulet', 120, 0.55, 1, 'Cần 6 Lõi Dung Nham + 3 Bọ Hung Cát'),
  ('craft_shadow_cloak', 'Chế Áo Choàng Bóng Đêm', 'shadow_cloak', 160, 0.5, 1, 'Cần 6 Tinh Chất Bóng Đêm'),
  ('craft_bone_ring', 'Chế Nhẫn Xương', 'bone_ring', 160, 0.5, 1, 'Cần 6 Tinh Chất Bóng Đêm + 3 Lõi Dung Nham'),
  ('craft_paladin_helm', 'Chế Mũ Hiệp Sĩ Thánh', 'paladin_helm', 220, 0.45, 1, 'Cần 6 Thánh Tích'),
  ('craft_radiant_belt', 'Chế Đai Rạng Ngời', 'radiant_belt', 220, 0.45, 1, 'Cần 6 Thánh Tích'),
  ('craft_voidwalker_boots', 'Chế Giày Lữ Khách Hư Không', 'voidwalker_boots', 300, 0.4, 1, 'Cần 6 Pha Lê Hư Không'),
  ('craft_star_ring', 'Chế Nhẫn Tinh Tú', 'star_ring', 300, 0.4, 1, 'Cần 6 Pha Lê Hư Không + 3 Thánh Tích'),
  ('craft_crystal_plate', 'Chế Giáp Pha Lê', 'crystal_plate', 380, 0.35, 1, 'Cần 6 Lăng Kính Hỗn Mang'),
  ('craft_prism_amulet', 'Chế Bùa Lăng Kính', 'prism_amulet', 380, 0.35, 1, 'Cần 6 Lăng Kính Hỗn Mang + 3 Pha Lê Hư Không'),
  ('craft_seraph_crown', 'Chế Vương Miện Thiên Sứ', 'seraph_crown', 480, 0.3, 1, 'Cần 6 Lông Thiên Sứ'),
  ('craft_celestial_shield', 'Chế Khiên Thiên Giới', 'celestial_shield', 480, 0.3, 1, 'Cần 6 Lông Thiên Sứ + 3 Lăng Kính Hỗn Mang'),
  ('craft_potion_minor', 'Pha Bình Máu Nhỏ', 'potion_minor', 0, 0.9, 1, 'Cần 2 Nanh Sói'),
  ('craft_potion_medium', 'Pha Bình Máu Vừa', 'potion_medium', 0, 0.85, 1, 'Cần 2 Bọ Hung Cát'),
  ('craft_potion_large', 'Pha Bình Máu Lớn', 'potion_large', 0, 0.8, 1, 'Cần 2 Lõi Dung Nham'),
  ('craft_potion_supreme', 'Pha Bình Máu Thượng Hạng', 'potion_supreme', 0, 0.75, 1, 'Cần 2 Thánh Tích')
) as v(key, name, result_key, gold, rate, qty, description)
join items i on i.key = v.result_key
on conflict (key) do nothing;

insert into recipe_ingredients (recipe_id, item_id, quantity)
select r.id, i.id, ing.qty
from (values
  ('craft_iron_helmet', 'wolf_fang', 4),
  ('craft_traveler_boots', 'wolf_fang', 4),
  ('craft_leather_armor', 'wolf_fang', 5),
  ('craft_iron_shield', 'wolf_fang', 5),
  ('craft_ring_ruby', 'wolf_fang', 6),
  ('craft_guardian_amulet', 'wolf_fang', 6),
  ('craft_desert_turban', 'sand_scarab', 6),
  ('craft_sandstrider_boots', 'sand_scarab', 6),
  ('craft_obsidian_shield', 'magma_core', 6),
  ('craft_ember_amulet', 'magma_core', 6),
  ('craft_ember_amulet', 'sand_scarab', 3),
  ('craft_shadow_cloak', 'shadow_essence', 6),
  ('craft_bone_ring', 'shadow_essence', 6),
  ('craft_bone_ring', 'magma_core', 3),
  ('craft_paladin_helm', 'holy_relic', 6),
  ('craft_radiant_belt', 'holy_relic', 6),
  ('craft_voidwalker_boots', 'void_crystal', 6),
  ('craft_star_ring', 'void_crystal', 6),
  ('craft_star_ring', 'holy_relic', 3),
  ('craft_crystal_plate', 'chaos_prism', 6),
  ('craft_prism_amulet', 'chaos_prism', 6),
  ('craft_prism_amulet', 'void_crystal', 3),
  ('craft_seraph_crown', 'angel_feather', 6),
  ('craft_celestial_shield', 'angel_feather', 6),
  ('craft_celestial_shield', 'chaos_prism', 3),
  ('craft_potion_minor', 'wolf_fang', 2),
  ('craft_potion_medium', 'sand_scarab', 2),
  ('craft_potion_large', 'magma_core', 2),
  ('craft_potion_supreme', 'holy_relic', 2)
) as ing(recipe_key, item_key, qty)
join recipes r on r.key = ing.recipe_key
join items i on i.key = ing.item_key
on conflict (recipe_id, item_id) do nothing;

-- ============================================================================
-- DÒNG TIỆN ÍCH TRANG BỊ + GỘP CHỈ SỐ VÒNG ĐÁNH
-- ============================================================================

alter table inventory add column if not exists rolled_extra jsonb not null default '{}'::jsonb;

-- Tổng dòng tiện ích của đồ đang mặc
create or replace function public.get_gear_mods(p_character_id uuid)
returns jsonb
language sql
stable
set search_path = 'public'
as $$
  select coalesce(jsonb_object_agg(e.key, e.total), '{}'::jsonb)
  from (
    select x.key, sum(x.value::text::numeric) as total
    from inventory inv cross join lateral jsonb_each(inv.rolled_extra) x
    where inv.character_id = p_character_id and inv.equipped
    group by x.key
  ) e;
$$;

-- Mọi thứ vòng đánh cần ngoài chỉ số: thiên phú + dòng tiện ích trang bị (cộng dồn) + bộ kỹ năng.
-- dmg_red của đồ đi riêng (gear_dmg_red) vì dmg_red thiên phú đã gộp ở get_combat_skills.
create or replace function public.combat_mods(p_character_id uuid)
returns jsonb
language plpgsql
stable
set search_path = 'public'
as $$
declare
  v jsonb := get_talent_totals(p_character_id);
  g jsonb := get_gear_mods(p_character_id);
  k text;
begin
  for k in select jsonb_object_keys(g) loop
    if k = 'dmg_red' then
      v := v || jsonb_build_object('gear_dmg_red', (g->>k)::numeric);
    else
      v := v || jsonb_build_object(k, coalesce((v->>k)::numeric, 0) + (g->>k)::numeric);
    end if;
  end loop;
  return v || jsonb_build_object('kit', get_skill_kit(p_character_id));
end;
$$;

-- Chân dung nhân vật (public/portraits/<class>_<n>.png)
alter table characters add column if not exists portrait text;
alter table characters drop constraint if exists characters_portrait_format;
alter table characters
  add constraint characters_portrait_format check (portrait ~ '^(warrior|mage|archer|assassin)_([1-9]|10)$');

-- Icon kỹ năng + khung chân dung
update skills set icon = '/skills/' || key || '.png'
where key in ('warrior_slash', 'warrior_knight', 'warrior_drain', 'warrior_despair', 'warrior_holy', 'warrior_armor', 'warrior_will', 'mage_fireball', 'mage_frost', 'mage_shatter', 'mage_inferno', 'mage_meteor', 'mage_shield', 'mage_focus', 'assassin_stab', 'assassin_venom', 'assassin_iai', 'assassin_divine', 'assassin_execute', 'assassin_critdmg', 'assassin_shadow', 'archer_shot', 'archer_pierce', 'archer_aimed', 'archer_fire', 'archer_volley', 'archer_eagle', 'archer_reflex');

alter table characters add column if not exists frame text;
alter table characters drop constraint if exists characters_frame_key;
alter table characters
  add constraint characters_frame_key check (frame in ('wood', 'bronze', 'silver', 'gold', 'bloom', 'engraved', 'moss'));

-- Điều kiện mở khung chân dung — khớp FRAMES trong lib/frames.ts
create or replace function public.frame_unlocked(
  p_frame text, p_level int, p_tower_best int, p_legendary_found int, p_boss_kills int
)
returns boolean
language sql
immutable
as $$
  select case p_frame
    when 'wood' then true
    when 'bronze' then p_level >= 20
    when 'silver' then p_level >= 40 or p_tower_best >= 30
    when 'gold' then p_level >= 60 or p_tower_best >= 60
    when 'bloom' then p_legendary_found >= 1
    when 'moss' then p_boss_kills >= 50
    when 'engraved' then p_tower_best >= 100
    else false
  end;
$$;

-- ============================================================================
-- CHỢ: TIẾP TẾ CHO CHUYẾN ĐI (bình % HP tự uống, cuộn / bùa, giá theo cấp, giới hạn ngày)
-- ============================================================================

alter table items add column if not exists heal_pct numeric not null default 0;       -- hồi % HP tối đa
alter table items add column if not exists price_per_level int not null default 0;    -- giá = buy_price + x × cấp
alter table items add column if not exists daily_limit int;                          -- null = không giới hạn
alter table items add column if not exists buff_key text;                            -- exp | luck | guard
alter table items add column if not exists shop_listed boolean not null default true;
alter table characters add column if not exists auto_potion boolean not null default true;

-- Cuộn / bùa đã dùng, chờ áp vào chuyến khám phá hoặc lần leo tháp kế tiếp
create table if not exists character_buffs (
  character_id uuid not null references characters(id) on delete cascade,
  buff_key     text not null,
  created_at   timestamptz not null default now(),
  primary key (character_id, buff_key)
);
alter table character_buffs enable row level security;
drop policy if exists "own buffs select" on character_buffs;
create policy "own buffs select" on character_buffs
  for select using (exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid()));
grant select on table character_buffs to authenticated;

-- Số lượng đã mua trong ngày (giờ VN) cho món có daily_limit
create table if not exists shop_daily (
  character_id uuid not null references characters(id) on delete cascade,
  item_id      uuid not null references items(id),
  day          date not null,
  qty          int not null default 0,
  primary key (character_id, item_id, day)
);
alter table shop_daily enable row level security;
drop policy if exists "own shop_daily select" on shop_daily;
create policy "own shop_daily select" on shop_daily
  for select using (exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid()));
grant select on table shop_daily to authenticated;

-- Bình máu hồi theo % HP (không lỗi thời theo cấp), giá nhích theo cấp
update items i set heal_pct = v.pct, price_per_level = v.ppl, description = v.descr
from (values
  ('potion_minor', 0.15, 1, 'Hồi 15% HP tối đa. Tự uống trong khám phá / tháp khi HP dưới 35%.'),
  ('potion_medium', 0.25, 2, 'Hồi 25% HP tối đa. Tự uống trong khám phá / tháp khi HP dưới 35%.'),
  ('potion_large', 0.35, 4, 'Hồi 35% HP tối đa. Tự uống trong khám phá / tháp khi HP dưới 35%.'),
  ('potion_supreme', 0.50, 6, 'Hồi 50% HP tối đa. Tự uống trong khám phá / tháp khi HP dưới 35%.')
) as v(key, pct, ppl, descr)
where i.key = v.key;

-- Trang bị thường cấp 1 không còn bán (vô dụng từ cấp 5); đồ đã mua vẫn giữ
update items set shop_listed = false
where key in ('iron_helmet', 'traveler_boots', 'ring_ruby', 'guardian_amulet', 'iron_shield');

insert into items (key, name, type, rarity, buy_price, price_per_level, daily_limit, buff_key, sell_price, description, icon) values
  ('scroll_exp', 'Cuộn Tri Thức', 'consumable', 'epic', 500, 200, 1, 'exp', 0,
   '+25% EXP cho chuyến khám phá / lần leo tháp kế tiếp. Mua tối đa 1 cuộn mỗi ngày.', 'scroll_exp.png'),
  ('scroll_luck', 'Cuộn May Mắn', 'consumable', 'rare', 300, 80, 2, 'luck', 0,
   '+30% tỉ lệ rơi đồ cho chuyến khám phá / lần leo tháp kế tiếp. Mua tối đa 2 cuộn mỗi ngày.', 'scroll_luck.png'),
  ('charm_guard', 'Bùa Hộ Mệnh', 'consumable', 'epic', 400, 100, 1, 'guard', 0,
   'Gục ngã trong chuyến kế tiếp thì đứng dậy với 50% HP và đánh tiếp (1 lần). Mua tối đa 1 bùa mỗi ngày.', 'charm_guard.png')
on conflict (key) do nothing;

-- Uống bình máu mạnh nhất đang có (dùng trong khám phá / tháp). Hết bình → out_name null.
create or replace function public.drink_best_potion(p_character_id uuid, p_hp int, p_max_hp int)
returns table(out_hp int, out_name text)
language plpgsql
set search_path = 'public'
as $$
declare
  v_row record;
begin
  select inv.id as inv_id, inv.quantity as qty, i.name as item_name,
         greatest(coalesce(i.heal_amount, 0), round(p_max_hp * i.heal_pct)::int) as heal
    into v_row
  from inventory inv join items i on i.id = inv.item_id
  where inv.character_id = p_character_id and i.heal_pct > 0 and inv.quantity > 0
  order by i.heal_pct desc, inv.acquired_at
  limit 1
  for update of inv;

  if v_row.inv_id is null then
    return query select p_hp, null::text;
    return;
  end if;

  if v_row.qty <= 1 then
    delete from inventory where id = v_row.inv_id;
  else
    update inventory set quantity = quantity - 1 where id = v_row.inv_id;
  end if;

  return query select least(p_max_hp, p_hp + v_row.heal), v_row.item_name;
end;
$$;

revoke execute on function public.drink_best_potion(uuid, int, int) from public, anon, authenticated;

-- ============================================================================
-- CÂN BẰNG HARDCORE (chạy sau seed: class, skill, quái vùng, mốc EXP)
-- ============================================================================

-- Class: bớt khoảng cách máu mỏng / máu trâu (quái trâu hơn → trận dài hơn → HP quyết định)
update classes c set base_hp = v.hp, base_def = v.def
from (values ('warrior', 120, 10), ('mage', 95, 8), ('archer', 115, 11), ('assassin', 120, 10)) as v(key, hp, def)
where c.key = v.key;
update skills set effect = '{"lifesteal": 0.12}'::jsonb, description = '140% ATK, hồi HP bằng 12% sát thương gây ra'
where key = 'warrior_drain';
update skills set power_multiplier = 1.6, description = '160% ATK, xuyên 50% DEF' where key = 'archer_pierce';

-- Quái vùng: HP ×(2 + 0.025 × cấp), ATK ×1.15 (chạy 1 lần — nhân trên chỉ số đang có)
update zone_enemies set hp = round(hp * (2 + 0.025 * level)), atk = round(atk * 1.15);

-- Đường EXP gấp 2.5 lần: cập nhật mốc của nhân vật hiện có (giữ EXP đang tích)
update characters set exp_to_next = round(2.5 * (100 + (level - 1) * 50));

-- ============================================================================
-- CÂN BẰNG CẤP CAO + ĐẶC TÍNH QUÁI (chạy sau seed + cân bằng hardcore)
-- ============================================================================
update classes c set base_crit = v.crit
from (values ('warrior', 0.05), ('mage', 0.08), ('archer', 0.10), ('assassin', 0.15)) as v(key, crit)
where c.key = v.key;

update zones z set traits = v.traits
from (values
  ('hang_dong', array['evasive']), ('nui_tuyet', array['armored']), ('sa_mac', array['venom']),
  ('nui_lua', array['enrage']), ('vuc_toi', array['unholy']), ('thanh_dia', array['regen']),
  ('hu_khong', array['evasive']), ('hon_nguyen', array['thorny']), ('thien_duong', array['savage'])
) as v(key, traits)
where z.key = v.key;

create or replace function public.enemy_level_mult(p_level int, p_atk boolean default false)
returns numeric
language sql
immutable
as $$
  select 1 + case when p_atk then 1.8 else 1.2 end * greatest(0, least(p_level, 85) - 30) / 55.0;
$$;

-- Quái vùng từ Lv30 (chạy 1 lần — nhân trên chỉ số đang có)
update zone_enemies set hp = round(hp * enemy_level_mult(level)), atk = round(atk * enemy_level_mult(level, true))
where level > 30;

create or replace function public.enemy_extra_traits(p_n int, p_exclude text[])
returns text[]
language sql
volatile
as $$
  select coalesce(array_agg(t), '{}') from (
    select t from unnest(array['armored','evasive','savage','enrage','venom','regen','thorny','unholy']) t
    where not t = any(p_exclude)
    order by random() limit p_n
  ) x;
$$;

-- Xoá nhân vật (client không có quyền DELETE trên characters)
create or replace function public.delete_character(p_character_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  delete from characters c where c.id = p_character_id and c.user_id = auth.uid();
  if not found then raise exception 'Không tìm thấy nhân vật hoặc không có quyền xoá'; end if;
end;
$$;

revoke execute on function public.delete_character(uuid) from public, anon;
grant execute on function public.delete_character(uuid) to authenticated;
