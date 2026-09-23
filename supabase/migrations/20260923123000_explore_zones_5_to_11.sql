-- 7 vùng explore còn lại (Lv 15-80) + trang bị/nguyên liệu mới cho từng vùng.
--
-- Mỗi vùng: 1 nguyên liệu (bán lấy vàng), 2 món giáp/phụ kiện, 1 vũ khí chỉ
-- rơi từ boss, và bình máu. Chỉ số gốc tăng theo level vùng; tier sàn của vũ
-- khí boss tăng dần (rare → epic → legendary) nên tier thật (×1.25/×1.6/×2
-- lúc tạo đồ) cũng mạnh dần.

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
