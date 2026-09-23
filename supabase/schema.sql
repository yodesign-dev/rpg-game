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
  ap_regen_minutes  int not null default 10,   -- +1 AP mỗi X phút
  last_ap_update    timestamptz not null default now(),
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
create policy "own pets insert" on character_pets
  for insert with check (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );
create policy "own pets update" on character_pets
  for update using (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );

create policy "own inventory select" on inventory
  for select using (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );
create policy "own inventory insert" on inventory
  for insert with check (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );
create policy "own inventory update" on inventory
  for update using (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );

create policy "own dungeon_runs select" on dungeon_runs
  for select using (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );
create policy "own dungeon_runs insert" on dungeon_runs
  for insert with check (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );
create policy "own dungeon_runs update" on dungeon_runs
  for update using (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );

create policy "own character_quests select" on character_quests
  for select using (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );
create policy "own character_quests insert" on character_quests
  for insert with check (
    exists (select 1 from characters c where c.id = character_id and c.user_id = auth.uid())
  );
create policy "own character_quests update" on character_quests
  for update using (
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
  v_level int; v_exp int; v_gold int; v_current_hp int; v_current_ap int; v_max_ap int; v_class_id uuid;
  v_max_hp int;
  -- Chỉ số tổng hợp (class + cấp + điểm chỉ số + trang bị, xem get_character_stats)
  v_stat_crit_bonus numeric; v_stat_lifesteal_bonus numeric;
  -- Skill
  v_a1_name text; v_a1_power numeric; v_a2_name text; v_a2_power numeric;
  v_passive_type text; v_passive_value numeric;
  v_dmg_reduction numeric := 0; v_lifesteal numeric := 0; v_crit_chance numeric := 0;
  -- Tầng / quái
  v_dungeon_id uuid; v_ap_cost int; v_enemy_name text; v_enemy_level int;
  v_enemy_hp int; v_enemy_atk int; v_enemy_def int;
  v_reward_exp int; v_reward_gold int; v_drop_item_id uuid; v_drop_rate numeric; v_drop_item_key text;
  v_is_boss boolean; v_floor_number int;
  -- Roll đồ rơi
  v_drop_slot text; v_drop_school text; v_drop_rarity text;
  v_roll_atk int; v_roll_def int; v_roll_hp int; v_roll_crit numeric; v_roll_lifesteal numeric;
  -- Scaling
  v_exp_multiplier numeric; v_damage_multiplier numeric;
  -- Vòng lặp trận đấu
  v_char_atk int; v_char_def int;
  v_char_hp int; v_enemy_cur_hp int; v_turn int := 0;
  v_skill_name text; v_skill_power numeric;
  v_base_dmg numeric; v_is_crit boolean; v_dmg int;
  v_enemy_dmg numeric;
  v_log jsonb := '[]'::jsonb;
  v_win boolean;
  v_timed_out boolean := false;
  v_final_hp int;
  v_was_full_ap boolean;
  -- Kết quả cộng dồn
  v_exp_gained int := 0; v_gold_gained int := 0; v_item_dropped text := null;
  v_leveled_up boolean := false; v_new_level int;
begin
  -- 1. Khóa + đọc dữ liệu nhân vật
  select user_id, level, exp, gold, current_hp, current_ap, max_ap, class_id
    into v_owner_user_id, v_level, v_exp, v_gold, v_current_hp, v_current_ap, v_max_ap, v_class_id
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  -- 2. Chỉ số tổng hợp: class + cấp + điểm chỉ số + trang bị (kể cả affix roll)
  select gs.max_hp, gs.atk, gs.def, gs.crit_bonus, gs.lifesteal_bonus
    into v_max_hp, v_char_atk, v_char_def, v_stat_crit_bonus, v_stat_lifesteal_bonus
  from get_character_stats(p_character_id) gs;

  v_current_hp := coalesce(v_current_hp, v_max_hp);

  if v_current_hp <= 0 then
    raise exception 'Nhân vật đang kiệt sức, cần hồi máu trước khi vào dungeon';
  end if;

  -- 3. Tầng dungeon đang đánh
  select df.dungeon_id, df.floor_number, df.is_boss_floor, df.enemy_name, df.enemy_level,
         df.enemy_hp, df.enemy_atk, df.enemy_def, df.reward_exp, df.reward_gold,
         df.drop_item_id, df.drop_rate, d.ap_cost
    into v_dungeon_id, v_floor_number, v_is_boss, v_enemy_name, v_enemy_level,
         v_enemy_hp, v_enemy_atk, v_enemy_def, v_reward_exp, v_reward_gold,
         v_drop_item_id, v_drop_rate, v_ap_cost
  from dungeon_floors df join dungeons d on d.id = df.dungeon_id
  where df.id = p_dungeon_floor_id;

  if not found then raise exception 'Không tìm thấy tầng dungeon'; end if;

  if v_current_ap < v_ap_cost then
    raise exception 'Không đủ AP để vào tầng này (cần % AP)', v_ap_cost;
  end if;

  -- 4. Skill đang trang bị (2 active + tối đa 1 passive)
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

  if v_passive_type = 'damage_reduction' then v_dmg_reduction := v_passive_value;
  elsif v_passive_type = 'lifesteal' then v_lifesteal := v_passive_value;
  elsif v_passive_type = 'crit_chance' then v_crit_chance := v_passive_value;
  end if;

  -- Cộng dồn bonus chí mạng (AGI/DEX + affix) và hút máu (affix) trên nền skill
  -- bị động. Chí mạng chặn ở 75% để AGI dồn cao không thành crit mọi đòn.
  v_crit_chance := least(0.75, v_crit_chance + v_stat_crit_bonus);
  v_lifesteal := v_lifesteal + v_stat_lifesteal_bonus;

  -- 5. Hệ số scaling theo chênh lệch cấp độ
  select exp_multiplier, damage_multiplier into v_exp_multiplier, v_damage_multiplier
  from calculate_combat_scaling(v_level, v_enemy_level);

  -- 6. Mô phỏng trận đấu
  v_char_hp := v_current_hp;
  v_enemy_cur_hp := v_enemy_hp;

  while v_char_hp > 0 and v_enemy_cur_hp > 0 and v_turn < 30 loop
    v_turn := v_turn + 1;

    if v_turn % 2 = 1 then
      v_skill_name := v_a1_name; v_skill_power := v_a1_power;
    else
      v_skill_name := v_a2_name; v_skill_power := v_a2_power;
    end if;

    v_base_dmg := greatest(1, v_char_atk * v_skill_power - v_enemy_def);
    v_is_crit := random() < v_crit_chance;
    v_dmg := round(v_base_dmg * (case when v_is_crit then 1.5 else 1 end));
    v_enemy_cur_hp := greatest(0, v_enemy_cur_hp - v_dmg);

    if v_lifesteal > 0 then
      v_char_hp := least(v_max_hp, v_char_hp + round(v_dmg * v_lifesteal));
    end if;

    v_log := v_log || jsonb_build_object(
      'turn', v_turn, 'actor', 'character', 'skill', v_skill_name,
      'damage', v_dmg, 'crit', v_is_crit, 'enemy_hp_left', v_enemy_cur_hp
    );

    exit when v_enemy_cur_hp <= 0;

    v_enemy_dmg := greatest(1, v_enemy_atk - v_char_def) * v_damage_multiplier * (1 - v_dmg_reduction);
    v_char_hp := greatest(0, v_char_hp - round(v_enemy_dmg));

    v_log := v_log || jsonb_build_object(
      'turn', v_turn, 'actor', 'enemy', 'enemy_name', v_enemy_name,
      'damage', round(v_enemy_dmg), 'character_hp_left', v_char_hp
    );
  end loop;

  v_win := v_enemy_cur_hp <= 0 and v_char_hp > 0;

  -- Hết 30 lượt mà cả hai còn sống: không xác định được thắng thua bằng sát
  -- thương, ghi rõ lý do vào log thay vì báo "Thất bại" mập mờ dù HP còn đầy.
  if not v_win and v_char_hp > 0 and v_enemy_cur_hp > 0 then
    v_timed_out := true;
    v_log := v_log || jsonb_build_object(
      'turn', v_turn, 'actor', 'system',
      'message', 'Hết giới hạn lượt đánh (30 lượt), buộc phải rút lui'
    );
  end if;

  v_final_hp := case when v_win then v_char_hp else greatest(1, v_char_hp) end;

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
      select slot, coalesce(school, 'physical'), rarity
        into v_drop_slot, v_drop_school, v_drop_rarity
      from items where id = v_drop_item_id;

      select roll_atk, roll_def, roll_hp, roll_crit, roll_lifesteal
        into v_roll_atk, v_roll_def, v_roll_hp, v_roll_crit, v_roll_lifesteal
      from roll_item_affixes(v_drop_slot, v_drop_school, v_drop_rarity);

      insert into inventory (character_id, item_id, quantity, rolled_atk, rolled_def, rolled_hp, rolled_crit, rolled_lifesteal)
      values (p_character_id, v_drop_item_id, 1, v_roll_atk, v_roll_def, v_roll_hp, v_roll_crit, v_roll_lifesteal);

      select key into v_drop_item_key from items where id = v_drop_item_id;
      v_item_dropped := v_drop_item_key;
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

create or replace function public.use_item(p_character_id uuid, p_inventory_id uuid)
returns table(new_current_hp int, new_max_hp int, new_current_ap int, new_quantity int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_level int; v_current_hp int; v_current_ap int; v_max_ap int; v_class_id uuid;
  v_max_hp int;
  v_item_id uuid; v_quantity int; v_type text; v_heal_amount int; v_restore_ap int;
  v_new_hp int; v_new_ap int; v_new_quantity int;
begin
  select user_id, level, current_hp, current_ap, max_ap, class_id
    into v_owner_user_id, v_level, v_current_hp, v_current_ap, v_max_ap, v_class_id
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

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

create or replace function public.craft_item(p_character_id uuid, p_recipe_id uuid)
returns table(success boolean, result_name text, new_gold int)
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
      insert into inventory (character_id, item_id, quantity) values (p_character_id, v_result_item_id, v_result_qty);
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

  return query select v_success, v_result_name, (v_gold - v_gold_cost);
end;
$$;

-- ============================================================================
-- Trang bị đầy đủ: head/chest/belt/amulet/boot + 2 khớp tay riêng (l_arm/
-- r_arm) cho vũ khí/khiên. Vũ khí 2 tay (ví dụ trượng của pháp sư) chiếm cả
-- hai khớp tay cùng lúc và không thể mặc thêm khiên/vũ khí khác cho đến khi
-- gỡ ra. Trang bị/gỡ vẫn là update() trực tiếp từ client theo RLS
-- "own inventory update" sẵn có — không đụng gold/HP nên không cần RPC.
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
      new.ap_regen_minutes := 10;
      new.last_ap_update := now();
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

-- Hồi AP kiểu lazy: +1 AP mỗi ap_regen_minutes phút kể từ last_ap_update, tối
-- đa max_ap. Mốc last_ap_update chỉ tiến đúng số tick đã cộng để phần phút lẻ
-- không bị mất. Trả về AP hiện tại và số phút tới lần hồi kế tiếp (null nếu
-- AP đã đầy). Tên cột trả về có tiền tố out_ để tránh lỗi 42702 (trùng tên với
-- cột current_ap của bảng characters).
create or replace function public.apply_ap_regen(p_character_id uuid)
returns table(out_current_ap int, out_next_ap_minutes int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_current_ap int; v_max_ap int; v_regen_minutes int; v_last_update timestamptz;
  v_elapsed_minutes int; v_ticks int;
  v_next int := null;
begin
  select c.user_id, c.current_ap, c.max_ap, greatest(1, c.ap_regen_minutes), c.last_ap_update
    into v_owner_user_id, v_current_ap, v_max_ap, v_regen_minutes, v_last_update
  from characters c where c.id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  v_elapsed_minutes := greatest(0, floor(extract(epoch from (now() - v_last_update)) / 60))::int;
  v_ticks := v_elapsed_minutes / v_regen_minutes;

  if v_ticks > 0 and v_current_ap < v_max_ap then
    v_current_ap := least(v_max_ap, v_current_ap + v_ticks);

    update characters c
    set current_ap = v_current_ap,
        last_ap_update = c.last_ap_update + make_interval(mins => v_ticks * v_regen_minutes)
    where c.id = p_character_id;
  end if;

  if v_current_ap < v_max_ap then
    v_next := v_regen_minutes - (v_elapsed_minutes % v_regen_minutes);
  end if;

  return query select v_current_ap, v_next;
end;
$$;

-- ============================================================================
-- Ghi chú:
-- - Các thao tác nhạy cảm (trừ AP, mua bán, nhận thưởng dungeon/quest) đi qua
--   RPC security definer; trigger guard_character_game_state chặn client tự
--   sửa gold/exp/level/HP/AP của characters qua console trình duyệt.
-- - RLS ở trên chỉ chặn việc đọc/ghi TRỰC TIẾP từ client bằng anon key.
-- ============================================================================
