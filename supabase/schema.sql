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
  id           uuid primary key default gen_random_uuid(),
  key          text unique not null,
  name         text not null,
  min_level    int not null default 1,
  ap_cost      int not null default 10,
  floor_count  int not null default 5,
  description  text
);

create table dungeon_floors (
  id            uuid primary key default gen_random_uuid(),
  dungeon_id    uuid not null references dungeons(id) on delete cascade,
  floor_number  int not null,
  is_boss_floor boolean not null default false,
  enemy_name    text not null,
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
-- 6. STORY (nội dung cốt truyện mở dần theo level)
-- ----------------------------------------------------------------------------
create table story_chapters (
  id             uuid primary key default gen_random_uuid(),
  chapter_number int unique not null,
  title          text not null,
  content        text not null,
  level_required int not null default 1
);

-- ----------------------------------------------------------------------------
-- 7. QUESTS (nhiệm vụ chính + phụ) + tiến trình của từng nhân vật
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

create policy "public read classes" on classes for select using (true);
create policy "public read pet_species" on pet_species for select using (true);
create policy "public read items" on items for select using (true);
create policy "public read dungeons" on dungeons for select using (true);
create policy "public read dungeon_floors" on dungeon_floors for select using (true);
create policy "public read story_chapters" on story_chapters for select using (true);
create policy "public read quests" on quests for select using (true);

-- Bảng dữ liệu người chơi (chỉ chủ sở hữu mới đọc/ghi được)
alter table characters enable row level security;
alter table character_pets enable row level security;
alter table inventory enable row level security;
alter table dungeon_runs enable row level security;
alter table character_quests enable row level security;

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

-- ============================================================================
-- Ghi chú:
-- - Các thao tác nhạy cảm (trừ AP, mua bán, nhận thưởng dungeon/quest) nên
--   thực hiện qua Server Action / API Route bằng service_role key, để tránh
--   người chơi tự sửa gold/exp qua console trình duyệt.
-- - RLS ở trên chỉ chặn việc đọc/ghi TRỰC TIẾP từ client bằng anon key.
-- ============================================================================
