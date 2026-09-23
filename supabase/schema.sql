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
  hp_per_level  int not null default 8,
  atk_per_level int not null default 2,
  def_per_level int not null default 2,
  spd_per_level int not null default 1,
  icon          text,                         -- emoji hoặc tên icon dùng ở frontend
  sort_order    int not null default 0
);

insert into classes (key, name, description, base_hp, base_atk, base_def, base_spd, icon, sort_order) values
  ('warrior',  'Chiến Binh', 'Máu trâu, phòng thủ cao, đánh cận chiến ổn định. Dễ chơi cho người mới.', 120, 14, 12, 8,  '⚔️', 1),
  ('mage',     'Pháp Sư',    'Sát thương phép cực cao nhưng máu giấy, cần né đòn khéo léo.',           80,  20, 6,  9,  '🔮', 2),
  ('archer',   'Xạ Thủ',     'Tốc độ và sát thương ổn định, ra đòn liên tục, khắc chế boss đơn.',       95,  16, 8,  13, '🏹', 3),
  ('assassin', 'Sát Thủ',    'Chí mạng cao, đánh nhanh kết liễu sớm, nhưng dễ chết nếu bị dồn.',       85,  18, 7,  15, '🗡️', 4);

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
  slot         text,                           -- weapon | head | body | accessory | null
  rarity       text not null default 'common', -- common | rare | epic | legendary
  bonus_atk    int not null default 0,
  bonus_def    int not null default 0,
  bonus_hp     int not null default 0,
  heal_amount  int not null default 0,         -- dùng cho potion
  buy_price    int,                            -- null = không bán trong shop
  sell_price   int not null default 0,
  description  text
);

