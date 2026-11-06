-- Карты. Каждая собирается кодом (src/server/World/MapBuilder.luau) из описания ниже,
-- поэтому новую карту можно сделать, не открывая Studio. Позже серые коробки можно
-- заменить красивыми моделями, оставив те же базы, зоны и маршруты.
--
-- Устройство любой карты:
--   * База каждой команды на краю карты: точки появления, площадки с машинами, защищённая зона.
--     Чужаку на базе каждую секунду наносится урон (защита от «спавн-кемпинга»).
--   * Передовые точки (Forward) ближе к центру: там появляются в режимах с частым возрождением (TDM).
--     В капте все появляются на базе и добираются до зоны сами: пешком, бегом или на машине.
--   * Зоны каптов (Zones) в глубине карты, 300–450 студов от баз: пешком ≈ 20–25 с, на машине ≈ 5–7 с.
--   * Здания с доступом на крышу: лестницы (ladder), наружные пандусы (stairs), люки изнутри (hatch),
--     низкие гаражи и контейнеры, на которые можно подтянуться (до 9.8 студа).
--
-- Координаты: x, z — центр на земле; w, d — ширина и глубина; h — высота; rot — поворот в градусах.
-- Стороны: N = -Z, S = +Z, E = +X, W = -X (в системе координат самого здания).

-- Глухое здание. access = { сторона, "ladder" | "stairs" }: как попасть на крышу.
local function Block(x, z, w, d, h, access, extra)
	local t = { kind = "block", x = x, z = z, w = w, d = d, h = h, access = access }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end

-- Здание с интерьером: стены с окнами, дверные проёмы, люк на крышу с лестницей внутри.
local function Shell(x, z, w, d, h, doors, extra)
	local t = { kind = "shell", x = x, z = z, w = w, d = d, h = h, doors = doors, hatch = true }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end

local function Container(x, z, rot, stack)
	return { kind = "container", x = x, z = z, rot = rot or 0, stack = stack or 1 }
end

local function Crate(x, z, s)
	return { kind = "crate", x = x, z = z, s = s or 4 }
end

-- Забор (перемахнуть) и стена (подтянуться).
local function Fence(x1, z1, x2, z2, h)
	return { kind = "fence", x1 = x1, z1 = z1, x2 = x2, z2 = z2, h = h or 4 }
end

local function Wall(x1, z1, x2, z2, h)
	return { kind = "wall", x1 = x1, z1 = z1, x2 = x2, z2 = z2, h = h or 7 }
end

local function Road(x1, z1, x2, z2, w)
	return { kind = "road", x1 = x1, z1 = z1, x2 = x2, z2 = z2, w = w or 18 }
end

-- Трамплин/пандус. Поднимается в сторону rot (0 = на север, 90 = на запад, 180 = юг, 270 = восток).
local function Ramp(x, z, w, h, len, rot)
	return { kind = "ramp", x = x, z = z, w = w, h = h, len = len, rot = rot or 0 }
end

-- Висячая балка (стрела крана, переход между крышами). y — высота низа.
local function Beam(x, z, y, w, d, h, rot)
	return { kind = "beam", x = x, z = z, y = y, w = w, d = d, h = h, rot = rot or 0 }
end

