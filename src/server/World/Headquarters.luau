-- Штабы сторон вместо серой коробки лобби: подпольный гараж Банды и дежурная часть Силовиков.
-- Между матчами игрок стоит в штабе своей стороны. Внутри:
--   • круги голосования за режим на полу (встал в круг — проголосовал, см. MatchService);
--   • арсенал, гардероб, доска заданий и магазин — подсказки [E] открывают нужное меню
--     (атрибут OpenMenu у ProximityPrompt, клиент: client/CityInteract.luau).
--
-- Штабы закрытые (без окон) и висят высоко над картой (Config/MapsData.json: Lobby),
-- поэтому не зависят от того, какая карта сейчас собрана.
--
-- Локальная система штаба: пол на y = 0, -Z — сторона кругов голосования («перед»),
-- +Z — задняя стена с названием стороны, у неё точки появления (лицом к кругам).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapsConfig = require(Shared.Config.Maps)
local ModesConfig = require(Shared.Config.Modes)
local TeamsConfig = require(Shared.Config.Teams)
local Props = require(script.Parent.Props)

local Headquarters = {}

local rgb = Color3.fromRGB
local yaw = Props.yaw
local part = Props.part

local W, D, H = 64, 48, 16 -- внутренний размер комнаты
local GAP = 45 -- центры штабов: Lobby.Position ± GAP по X
local ZONE_RADIUS = 5.5

-- Цвета кругов голосования по режимам (для новых режимов — запасной цвет).
local MODE_COLORS = {
	TDM = rgb(235, 90, 60),
	Capture = rgb(240, 190, 50),
	City = rgb(80, 200, 120),
}
local FALLBACK_MODE_COLOR = rgb(120, 170, 240)

-- Оформление штабов по сторонам.
local STYLES = {
	Bandits = {
		Title = "БАНДА",
		Subtitle = "ПОДПОЛЬНЫЙ ГАРАЖ",
		Floor = { rgb(88, 86, 82), Enum.Material.Concrete },
		Wall = { rgb(118, 64, 50), Enum.Material.Brick },
		Lower = { rgb(70, 66, 62), Enum.Material.Concrete },
		Ceiling = { rgb(72, 70, 66), Enum.Material.CorrodedMetal },
		Lamp = rgb(255, 186, 120),
		ShopName = "Чёрный рынок",
		SignBg = rgb(25, 22, 20),
		SignFont = Enum.Font.PermanentMarker,
	},
	Gov = {
		Title = "СИЛОВИКИ",
		Subtitle = "ДЕЖУРНАЯ ЧАСТЬ",
		Floor = { rgb(176, 176, 170), Enum.Material.Marble },
		Wall = { rgb(178, 188, 196), Enum.Material.Plaster },
		Lower = { rgb(48, 66, 96), Enum.Material.SmoothPlastic },
		Ceiling = { rgb(225, 225, 222), Enum.Material.Plaster },
		Lamp = rgb(235, 242, 255),
		ShopName = "Снабжение",
		SignBg = rgb(20, 32, 58),
		SignFont = Enum.Font.GothamBlack,
	},
}

local built: Model? = nil
local origins: { [string]: CFrame } = {}
local spawnSpots: { [string]: { CFrame } } = {}
local zones: { { modeId: string, center: Vector3, label: TextLabel } } = {}

------------------------------------------------------------------------
-- Мелкие помощники

local function solid(parent: Instance, name: string, size: Vector3, cf: CFrame, look: { any })
	return part(parent, name, size, cf, look[1], look[2], true)
end

-- Подсказка [E], которая открывает меню у игрока.
local function prompt(parent: Instance, cf: CFrame, action: string, object: string, menu: string)
	local anchor = part(parent, "PromptAnchor", Vector3.new(1, 1, 1), cf, rgb(0, 0, 0), Enum.Material.SmoothPlastic, false, { Transparency = 1, CastShadow = false })
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p:SetAttribute("OpenMenu", menu)
	p.Parent = anchor
	return p
end

