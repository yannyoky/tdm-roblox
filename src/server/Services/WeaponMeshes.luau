-- Готовые модели оружия из Creator Store, записанные как данные (id мешей, размеры, цвета).
-- Источник: бесплатные паки «LowPolygon Gun Pack» (low-poly модели TastyTony, asset 9327209214)
-- и «STREETMODELS» (asset 3495901227, нож). Скрипты из паков не используются: берём только меши.
--
-- Каждая деталь — Part + SpecialMesh. Координаты уже приведены к виду игры:
-- начало координат — точка хвата (рука), ствол смотрит в −Z, верх — +Y.
--   mesh / tex — id меша и текстуры, scale — масштаб меша,
--   cf — CFrame детали (12 чисел, как в CFrame.new(...)), color — цвет, mat — материал (по умолчанию SmoothPlastic).
--   muzzle — точка у дула (трассер и вспышка).
-- Чтобы вернуть старую самодельную модель оружия, удалите его запись отсюда.
local function v(x, y, z)
	return Vector3.new(x, y, z)
end
local rgb = Color3.fromRGB

-- Повёрнутые на 90° детали (почти у всех стволов так лежат меши).
local function side(x: number, y: number, z: number): { number }
	return { x, y, z, 0, 0, -1, 0, 1, 0, 1, 0, 0 }