create table inventory (
  id            uuid primary key default gen_random_uuid(),
  character_id  uuid not null references characters(id) on delete cascade,
  item_id       uuid not null references items(id),
  quantity      int not null default 1,
  equipped      boolean not null default false,
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

-- Cộng EXP cho nhân vật, tự động lên cấp (có thể lên nhiều cấp cùng lúc).
create or replace function public.add_experience(p_character_id uuid, p_exp_gained int)
returns table(leveled_up boolean, new_level int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_level int; v_exp int; v_exp_to_next int;
  v_leveled_up boolean := false;
begin
  select user_id, level, exp, exp_to_next
    into v_owner_user_id, v_level, v_exp, v_exp_to_next
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  v_exp := v_exp + greatest(0, p_exp_gained);

  while v_exp >= v_exp_to_next loop
    v_exp := v_exp - v_exp_to_next;
    v_level := v_level + 1;
    v_exp_to_next := 100 + (v_level - 1) * 50;
    v_leveled_up := true;
  end loop;

  update characters
  set level = v_level, exp = v_exp, exp_to_next = v_exp_to_next
  where id = p_character_id;

  return query select v_leveled_up, v_level;
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
  -- Class
  v_base_atk int; v_atk_per_level int; v_base_def int; v_def_per_level int;
  v_base_hp int; v_hp_per_level int;
  -- Trang bị
  v_weapon_atk int; v_armor_def int;
  -- Skill
  v_a1_name text; v_a1_power numeric; v_a2_name text; v_a2_power numeric;
  v_passive_type text; v_passive_value numeric;
  v_dmg_reduction numeric := 0; v_lifesteal numeric := 0; v_crit_chance numeric := 0;
  -- Tầng / quái
  v_dungeon_id uuid; v_ap_cost int; v_enemy_name text; v_enemy_level int;
  v_enemy_hp int; v_enemy_atk int; v_enemy_def int;
  v_reward_exp int; v_reward_gold int; v_drop_item_id uuid; v_drop_rate numeric; v_drop_item_key text;
  v_is_boss boolean; v_floor_number int;
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

  select base_atk, atk_per_level, base_def, def_per_level, base_hp, hp_per_level
    into v_base_atk, v_atk_per_level, v_base_def, v_def_per_level, v_base_hp, v_hp_per_level
  from classes where id = v_class_id;

  v_max_hp := v_base_hp + (v_level - 1) * v_hp_per_level;
  v_current_hp := coalesce(v_current_hp, v_max_hp);

  if v_current_hp <= 0 then
    raise exception 'Nhân vật đang kiệt sức, cần hồi máu trước khi vào dungeon';
  end if;

  -- 2. Tầng dungeon đang đánh
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

  -- 3. Chỉ số vũ khí/giáp đang trang bị
  select coalesce(sum(i.bonus_atk), 0), coalesce(sum(i.bonus_def), 0)
    into v_weapon_atk, v_armor_def
  from inventory inv join items i on i.id = inv.item_id
  where inv.character_id = p_character_id and inv.equipped = true;

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

  -- 5. Hệ số scaling theo chênh lệch cấp độ
  select exp_multiplier, damage_multiplier into v_exp_multiplier, v_damage_multiplier
  from calculate_combat_scaling(v_level, v_enemy_level);

  -- 6. Mô phỏng trận đấu
  v_char_atk := v_base_atk + (v_level - 1) * v_atk_per_level + v_weapon_atk;
  v_char_def := v_base_def + (v_level - 1) * v_def_per_level + v_armor_def;
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
    select leveled_up, new_level into v_leveled_up, v_new_level
    from add_experience(p_character_id, v_exp_gained);

    if v_drop_item_id is not null and random() < v_drop_rate then
      insert into inventory (character_id, item_id, quantity) values (p_character_id, v_drop_item_id, 1);
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

  select buy_price into v_buy_price from items where id = p_item_id;

  if v_buy_price is null then
    raise exception 'Vật phẩm này không bán trong chợ';
  end if;

  v_total_cost := v_buy_price * p_quantity;

  if v_gold < v_total_cost then
    raise exception 'Không đủ vàng (cần % vàng)', v_total_cost;
  end if;

  update characters set gold = gold - v_total_cost where id = p_character_id;

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

  return query select (v_gold - v_total_cost), v_new_quantity;
end;
$$;

create or replace function public.use_item(p_character_id uuid, p_inventory_id uuid)
returns table(new_current_hp int, new_max_hp int, new_quantity int)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_user_id uuid;
  v_level int; v_current_hp int; v_class_id uuid;
  v_base_hp int; v_hp_per_level int; v_max_hp int;
  v_item_id uuid; v_quantity int; v_type text; v_heal_amount int;
  v_new_hp int; v_new_quantity int;
begin
  select user_id, level, current_hp, class_id
    into v_owner_user_id, v_level, v_current_hp, v_class_id
  from characters where id = p_character_id for update;

  if not found then raise exception 'Không tìm thấy nhân vật'; end if;

  if v_owner_user_id is distinct from auth.uid() then
    raise exception 'Không có quyền điều khiển nhân vật này';
  end if;

  select base_hp, hp_per_level into v_base_hp, v_hp_per_level
  from classes where id = v_class_id;

  v_max_hp := v_base_hp + (v_level - 1) * v_hp_per_level;
  v_current_hp := coalesce(v_current_hp, v_max_hp);

  select item_id, quantity into v_item_id, v_quantity
  from inventory where id = p_inventory_id and character_id = p_character_id
  for update;

  if not found then
    raise exception 'Không tìm thấy vật phẩm trong túi đồ';
  end if;

  select type, heal_amount into v_type, v_heal_amount from items where id = v_item_id;

  if v_type is distinct from 'consumable' or coalesce(v_heal_amount, 0) <= 0 then
    raise exception 'Vật phẩm này không thể sử dụng để hồi máu';
  end if;

  if v_current_hp >= v_max_hp then
    raise exception 'HP đã đầy';
  end if;

  v_new_hp := least(v_max_hp, v_current_hp + v_heal_amount);
  update characters set current_hp = v_new_hp where id = p_character_id;

  v_new_quantity := v_quantity - 1;

  if v_new_quantity <= 0 then
    delete from inventory where id = p_inventory_id;
  else
    update inventory set quantity = v_new_quantity where id = p_inventory_id;
  end if;

  return query select v_new_hp, v_max_hp, v_new_quantity;
end;
$$;

-- ============================================================================
-- Ghi chú:
-- - Các thao tác nhạy cảm (trừ AP, mua bán, nhận thưởng dungeon/quest) nên
--   thực hiện qua Server Action / API Route bằng service_role key, để tránh
--   người chơi tự sửa gold/exp qua console trình duyệt.
-- - RLS ở trên chỉ chặn việc đọc/ghi TRỰC TIẾP từ client bằng anon key.
-- ============================================================================