-- Силуэт автомата (лежит или висит; cf — центр, ствол вдоль -Z).
local function rifle(parent: Instance, cf: CFrame, dark: Color3)
	local wood = rgb(110, 70, 40)
	part(parent, "GunBody", Vector3.new(0.3, 0.55, 2.2), cf, dark, Enum.Material.Metal)
	part(parent, "GunBarrel", Vector3.new(0.14, 0.14, 1.5), cf * CFrame.new(0, 0.1, -1.8), dark, Enum.Material.Metal)
	part(parent, "GunStock", Vector3.new(0.26, 0.5, 1.2), cf * CFrame.new(0, -0.1, 1.6), wood, Enum.Material.Wood)
	part(parent, "GunMag", Vector3.new(0.22, 0.9, 0.35), cf * CFrame.new(0, -0.6, -0.4) * CFrame.Angles(math.rad(-15), 0, 0), dark, Enum.Material.Metal)
end

local function table4(parent: Instance, cf: CFrame, w: number, d: number, h: number, color: Color3, mat: Enum.Material)
	part(parent, "TableTop", Vector3.new(w, 0.3, d), cf * CFrame.new(0, h, 0), color, mat, true)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(parent, "TableLeg", Vector3.new(0.3, h, 0.3), cf * CFrame.new(sx * (w / 2 - 0.3), h / 2, sz * (d / 2 - 0.3)), rgb(50, 50, 52), Enum.Material.Metal, true)
		end
	end
end

local function sign(parent: Instance, cf: CFrame, w: number, h: number, text: string, style)
	Props.sign(parent, cf, w, h, text, style.SignBg, rgb(240, 236, 228), style.SignFont)
end

------------------------------------------------------------------------
-- Станции у стен. cf — точка на полу у стены, -Z смотрит в комнату.

local stations = {}

function stations.arsenal(g: Instance, cf: CFrame, key: string, style)
	if key == "Bandits" then
		-- Верстак с разложенным оружием и ящики с патронами.
		table4(g, cf * CFrame.new(0, 0, 0.6), 9, 3.2, 3.2, rgb(120, 85, 55), Enum.Material.WoodPlanks)
		for i = -1, 1 do
			rifle(g, cf * CFrame.new(i * 2.6, 3.65, 0.6) * yaw(90) * CFrame.Angles(0, 0, math.rad(90)), rgb(35, 35, 38))
		end
		for i, x in { -5.6, 5.6 } do
			part(g, "AmmoCrate", Vector3.new(2.2, 1.6, 1.6), cf * CFrame.new(x, 0.8, 0.8) * yaw(i * 8), rgb(85, 95, 60), Enum.Material.WoodPlanks, true)
		end
		part(g, "Pegboard", Vector3.new(10, 5, 0.3), cf * CFrame.new(0, 6.5, 1.7), rgb(150, 120, 85), Enum.Material.Wood)
	else
		-- Оружейная пирамида: металлическая стойка с автоматами.
		part(g, "RackBack", Vector3.new(10, 7, 0.4), cf * CFrame.new(0, 4.5, 1.6), rgb(60, 66, 72), Enum.Material.DiamondPlate, true)
		part(g, "RackBase", Vector3.new(10, 1, 1.6), cf * CFrame.new(0, 0.5, 0.8), rgb(70, 76, 82), Enum.Material.Metal, true)
		for i = -2, 2 do
			rifle(g, cf * CFrame.new(i * 1.8, 3.6, 1) * CFrame.Angles(math.rad(90), 0, 0), rgb(28, 30, 32))
		end
		table4(g, cf * CFrame.new(0, 0, -2.2), 7, 2, 3.2, rgb(90, 96, 100), Enum.Material.Metal)
	end
	sign(g, cf * CFrame.new(0, 10, 1.75), 8, 1.6, "АРСЕНАЛ", style)
	prompt(g, cf * CFrame.new(0, 3, -1.5), "Открыть", "Арсенал", "Inventory")
end