end
local function up(x: number, y: number, z: number): { number }
	return { x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
end

local WOOD = rgb(112, 70, 40)
local BLACK = rgb(27, 42, 53)
local STEEL = rgb(163, 162, 165)
local DARK = rgb(99, 95, 98)
local GUNMETAL = rgb(91, 93, 105)
local OLIVE = rgb(39, 70, 45)

return {
	-- АК (Kalash-200), дерево вместо синего пластика
	Rifle = {
		muzzle = v(0, 0.528, -2.161),
		parts = {
			{ mesh = 4635934318, scale = v(0.34, 0.34, 0.34), cf = side(0.019, 0.068, -0.288), color = WOOD },
			{ mesh = 4635933482, scale = v(0.34, 0.34, 0.34), cf = side(0.025, 0.323, 0.096), color = STEEL },
			{ mesh = 4635938368, scale = v(0.34, 0.34, 0.34), cf = side(0.023, 0.64, 0.242), color = DARK },
			{ mesh = 4635936863, scale = v(0.34, 0.34, 0.34), cf = side(-0.012, 0.501, -0.628), color = STEEL },
			{ mesh = 4635931684, scale = v(0.34, 0.34, 0.34), cf = side(0.025, 0.272, 0.018), color = WOOD },
			{ mesh = 4635936362, scale = v(0.34, 0.34, 0.34), cf = side(0.023, 0.528, -1.301), color = BLACK },
			{ mesh = 4635932459, scale = v(0.34, 0.34, 0.34), cf = side(0.025, 0.374, 0.086), color = BLACK },
		},
	},
	-- MP5
	SMG = {
		muzzle = v(0, 0.502, -1.387),
		parts = {
			{ mesh = 4508831044, scale = v(0.3, 0.3, 0.3), cf = side(0.009, 0.362, 0.392), color = BLACK },
			{ mesh = 4508832265, scale = v(0.3, 0.3, 0.3), cf = side(-0.045, 0.627, -0.725), color = STEEL },
			{ mesh = 4508835532, scale = v(0.3, 0.3, 0.3), cf = side(0.009, 0.296, 0.014), color = DARK },
			{ mesh = 4508834331, scale = v(0.3, 0.3, 0.3), cf = side(0.009, 0.056, -0.406), color = DARK },
			{ mesh = 4508832867, scale = v(0.3, 0.3, 0.3), cf = side(0.009, 0.542, -0.274), color = STEEL },
			{ mesh = 4508828635, scale = v(0.3, 0.3, 0.3), cf = side(0.009, 0.302, -0.329), color = BLACK },
		},
	},
	-- M1014
	Shotgun = {
		muzzle = v(0, 0.27, -2.441),
		parts = {
			{ mesh = 4726805276, scale = v(0.551, 0.551, 0.551), cf = side(0.014, 0.32, -0.615), color = rgb(159, 161, 172) },
			{ mesh = 4726803439, scale = v(0.551, 0.551, 0.551), cf = side(-0.041, 0.11, -0.648), color = rgb(53, 53, 53) },
			{ mesh = 4726806559, scale = v(0.551, 0.674, 0.551), cf = side(-0.041, 0.176, -0.538), color = rgb(159, 161, 172) },
			{ mesh = 4726803177, scale = v(0.551, 0.551, 0.551), cf = side(-0.047, 0.038, -0.273), color = BLACK },
		},
	},
	-- M60
	LMG = {
		muzzle = v(0, 0.312, -2.99),
		parts = {
			{ mesh = 4541330393, scale = v(0.423, 0.423, 0.423), cf = side(0.105, 0.328, -0.277), color = rgb(239, 184, 56) },
			{ mesh = 4541332105, scale = v(0.423, 0.423, 0.423), cf = side(0.258, 0.311, 0.349), color = GUNMETAL },
			{ mesh = 4541322663, scale = v(0.423, 0.423, 0.423), cf = side(0.326, 0.108, -0.231), color = BLACK },
			{ mesh = 4541327567, scale = v(0.423, 0.423, 0.423), cf = side(0.212, 0.404, 0.15), color = BLACK },
			{ mesh = 4541322244, scale = v(0.423, 0.423, 0.423), cf = side(0.258, 0.311, -0.947), color = GUNMETAL },
			{ mesh = 4541329104, scale = v(0.423, 0.423, 0.423), cf = side(-0.233, 0.184, -0.277), color = OLIVE },
			{ mesh = 4541332617, scale = v(0.423, 0.423, 0.423), cf = side(0.393, 0.205, -0.032), color = GUNMETAL },
		},
	},
	-- AWP с прицелом
	Sniper = {
		muzzle = v(0, 0.27, -3.24),
		parts = {
			{ mesh = 4723320738, scale = v(0.497, 0.497, 0.497), cf = side(0.035, 0.247, -0.262), color = GUNMETAL },
			{ mesh = 4723290236, scale = v(0.497, 0.497, 0.497), cf = side(-0.032, 0.123, -1.475), color = BLACK },
			{ mesh = 4723308106, scale = v(0.497, 0.497, 0.497), cf = side(-0.042, 0.04, 0.706), color = BLACK },
			{ mesh = 4723329904, scale = v(0.497, 0.497, 0.497), cf = side(-0.013, 0.525, -0.416), color = BLACK },
			{ mesh = 4723337069, scale = v(0.497, 0.497, 0.497), cf = side(-0.032, 0.528, -0.416), color = rgb(128, 187, 219), mat = "Glass" },
			{ mesh = 4723324092, scale = v(0.497, 0.497, 0.497), cf = side(-0.028, 0.326, 0.041), color = GUNMETAL },
			{ mesh = 4723301353, scale = v(0.497, 0.497, 0.497), cf = side(-0.03, 0.04, 0.706), color = OLIVE },
			{ mesh = 4723291853, scale = v(0.497, 0.497, 0.497), cf = side(-0.045, 0.033, -0.521), color = OLIVE },
			{ mesh = 4723313094, scale = v(0.497, 0.497, 0.497), cf = side(-0.03, 0.083, -0.362), color = BLACK },
		},
	},
	-- Макаров
	Pistol = {
		muzzle = v(0, 0.515, -0.921),
		parts = {
			{ mesh = 4569850783, scale = v(0.206, 0.206, 0.206), cf = side(0.013, 0.075, -0.254), color = BLACK },
			{ mesh = 4569837031, scale = v(0.206, 0.206, 0.206), cf = side(0, 0.515, -0.348), color = BLACK },
			{ mesh = 4569845663, scale = v(0.206, 0.206, 0.206), cf = side(0.013, 0.046, -0.001), color = rgb(105, 64, 40) },
			{ mesh = 4569851079, scale = v(0.206, 0.206, 0.206), cf = side(-0.003, 0.147, -0.357), color = GUNMETAL },
			{ mesh = 4569858469, scale = v(0.206, 0.206, 0.206), cf = side(0.017, 0.085, -0.048), color = BLACK },
		},
	},
	Knife = {
		parts = {
			{ mesh = 442337985, tex = 442337993, scale = v(0.161, 0.206, 0.75), cf = side(0, 0, -0.45), color = STEEL, mat = "Plastic" },
		},
	},
	Frag = {
		parts = {
			{ mesh = 3558654073, scale = v(0.259, 0.259, 0.259), cf = up(0, 0.25, 0.014), color = rgb(76, 76, 77) },
			{ mesh = 3558653989, scale = v(0.259, 0.259, 0.259), cf = up(0, 0.078, -0.045), color = rgb(101, 100, 102) },
			{ mesh = 3558654169, scale = v(0.259, 0.259, 0.259), cf = up(0, -0.051, 0.021), color = rgb(71, 82, 60) },
			{ mesh = 3558653872, scale = v(0.259, 0.259, 0.259), cf = up(0.054, 0.188, -0.055), color = rgb(101, 100, 102) },
		},
	},
	Flash = {
		parts = {
			{ mesh = 3738272575, scale = v(0.126, 0.126, 0.126), cf = up(-0.035, 0.306, 0.086), color = rgb(107, 107, 108) },
			{ mesh = 3738272393, scale = v(0.126, 0.126, 0.126), cf = up(0.02, 0.347, 0.027), color = rgb(107, 107, 108) },
			{ mesh = 3738272159, scale = v(0.126, 0.126, 0.126), cf = up(0.02, -0.069, -0.029), color = rgb(60, 64, 68) },
			{ mesh = 3738272315, scale = v(0.126, 0.126, 0.126), cf = up(0.02, -0.069, -0.029), color = rgb(70, 90, 140) },
			{ mesh = 3738272476, scale = v(0.126, 0.126, 0.126), cf = up(0.02, 0.108, 0.046), color = rgb(83, 83, 84) },
		},
	},
}
