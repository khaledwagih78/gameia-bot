-- =====================================================================
-- AMS v1 — بيانات أولية (المسارات، الفترات، مصادر العملاء)
-- شغّلها مرة واحدة بعد الـ migrations
-- =====================================================================

insert into tracks (name, min_age, max_age, description, sort_order) values
  ('البراعم',       6,  11,   'برمجة مرئية وسكراتش',          1),
  ('اليافعين',      12, 15,   'بايثون والأردوينو',             2),
  ('المتقدمين',     16, null, 'ذكاء اصطناعي وتطوير ويب',       3),
  ('صيانة الأجهزة', 12, null, 'تشخيص وصيانة هاردوير (من سن الإعدادي)', 4)
on conflict (name) do nothing;

-- 7 فترات × ساعة ونص (شاملة البريك)
insert into periods (slot_no, label, start_time, end_time) values
  (1, 'الفترة 1', '10:00', '11:30'),
  (2, 'الفترة 2', '11:30', '13:00'),
  (3, 'الفترة 3', '13:00', '14:30'),
  (4, 'الفترة 4', '14:30', '16:00'),
  (5, 'الفترة 5', '16:00', '17:30'),
  (6, 'الفترة 6', '17:30', '19:00'),
  (7, 'الفترة 7', '19:00', '20:30')
on conflict (slot_no) do nothing;

insert into lead_sources (type, label) values
  ('paid_ad',    'إعلان فيسبوك ممول'),
  ('paid_ad',    'إعلان تيك توك ممول'),
  ('influencer', 'مؤثر / صفحة محلية'),
  ('promo_code', 'كود ترويجي'),
  ('direct',     'مباشر / زيارة للمركز'),
  ('direct',     'ترشيح من ولي أمر')
on conflict (type, label) do nothing;

-- كورسات مبدئية (عدّل الأسعار من شاشة الإعدادات)
insert into courses (track_id, name, type, monthly_fee)
select t.id, c.name, c.type::course_type, c.fee
  from (values
    ('البراعم',       'سكراتش للمبتدئين',     'normal',      600),
    ('اليافعين',      'بايثون وأردوينو',       'normal',      700),
    ('المتقدمين',     'تطوير الويب',          'normal',      700),
    ('المتقدمين',     'الذكاء الاصطناعي',      'advanced',    900),
    ('صيانة الأجهزة', 'صيانة الموبايل واللابتوب', 'maintenance', 800)
  ) as c(track, name, type, fee)
  join tracks t on t.name = c.track
on conflict (track_id, name) do nothing;