function stations.wardrobe(g: Instance, cf: CFrame, key: string, style)
	local cloth = if key == "Bandits"
		then { rgb(40, 40, 44), rgb(150, 30, 30), rgb(70, 75, 60), rgb(200, 200, 195), rgb(30, 50, 90) }
		else { rgb(30, 40, 70), rgb(25, 25, 28), rgb(60, 70, 55), rgb(30, 40, 70), rgb(210, 210, 205) }
	-- Вешалка с одеждой.
	for _, x in { -3.8, 3.8 } do
		Props.post(g, "RackPost", cf * CFrame.new(x, 0, 0.4), 6.4, 0.25, rgb(160, 160, 165), Enum.Material.Metal, true)
	end
	Props.rod(g, "RackBar", (cf * CFrame.new(-3.8, 6.2, 0.4)).Position, (cf * CFrame.new(3.8, 6.2, 0.4)).Position, 0.2, rgb(170, 170, 175), Enum.Material.Metal)
	for i, color in cloth do
		local x = -3 + (i - 1) * 1.5
		part(g, "Jacket", Vector3.new(1.1, 3.2, 0.5), cf * CFrame.new(x, 4.4, 0.4) * yaw(80), color, Enum.Material.Fabric)
	end
	-- Зеркало.
	part(g, "MirrorFrame", Vector3.new(2.6, 6.2, 0.2), cf * CFrame.new(6.2, 3.6, 1.7), rgb(40, 35, 30), Enum.Material.Wood)
	part(g, "Mirror", Vector3.new(2.2, 5.8, 0.1), cf * CFrame.new(6.2, 3.6, 1.55), rgb(200, 210, 215), Enum.Material.Glass, false, { Reflectance = 0.5 })
	if key == "Gov" then
		-- Шкафчики.
		for i = 0, 2 do
			local c = cf * CFrame.new(-9 + i * 1.8, 3.5, 1.2)
			part(g, "Locker", Vector3.new(1.7, 7, 1.6), c, rgb(70, 90, 110), Enum.Material.Metal, true)
			part(g, "LockerVent", Vector3.new(1, 0.6, 0.05), c * CFrame.new(0, 2.6, -0.82), rgb(40, 50, 60), Enum.Material.DiamondPlate)
		end
	else
		Props.mattress(g, cf * CFrame.new(-7, 0, 1.8))
	end
	sign(g, cf * CFrame.new(0, 10, 1.75), 8, 1.6, "ГАРДЕРОБ", style)
	prompt(g, cf * CFrame.new(0, 3, -1.5), "Переодеться", "Гардероб", "Skins")
end

function stations.board(g: Instance, cf: CFrame, key: string, style)
	local board = part(g, "Board", Vector3.new(11, 5.5, 0.3), cf * CFrame.new(0, 5.6, 1.7), if key == "Bandits" then rgb(170, 130, 80) else rgb(235, 238, 240), if key == "Bandits" then Enum.Material.Cardboard else Enum.Material.SmoothPlastic)
	part(g, "BoardFrame", Vector3.new(11.6, 6.1, 0.2), cf * CFrame.new(0, 5.6, 1.85), rgb(60, 50, 40), Enum.Material.Wood)
	local rng = Random.new(if key == "Bandits" then 11 else 12)
	-- Листки и фото на доске.
	for _ = 1, 9 do
		local x, y = rng:NextNumber(-4.6, 4.6), rng:NextNumber(-2, 2)
		local tone = if rng:NextNumber() < 0.5 then rgb(240, 236, 220) else rgb(210, 200, 180)
		part(g, "Note", Vector3.new(rng:NextNumber(0.9, 1.6), rng:NextNumber(1, 1.6), 0.05), cf * CFrame.new(x, 5.6 + y, 1.52) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-8, 8))), tone, Enum.Material.SmoothPlastic, false, { CastShadow = false })
	end
	if key == "Bandits" then
		-- Красные нитки между фото.
		for _ = 1, 4 do
			local a = cf * CFrame.new(rng:NextNumber(-4.5, 4.5), 5.6 + rng:NextNumber(-2, 2), 1.48)
			local b = cf * CFrame.new(rng:NextNumber(-4.5, 4.5), 5.6 + rng:NextNumber(-2, 2), 1.48)
			Props.rod(g, "String", a.Position, b.Position, 0.05, rgb(190, 30, 30), Enum.Material.Fabric)
		end
	end
	sign(g, cf * CFrame.new(0, 10, 1.75), 8, 1.6, "ЗАДАНИЯ", style)
	prompt(g, cf * CFrame.new(0, 3, -1.5), "Смотреть", "Задания и прогресс", "Progress")
end

