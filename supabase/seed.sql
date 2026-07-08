INSERT INTO public.vehicles (brand, model, year, version, list_price_pen, list_price_usd, default_tea, default_rate_type, default_initial_payment_pct)
VALUES
  ('Toyota',   'Corolla',       2025, '2.0 XEI CVT',           84950, 22500, 0.1450, 'TEA', 20.00),
  ('Toyota',   'RAV4',          2025, '2.0 XLE CVT',          126900, 33500, 0.1450, 'TEA', 20.00),
  ('Toyota',   'Hilux',         2025, '2.8 TDI 4x4 SRV',      155800, 41200, 0.1400, 'TEA', 25.00),
  ('Toyota',   'Yaris',         2025, '1.5 S CVT',             63400, 16800, 0.1500, 'TEA', 15.00),
  ('Kia',      'Sportage',      2025, '2.0 EX',               102500, 27100, 0.1480, 'TEA', 20.00),
  ('Kia',      'Seltos',        2025, '1.6 Turbo EX',          87400, 23100, 0.1500, 'TEA', 20.00),
  ('Kia',      'Picanto',       2025, '1.2 M/T',               49300, 13000, 0.1550, 'TEA', 15.00),
  ('Hyundai',  'Tucson',        2025, '2.0 GL',               108200, 28600, 0.1480, 'TEA', 20.00),
  ('Hyundai',  'Creta',         2025, '1.6 GLS',               91400, 24200, 0.1500, 'TEA', 20.00),
  ('Hyundai',  'Grand i10',     2025, '1.2 M/T',               49000, 13000, 0.1550, 'TEA', 15.00),
  ('Nissan',   'Sentra',        2025, '2.0 SR CVT',            83200, 22000, 0.1450, 'TEA', 20.00),
  ('Nissan',   'Qashqai',       2025, '2.0 EX',               111500, 29500, 0.1480, 'TEA', 20.00),
  ('Nissan',   'Navara',        2025, '2.3 TDI LE 4x4',       145200, 38400, 0.1400, 'TEA', 25.00),
  ('Chevrolet', 'Onix',         2025, '1.4 LS',                56700, 15000, 0.1550, 'TEA', 15.00),
  ('Chevrolet', 'Tracker',      2025, '1.2 Turbo LS',          84800, 22400, 0.1500, 'TEA', 20.00),
  ('Chevrolet', 'Silverado',    2025, '2.7 Turbo LT',         162300, 43000, 0.1380, 'TEA', 25.00),
  ('Mazda',    'CX-30',         2025, '2.5 S',                114600, 30300, 0.1450, 'TEA', 20.00),
  ('Mazda',    'Mazda3',        2025, '2.0 G',                 91600, 24200, 0.1480, 'TEA', 20.00),
  ('Suzuki',   'Vitara',        2025, '1.4 Turbo GL',          82300, 21800, 0.1500, 'TEA', 20.00),
  ('Suzuki',   'Swift',         2025, '1.2 GL',                56300, 14900, 0.1550, 'TEA', 15.00);

UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/f/fe/Toyota_Corolla_Hybrid_%28E210%29_IMG_4338.jpg'           WHERE brand = 'Toyota'   AND model = 'Corolla';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/2/2d/2024_Toyota_RAV4_Prime_XSE_Premium_in_Silver_Sky_with_Midnight_Black_roof%2C_front_left.jpg' WHERE brand = 'Toyota'   AND model = 'RAV4';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/1/1b/2016_Toyota_HiLux_Invincible_D-4D_4WD_2.4_Front.jpg'                                          WHERE brand = 'Toyota'   AND model = 'Hilux';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/3/3e/2020_Toyota_Yaris_Design_HEV_CVT_1.5_Front.jpg'                                              WHERE brand = 'Toyota'   AND model = 'Yaris';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/5/5d/2025_Kia_Sportage_S_front_only.jpg'                                                          WHERE brand = 'Kia'      AND model = 'Sportage';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/6/6c/Kia_Seltos_SP2_PE_Snow_White_Pearl_%2817%29_%28cropped%29.jpg'                               WHERE brand = 'Kia'      AND model = 'Seltos';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/8/8d/2018_Kia_Picanto_3_Automatic_1.2_Front.jpg'                                                 WHERE brand = 'Kia'      AND model = 'Picanto';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/c/c6/2022_Hyundai_Tucson_Preferred%2C_Front_Right%2C_05-24-2021.jpg'                             WHERE brand = 'Hyundai'  AND model = 'Tucson';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/2/25/2022_Hyundai_Creta_1.6_Plus_%28Chile%29_front_view.jpg'                                     WHERE brand = 'Hyundai'  AND model = 'Creta';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/4/44/Hyundai_i10_1.0_Intro_%28III%29_%E2%80%93_f_03012021.jpg'                                   WHERE brand = 'Hyundai'  AND model = 'Grand i10';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/0/0c/2024_Nissan_Sentra_%28B18%29_DSC_3754.jpg'                                                  WHERE brand = 'Nissan'   AND model = 'Sentra';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/d/dc/2024_Nissan_Qashqai_e-Power_IMG_2187.jpg'                                                   WHERE brand = 'Nissan'   AND model = 'Qashqai';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/e/e9/2018_Nissan_Navara_Tekna_DCi_Automatic_2.3.jpg'                                            WHERE brand = 'Nissan'   AND model = 'Navara';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/2/20/2022_Chevrolet_Onix_RS_1.0_Turbo.jpg'                                                       WHERE brand = 'Chevrolet' AND model = 'Onix';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/f/f0/Chevrolet_Tracker_2021_%28front%29.png'                                                     WHERE brand = 'Chevrolet' AND model = 'Tracker';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/b/b3/2022_Chevrolet_Silverado_2500HD_High_Country%2C_Front_Left%2C_11-21-2021.jpg'             WHERE brand = 'Chevrolet' AND model = 'Silverado';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/b/b2/Mazda_CX-30_Touring%2C_2020_front.jpg'                                                     WHERE brand = 'Mazda'    AND model = 'CX-30';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/2/2a/Mazda3_SKYACTIV-G.jpg'                                                                     WHERE brand = 'Mazda'    AND model = 'Mazda3';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/7/7b/2024_Suzuki_Vitara_%284th_generation%29_DSC_6083.jpg'                                     WHERE brand = 'Suzuki'   AND model = 'Vitara';
UPDATE public.vehicles SET image_url = 'https://upload.wikimedia.org/wikipedia/commons/3/3d/Suzuki_Swift_%282024%29_hybrid_DSC_6076.jpg'                                               WHERE brand = 'Suzuki'   AND model = 'Swift';
