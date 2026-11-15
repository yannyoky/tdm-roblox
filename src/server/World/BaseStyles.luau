-- Оформление баз команд: полицейский участок у силовиков и район гетто у банды.
-- Какой команде какой стиль — Config/Decor.luau (BaseStyle).
--
-- Геймплей базы не меняется: те же стены и ворота, площадки машин, невидимый объём базы.
-- Здания стоят у задней стены, точки появления — перед ними (MapBuilder сдвигает их вперёд,
-- если у базы есть стиль), машины — у ворот. Мелочь стоит по бокам и не мешает выезду.
--
-- Локальная система базы (cf): -Z смотрит на ворота (к центру карты), база 110 x 84,
-- x от -55 до 55, z от -42 (ворота) до 42 (задняя стена).
local Props = require(script.Parent.Props)

local BaseStyles = {}

local rgb = Color3.fromRGB
local yaw = Props.yaw
local part = Props.part

-- Ключевые размеры (должны совпадать с MapBuilder).
local BASE_W, BASE_D = 110, 84
local GATE_W = 44

export type Ctx = {
	cf: CFrame, -- система базы
	geo: Instance, -- папка Base_<Team>
	teamColor: Color3,
	place: (e: { [string]: any }) -> (), -- поставить элемент карты (block, shell...) с отделкой
	padXs: { number }, -- центры площадок машин по X
	padZ: number, -- центр площадок по Z
}

-- Элемент карты в локальных координатах базы -> мировые.
local function element(ctx: Ctx, e: { [string]: any }, lx: number, lz: number, localRot: number?)
	local p = ctx.cf:PointToWorldSpace(Vector3.new(lx, 0, lz))
	local look = ctx.cf.LookVector
	local baseYaw = math.deg(math.atan2(-look.X, -look.Z))
	e.x, e.z = p.X, p.Z
	e.rot = baseYaw + (localRot or 0)
	ctx.place(e)
end

-- Точка на земле базы, повёрнутая на rot (0 — лицом к воротам, 180 — к задней стене,
-- -90 — лицом к +X, 90 — к -X).
local function at(ctx: Ctx, lx: number, lz: number, rot: number?, ly: number?): CFrame
	return ctx.cf * CFrame.new(lx, ly or 0, lz) * yaw(rot or 0)
end

-- Стены базы: для каждой — центр, длина, нормаль внутрь (в локальных координатах базы).
local function walls(ctx: Ctx)
	local list = {}
	for _, w in ctx.geo:GetChildren() do
		if w:IsA("BasePart") and w.Name == "BaseWall" then
			local lc = ctx.cf:ToObjectSpace(w.CFrame)
			local along = if w.Size.X > w.Size.Z then "X" else "Z"
			local len = math.max(w.Size.X, w.Size.Z)
			local p = lc.Position
			local inward = if along == "X" then Vector3.new(0, 0, -math.sign(p.Z)) else Vector3.new(-math.sign(p.X), 0, 0)
			table.insert(list, { part = w, pos = p, len = len, along = along, inward = inward, thick = math.min(w.Size.X, w.Size.Z), h = w.Size.Y })
		end
	end
	return list
end

-- Рамка на поверхности стены: X вдоль стены, -Z наружу от поверхности (inside = внутренняя сторона).
local function wallFace(ctx: Ctx, wall, u: number, y: number, inside: boolean): CFrame
	local n = if inside then wall.inward else -wall.inward
	local p = Vector3.new(wall.pos.X, y, wall.pos.Z) + n * (wall.thick / 2)
	local axis = if wall.along == "X" then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
	p += axis * u
	local localCf = CFrame.lookAt(p, p + n)
	return ctx.cf * localCf
end

local function floorColor(ctx: Ctx, color: Color3, mat: Enum.Material)
	local floor = ctx.geo:FindFirstChild("BaseFloor") :: BasePart?
	if floor then
		floor.Color = color
		floor.Material = mat
	end
end

local function recolorWalls(ctx: Ctx, color: Color3, mat: Enum.Material)
	for _, w in ctx.geo:GetChildren() do
		if w:IsA("BasePart") and w.Name == "BaseWall" then
			w.Color = color
			w.Material = mat
		end
	end
end