function stations.shop(g: Instance, cf: CFrame, key: string, style)
	table4(g, cf * CFrame.new(0, 0, 0.4), 6, 3, 3.2, if key == "Bandits" then rgb(70, 60, 50) else rgb(110, 115, 120), if key == "Bandits" then Enum.Material.Wood else Enum.Material.Metal)
	-- Ноутбук с горящим экраном.
	part(g, "LaptopBase", Vector3.new(2.2, 0.12, 1.5), cf * CFrame.new(0, 3.42, 0.2), rgb(30, 30, 32), Enum.Material.Metal)
	local screen = part(g, "LaptopScreen", Vector3.new(2.2, 1.4, 0.08), cf * CFrame.new(0, 4.1, 1) * CFrame.Angles(math.rad(-12), 0, 0), rgb(30, 30, 32), Enum.Material.Metal)
	local glow = part(g, "LaptopGlow", Vector3.new(2, 1.2, 0.02), screen.CFrame * CFrame.new(0, 0, -0.05), if key == "Bandits" then rgb(90, 200, 120) else rgb(110, 170, 255), Enum.Material.Neon, false, { CastShadow = false })
	local light = Instance.new("PointLight")
	light.Range = 7
	light.Brightness = 0.8
	light.Color = glow.Color
	light.Parent = glow
	if key == "Bandits" then
		-- Пачки денег и сумка.
		for i = 0, 2 do
			part(g, "Cash", Vector3.new(0.9, 0.3, 0.45), cf * CFrame.new(-2 + i * 0.3, 3.5 + i * 0.3, -0.6), rgb(110, 150, 90), Enum.Material.Fabric)
		end
		part(g, "Bag", Vector3.new(2.6, 1.4, 1.2), cf * CFrame.new(4, 0.7, -0.4), rgb(25, 25, 28), Enum.Material.Fabric, true)
	else
		Props.post(g, "Cooler", cf * CFrame.new(4.4, 0, 1), 4.2, 1.4, rgb(230, 230, 235), Enum.Material.SmoothPlastic, true)
	end
	sign(g, cf * CFrame.new(0, 10, 1.75), 8, 1.6, string.upper(style.ShopName), style)
	prompt(g, cf * CFrame.new(0, 3, -1.5), "Открыть", style.ShopName, "Shop")
end

------------------------------------------------------------------------
-- Круг голосования

local function voteZone(g: Instance, cf: CFrame, modeId: string)
	local def = ModesConfig.List[modeId]
	local color = MODE_COLORS[modeId] or FALLBACK_MODE_COLOR
	local d = ZONE_RADIUS * 2
	part(g, "VoteRing", Vector3.new(0.1, d, d), cf * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, false, { Shape = Enum.PartType.Cylinder, CastShadow = false })
	local inner = part(g, "VoteDisc", Vector3.new(0.14, d - 0.8, d - 0.8), cf * CFrame.new(0, 0.07, 0) * CFrame.Angles(0, 0, math.rad(90)), color:Lerp(rgb(15, 15, 18), 0.75), Enum.Material.SmoothPlastic, false, { Shape = Enum.PartType.Cylinder, CastShadow = false })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 0.9
	light.Parent = inner

	-- Название режима над кругом и счётчик голосов.
	local bb = Instance.new("BillboardGui")
	-- Размер в пикселях: вблизи надпись не раздувается, издалека соседние не наезжают друг на друга.
	bb.Size = UDim2.fromOffset(190, 64)
	bb.StudsOffset = Vector3.new(0, 4.5, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 60
	bb.Parent = inner
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 0.5)
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.TextColor3 = color
	name.TextStrokeTransparency = 0.4
	name.Text = string.upper(if def then def.DisplayName else modeId)
	name.Parent = bb
	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.fromScale(0, 0.5)
	desc.Size = UDim2.fromScale(1, 0.22)
	desc.Font = Enum.Font.Gotham
	desc.TextScaled = true
	desc.TextColor3 = rgb(220, 220, 225)
	desc.TextStrokeTransparency = 0.5
	desc.Text = if def and def.Description then def.Description else ""
	desc.Parent = bb
	local votes = Instance.new("TextLabel")
	votes.BackgroundTransparency = 1
	votes.Position = UDim2.fromScale(0, 0.74)
	votes.Size = UDim2.fromScale(1, 0.26)
	votes.Font = Enum.Font.GothamBold
	votes.TextScaled = true
	votes.TextColor3 = rgb(255, 255, 255)
	votes.TextStrokeTransparency = 0.4
	votes.Text = "Голосов: 0"
	votes.Parent = bb

	table.insert(zones, { modeId = modeId, center = cf.Position, label = votes })
