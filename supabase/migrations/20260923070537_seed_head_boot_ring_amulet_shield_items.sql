-- First items for 5 of the 6 equipment slots added earlier that had
-- nothing to put in them (head, boot, ring, amulet, shield). Belt still
-- has no matching icon in the Raven Fantasy Icons pack after checking
-- several likely spots — left empty rather than forcing a mismatched one
-- in, same reasoning as not using the Orc sprite for a player class.
-- All common-tier, shop-purchasable, stats roughly in line with the
-- existing leather_armor (bonus_def 3 / bonus_hp 10 / buy 40 / sell 12).

insert into items (key, name, type, slot, hand, rarity, bonus_atk, bonus_def, bonus_hp, buy_price, sell_price, description, icon) values
  ('iron_helmet', 'Nón Sắt Cũ', 'armor', 'head', null, 'common', 0, 2, 5, 30, 10, 'Mũ sắt cơ bản, bảo vệ phần đầu.', 'iron_helmet.png'),
  ('traveler_boots', 'Giày Da Lữ Hành', 'armor', 'boot', null, 'common', 0, 1, 5, 25, 8, 'Đôi giày bền bỉ cho hành trình dài.', 'traveler_boots.png'),
  ('ring_ruby', 'Nhẫn Bạc Đá Đỏ', 'armor', 'ring', null, 'common', 2, 0, 0, 35, 10, 'Chiếc nhẫn bạc khảm đá đỏ, tăng nhẹ sức mạnh.', 'ring_ruby.png'),
  ('guardian_amulet', 'Bùa Hộ Mệnh', 'armor', 'amulet', null, 'common', 0, 0, 15, 40, 12, 'Bùa chú cổ xưa, gia tăng sinh lực.', 'guardian_amulet.png'),
  ('iron_shield', 'Khiên Gỗ Bọc Sắt', 'armor', 'shield', 'one_hand', 'common', 0, 4, 0, 45, 15, 'Khiên gỗ chắc chắn, bọc viền sắt.', 'iron_shield.png')
on conflict (key) do nothing;
