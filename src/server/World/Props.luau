-- Городские мелочи из деталей: урны, мусорные площадки, знаки, столбы, остановки, киоски,
-- рекламные щиты, живые изгороди, бетонные блоки, бочки с огнём и т.п.
-- Используется в Detailer (улицы и дворы) и BaseStyles (полицейский участок, гетто).
--
-- Соглашение: cf — точка на земле, локальная -Z смотрит «вперёд» (на улицу, к зрителю),
-- X — вправо, Y — вверх. Твёрдые детали (solid) — укрытия: по ним бьют пули и о них спотыкаются.
-- Остальное — отделка без столкновений и без попаданий.
local Props = {}

local rgb = Color3.fromRGB
local HALF_PI = math.pi / 2

local METAL = rgb(70, 74, 78)
local LIGHT_METAL = rgb(150, 152, 155)
local CONCRETE = rgb(165, 162, 155)

local function yaw(deg: number): CFrame
	return CFrame.Angles(0, math.rad(deg), 0)
end
Props.yaw = yaw

-- Деталь. solid = true: твёрдая и с попаданиями.
function Props.part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, solid: boolean?, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if not solid and (size.X < 1 or size.Y < 1 or size.Z < 1) then
		p.CastShadow = size.X * size.Y * size.Z > 3
	end
	for k, v in props or {} do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end
local part = Props.part

-- Вертикальный цилиндр высотой h и диаметром d, низ в точке cf.
function Props.post(parent: Instance, name: string, cf: CFrame, h: number, d: number, color: Color3, mat: Enum.Material, solid: boolean?): Part
	return part(parent, name, Vector3.new(h, d, d), cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, HALF_PI), color, mat, solid, { Shape = Enum.PartType.Cylinder })
end
local post = Props.post

-- Диск, плоской стороной вперёд (-Z). cf — центр диска.
function Props.disc(parent: Instance, name: string, cf: CFrame, d: number, thick: number, color: Color3, mat: Enum.Material): Part
	return part(parent, name, Vector3.new(thick, d, d), cf * CFrame.Angles(0, HALF_PI, 0), color, mat, false, { Shape = Enum.PartType.Cylinder })
end
local disc = Props.disc

-- Цилиндр между двумя точками (провод, перила, труба).
function Props.rod(parent: Instance, name: string, a: Vector3, b: Vector3, d: number, color: Color3, mat: Enum.Material, solid: boolean?): Part?
	local len = (b - a).Magnitude
	if len < 0.05 then
		return nil
	end
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, HALF_PI, 0)
	return part(parent, name, Vector3.new(len, d, d), cf, color, mat, solid, { Shape = Enum.PartType.Cylinder })
end
local rod = Props.rod