end

------------------------------------------------------------------------
-- Комната

local function lamps(g: Instance, cf: CFrame, key: string, style)
	if key == "Bandits" then
		-- Подвесные лампы с абажурами.
		for _, x in { -18, 0, 18 } do
			for _, z in { -10, 10 } do
				local top = cf * CFrame.new(x, H, z)
				Props.rod(g, "LampCord", top.Position, (top * CFrame.new(0, -4, 0)).Position, 0.08, rgb(20, 20, 20), Enum.Material.SmoothPlastic)
				part(g, "LampShade", Vector3.new(2.4, 0.9, 2.4), top * CFrame.new(0, -4.3, 0), rgb(50, 55, 50), Enum.Material.Metal)
				local bulb = part(g, "LampBulb", Vector3.new(0.7, 0.7, 0.7), top * CFrame.new(0, -4.9, 0), style.Lamp, Enum.Material.Neon, false, { Shape = Enum.PartType.Ball, CastShadow = false })
				local light = Instance.new("PointLight")
				light.Color = style.Lamp
				light.Range = 24
				light.Brightness = 1.4
				light.Shadows = true
				light.Parent = bulb
			end
		end
	else
		-- Лампы дневного света в потолке.
		for _, x in { -21, -7, 7, 21 } do
			for _, z in { -11, 11 } do
				local panel = part(g, "CeilingLamp", Vector3.new(7, 0.2, 2.2), cf * CFrame.new(x, H - 0.15, z), style.Lamp, Enum.Material.Neon, false, { CastShadow = false })
				local light = Instance.new("SurfaceLight")
				light.Face = Enum.NormalId.Bottom
				light.Color = style.Lamp
				light.Range = 22
				light.Brightness = 1.1
				light.Angle = 110
				light.Shadows = true
				light.Parent = panel
			end
		end
	end
end

