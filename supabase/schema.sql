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
  effect_type      text,                           -- damage_reduction | lifesteal | crit_chance (passive)
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
    -- Chặn trong khoảng [0.2x, 3.0x] để không rơi về 0 hoặc vọt quá vô lý.
    greatest(0.2, least(3.0, 1 + (p_enemy_level - p_character_level) * 0.15)) as exp_multiplier,
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
    -- AGI +0.5% chí mạng, DEX +0.3% chí mạng (mọi class)
    p_agi * 0.005 + p_dex * 0.003;
$$;

-- Chỉ số tổng hợp của nhân vật: base_* = class + cấp + điểm chỉ số (chưa có
-- trang bị), còn max_hp/atk/def/crit_bonus/lifesteal_bonus = đã cộng trang bị.
-- Dùng chung cho combat, use_item, reset_stats và các trang hiển thị để số
-- trên UI không lệch với số trong trận. security invoker: RLS vẫn áp dụng khi
-- client gọi trực tiếp (chỉ đọc được nhân vật của chính mình).
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
    b.attr_crit + e.crit, e.lifesteal
  from (
    select
      cl.base_hp + (ch.level - 1) * cl.hp_per_level + ab.attr_hp as base_max_hp,
      cl.base_atk + (ch.level - 1) * cl.atk_per_level + ab.attr_atk as base_atk,
      cl.base_def + (ch.level - 1) * cl.def_per_level + ab.attr_def as base_def,
      cl.base_spd + (ch.level - 1) * cl.spd_per_level as base_spd,
      ab.attr_crit
    from characters ch
    join classes cl on cl.id = ch.class_id
    cross join lateral attribute_bonuses(
      cl.main_stat, ch.stat_str, ch.stat_int, ch.stat_agi, ch.stat_dex, ch.stat_vit
    ) ab
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
    v_exp_to_next := 100 + (v_level - 1) * 50;
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
returns table(roll_atk int, roll_def int, roll_hp int, roll_crit numeric, roll_lifesteal numeric)
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
  i int;
begin
  case p_rarity
    when 'legendary' then v_roll_count := 4; v_flat_min := 7; v_flat_max := 12; v_pct_min := 0.05; v_pct_max := 0.10;
    when 'epic'      then v_roll_count := 3; v_flat_min := 4; v_flat_max := 8;  v_pct_min := 0.03; v_pct_max := 0.06;
    when 'rare'      then v_roll_count := 2; v_flat_min := 2; v_flat_max := 5;  v_pct_min := 0.02; v_pct_max := 0.04;
    else                  v_roll_count := 1; v_flat_min := 1; v_flat_max := 3;  v_pct_min := 0.01; v_pct_max := 0.02;
  end case;

  v_pool := case
    when p_slot = 'weapon' and p_school = 'magic' then array['atk', 'lifesteal']
    when p_slot = 'weapon' then array['atk', 'crit', 'lifesteal']
    when p_slot in ('amulet', 'ring') then array['atk', 'def', 'hp', 'crit', 'lifesteal']
    when p_slot in ('shield', 'head', 'chest', 'belt', 'boot') then array['def', 'hp']
    else null
  end;

  if v_pool is null then
    return query select 0, 0, 0, 0::numeric, 0::numeric;
    return;
  end if;

  for i in 1..v_roll_count loop
    v_stat := v_pool[1 + floor(random() * array_length(v_pool, 1))::int];
    if v_stat = 'atk' then
      v_atk := v_atk + (v_flat_min + floor(random() * (v_flat_max - v_flat_min + 1)))::int;
    elsif v_stat = 'def' then
      v_def := v_def + (v_flat_min + floor(random() * (v_flat_max - v_flat_min + 1)))::int;
    elsif v_stat = 'hp' then
      v_hp := v_hp + ((v_flat_min + floor(random() * (v_flat_max - v_flat_min + 1))) * 3)::int;
    elsif v_stat = 'crit' then
      v_crit := v_crit + round((v_pct_min + random() * (v_pct_max - v_pct_min))::numeric, 4);
    elsif v_stat = 'lifesteal' then
      v_lifesteal := v_lifesteal + round((v_pct_min + random() * (v_pct_max - v_pct_min))::numeric, 4);
    end if;
  end loop;

  return query select v_atk, v_def, v_hp, v_crit, v_lifesteal;
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
-- ============================================================================
-- BẢNG TIN + HIỆU ỨNG HUYỀN THOẠI
-- ============================================================================

-- 1. Bảng tin ----------------------------------------------------------------
create table if not exists activity_feed (
  id             uuid primary key default gen_random_uuid(),
  character_id   uuid references characters(id) on delete set null,
  character_name text not null,               -- chụp lại tên lúc xảy ra
  kind           text not null check (kind in ('boss_kill', 'legendary_item', 'title')),
  character_title text,                       -- danh hiệu đang đeo lúc đăng
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
  select case p_rarity when 'legendary' then 2.0 when 'epic' then 1.6 when 'rare' then 1.25 else 1.0 end;
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

  select buy_price, type into v_buy_price, v_item_type from items where id = p_item_id;

  if v_buy_price is null then
    raise exception 'Vật phẩm này không bán trong chợ';
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
      new.exp_to_next := 100;
      new.gold := 100;
      new.current_chapter := 1;
      new.current_hp := null;
      new.current_ap := 100;
      new.max_ap := 100;
      new.ap_regen_minutes := 1;
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

  v_limit := case when v_skill_type = 'passive' then 1 else 2 end;

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
  ('thien_duong', 'Phượng Hoàng', 75, 30, false),
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