return {
	-- Порядок ротации: каждый новый матч — следующая карта.
	Order = { "Industrial", "Suburb", "Port", "Village" },

	-- Лобби висит в воздухе над картой и не пересобирается при смене карты.
	Lobby = { Position = Vector3.new(0, 400, 0) },

	List = {
		------------------------------------------------------------------
		Industrial = {
			Name = "Промзона",
			Size = 1000,
			Ground = { Material = Enum.Material.Concrete, Color = Color3.fromRGB(110, 108, 100) },
			Bases = {
				Bandits = { x = -420, z = 0 },
				Gov = { x = 420, z = 0 },
			},
			Roads = {
				Road(-440, 0, 440, 0, 24),
				Road(-150, -320, -150, 320),
				Road(150, -320, 150, 320),
				Road(-150, -260, 150, -260, 16),
				Road(-150, 260, 150, 260, 16),
			},
			Zones = {
				{
					Name = "Литейный цех",
					x = 0,
					z = -150,
					w = 70,
					d = 70,
					Props = {
						Shell(0, -150, 46, 30, 16, { "E", "W" }),
						Container(-30, -118, 90),
						Container(32, -186, 0, 2),
						Container(40, -120, 90),
						Crate(-22, -186),
						Crate(-18, -190, 3),
						Block(-38, -184, 10, 10, 8, { "N", "ladder" }),
						Wall(-10, -125, 12, -125, 4),
					},
				},
				{
					Name = "Котельная",
					x = 0,
					z = 0,
					w = 64,
					d = 64,
					Props = {
						Block(0, 30, 30, 18, 14, { "W", "stairs" }),
						Block(24, -26, 7, 7, 42, { "N", "ladder" }), -- труба: самая высокая точка карты
						Wall(-28, -26, -6, -26, 7),
						Crate(-18, -18),
						Crate(14, 18, 3),
						Container(-30, 26, 0),
					},
				},
				{
					Name = "Склад ГСМ",
					x = 0,
					z = 150,
					w = 70,
					d = 70,
					Props = {
						Block(-20, 145, 14, 14, 11, { "E", "ladder" }, { material = "Metal" }),
						Block(20, 145, 14, 14, 11, { "W", "ladder" }, { material = "Metal" }),
						Beam(0, 145, 11, 26, 3, 1), -- мостик между баками
						Shell(0, 178, 26, 14, 9, { "S" }),
						Fence(-35, 118, -8, 118),
						Fence(8, 118, 35, 118),
						Crate(-6, 128),
					},
				},
			},
			Extras = {
				Ramp(-100, -40, 10, 5, 20, 270),
				Ramp(100, 40, 10, 5, 20, 90),
			},
			Filler = { Area = { -340, -310, 340, 310 }, Count = 34, Seed = 11, Kinds = { "block", "shell", "containers", "crates" } },
		},

		------------------------------------------------------------------
		Suburb = {
			Name = "Спальный район",
			Size = 1000,
			Ground = { Material = Enum.Material.Grass, Color = Color3.fromRGB(88, 110, 70) },
			Bases = {
				Bandits = { x = 0, z = -420 },
				Gov = { x = 0, z = 420 },
			},
			Roads = {
				Road(0, -440, 0, 440, 24),
				Road(-300, -150, 300, -150),
				Road(-300, 150, 300, 150),
				Road(-200, -300, -200, 300, 16),
				Road(200, -300, 200, 300, 16),
			},
			Zones = {
				{
					Name = "Гаражи",
					x = -100,
					z = 0,
					w = 80,
					d = 64,
					Props = {
						-- ряды гаражей высотой 6: можно подтянуться и бегать по крышам
						Block(-100, -18, 64, 10, 6, nil, { material = "CorrodedMetal", color = Color3.fromRGB(110, 100, 90) }),
						Block(-100, 18, 64, 10, 6, nil, { material = "CorrodedMetal", color = Color3.fromRGB(100, 96, 92) }),
						Crate(-120, 0),
						Crate(-80, 2, 3),
						Wall(-100, -2, -96, -2, 4),
					},
				},
				{
					Name = "Школа",
					x = 110,
					z = 0,
					w = 74,
					d = 74,
					Props = {
						Shell(110, 0, 40, 26, 14, { "N", "S" }),
						Fence(75, -36, 100, -36),
						Fence(120, -36, 145, -36),
						Fence(75, 36, 100, 36),
						Fence(120, 36, 145, 36),
						Fence(75, -36, 75, 36),
						Fence(145, -36, 145, 36),
						Crate(95, -26),
						Crate(126, 26, 3),
					},
				},
				{
					Name = "Рынок",
					x = 0,
					z = 70,
					w = 70,
					d = 56,
					Props = {
						-- прилавки: низкие, перемахиваются на бегу
						Block(-20, 55, 10, 4, 3.5),
						Block(-20, 70, 10, 4, 3.5),
						Block(-20, 85, 10, 4, 3.5),
						Block(20, 55, 10, 4, 3.5),
						Block(20, 70, 10, 4, 3.5),
						Block(20, 85, 10, 4, 3.5),
						Block(30, 95, 8, 8, 10, { "W", "ladder" }),
						Crate(-30, 92),
					},
				},
			},
			Extras = {
				Ramp(-200, -60, 10, 4, 18, 0),
			},
			Filler = { Area = { -340, -330, 340, 330 }, Count = 26, Seed = 23, Kinds = { "panel", "panel", "block", "shell", "crates" } },
		},

		------------------------------------------------------------------
		Port = {
			Name = "Порт",
			Size = 1000,
			Ground = { Material = Enum.Material.Asphalt, Color = Color3.fromRGB(80, 82, 86) },
			Bases = {
				Bandits = { x = -420, z = 120 },
				Gov = { x = 420, z = -120 },
			},
			Roads = {
				Road(-440, 120, -100, 120, 22),
				Road(-100, 120, 100, -120, 22),
				Road(100, -120, 440, -120, 22),
				Road(-320, -260, 320, -260, 20),
				Road(-320, 260, 320, 260, 20),
				Road(-250, -260, -250, 260, 16),
				Road(250, -260, 250, 260, 16),
			},
			Zones = {
				{
					Name = "Причал",
					x = 0,
					z = -200,
					w = 80,
					d = 60,
					Props = {
						Block(-6, -222, 8, 8, 34, { "N", "ladder" }, { material = "Metal", color = Color3.fromRGB(200, 160, 40) }),
						Beam(-6, -205, 30, 4, 40, 3), -- стрела крана
						Container(-28, -190, 0, 2),
						Container(-18, -190, 0),
						Container(20, -205, 90),
						Container(26, -180, 0, 2),
						Crate(6, -180),
					},
				},
				{
					Name = "Склад №3",
					x = -120,
					z = 40,
					w = 70,
					d = 60,
					Props = {
						Shell(-120, 40, 50, 32, 15, { "N", "S", "E" }),
						Container(-155, 18, 0),
						Container(-88, 64, 90),
						Crate(-150, 64),
					},
				},
				{
					Name = "Контейнерный двор",
					x = 130,
					z = 60,
					w = 80,
					d = 80,
					Props = {
						Container(105, 40, 0, 2),
						Container(115, 40, 0),
						Container(125, 40, 0, 2),
						Container(150, 60, 90),
						Container(150, 80, 90, 2),
						Container(110, 85, 90),
						Container(135, 95, 0),
						Crate(130, 62),
					},
				},
			},
			Extras = {
				Ramp(0, 0, 12, 6, 24, 315),
			},
			Filler = { Area = { -330, -300, 330, 300 }, Count = 44, Seed = 37, Kinds = { "containers", "containers", "containers", "shell", "block" } },
		},

		------------------------------------------------------------------
		Village = {
			Name = "Дачи",
			Size = 1000,
			Ground = { Material = Enum.Material.Grass, Color = Color3.fromRGB(95, 120, 64) },
			Bases = {
				Bandits = { x = -380, z = -380 },
				Gov = { x = 380, z = 380 },
			},
			Roads = {
				Road(-350, -200, 350, -200, 14),
				Road(-350, 200, 350, 200, 14),
				Road(-200, -350, -200, 350, 14),
				Road(200, -350, 200, 350, 14),
				Road(-380, -380, -200, -200, 16),
				Road(200, 200, 380, 380, 16),
				Road(-200, 0, 200, 0, 14),
			},
			Zones = {
				{
					Name = "Сельпо",
					x = 0,
					z = 40,
					w = 60,
					d = 56,
					Props = {
						Shell(0, 50, 22, 16, 9, { "S" }),
						Fence(-28, 26, -8, 26),
						Fence(8, 26, 28, 26),
						Crate(-14, 34),
						Crate(16, 66, 3),
						Block(22, 50, 6, 6, 5), -- сарай: подтянуться и на крышу магазина
					},
				},
				{
					Name = "Водокачка",
					x = -120,
					z = 130,
					w = 64,
					d = 64,
					Props = {
						Block(-120, 130, 8, 8, 30, { "S", "ladder" }, { material = "Brick", color = Color3.fromRGB(140, 70, 50) }),
						Wall(-148, 110, -128, 110, 7),
						Wall(-112, 150, -92, 150, 7),
						Block(-100, 112, 8, 8, 5),
						Crate(-140, 148),
					},
				},
				{
					Name = "Лесопилка",
					x = 130,
					z = -120,
					w = 80,
					d = 60,
					Props = {
						Shell(130, -128, 40, 16, 10, { "E", "W" }, { material = "WoodPlanks" }),
						Block(108, -100, 18, 4, 3, nil, { material = "Wood" }), -- штабеля брёвен
						Block(150, -100, 18, 4, 3, nil, { material = "Wood" }),
						Ramp(130, -95, 8, 3, 10, 180),
					},
				},
			},
			Extras = {
				Ramp(-200, -110, 10, 5, 20, 0),
				Ramp(200, 110, 10, 5, 20, 180),
			},
			Filler = { Area = { -340, -340, 340, 340 }, Count = 40, Seed = 51, Kinds = { "dacha", "dacha", "dacha", "shed", "crates" } },
		},
	},
}