local function decor(g: Instance, cf: CFrame, key: string, style)
	local rng = Random.new(if key == "Bandits" then 3 else 4)
	if key == "Bandits" then
		-- Ворота гаража на передней стене, граффити, диван, шины, поддоны, бочка с огнём.
		local door = cf * CFrame.new(0, 0, -D / 2 + 0.4)
		part(g, "GarageDoor", Vector3.new(22, 11, 0.4), door * CFrame.new(0, 5.5, 0), rgb(120, 125, 120), Enum.Material.CorrodedMetal)
		for i = 0, 9 do
			part(g, "DoorRib", Vector3.new(22, 0.2, 0.2), door * CFrame.new(0, 0.6 + i * 1.1, 0.25), rgb(95, 100, 95), Enum.Material.Metal)
		end
		Props.graffiti(g, door * CFrame.new(0, 6, 0.5) * yaw(180), 14, 5, rng, "БАНДА")
		Props.graffiti(g, cf * CFrame.new(-22, 6, -D / 2 + 0.6) * yaw(180), 10, 5, rng)
		Props.graffiti(g, cf * CFrame.new(22, 6, -D / 2 + 0.6) * yaw(180), 10, 5, rng)
		Props.couch(g, cf * CFrame.new(-24, 0, 19) * yaw(25), rng)
		table4(g, cf * CFrame.new(-17, 0, 18), 4, 2.6, 1.8, rgb(90, 70, 50), Enum.Material.Wood)
		Props.tires(g, cf * CFrame.new(27, 0, 20), rng)
		Props.tires(g, cf * CFrame.new(24, 0, 21.5), rng)
		Props.pallets(g, cf * CFrame.new(18, 0, 20.5), rng)
		Props.fireBarrel(g, cf * CFrame.new(-26, 0, -18))
		Props.fireBarrel(g, cf * CFrame.new(26, 0, -18))
		-- Масляные пятна на полу.
		for _ = 1, 6 do
			local s = rng:NextNumber(2, 5)
			part(g, "OilStain", Vector3.new(0.02, s, s * rng:NextNumber(0.6, 1)), cf * CFrame.new(rng:NextNumber(-26, 26), 0.02, rng:NextNumber(-20, 20)) * CFrame.Angles(0, rng:NextNumber(0, 6), math.rad(90)), rgb(30, 30, 30), Enum.Material.SmoothPlastic, false, { Shape = Enum.PartType.Cylinder, Transparency = 0.55, CastShadow = false })
		end
	else
		-- Флаги и герб на передней стене, стойка дежурного, скамейки, растения.
		local front = cf * CFrame.new(0, 0, -D / 2 + 1.2)
		Props.flag(g, front * CFrame.new(-14, 0, 0), 11, TeamsConfig.List.Gov.Color, rgb(240, 240, 240))
		Props.flag(g, front * CFrame.new(10, 0, 0), 11, TeamsConfig.List.Gov.Color, rgb(240, 240, 240))
		local emblem = front * CFrame.new(0, 8.5, 0.5) * yaw(180)
		Props.disc(g, "Emblem", emblem, 6, 0.3, rgb(200, 170, 70), Enum.Material.Metal)
		Props.disc(g, "EmblemInner", emblem * CFrame.new(0, 0, -0.2), 4.6, 0.3, TeamsConfig.List.Gov.Color, Enum.Material.SmoothPlastic)
		-- Стойка дежурного в заднем углу.
		local desk = cf * CFrame.new(-22, 0, 17) * yaw(30)
		part(g, "Desk", Vector3.new(10, 3.6, 2.4), desk * CFrame.new(0, 1.8, 0), rgb(48, 66, 96), Enum.Material.SmoothPlastic, true)
		part(g, "DeskTop", Vector3.new(10.4, 0.25, 2.8), desk * CFrame.new(0, 3.7, 0), rgb(200, 200, 200), Enum.Material.Marble)
		part(g, "Monitor", Vector3.new(2, 1.3, 0.15), desk * CFrame.new(-2, 4.6, 0.6) * yaw(180), rgb(20, 20, 22), Enum.Material.Metal)
		Props.bench(g, cf * CFrame.new(18, 0, 21))
		Props.bench(g, cf * CFrame.new(26, 0, 21))
		Props.planter(g, cf * CFrame.new(29, 0, -20), rng)
		Props.planter(g, cf * CFrame.new(-29, 0, -20), rng)
		-- Плитка: швы на полу.
		for i = -7, 7 do
			part(g, "TileSeam", Vector3.new(0.08, 0.02, D), cf * CFrame.new(i * 4, 0.01, 0), rgb(140, 140, 135), Enum.Material.SmoothPlastic, false, { CastShadow = false })
		end
		for i = -5, 5 do
			part(g, "TileSeam", Vector3.new(W, 0.02, 0.08), cf * CFrame.new(0, 0.01, i * 4), rgb(140, 140, 135), Enum.Material.SmoothPlastic, false, { CastShadow = false })
		end
	end
end

