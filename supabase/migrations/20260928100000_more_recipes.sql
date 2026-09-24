-- Chế tạo mở rộng: trước chỉ có 5 công thức vũ khí. Thêm giáp / phụ kiện của mọi vùng
-- (nguyên liệu đúng bậc của vùng, bậc cao cần thêm nguyên liệu bậc dưới) và bình máu.
-- Vũ khí boss giữ độc quyền rơi từ boss. Món chưa có trong items (vd. leather_armor chỉ
-- có trên DB live) thì join tự bỏ qua như các seed trước.

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