-- Разметка парковки между площадками машин.
local function parkingLines(ctx: Ctx, color: Color3)
	local xs = table.clone(ctx.padXs)
	if #xs == 0 then
		return
	end
	table.sort(xs)
	local step = if #xs > 1 then xs[2] - xs[1] else 14
	for i = 0, #xs do
		local x = if i == 0 then xs[1] - step / 2 elseif i == #xs then xs[#xs] + step / 2 else (xs[i] + xs[i + 1]) / 2
		part(ctx.geo, "ParkingLine", Vector3.new(0.4, 0.03, 20), at(ctx, x, ctx.padZ, 0, 0.42), color, Enum.Material.SmoothPlastic, false, { CastShadow = false })
	end
	part(ctx.geo, "ParkingLine", Vector3.new(xs[#xs] - xs[1] + step, 0.03, 0.4), at(ctx, (xs[1] + xs[#xs]) / 2, ctx.padZ + 10, 0, 0.42), color, Enum.Material.SmoothPlastic, false, { CastShadow = false })
end

------------------------------------------------------------------------
-- Полицейский участок

local function police(ctx: Ctx)
	local white = rgb(222, 220, 212)
	local blue = rgb(30, 70, 150)
	local navy = rgb(25, 40, 80)
	floorColor(ctx, rgb(62, 64, 68), Enum.Material.Asphalt)
	recolorWalls(ctx, rgb(200, 200, 194), Enum.Material.Concrete)

	-- Главное здание: два этажа у задней стены, фасад к воротам.
	local BW, BD, BH = 64, 17, 18
	local bz = BASE_D / 2 - 1 - BD / 2 -- 32.5
	local front = bz - BD / 2 -- 24
	element(ctx, { k = "block", w = BW, d = BD, h = BH, mat = "Concrete", color = { 222, 220, 212 } }, 0, bz)

	-- Синяя полоса по фасаду и бокам, белая под крышей.
	local function band(y: number, h: number, col: Color3)
		part(ctx.geo, "PoliceBand", Vector3.new(BW + 0.4, h, 0.3), at(ctx, 0, front - 0.15, 0, y), col, Enum.Material.SmoothPlastic)
		for _, sx in { -1, 1 } do
			part(ctx.geo, "PoliceBand", Vector3.new(0.3, h, BD + 0.4), at(ctx, sx * (BW / 2 + 0.15), bz, 0, y), col, Enum.Material.SmoothPlastic)
		end
	end
	band(8.3, 1.1, blue)
	band(1.6, 0.4, blue)

	-- Решётки на окнах первого этажа (окна ставит Detailer: шаг len / n, n = (len - 3) // 7).
	local n = math.floor((BW - 3) / 7)
	for i = 1, n do
		local u = -BW / 2 + (i - 0.5) * (BW / n)
		if math.abs(u) > 7 then
			for k = -1, 1 do
				part(ctx.geo, "WindowBar", Vector3.new(0.12, 4.6, 0.12), at(ctx, u + k * 0.75, front - 0.42, 0, 3.2 + 2.25), rgb(40, 40, 44), Enum.Material.Metal)
			end
			part(ctx.geo, "WindowBar", Vector3.new(3.2, 0.12, 0.12), at(ctx, u, front - 0.42, 0, 5.4), rgb(40, 40, 44), Enum.Material.Metal)
		end
	end

	-- Вход: крыльцо со ступенями, колонны, стеклянные двери, козырёк с вывеской.
	part(ctx.geo, "Porch", Vector3.new(14, 0.8, 5), at(ctx, 0, front - 2.5, 0, 0.4), rgb(175, 172, 165), Enum.Material.Concrete, true)
	part(ctx.geo, "PorchStep", Vector3.new(10, 0.4, 1.4), at(ctx, 0, front - 5.7, 0, 0.2), rgb(175, 172, 165), Enum.Material.Concrete, true)
	for _, x in { -6.2, 6.2 } do
		Props.post(ctx.geo, "PorchColumn", at(ctx, x, front - 4.4, 0, 0.8), 7.2, 0.9, white, Enum.Material.Concrete, true)
	end
	part(ctx.geo, "EntranceGlass", Vector3.new(5.6, 6.4, 0.12), at(ctx, 0, front - 0.25, 0, 3.6), rgb(120, 160, 180), Enum.Material.Glass, false, { Transparency = 0.2, Reflectance = 0.2 })
	part(ctx.geo, "EntranceFrame", Vector3.new(0.25, 6.4, 0.16), at(ctx, 0, front - 0.33, 0, 3.6), rgb(60, 60, 64), Enum.Material.Metal)
	part(ctx.geo, "Canopy", Vector3.new(15, 0.5, 6), at(ctx, 0, front - 3, 0, 8.25), white, Enum.Material.Concrete, true)
	local fascia = part(ctx.geo, "CanopyFascia", Vector3.new(15, 1.6, 0.3), at(ctx, 0, front - 6.05, 0, 8.6), blue, Enum.Material.SmoothPlastic)
	fascia.CastShadow = false
	local txt = part(ctx.geo, "CanopyText", Vector3.new(13, 1.3, 0.05), at(ctx, 0, front - 6.24, 0, 8.6), blue, Enum.Material.SmoothPlastic, false, { Transparency = 1 })
	Props.label(txt, "ПОЛИЦИЯ", rgb(255, 255, 255), Enum.Font.GothamBlack)
	Props.sign(ctx.geo, at(ctx, 8, front - 0.3, 0, 5.5), 3.6, 1.4, "ДЕЖУРНАЯ\nЧАСТЬ", navy, rgb(255, 255, 255), Enum.Font.GothamBold)
	-- Клумбы между точками появления (они через 12 по X, в 10 и 20 от фасада).
	for _, x in { -18, 18 } do
		Props.planter(ctx.geo, at(ctx, x, front - 6), Random.new(7))
	end

	-- Вывеска на крыше, видна издалека.
	for _, x in { -9, 9 } do
		part(ctx.geo, "RoofSignPost", Vector3.new(0.4, 3, 0.4), at(ctx, x, front + 1.5, 0, BH + 1.5), rgb(60, 60, 64), Enum.Material.Metal)
	end
	local roofSign = Props.sign(ctx.geo, at(ctx, 0, front + 1.3, 0, BH + 3.6), 24, 3.2, "ОТДЕЛ ПОЛИЦИИ", blue, rgb(255, 255, 255), Enum.Font.GothamBlack)
	roofSign.Name = "RoofSign"
	-- Мачта связи и мигалка на крыше.
	Props.post(ctx.geo, "Antenna", at(ctx, -22, bz + 3, 0, BH), 12, 0.35, rgb(180, 180, 182), Enum.Material.Metal)
	for i, col in { rgb(30, 90, 255), rgb(255, 40, 40) } do
		part(ctx.geo, "RoofBeacon", Vector3.new(1.2, 0.8, 1.2), at(ctx, 22 + (i - 1.5) * 1.4, bz, 0, BH + 0.4), col, Enum.Material.Neon)
	end

	-- Флаги перед зданием.
	local flagCols = { { ctx.teamColor, rgb(255, 255, 255) }, { blue, nil }, { white, blue } }
	for i, fc in flagCols do
		Props.flag(ctx.geo, at(ctx, -30 + (i - 1) * 7, front - 2.5, 0), 16, fc[1], fc[2])
	end

	-- Прожекторы в задних углах, камеры на углах стен.
	Props.floodlight(ctx.geo, at(ctx, -50, 37, 0))
	Props.floodlight(ctx.geo, at(ctx, 50, 37, 0))
	for _, wall in walls(ctx) do
		for _, u in { -wall.len / 2 + 2, wall.len / 2 - 2 } do
			Props.camera(ctx.geo, wallFace(ctx, wall, u, wall.h - 1.2, true))
		end
		-- Металлический забор поверх стены.
		local top = ctx.cf * CFrame.new(wall.pos) * (if wall.along == "X" then CFrame.new() else yaw(90))
		part(ctx.geo, "WallFence", Vector3.new(wall.len, 3, 0.15), top * CFrame.new(0, wall.h / 2 + 2.1, 0), rgb(60, 64, 70), Enum.Material.DiamondPlate, false, { Transparency = 0.5 })
		part(ctx.geo, "WallFenceRail", Vector3.new(wall.len, 0.25, 0.25), top * CFrame.new(0, wall.h / 2 + 3.6, 0), rgb(60, 64, 70), Enum.Material.Metal)
		-- Синяя полоса по внешней стороне.
		local out = wallFace(ctx, wall, 0, 3, false)
		part(ctx.geo, "WallStripe", Vector3.new(wall.len, 0.8, 0.1), out * CFrame.new(0, 0, -0.06), blue, Enum.Material.SmoothPlastic, false, { CastShadow = false })
	end

	-- КПП у ворот снаружи: будка, поднятый шлагбаум, знаки, бетонные блоки.
	local gz = -BASE_D / 2 - 1 -- внешняя сторона передней стены
	local gx = GATE_W / 2
	local booth = at(ctx, gx + 6, gz - 4.5, 0)
	part(ctx.geo, "Booth", Vector3.new(6, 8, 6), booth * CFrame.new(0, 4, 0), white, Enum.Material.Concrete, true)
	part(ctx.geo, "BoothRoof", Vector3.new(7, 0.6, 7), booth * CFrame.new(0, 8.3, 0), blue, Enum.Material.Metal, true)
	for _, face in { CFrame.new(0, 0, -3.02), CFrame.new(-3.02, 0, 0) * yaw(90) } do
		part(ctx.geo, "BoothWindow", Vector3.new(4.2, 2.4, 0.1), booth * face * CFrame.new(0, 5, 0), rgb(110, 150, 170), Enum.Material.Glass, false, { Reflectance = 0.2 })
	end
	Props.sign(ctx.geo, booth * CFrame.new(0, 7.1, -3.15), 3, 0.9, "КПП", blue, rgb(255, 255, 255), Enum.Font.GothamBlack)
	-- Шлагбаум поднят (не мешает машинам).
	local bpost = at(ctx, gx + 2, gz - 2, 0)
	part(ctx.geo, "BarrierPost", Vector3.new(1, 3.4, 1), bpost * CFrame.new(0, 1.7, 0), rgb(240, 240, 240), Enum.Material.Metal, true)
	local arm = bpost * CFrame.new(0, 3.2, 0) * CFrame.Angles(0, 0, math.rad(80)) * CFrame.new(6, 0, 0)
	part(ctx.geo, "BarrierArm", Vector3.new(12, 0.35, 0.35), arm, rgb(240, 240, 240), Enum.Material.SmoothPlastic)
	for i = 0, 5, 2 do
		part(ctx.geo, "BarrierStripe", Vector3.new(1, 0.38, 0.38), arm * CFrame.new(-5.5 + i * 2, 0, 0), rgb(210, 40, 40), Enum.Material.SmoothPlastic)
	end
	Props.sign(ctx.geo, at(ctx, -gx - 7, gz - 0.55, 0, 6), 9, 2.2, "ВЪЕЗД ТОЛЬКО ДЛЯ\nСЛУЖЕБНОГО ТРАНСПОРТА", rgb(240, 240, 236), rgb(180, 30, 30), Enum.Font.GothamBold)
	Props.sign(ctx.geo, at(ctx, gx + 16, gz - 0.55, 0, 7.5), 10, 1.6, "ОТДЕЛ ПОЛИЦИИ", blue, rgb(255, 255, 255), Enum.Font.GothamBlack)
	for _, x in { -gx - 4, -gx - 11, -gx - 18 } do
		Props.jersey(ctx.geo, at(ctx, x, gz - 4, 0), rgb(200, 198, 190))
	end
	Props.roadSign(ctx.geo, at(ctx, -gx - 2, gz - 2, 0), "speed", Random.new(1))

	-- Боковые площадки: курилка со скамейками, урны, генератор, доска объявлений.
	local rng = Random.new(42)
	Props.bench(ctx.geo, at(ctx, 47, 12, 90))
	Props.bench(ctx.geo, at(ctx, 47, 4, 90))
	Props.bin(ctx.geo, at(ctx, 47, 8, 0), rng)
	Props.planter(ctx.geo, at(ctx, 51, 18, 0), rng)
	part(ctx.geo, "Generator", Vector3.new(4, 4, 7), at(ctx, -48, 12, 0, 2), rgb(70, 100, 70), Enum.Material.Metal, true)
	part(ctx.geo, "GeneratorVent", Vector3.new(4.1, 1.2, 2), at(ctx, -48, 12, 0, 3), rgb(40, 50, 40), Enum.Material.DiamondPlate)
	local board = Props.sign(ctx.geo, at(ctx, -48, 2, -90, 3.6), 6, 3, "ВНИМАНИЕ!\nРОЗЫСК", rgb(235, 232, 220), rgb(30, 30, 30), Enum.Font.GothamBold, true)
	board.Name = "NoticeBoard"
	for _, dx in { -2.6, 2.6 } do
		part(ctx.geo, "BoardLeg", Vector3.new(0.3, 3.6, 0.3), at(ctx, -48, 2, -90) * CFrame.new(dx, 1.8, 0.15), rgb(60, 60, 64), Enum.Material.Metal)
	end
	Props.jersey(ctx.geo, at(ctx, -48, 20, 90))

	parkingLines(ctx, rgb(235, 235, 235))
end

------------------------------------------------------------------------
-- Гетто

local function ghetto(ctx: Ctx)
	local rng = Random.new(1337)
	floorColor(ctx, rgb(78, 74, 70), Enum.Material.Asphalt)
	recolorWalls(ctx, rgb(128, 118, 106), Enum.Material.Concrete)

	-- Кирпичная трёхэтажка слева у задней стены.
	local AW, AD, AH = 48, 20, 27
	local ax, az = -29, BASE_D / 2 - 1 - AD / 2 -- центр
	local afront = az - AD / 2
	element(ctx, { k = "block", w = AW, d = AD, h = AH, mat = "Brick", color = { 125, 72, 56 } }, ax, az)

	-- Заколоченные окна (окна ставит Detailer: шаг len / n, n = (len - 3) // 7, этаж 9).
	local n = math.floor((AW - 3) / 7)
	for f = 0, 2 do
		for i = 1, n do
			local u = -AW / 2 + (i - 0.5) * (AW / n)
			if rng:NextNumber() < 0.45 and not (f == 0 and math.abs(u) < 3.5) then
				for k, ang in { 18, -14 } do
					part(ctx.geo, "Plank", Vector3.new(3.8, 0.5, 0.15), at(ctx, ax + u, afront - 0.45 - k * 0.05, 0, f * 9 + 3.2 + 2.25) * CFrame.Angles(0, 0, math.rad(ang)), rgb(150, 120, 85), Enum.Material.WoodPlanks)
				end
			end
		end
	end
	-- Пожарная лестница по фасаду: площадки на каждом этаже и марши между ними.
	local fx = ax + 12
	for f = 1, 2 do
		local y = f * 9 - 0.3
		part(ctx.geo, "FireEscape", Vector3.new(8, 0.25, 2.6), at(ctx, fx, afront - 1.4, 0, y), rgb(45, 45, 48), Enum.Material.DiamondPlate)
		part(ctx.geo, "FireEscapeRail", Vector3.new(8, 0.15, 0.15), at(ctx, fx, afront - 2.6, 0, y + 2.8), rgb(45, 45, 48), Enum.Material.Metal)
		for _, dx in { -3.9, 0, 3.9 } do
			part(ctx.geo, "FireEscapeBar", Vector3.new(0.15, 2.8, 0.15), at(ctx, fx + dx, afront - 2.6, 0, y + 1.4), rgb(45, 45, 48), Enum.Material.Metal)
		end
		if f > 1 then
			local a = (at(ctx, fx - 3.5, afront - 1.4, 0, y - 9)).Position
			local b = (at(ctx, fx + 3.5, afront - 1.4, 0, y)).Position
			Props.rod(ctx.geo, "FireEscapeStairs", a, b, 0.5, rgb(45, 45, 48), Enum.Material.Metal)
		end
	end
	-- Спутниковые тарелки и граффити на фасаде.
	for _ = 1, 3 do
		local c = at(ctx, ax + rng:NextNumber(-20, 6), afront - 0.6, 0, rng:NextInteger(1, 2) * 9 + 6.5) * CFrame.Angles(math.rad(20), math.rad(rng:NextNumber(-25, 25)), 0)
		Props.disc(ctx.geo, "SatDish", c, 2, 0.2, rgb(215, 215, 210), Enum.Material.SmoothPlastic)
	end
	Props.graffiti(ctx.geo, at(ctx, ax - 12, afront - 0.33, 0, 1.9), 9, 2.9, rng, "БАНДА")
	Props.graffiti(ctx.geo, at(ctx, ax + 10, afront - 0.33, 0, 1.9), 6, 2.9, rng)
	Props.mattress(ctx.geo, at(ctx, ax - 21, afront, 0))

	-- Мастерская из профлиста справа: ворота-роллета приоткрыты, вывеска от руки.
	local WW, WD, WH = 26, 16, 9
	local wx, wz = 24, BASE_D / 2 - 1 - WD / 2
	local wfront = wz - WD / 2
	element(ctx, { k = "block", w = WW, d = WD, h = WH, mat = "CorrodedMetal", color = { 135, 118, 98 } }, wx, wz)
	part(ctx.geo, "RollUpDoor", Vector3.new(8, 4.2, 0.2), at(ctx, wx + 7.5, wfront - 0.15, 0, 5.4), rgb(150, 150, 145), Enum.Material.CorrodedMetal)
	part(ctx.geo, "RollUpGap", Vector3.new(8, 3.3, 0.1), at(ctx, wx + 7.5, wfront - 0.08, 0, 1.65), rgb(18, 18, 18), Enum.Material.SmoothPlastic)
	Props.sign(ctx.geo, at(ctx, wx - 6, wfront - 0.3, 0, 7.6), 9, 1.6, "ШИНОМОНТАЖ", rgb(230, 225, 205), rgb(40, 40, 40), Enum.Font.PermanentMarker)
	Props.graffiti(ctx.geo, at(ctx, wx - 6, wfront - 0.33, 0, 3), 7, 2.6, rng)
	Props.flag(ctx.geo, at(ctx, wx - 10, wz, 0, WH), 10, ctx.teamColor, rgb(25, 25, 25))
	Props.tires(ctx.geo, at(ctx, wx - 13 + 1, wfront - 3), rng)
	Props.tires(ctx.geo, at(ctx, wx + 13 - 1.5, wfront - 2.5), rng)

	-- Баскетбольная площадка в правом заднем углу за сеткой.
	local cx0, cx1, cz0, cz1 = 40, 54, 14, 41
	part(ctx.geo, "Court", Vector3.new(cx1 - cx0, 0.05, cz1 - cz0), at(ctx, (cx0 + cx1) / 2, (cz0 + cz1) / 2, 0, 0.43), rgb(150, 70, 55), Enum.Material.Concrete, false, { CastShadow = false })
	part(ctx.geo, "CourtLine", Vector3.new(cx1 - cx0 - 1, 0.06, 0.3), at(ctx, (cx0 + cx1) / 2, 30, 0, 0.44), rgb(230, 230, 225), Enum.Material.SmoothPlastic, false, { CastShadow = false })
	Props.hoop(ctx.geo, at(ctx, (cx0 + cx1) / 2, cz1 - 1, 0))
	local function lp(x: number, z: number): Vector3
		return ctx.cf:PointToWorldSpace(Vector3.new(x, 0.4, z))
	end
	Props.chainLink(ctx.geo, lp(cx0, cz1 - 1), lp(cx0, cz0), 7)
	Props.chainLink(ctx.geo, lp(cx0, cz0), lp(cx0 + 6, cz0), 7)

	-- Бельевые верёвки перед трёхэтажкой.
	for _, x in { ax - 20, ax - 6 } do
		Props.post(ctx.geo, "LinePost", at(ctx, x, afront - 3.5), 7.5, 0.3, rgb(80, 80, 80), Enum.Material.Metal)
	end
	Props.clothesline(ctx.geo, (at(ctx, ax - 20, afront - 3.5, 0, 7.3)).Position, (at(ctx, ax - 6, afront - 3.5, 0, 7.3)).Position, rng)

	-- Бочки с огнём, диван, мусор, сгоревшая машина, поддоны.
	Props.fireBarrel(ctx.geo, at(ctx, -6, 19))
	Props.fireBarrel(ctx.geo, at(ctx, -46, -8))
	Props.fireBarrel(ctx.geo, at(ctx, 46, 6))
	Props.couch(ctx.geo, at(ctx, -48, 14, -90), rng)
	Props.trashbags(ctx.geo, at(ctx, -30, afront - 2), rng)
	Props.trashbags(ctx.geo, at(ctx, 8, wfront - 2.5), rng)
	Props.dumpster(ctx.geo, at(ctx, 49, -4, -90), rng)
	Props.trashbags(ctx.geo, at(ctx, 49, 1), rng)
	Props.wreck(ctx.geo, at(ctx, -48, 2, 0), rng)
	Props.pallets(ctx.geo, at(ctx, 48, 11), rng)
	Props.bench(ctx.geo, at(ctx, 47, 17, 0))

	-- Сломанный фонарь, накренился.
	local lamp = at(ctx, 5, 20) * CFrame.Angles(math.rad(8), 0, math.rad(5))
	Props.post(ctx.geo, "BrokenLamp", lamp, 13, 0.6, rgb(70, 74, 78), Enum.Material.Metal, true)
	part(ctx.geo, "BrokenLampHead", Vector3.new(1.1, 0.45, 2.2), lamp * CFrame.new(0, 13, -1), rgb(70, 74, 78), Enum.Material.Metal)

	-- Стены: колючка поверху, заплатки из профлиста, граффити внутри и снаружи.
	for _, wall in walls(ctx) do
		local top = ctx.cf * CFrame.new(wall.pos) * (if wall.along == "X" then CFrame.new() else yaw(90))
		Props.razorWire(ctx.geo, top * CFrame.new(0, wall.h / 2 + 0.35, 0), wall.len - 1)
		for _ = 1, math.max(1, math.floor(wall.len / 30)) do
			local inside = rng:NextNumber() < 0.5
			local sw = rng:NextNumber(5, 9)
			local u = rng:NextNumber(-wall.len / 2 + sw / 2 + 1, wall.len / 2 - sw / 2 - 1)
			local f = wallFace(ctx, wall, u, rng:NextNumber(4, 8), inside)
			part(ctx.geo, "MetalSheet", Vector3.new(sw, rng:NextNumber(4, 7), 0.15), f * CFrame.new(0, 0, -0.5) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-4, 4))), Props.pick({ rgb(130, 85, 55), rgb(110, 115, 118), rgb(95, 110, 95) }, rng), Enum.Material.CorrodedMetal)
		end
		for _, inside in { true, false } do
			if rng:NextNumber() < 0.75 and wall.len > 14 then
				local gw = math.min(wall.len - 6, rng:NextNumber(7, 12))
				local u = rng:NextNumber(-wall.len / 2 + gw / 2 + 2, wall.len / 2 - gw / 2 - 2)
				Props.graffiti(ctx.geo, wallFace(ctx, wall, u, 2.5, inside) * CFrame.new(0, 0, -0.45), gw, 3.6, rng)
			end
		end
	end

	-- Снаружи у ворот: баррикады из покрышек и поддонов по краям проезда, надпись на стене.
	local gz = -BASE_D / 2 - 1
	local gx = GATE_W / 2
	for _, sx in { -1, 1 } do
		Props.tires(ctx.geo, at(ctx, sx * (gx + 3), gz - 3), rng)
		Props.pallets(ctx.geo, at(ctx, sx * (gx + 7), gz - 3.5), rng)
		Props.fireBarrel(ctx.geo, at(ctx, sx * (gx + 11), gz - 3))
	end
	Props.graffiti(ctx.geo, at(ctx, -gx - 16, gz - 0.5, 0, 5), 18, 5, rng, "ЗДЕСЬ НАШ РАЙОН")

	parkingLines(ctx, rgb(200, 180, 90):Lerp(rgb(78, 74, 70), 0.35))
end

------------------------------------------------------------------------

local STYLES = { Police = police, Ghetto = ghetto }

-- true, если стиль применён (тогда MapBuilder не ставит обычный флаг).
function BaseStyles.build(style: string?, ctx: Ctx): boolean
	local fn = style and STYLES[style]
	if not fn then
		return false
	end
	local ok, err = pcall(fn, ctx)
	if not ok then
		warn("[BaseStyles] Оформление базы (" .. tostring(style) .. "):", err)
	end
	return true
end

BaseStyles.BASE_W, BaseStyles.BASE_D = BASE_W, BASE_D

return BaseStyles