-- Надпись на передней грани (-Z) детали.
function Props.label(target: BasePart, text: string, color: Color3, font: Enum.Font?, face: Enum.NormalId?, rotation: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	local longest = math.max(target.Size.X, target.Size.Y, target.Size.Z)
	gui.PixelsPerStud = math.clamp(math.floor(400 / longest), 8, 50)
	gui.LightInfluence = 1
	gui.MaxDistance = 260
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.TextWrapped = true
	t.Font = font or Enum.Font.GothamBold
	t.TextColor3 = color
	t.Rotation = rotation or 0
	t.Parent = gui
	gui.Parent = target
	return gui
end
local label = Props.label

-- Табличка с текстом: фон, рамка, надпись. cf — центр таблички, лицом вперёд.
function Props.sign(parent: Instance, cf: CFrame, w: number, h: number, text: string, bg: Color3, fg: Color3, font: Enum.Font?, solid: boolean?): Part
	local board = part(parent, "SignBoard", Vector3.new(w, h, 0.2), cf, bg, Enum.Material.SmoothPlastic, solid)
	local face = part(parent, "SignText", Vector3.new(w * 0.92, h * 0.8, 0.05), cf * CFrame.new(0, 0, -0.13), bg, Enum.Material.SmoothPlastic, false, { Transparency = 1, CastShadow = false })
	label(face, text, fg, font)
	return board
end
local sign = Props.sign

local function pick<T>(list: { T }, rng: Random): T
	return list[rng:NextInteger(1, #list)]
end
Props.pick = pick

------------------------------------------------------------------------
-- Улица

-- Урна у тротуара.
function Props.bin(parent: Instance, cf: CFrame, rng: Random)
	local col = pick({ rgb(52, 92, 62), rgb(60, 62, 66), rgb(40, 70, 120) }, rng)
	post(parent, "Bin", cf, 2.4, 1.5, col, Enum.Material.Metal, true)
	post(parent, "BinRim", cf * CFrame.new(0, 2.3, 0), 0.2, 1.65, col:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Metal)
	post(parent, "BinTrash", cf * CFrame.new(0, 2.25, 0), 0.1, 1.3, rgb(28, 28, 28), Enum.Material.SmoothPlastic)
end

-- Куча мешков с мусором.
function Props.trashbags(parent: Instance, cf: CFrame, rng: Random)
	for _ = 1, rng:NextInteger(2, 5) do
		local s = rng:NextNumber(1.5, 2.3)
		local col = pick({ rgb(25, 25, 27), rgb(30, 32, 36), rgb(40, 55, 40), rgb(90, 80, 60) }, rng)
		local c = cf * CFrame.new(rng:NextNumber(-1.6, 1.6), s * 0.42, rng:NextNumber(-1.2, 1.2))
		part(parent, "TrashBag", Vector3.new(s, s * 0.85, s), c, col, Enum.Material.Plastic, true, { Shape = Enum.PartType.Ball })
	end
end

-- Мусорный контейнер с крышкой.
function Props.dumpster(parent: Instance, cf: CFrame, rng: Random)
	local col = pick({ rgb(45, 95, 60), rgb(60, 70, 95), rgb(120, 120, 118), rgb(150, 110, 40) }, rng)
	part(parent, "Dumpster", Vector3.new(5.5, 3.8, 3.4), cf * CFrame.new(0, 2.3, 0), col, Enum.Material.Metal, true)
	local open = rng:NextNumber() < 0.35
	local lid = if open then cf * CFrame.new(0, 4.6, 1.9) * CFrame.Angles(math.rad(-70), 0, 0) else cf * CFrame.new(0, 4.3, 0.1) * CFrame.Angles(math.rad(-5), 0, 0)
	part(parent, "DumpsterLid", Vector3.new(5.7, 0.2, 3.6), lid, col:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Plastic)
	for _, sx in { -2.3, 2.3 } do
		for _, sz in { -1.3, 1.3 } do
			part(parent, "Wheel", Vector3.new(0.35, 0.7, 0.7), cf * CFrame.new(sx, 0.35, sz) * CFrame.Angles(0, 0, HALF_PI), rgb(25, 25, 25), Enum.Material.Rubber, false, { Shape = Enum.PartType.Cylinder })
		end
	end
	if open then
		part(parent, "DumpsterTrash", Vector3.new(5.2, 0.2, 3.1), cf * CFrame.new(0, 4.15, 0), rgb(40, 40, 38), Enum.Material.SmoothPlastic)
	end
end

-- Контейнерная площадка: бетонный пол, низкая стенка с трёх сторон, два бака, мешки.
-- Размер 13 x 6, открыта вперёд.
function Props.binArea(parent: Instance, cf: CFrame, rng: Random)
	local brick = pick({ rgb(150, 90, 70), rgb(170, 165, 155), rgb(120, 118, 112) }, rng)
	part(parent, "BinPad", Vector3.new(13, 0.3, 6), cf * CFrame.new(0, 0.15, 0), CONCRETE, Enum.Material.Concrete, true)
	part(parent, "BinWall", Vector3.new(13, 3.6, 0.6), cf * CFrame.new(0, 1.8, 2.7), brick, Enum.Material.Brick, true)
	for _, sx in { -1, 1 } do
		part(parent, "BinWall", Vector3.new(0.6, 3.6, 5.4), cf * CFrame.new(sx * 6.2, 1.8, 0), brick, Enum.Material.Brick, true)
	end
	for _, x in { -3, 3 } do
		Props.dumpster(parent, cf * CFrame.new(x, 0.3, 0.4) * yaw(rng:NextNumber(-4, 4)), rng)
	end
	if rng:NextNumber() < 0.7 then
		Props.trashbags(parent, cf * CFrame.new(rng:NextNumber(-4, 4), 0, -4.2), rng)
	end
end

-- Пожарный гидрант.
function Props.hydrant(parent: Instance, cf: CFrame)
	local red = rgb(185, 40, 35)
	post(parent, "Hydrant", cf, 2.2, 0.9, red, Enum.Material.Metal, true)
	post(parent, "HydrantCap", cf * CFrame.new(0, 2.2, 0), 0.4, 0.7, rgb(210, 200, 60), Enum.Material.Metal)
	rod(parent, "HydrantNozzle", (cf * CFrame.new(-0.8, 1.5, 0)).Position, (cf * CFrame.new(0.8, 1.5, 0)).Position, 0.4, red, Enum.Material.Metal)
end

-- Дорожные знаки. kind: speed, stop, noparking, crossing, mainroad, noentry, bus.
Props.SIGN_KINDS = { "speed", "speed", "stop", "noparking", "noparking", "crossing", "mainroad", "noentry" }

local function signPlate(parent: Instance, c: CFrame, kind: string, rng: Random)
	local white, red, blue = rgb(240, 240, 236), rgb(200, 35, 35), rgb(30, 80, 170)
	local back = rgb(150, 152, 155)
	if kind == "speed" then
		disc(parent, "SignRing", c, 2.6, 0.12, red, Enum.Material.SmoothPlastic)
		disc(parent, "SignFace", c * CFrame.new(0, 0, -0.04), 2.1, 0.1, white, Enum.Material.SmoothPlastic)
		local t = part(parent, "SignText", Vector3.new(1.6, 1.2, 0.05), c * CFrame.new(0, 0, -0.12), white, Enum.Material.SmoothPlastic, false, { Transparency = 1 })
		label(t, pick({ "40", "40", "60", "20", "30" }, rng), rgb(20, 20, 20), Enum.Font.GothamBlack)
	elseif kind == "stop" then
		disc(parent, "SignFace", c, 2.6, 0.12, red, Enum.Material.SmoothPlastic)
		local t = part(parent, "SignText", Vector3.new(2, 0.9, 0.05), c * CFrame.new(0, 0, -0.1), red, Enum.Material.SmoothPlastic, false, { Transparency = 1 })
		label(t, "STOP", white, Enum.Font.GothamBlack)
	elseif kind == "noparking" then
		disc(parent, "SignRing", c, 2.6, 0.12, red, Enum.Material.SmoothPlastic)
		disc(parent, "SignFace", c * CFrame.new(0, 0, -0.04), 2.1, 0.1, blue, Enum.Material.SmoothPlastic)
		part(parent, "SignSlash", Vector3.new(2.3, 0.3, 0.06), c * CFrame.new(0, 0, -0.11) * CFrame.Angles(0, 0, math.rad(45)), red, Enum.Material.SmoothPlastic)
	elseif kind == "noentry" then
		disc(parent, "SignFace", c, 2.6, 0.12, red, Enum.Material.SmoothPlastic)
		part(parent, "SignBar", Vector3.new(1.8, 0.45, 0.06), c * CFrame.new(0, 0, -0.1), white, Enum.Material.SmoothPlastic)
	elseif kind == "mainroad" then
		local d = c * CFrame.Angles(0, 0, math.rad(45))
		part(parent, "SignFace", Vector3.new(1.9, 1.9, 0.12), d, white, Enum.Material.SmoothPlastic)
		part(parent, "SignInner", Vector3.new(1.3, 1.3, 0.06), d * CFrame.new(0, 0, -0.08), rgb(240, 190, 30), Enum.Material.SmoothPlastic)
	elseif kind == "crossing" then
		part(parent, "SignFace", Vector3.new(2.2, 2.2, 0.12), c, blue, Enum.Material.SmoothPlastic)
		part(parent, "SignInner", Vector3.new(1.6, 1.6, 0.06), c * CFrame.new(0, 0, -0.08), white, Enum.Material.SmoothPlastic)
		local t = part(parent, "SignText", Vector3.new(1.5, 1.5, 0.05), c * CFrame.new(0, 0, -0.13), white, Enum.Material.SmoothPlastic, false, { Transparency = 1 })
		label(t, "🚶", rgb(20, 20, 20), Enum.Font.GothamBlack)
	elseif kind == "bus" then
		part(parent, "SignFace", Vector3.new(2, 2, 0.12), c, blue, Enum.Material.SmoothPlastic)
		local t = part(parent, "SignText", Vector3.new(1.7, 1.7, 0.05), c * CFrame.new(0, 0, -0.1), blue, Enum.Material.SmoothPlastic, false, { Transparency = 1 })
		label(t, "A", white, Enum.Font.GothamBlack)
	end
	-- Обратная сторона: серая.
	part(parent, "SignBack", Vector3.new(2, 2, 0.05), c * CFrame.new(0, 0, 0.1), back, Enum.Material.Metal, false, { Transparency = if kind == "mainroad" then 1 else 0 })
end

-- Знак на столбе. Лицом вперёд (-Z).
function Props.roadSign(parent: Instance, cf: CFrame, kind: string, rng: Random)
	post(parent, "SignPole", cf, 8.4, 0.3, LIGHT_METAL, Enum.Material.Metal, true)
	signPlate(parent, cf * CFrame.new(0, 7.2, -0.25), kind, rng)
	-- Иногда второй знак под первым.
	if rng:NextNumber() < 0.25 then
		signPlate(parent, cf * CFrame.new(0, 4.6, -0.25), pick({ "noparking", "speed", "mainroad" }, rng), rng)
	end
end

-- Деревянный столб ЛЭП с перекладиной. Возвращает точки крепления проводов (слева, справа).
function Props.powerPole(parent: Instance, cf: CFrame): (Vector3, Vector3)
	local wood = rgb(92, 72, 52)
	post(parent, "PowerPole", cf, 19, 0.8, wood, Enum.Material.Wood, true)
	part(parent, "PoleCross", Vector3.new(6, 0.45, 0.45), cf * CFrame.new(0, 17.8, 0), wood, Enum.Material.Wood)
	for _, x in { -2.6, 0, 2.6 } do
		post(parent, "Insulator", cf * CFrame.new(x, 18, 0), 0.6, 0.3, rgb(230, 230, 225), Enum.Material.Glass)
	end
	if math.abs(cf.Position.X * 7 + cf.Position.Z * 3) % 3 < 1 then
		-- Трансформатор на некоторых столбах.
		post(parent, "Transformer", cf * CFrame.new(0, 12.5, 0.9), 2.2, 1.4, LIGHT_METAL, Enum.Material.Metal)
	end
	return (cf * CFrame.new(-2.6, 18.6, 0)).Position, (cf * CFrame.new(2.6, 18.6, 0)).Position
end

function Props.wire(parent: Instance, a: Vector3, b: Vector3)
	-- Провисание: две половины с опущенной серединой.
	local sag = math.min(2.2, (b - a).Magnitude * 0.03)
	local mid = (a + b) / 2 - Vector3.new(0, sag, 0)
	rod(parent, "Wire", a, mid, 0.12, rgb(25, 25, 25), Enum.Material.SmoothPlastic)
	rod(parent, "Wire", mid, b, 0.12, rgb(25, 25, 25), Enum.Material.SmoothPlastic)
end

-- Остановка: навес 10 x 4, задняя стенка из стекла, скамейка, табличка. Лицом к дороге (-Z).
function Props.busStop(parent: Instance, cf: CFrame, rng: Random)
	local frame = pick({ rgb(60, 90, 140), rgb(70, 74, 78), rgb(150, 50, 40) }, rng)
	for _, x in { -4.8, 4.8 } do
		part(parent, "StopPost", Vector3.new(0.4, 8, 0.4), cf * CFrame.new(x, 4, 1.6), frame, Enum.Material.Metal, true)
		part(parent, "StopPost", Vector3.new(0.4, 8, 0.4), cf * CFrame.new(x, 4, -1.4), frame, Enum.Material.Metal, true)
		part(parent, "StopSideGlass", Vector3.new(0.15, 5.5, 2.6), cf * CFrame.new(x, 4.2, 0.1), rgb(170, 200, 210), Enum.Material.Glass, true, { Transparency = 0.55 })
	end
	part(parent, "StopRoof", Vector3.new(10.6, 0.4, 4.4), cf * CFrame.new(0, 8.2, 0.1), frame, Enum.Material.Metal, true)
	part(parent, "StopBackGlass", Vector3.new(9.2, 5.5, 0.15), cf * CFrame.new(0, 4.2, 1.6), rgb(170, 200, 210), Enum.Material.Glass, true, { Transparency = 0.55 })
	-- Реклама на задней стенке.
	local ad = part(parent, "StopAd", Vector3.new(3.4, 4.6, 0.1), cf * CFrame.new(3, 4.2, 1.5), rgb(240, 236, 220), Enum.Material.SmoothPlastic)
	label(ad, pick({ "ЛЕТО\nСКИДКИ", "КУРСЫ\nВОЖДЕНИЯ", "НОВЫЙ\nСЕЗОН", "ДОМ\nБЫСТРО" }, rng), rgb(180, 40, 40), Enum.Font.GothamBlack)
	part(parent, "StopBench", Vector3.new(6, 0.3, 1.4), cf * CFrame.new(-1, 1.9, 0.6), rgb(150, 105, 65), Enum.Material.WoodPlanks, true)
	for _, x in { -3.5, 1.5 } do
		part(parent, "StopBenchLeg", Vector3.new(0.3, 1.8, 1.2), cf * CFrame.new(x, 0.9, 0.6), METAL, Enum.Material.Metal)
	end
	local s = sign(parent, cf * CFrame.new(-2.5, 7.4, -0.5), 4, 0.9, "ОСТАНОВКА", rgb(30, 80, 170), rgb(255, 255, 255), Enum.Font.GothamBold)
	s.Name = "StopSign"
	Props.bin(parent, cf * CFrame.new(6.3, 0, -0.6), rng)
end

local KIOSKS = {
	{ "ТАБАК", rgb(180, 50, 40) },
	{ "ПРЕССА", rgb(40, 90, 160) },
	{ "ШАУРМА", rgb(200, 120, 30) },
	{ "ЦВЕТЫ", rgb(60, 140, 70) },
	{ "КОФЕ", rgb(110, 70, 45) },
	{ "КЛЮЧИ\nРЕМОНТ ОБУВИ", rgb(90, 90, 100) },
	{ "ЛОТЕРЕЯ", rgb(200, 160, 30) },
}

-- Киоск 7 x 5, окно и вывеска спереди.
function Props.kiosk(parent: Instance, cf: CFrame, rng: Random)
	local k = pick(KIOSKS, rng)
	local body = k[2]:Lerp(rgb(235, 232, 225), 0.45)
	part(parent, "Kiosk", Vector3.new(7, 7.2, 5), cf * CFrame.new(0, 3.6, 0), body, Enum.Material.SmoothPlastic, true)
	part(parent, "KioskRoof", Vector3.new(7.6, 0.4, 5.6), cf * CFrame.new(0, 7.4, -0.1), k[2], Enum.Material.Metal)
	part(parent, "KioskWindow", Vector3.new(5, 2.6, 0.1), cf * CFrame.new(0, 4, -2.54), rgb(60, 80, 95), Enum.Material.Glass, false, { Reflectance = 0.15 })
	part(parent, "KioskShelf", Vector3.new(5.4, 0.25, 0.9), cf * CFrame.new(0, 2.6, -2.9), rgb(200, 200, 196), Enum.Material.Metal)
	local s = sign(parent, cf * CFrame.new(0, 6.3, -2.62), 6.4, 1.3, k[1], k[2], rgb(255, 255, 255), Enum.Font.GothamBlack)
	s.Name = "KioskSign"
end

local ADS = {
	{ "ШИНОМОНТАЖ 24/7", rgb(30, 30, 30), rgb(250, 200, 40) },
	{ "КРЕДИТ ЗА 5 МИНУТ", rgb(20, 90, 170), rgb(255, 255, 255) },
	{ "НОВОСТРОЙКИ У ПАРКА", rgb(60, 140, 80), rgb(255, 255, 255) },
	{ "ПИЦЦА — ДОСТАВКА 30 МИН", rgb(200, 50, 40), rgb(255, 240, 200) },
	{ "АВТОСЕРВИС «МОТОР»", rgb(40, 40, 50), rgb(230, 90, 40) },
	{ "СДАЮТСЯ ОФИСЫ", rgb(230, 230, 225), rgb(40, 60, 120) },
	{ "МЕБЕЛЬ НА ЗАКАЗ", rgb(150, 100, 60), rgb(255, 255, 255) },
	{ "СВЯЗЬ БЕЗ ГРАНИЦ", rgb(120, 40, 140), rgb(255, 255, 255) },
}

-- Рекламный щит на двух ногах, 22 x 9, низ щита на высоте 11. Лицом вперёд.
function Props.billboard(parent: Instance, cf: CFrame, rng: Random)
	local ad = pick(ADS, rng)
	for _, x in { -6, 6 } do
		part(parent, "BillboardLeg", Vector3.new(1, 11, 1), cf * CFrame.new(x, 5.5, 0.6), METAL, Enum.Material.Metal, true)
	end
	part(parent, "BillboardFrame", Vector3.new(22.6, 9.6, 0.6), cf * CFrame.new(0, 15.5, 0.6), METAL, Enum.Material.Metal, true)
	local face = part(parent, "BillboardFace", Vector3.new(22, 9, 0.1), cf * CFrame.new(0, 15.5, 0.25), ad[2], Enum.Material.SmoothPlastic)
	local txt = part(parent, "BillboardText", Vector3.new(20, 6, 0.05), cf * CFrame.new(0, 15.5, 0.17), ad[2], Enum.Material.SmoothPlastic, false, { Transparency = 1 })
	label(txt, ad[1], ad[3], Enum.Font.GothamBlack)
	part(parent, "BillboardWalk", Vector3.new(22, 0.2, 1.4), cf * CFrame.new(0, 10.9, -0.2), METAL, Enum.Material.DiamondPlate)
	for _, x in { -7, 0, 7 } do
		part(parent, "BillboardLamp", Vector3.new(0.5, 0.4, 1.2), cf * CFrame.new(x, 20.6, -0.4), METAL, Enum.Material.Metal)
	end
	return face
end

-- Живая изгородь длиной len вдоль X.
function Props.hedge(parent: Instance, cf: CFrame, len: number, rng: Random)
	local col = pick({ rgb(70, 110, 52), rgb(62, 98, 48), rgb(80, 118, 58) }, rng)
	part(parent, "Hedge", Vector3.new(len, 2.4, 1.8), cf * CFrame.new(0, 1.2, 0), col, Enum.Material.LeafyGrass, true)
	part(parent, "HedgeTop", Vector3.new(len - 0.3, 0.5, 1.5), cf * CFrame.new(0, 2.6, 0), col:Lerp(rgb(120, 150, 70), 0.25), Enum.Material.LeafyGrass)
end

-- Бетонная клумба с кустом.
function Props.planter(parent: Instance, cf: CFrame, rng: Random)
	part(parent, "Planter", Vector3.new(3.2, 1.6, 3.2), cf * CFrame.new(0, 0.8, 0), CONCRETE, Enum.Material.Concrete, true)
	part(parent, "PlanterSoil", Vector3.new(2.8, 0.1, 2.8), cf * CFrame.new(0, 1.62, 0), rgb(70, 52, 38), Enum.Material.Ground)
	local leaf = pick({ rgb(80, 130, 60), rgb(95, 140, 62), rgb(120, 90, 140) }, rng)
	part(parent, "PlanterBush", Vector3.new(2.6, 2, 2.6), cf * CFrame.new(0, 2.5, 0), leaf, Enum.Material.LeafyGrass, false, { Shape = Enum.PartType.Ball })
end

-- Бетонный блок-отбойник 6 x 2.8 вдоль X.
function Props.jersey(parent: Instance, cf: CFrame, color: Color3?)
	local col = color or rgb(190, 188, 180)
	part(parent, "Barrier", Vector3.new(6, 1.2, 2), cf * CFrame.new(0, 0.6, 0), col, Enum.Material.Concrete, true)
	part(parent, "Barrier", Vector3.new(6, 1.6, 0.9), cf * CFrame.new(0, 2, 0), col, Enum.Material.Concrete, true)
end

-- Скамейка.
function Props.bench(parent: Instance, cf: CFrame)
	local wood = rgb(150, 105, 65)
	for _, x in { -2.4, 2.4 } do
		part(parent, "BenchLeg", Vector3.new(0.3, 1.8, 1.6), cf * CFrame.new(x, 0.9, 0), METAL, Enum.Material.Metal, true)
	end
	part(parent, "BenchSeat", Vector3.new(5.6, 0.3, 1.4), cf * CFrame.new(0, 1.85, 0), wood, Enum.Material.WoodPlanks, true)
	part(parent, "BenchBack", Vector3.new(5.6, 1, 0.18), cf * CFrame.new(0, 2.6, 0.8) * CFrame.Angles(math.rad(-12), 0, 0), wood, Enum.Material.WoodPlanks)
end

-- Табличка с адресом на стене. cf — точка на стене, лицом наружу.
local STREETS = { "ул. Заводская", "ул. Лесная", "ул. Садовая", "пр. Строителей", "ул. Рабочая", "ул. Речная", "ул. Школьная", "ул. Новая", "пер. Тихий", "ул. Северная" }
function Props.addressPlate(parent: Instance, cf: CFrame, rng: Random)
	local text = pick(STREETS, rng) .. ", " .. rng:NextInteger(1, 48)
	sign(parent, cf * CFrame.new(0, 0, -0.12), 4.2, 1, text, rgb(30, 70, 150), rgb(255, 255, 255), Enum.Font.GothamBold)
end

------------------------------------------------------------------------
-- Гетто и окраины

local TAGS = { "БАНДА", "ЮГ", "НАШ РАЙОН", "ZONA", "777", "КРУГ", "ВОСТОК", "SK8", "ЧЁРНЫЕ", "ПРОРВЁМСЯ", "ДВОР", "ЖИЗНЬ ТАКАЯ" }
local TAG_COLORS = { rgb(230, 60, 60), rgb(250, 200, 40), rgb(60, 200, 230), rgb(140, 230, 70), rgb(240, 120, 200), rgb(255, 255, 255), rgb(250, 140, 40) }

-- Граффити на стене: пятна краски и надпись. cf — центр на поверхности стены, лицом наружу.
function Props.graffiti(parent: Instance, cf: CFrame, w: number, h: number, rng: Random, text: string?)
	local base = pick(TAG_COLORS, rng)
	for _ = 1, rng:NextInteger(1, 3) do
		local sw, sh = w * rng:NextNumber(0.4, 0.9), h * rng:NextNumber(0.4, 0.9)
		part(parent, "Paint", Vector3.new(sw, sh, 0.05), cf * CFrame.new(rng:NextNumber(-w / 2 + sw / 2, w / 2 - sw / 2), rng:NextNumber(-h / 2 + sh / 2, h / 2 - sh / 2), -0.04), pick(TAG_COLORS, rng):Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.SmoothPlastic, false, { Transparency = 0.25, CastShadow = false })
	end
	local t = part(parent, "Graffiti", Vector3.new(w, h, 0.05), cf * CFrame.new(0, 0, -0.09), base, Enum.Material.SmoothPlastic, false, { Transparency = 1 })
	label(t, text or pick(TAGS, rng), base, Enum.Font.PermanentMarker, nil, rng:NextNumber(-8, 8))
end

-- Бочка с огнём.
function Props.fireBarrel(parent: Instance, cf: CFrame)
	local rust = rgb(110, 60, 35)
	post(parent, "FireBarrel", cf, 3.4, 2.2, rust, Enum.Material.CorrodedMetal, true)
	local coals = post(parent, "Coals", cf * CFrame.new(0, 3.25, 0), 0.2, 1.9, rgb(255, 120, 40), Enum.Material.Neon)
	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 7
	fire.Color = rgb(255, 140, 50)
	fire.SecondaryColor = rgb(255, 60, 20)
	fire.Parent = coals
	local light = Instance.new("PointLight")
	light.Range = 16
	light.Brightness = 1.6
	light.Color = rgb(255, 150, 70)
	light.Shadows = false
	light.Parent = coals
end

-- Старый диван.
function Props.couch(parent: Instance, cf: CFrame, rng: Random)
	local col = pick({ rgb(120, 60, 50), rgb(70, 80, 60), rgb(90, 80, 110), rgb(130, 110, 80) }, rng)
	part(parent, "Couch", Vector3.new(6.5, 1.6, 2.8), cf * CFrame.new(0, 0.8, 0), col, Enum.Material.Fabric, true)
	part(parent, "CouchBack", Vector3.new(6.5, 1.8, 0.8), cf * CFrame.new(0, 2.4, 1), col, Enum.Material.Fabric, true)
	for _, x in { -3, 3 } do
		part(parent, "CouchArm", Vector3.new(0.8, 1, 2.8), cf * CFrame.new(x, 2.1, 0), col:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Fabric)
	end
	part(parent, "CouchCushion", Vector3.new(2.6, 0.5, 2), cf * CFrame.new(-1.4, 1.85, -0.2) * CFrame.Angles(0, math.rad(rng:NextNumber(-10, 10)), 0), col:Lerp(Color3.new(1, 1, 1), 0.08), Enum.Material.Fabric)
end

-- Матрас, прислонённый к стене (cf — у стены, лицом наружу).
function Props.mattress(parent: Instance, cf: CFrame)
	part(parent, "Mattress", Vector3.new(4, 7, 0.8), cf * CFrame.new(0, 3.3, -0.9) * CFrame.Angles(math.rad(-14), 0, 0), rgb(200, 190, 165), Enum.Material.Fabric)
	part(parent, "MattressStain", Vector3.new(1.6, 1.4, 0.05), cf * CFrame.new(0.6, 3.6, -1.35) * CFrame.Angles(math.rad(-14), 0, 0), rgb(150, 125, 85), Enum.Material.SmoothPlastic)
end

-- Покрышки стопкой.
function Props.tires(parent: Instance, cf: CFrame, rng: Random)
	for i = 0, rng:NextInteger(2, 4) - 1 do
		local c = cf * CFrame.new(rng:NextNumber(-0.3, 0.3), 0.45 + i * 0.85, rng:NextNumber(-0.3, 0.3))
		part(parent, "Tire", Vector3.new(0.85, 2.8, 2.8), c * CFrame.Angles(0, 0, HALF_PI), rgb(28, 28, 30), Enum.Material.Rubber, true, { Shape = Enum.PartType.Cylinder })
		part(parent, "TireHole", Vector3.new(0.9, 1.3, 1.3), c * CFrame.Angles(0, 0, HALF_PI), rgb(12, 12, 12), Enum.Material.SmoothPlastic, false, { Shape = Enum.PartType.Cylinder })
	end
end

-- Поддоны стопкой.
function Props.pallets(parent: Instance, cf: CFrame, rng: Random)
	local wood = rgb(170, 135, 90)
	for i = 0, rng:NextInteger(2, 5) - 1 do
		local c = cf * CFrame.new(rng:NextNumber(-0.2, 0.2), 0.3 + i * 0.6, rng:NextNumber(-0.2, 0.2)) * yaw(rng:NextNumber(-6, 6))
		part(parent, "Pallet", Vector3.new(4, 0.6, 4), c, wood, Enum.Material.WoodPlanks, true)
	end
end

-- Сгоревшая машина на кирпичах (просто декорация из деталей, не транспорт).
function Props.wreck(parent: Instance, cf: CFrame, rng: Random)
	local col = pick({ rgb(60, 45, 40), rgb(45, 45, 48), rgb(80, 55, 40) }, rng)
	part(parent, "WreckBody", Vector3.new(6.4, 2.4, 14), cf * CFrame.new(0, 2.4, 0), col, Enum.Material.CorrodedMetal, true)
	part(parent, "WreckCabin", Vector3.new(5.8, 2.2, 6.5), cf * CFrame.new(0, 4.7, 0.8), col:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.CorrodedMetal, true)
	part(parent, "WreckWindow", Vector3.new(5.9, 1.4, 6.6), cf * CFrame.new(0, 4.8, 0.8), rgb(15, 15, 15), Enum.Material.SmoothPlastic)
	for _, sx in { -2.4, 2.4 } do
		for _, sz in { -4.5, 4.5 } do
			part(parent, "WreckBrick", Vector3.new(1.4, 1.2, 1.4), cf * CFrame.new(sx, 0.6, sz), rgb(150, 80, 60), Enum.Material.Brick, true)
		end
	end
	if rng:NextNumber() < 0.5 then
		Props.tires(parent, cf * CFrame.new(5.5, 0, -3), rng)
	end
end

-- Баскетбольное кольцо на столбе. Щит смотрит вперёд (-Z).
function Props.hoop(parent: Instance, cf: CFrame)
	post(parent, "HoopPole", cf, 11, 0.5, METAL, Enum.Material.Metal, true)
	part(parent, "HoopArm", Vector3.new(0.3, 0.3, 2.4), cf * CFrame.new(0, 10, -1.1), METAL, Enum.Material.Metal)
	part(parent, "Backboard", Vector3.new(6, 3.6, 0.2), cf * CFrame.new(0, 10.6, -2.3), rgb(235, 235, 230), Enum.Material.SmoothPlastic)
	part(parent, "BackboardMark", Vector3.new(2.2, 1.6, 0.05), cf * CFrame.new(0, 10.2, -2.42), rgb(200, 60, 40), Enum.Material.SmoothPlastic, false, { Transparency = 0.2 })
	part(parent, "Rim", Vector3.new(0.15, 1.8, 1.8), cf * CFrame.new(0, 9.4, -3.4) * CFrame.Angles(0, 0, HALF_PI), rgb(220, 90, 30), Enum.Material.Metal, false, { Shape = Enum.PartType.Cylinder })
end

-- Сетчатый забор между точками a и b (высота h): столбы, верхняя труба, сетка.
function Props.chainLink(parent: Instance, a: Vector3, b: Vector3, h: number)
	local len = (b - a).Magnitude
	if len < 1 then
		return
	end
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, mid + (b - a))
	part(parent, "ChainLink", Vector3.new(0.12, h, len), cf * CFrame.new(0, h / 2, 0), rgb(150, 155, 158), Enum.Material.DiamondPlate, true, { Transparency = 0.55 })
	rod(parent, "ChainRail", a + Vector3.new(0, h, 0), b + Vector3.new(0, h, 0), 0.25, LIGHT_METAL, Enum.Material.Metal)
	local n = math.max(1, math.floor(len / 8))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		post(parent, "ChainPost", CFrame.new(p), h + 0.2, 0.3, LIGHT_METAL, Enum.Material.Metal)
	end
end

-- Бельевая верёвка между точками a и b (на высоте точек) с бельём.
function Props.clothesline(parent: Instance, a: Vector3, b: Vector3, rng: Random)
	rod(parent, "Clothesline", a, b, 0.08, rgb(220, 220, 215), Enum.Material.SmoothPlastic)
	local n = math.floor((b - a).Magnitude / 2.6)
	for i = 1, n do
		if rng:NextNumber() < 0.7 then
			local p = a:Lerp(b, i / (n + 1))
			local sw, sh = rng:NextNumber(1.2, 2.2), rng:NextNumber(1.4, 2.8)
			part(parent, "Laundry", Vector3.new(sw, sh, 0.08), CFrame.lookAt(p, p + (b - a)) * CFrame.Angles(0, HALF_PI, 0) * CFrame.new(0, -sh / 2, 0), pick(TAG_COLORS, rng):Lerp(rgb(240, 240, 235), 0.5), Enum.Material.Fabric)
		end
	end
end

-- Колючая проволока по верху стены: зигзаг, похожий на спираль, вдоль X, длина len.
function Props.razorWire(parent: Instance, cf: CFrame, len: number)
	local n = math.max(2, math.floor(len / 1.2))
	local prev: Vector3? = nil
	for i = 0, n do
		local x = -len / 2 + i * (len / n)
		local k = i % 4
		local y = if k == 0 then 0.2 elseif k == 2 then 1.4 else 0.8
		local z = if k == 1 then -0.6 elseif k == 3 then 0.6 else 0
		local p = (cf * CFrame.new(x, y, z)).Position
		if prev then
			rod(parent, "RazorWire", prev, p, 0.1, rgb(165, 167, 170), Enum.Material.Metal)
		end
		prev = p
	end
end

------------------------------------------------------------------------
-- Силовые

-- Прожекторная мачта высотой 20; прожектор смотрит вперёд (-Z) и вниз.
function Props.floodlight(parent: Instance, cf: CFrame)
	post(parent, "MastPole", cf, 20, 0.7, LIGHT_METAL, Enum.Material.Metal, true)
	part(parent, "MastBar", Vector3.new(4, 0.3, 0.3), cf * CFrame.new(0, 19.6, 0), LIGHT_METAL, Enum.Material.Metal)
	for _, x in { -1.4, 1.4 } do
		local head = cf * CFrame.new(x, 19.6, -0.6) * CFrame.Angles(math.rad(-35), 0, 0)
		part(parent, "Floodlight", Vector3.new(1.4, 1, 0.6), head, METAL, Enum.Material.Metal)
		local glass = part(parent, "FloodGlass", Vector3.new(1.2, 0.8, 0.05), head * CFrame.new(0, 0, -0.32), rgb(255, 245, 220), Enum.Material.Neon)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Range = 45
		light.Angle = 70
		light.Brightness = 1.5
		light.Shadows = false
		light.Enabled = false
		light.Parent = glass
		game:GetService("CollectionService"):AddTag(glass, "StreetLamp")
	end
end

-- Камера наблюдения на кронштейне. cf — точка на стене, лицом наружу.
function Props.camera(parent: Instance, cf: CFrame)
	part(parent, "CamArm", Vector3.new(0.25, 0.25, 1.2), cf * CFrame.new(0, 0, -0.6), METAL, Enum.Material.Metal)
	local body = cf * CFrame.new(0, -0.3, -1.4) * CFrame.Angles(math.rad(-20), 0, 0)
	part(parent, "Camera", Vector3.new(0.7, 0.7, 1.6), body, rgb(230, 230, 228), Enum.Material.SmoothPlastic)
	part(parent, "CamLens", Vector3.new(0.4, 0.4, 0.1), body * CFrame.new(0, 0, -0.82), rgb(15, 15, 20), Enum.Material.Glass)
	part(parent, "CamLed", Vector3.new(0.1, 0.1, 0.05), body * CFrame.new(0.22, 0.22, -0.82), rgb(255, 40, 40), Enum.Material.Neon)
end

-- Флагшток высотой h с флагом цвета color.
function Props.flag(parent: Instance, cf: CFrame, h: number, color: Color3, stripe: Color3?)
	post(parent, "FlagPole", cf, h, 0.5, rgb(210, 210, 210), Enum.Material.Metal, true)
	part(parent, "PoleTop", Vector3.new(0.7, 0.7, 0.7), cf * CFrame.new(0, h + 0.3, 0), rgb(220, 200, 90), Enum.Material.Metal, false, { Shape = Enum.PartType.Ball })
	local fl = cf * CFrame.new(3.2, h - 2.4, 0)
	part(parent, "Flag", Vector3.new(6, 4, 0.12), fl, color, Enum.Material.Fabric)
	if stripe then
		part(parent, "FlagStripe", Vector3.new(6, 1.1, 0.14), fl, stripe, Enum.Material.Fabric)
	end
end

return Props
