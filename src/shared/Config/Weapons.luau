-- Арсенал.
--   Slot          -- Primary (основное), Secondary (пистолеты), Melee (ближний бой)
--   UnlockLevel   -- с какого уровня доступно
--   Damage        -- урон одной пули (у дробовика одной дробины)
--   HeadshotMultiplier / LimbMultiplier -- множители по зонам тела (корпус = 1)
--   FireRate      -- выстрелов в секунду
--   Range         -- дальность, studs
--   FalloffStart  -- с какой дистанции урон начинает падать
--   MinDamageMultiplier -- доля урона на максимальной дальности
--   Spread        -- разброс, градусы (считает сервер)
--   Pellets       -- дробин за выстрел
--   Penetration   -- какую толщину тонкого материала пробивает (studs), 0 = не пробивает
--   Zoom          -- угол обзора камеры в прицеле (правая кнопка мыши)
local Weapons = {}

Weapons.Slots = { "Primary", "Secondary", "Melee" }
Weapons.SlotNames = { Primary = "Основное", Secondary = "Пистолет", Melee = "Ближний бой" }

-- Инвентарь без ограничений: игрок берёт в бой любое открытое оружие, хоть всё сразу.
-- Slot нужен только для группировки в меню.
Weapons.DefaultInventory = { "Rifle", "Pistol", "Knife" }

-- Материалы, которые пули могут пробить, и сколько урона остаётся после пробития.
Weapons.PenetrableMaterials = {
	[Enum.Material.Wood] = true,
	[Enum.Material.WoodPlanks] = true,
	[Enum.Material.Plastic] = true,
	[Enum.Material.SmoothPlastic] = true,
	[Enum.Material.Glass] = true,
	[Enum.Material.Fabric] = true,
	[Enum.Material.CorrodedMetal] = true,
}
Weapons.PenetrationDamageMultiplier = 0.6

Weapons.List = {
	-- Основное
	Rifle = {
		Slot = "Primary",
		DisplayName = "Автомат",
		UnlockLevel = 1,
		Damage = 22,
		HeadshotMultiplier = 1.6,
		LimbMultiplier = 0.8,
		FireRate = 10,
		Range = 300,
		FalloffStart = 80,
		MinDamageMultiplier = 0.6,
		Spread = 1.5,
		Automatic = true,
		MagSize = 30,
		ReloadTime = 2.2,
		Penetration = 1,
		HandleSize = Vector3.new(0.4, 0.8, 2.4),
		Color = Color3.fromRGB(45, 45, 50),
	},
	SMG = {
		Slot = "Primary",
		DisplayName = "Пистолет-пулемёт",
		UnlockLevel = 3,
		Damage = 16,
		HeadshotMultiplier = 1.5,
		LimbMultiplier = 0.85,
		FireRate = 14,
		Range = 180,
		FalloffStart = 40,
		MinDamageMultiplier = 0.5,
		Spread = 2.5,
		Automatic = true,
		MagSize = 35,
		ReloadTime = 1.8,
		Penetration = 0.5,
		HandleSize = Vector3.new(0.35, 0.7, 1.6),
		Color = Color3.fromRGB(35, 35, 40),
	},
	Shotgun = {
		Slot = "Primary",
		DisplayName = "Дробовик",
		UnlockLevel = 6,
		Damage = 12,
		Pellets = 8,
		HeadshotMultiplier = 1.3,
		LimbMultiplier = 0.9,
		FireRate = 1.2,
		Range = 80,
		FalloffStart = 15,
		MinDamageMultiplier = 0.25,
		Spread = 6,
		Automatic = false,
		MagSize = 6,
		ReloadTime = 2.8,
		Penetration = 0,
		HandleSize = Vector3.new(0.4, 0.7, 2.6),
		Color = Color3.fromRGB(90, 60, 40),
	},
	LMG = {
		Slot = "Primary",
		DisplayName = "Пулемёт",
		UnlockLevel = 10,
		Damage = 24,
		HeadshotMultiplier = 1.5,
		LimbMultiplier = 0.8,
		FireRate = 9,
		Range = 300,
		FalloffStart = 100,
		MinDamageMultiplier = 0.6,
		Spread = 3,
		Automatic = true,
		MagSize = 80,
		ReloadTime = 4.5,
		Penetration = 2,
		HandleSize = Vector3.new(0.5, 0.9, 3),
		Color = Color3.fromRGB(55, 60, 50),
	},
	Sniper = {
		Slot = "Primary",
		DisplayName = "Снайперская винтовка",
		UnlockLevel = 15,
		Damage = 90,
		HeadshotMultiplier = 2.5,
		LimbMultiplier = 0.75,
		FireRate = 0.8,
		Range = 800,
		FalloffStart = 800,
		MinDamageMultiplier = 1,
		Spread = 0.1,
		Automatic = false,
		MagSize = 5,
		ReloadTime = 3,
		Penetration = 3,
		Zoom = 20,
		HandleSize = Vector3.new(0.35, 0.7, 3.4),
		Color = Color3.fromRGB(60, 70, 55),
	},

	-- Пистолеты
	Pistol = {
		Slot = "Secondary",
		DisplayName = "Пистолет",
		UnlockLevel = 1,
		Damage = 30,
		HeadshotMultiplier = 1.6,
		LimbMultiplier = 0.85,
		FireRate = 4,
		Range = 200,
		FalloffStart = 50,
		MinDamageMultiplier = 0.5,
		Spread = 1,
		Automatic = false,
		MagSize = 12,
		ReloadTime = 1.4,
		Penetration = 0.5,
		HandleSize = Vector3.new(0.3, 0.6, 1),
		Color = Color3.fromRGB(30, 30, 30),
	},
	Revolver = {
		Slot = "Secondary",
		DisplayName = "Револьвер",
		UnlockLevel = 8,
		Damage = 55,
		HeadshotMultiplier = 1.8,
		LimbMultiplier = 0.8,
		FireRate = 1.6,
		Range = 250,
		FalloffStart = 80,
		MinDamageMultiplier = 0.6,
		Spread = 0.8,
		Automatic = false,
		MagSize = 6,
		ReloadTime = 2.6,
		Penetration = 1,
		HandleSize = Vector3.new(0.3, 0.6, 1.3),
		Color = Color3.fromRGB(120, 120, 125),
	},

	-- Ближний бой
	Knife = {
		Slot = "Melee",
		DisplayName = "Нож",
		UnlockLevel = 1,
		Damage = 55,
		HeadshotMultiplier = 1,
		LimbMultiplier = 1,
		FireRate = 1.5,
		Range = 7,
		Melee = true,
		HandleSize = Vector3.new(0.2, 0.4, 1.4),
		Color = Color3.fromRGB(180, 180, 190),
	},
	Bat = {
		Slot = "Melee",
		DisplayName = "Бита",
		UnlockLevel = 5,
		Damage = 45,
		HeadshotMultiplier = 1.5,
		LimbMultiplier = 1,
		FireRate = 1.1,
		Range = 8,
		Melee = true,
		HandleSize = Vector3.new(0.35, 0.35, 3),
		Color = Color3.fromRGB(150, 110, 70),
	},
}

-- Открыт ли предмет на уровне level.
function Weapons.isUnlocked(id: string, level: number): boolean
	local def = Weapons.List[id]
	return def ~= nil and level >= (def.UnlockLevel or 1)
end

return Weapons