local function buildRoom(parent: Instance, key: string, cf: CFrame)
	local style = STYLES[key]
	local g = Instance.new("Model")
	g.Name = "HQ_" .. key
	g:SetAttribute("Side", key)

	-- Пол, потолок, стены (снизу панель, сверху основная отделка).
	solid(g, "Floor", Vector3.new(W + 2, 1, D + 2), cf * CFrame.new(0, -0.5, 0), style.Floor)
	solid(g, "Ceiling", Vector3.new(W + 2, 1, D + 2), cf * CFrame.new(0, H + 0.5, 0), style.Ceiling)
	for _, w in {
		{ Vector3.new(W + 2, H, 1), Vector3.new(0, H / 2, D / 2 + 0.5), Vector3.new(0, 0, -1) },
		{ Vector3.new(W + 2, H, 1), Vector3.new(0, H / 2, -D / 2 - 0.5), Vector3.new(0, 0, 1) },
		{ Vector3.new(1, H, D + 2), Vector3.new(W / 2 + 0.5, H / 2, 0), Vector3.new(-1, 0, 0) },
		{ Vector3.new(1, H, D + 2), Vector3.new(-W / 2 - 0.5, H / 2, 0), Vector3.new(1, 0, 0) },
	} do
		solid(g, "Wall", w[1], cf * CFrame.new(w[2]), style.Wall)
		-- Нижняя панель на 3.5 стада, чуть выступает внутрь.
		local lowerSize = Vector3.new(if w[1].X > 1 then w[1].X - 2 else 0.3, 3.5, if w[1].Z > 1 then w[1].Z - 2 else 0.3)
		local pos = w[2] + w[3] * 0.65
		part(g, "WallLower", lowerSize, cf * CFrame.new(pos.X, 1.75, pos.Z), style.Lower[1], style.Lower[2])
	end
	-- Балки под потолком.
	for _, x in { -24, -8, 8, 24 } do
		part(g, "Beam", Vector3.new(1.2, 1.2, D), cf * CFrame.new(x, H - 0.6, 0), if key == "Bandits" then rgb(60, 58, 55) else rgb(210, 210, 208), if key == "Bandits" then Enum.Material.Metal else Enum.Material.Plaster)
	end

	-- Название стороны на задней стене.
	sign(g, cf * CFrame.new(0, 10.5, D / 2 - 0.15), 26, 4.4, style.Title, style)
	sign(g, cf * CFrame.new(0, 7.4, D / 2 - 0.15), 14, 1.4, style.Subtitle, style)
	part(g, "TeamStripe", Vector3.new(W - 2, 0.4, 0.1), cf * CFrame.new(0, 13.3, D / 2 - 0.1), TeamsConfig.List[key].Color, Enum.Material.Neon, false, { CastShadow = false })

	lamps(g, cf, key, style)
	decor(g, cf, key, style)

	-- Станции: слева арсенал и гардероб, справа доска заданий и магазин.
	local left = function(z: number)
		return cf * CFrame.new(-W / 2, 0, z) * yaw(-90)
	end
	local right = function(z: number)
		return cf * CFrame.new(W / 2, 0, z) * yaw(90)
	end
	-- В системе станции +Z смотрит в стену, поэтому сдвигаем точку внутрь на 2 стада.
	stations.arsenal(g, left(6) * CFrame.new(0, 0, -2), key, style)
	stations.wardrobe(g, left(-9) * CFrame.new(0, 0, -2), key, style)
	stations.board(g, right(6) * CFrame.new(0, 0, -2), key, style)
	stations.shop(g, right(-9) * CFrame.new(0, 0, -2), key, style)

	-- Круги голосования по режимам вдоль передней части.
	local order = ModesConfig.Order
	for i, modeId in order do
		local x = (i - (#order + 1) / 2) * 16
		voteZone(g, cf * CFrame.new(x, 0, -11), modeId)
	end

	-- Точки появления у задней стены, лицом к кругам.
	local spots = {}
	for row = 0, 1 do
		for i = -2, 2 do
			table.insert(spots, cf * CFrame.new(i * 4.5, 0, 14 - row * 4))
		end
	end
	spawnSpots[key] = spots

	g.Parent = parent
end

------------------------------------------------------------------------

-- Собрать оба штаба (один раз за сервер).
function Headquarters.ensure(): Model
	if built and built.Parent then
		return built
	end
	local old = workspace:FindFirstChild("Lobby")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Model")
	root.Name = "Lobby"
	table.clear(zones)
	local p = MapsConfig.Lobby.Position
	for i, key in TeamsConfig.Order do
		local cf = CFrame.new(p + Vector3.new((if i == 1 then -1 else 1) * GAP, 0, 0))
		origins[key] = cf
		buildRoom(root, key, cf)
	end
	root.Parent = workspace
	built = root
	return root
end

-- Случайная точка появления в штабе стороны.
function Headquarters.spawnCFrame(side: string): CFrame
	Headquarters.ensure()
	local spots = spawnSpots[side] or spawnSpots[TeamsConfig.Order[1]]
	return spots[math.random(#spots)] + Vector3.new(0, 4, 0)
end

-- Режим, в круге которого стоит точка (или nil).
function Headquarters.voteZoneAt(position: Vector3): string?
	for _, z in zones do
		local flat = Vector3.new(position.X - z.center.X, 0, position.Z - z.center.Z)
		if flat.Magnitude <= ZONE_RADIUS and math.abs(position.Y - z.center.Y) < 7 then
			return z.modeId
		end
	end
	return nil
end

-- Обновить счётчики голосов над кругами в обоих штабах.
function Headquarters.setVotes(counts: { [string]: number })
	for _, z in zones do
		local n = counts[z.modeId] or 0
		z.label.Text = "Голосов: " .. n
	end
end

return Headquarters
