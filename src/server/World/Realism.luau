-- Реалистичная графика на сервере (то, что не делает Detailer):
--   * приглушённые цвета карты (Desaturate);
--   * высотки за краем карты (Skyline);
--   * земля из Terrain вместо большой детали Ground (сейчас выключено, см. Config/Graphics);
--   * свет под потолком в зданиях с интерьером.
-- Работает после сборки карты (MapService.Changed). Карты, сделанные руками в Studio
-- (Workspace.Map без атрибута MapId), не трогаются.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Graphics)
local MapsConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.Maps)

local Realism = {}

local TERRAIN_MATERIALS = {
	[Enum.Material.Grass] = true,
	[Enum.Material.Concrete] = true,
	[Enum.Material.Asphalt] = true,
	[Enum.Material.Sand] = true,
	[Enum.Material.Ground] = true,
	[Enum.Material.Pavement] = true,
	[Enum.Material.Mud] = true,
	[Enum.Material.LeafyGrass] = true,
}

-- Поворот детали только вокруг вертикали (для отпечатка на земле).
local function flatten(cf: CFrame): CFrame
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	local p = Vector3.new(cf.Position.X, 0, cf.Position.Z)
	return CFrame.lookAt(p, p + flat.Unit)
end

------------------------------------------------------------------------
-- Земля

local function buildTerrain(geo: Instance)
	local ground = geo:FindFirstChild("Ground")
	if not ground or not ground:IsA("BasePart") or not TERRAIN_MATERIALS[ground.Material] then
		return
	end
	local terrain = workspace.Terrain
	local mat = ground.Material
	pcall(function()
		terrain.Decoration = Config.GrassDecoration
	end)
	terrain:SetMaterialColor(mat, ground.Color)
	-- Только слой y = -8..0: холмы карты (они выше нуля) остаются как есть.
	terrain:FillBlock(CFrame.new(ground.Position.X, -4, ground.Position.Z), Vector3.new(ground.Size.X, 8, ground.Size.Z), mat)

	-- На траве травинки пробивались бы сквозь дороги, тротуары и полы: под ними кладём землю/асфальт.
	if mat == Enum.Material.Grass or mat == Enum.Material.LeafyGrass then
		for _, part in geo:GetDescendants() do
			if part:IsA("BasePart") and part ~= ground and part.Transparency < 1 and part.Name ~= "Patch" then
				local bottom = part.Position.Y - part.Size.Y / 2
				if bottom < 0.6 and bottom > -1 and part.Size.X * part.Size.Z >= 4 then
					local under = if part.Name == "Road" then Enum.Material.Asphalt else Enum.Material.Ground
					terrain:FillBlock(flatten(part.CFrame) * CFrame.new(0, -2, 0), Vector3.new(part.Size.X + 1, 4, part.Size.Z + 1), under)
				end
			end
		end
	end
	ground:Destroy()
end

------------------------------------------------------------------------
-- Приглушённые цвета

local KEEP_MATERIALS = {
	[Enum.Material.Neon] = true,
	[Enum.Material.Glass] = true,
	[Enum.Material.ForceField] = true,
}

local function desaturate(geo: Instance, amount: number)
	for _, part in geo:GetDescendants() do
		if part:IsA("BasePart") and not KEEP_MATERIALS[part.Material] and part.Transparency < 1
			and not part.Name:find("Flag") and not part:FindFirstChildOfClass("SurfaceAppearance") then
			local c = part.Color
			local l = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
			part.Color = c:Lerp(Color3.new(l, l, l), amount)
		end
	end
end

------------------------------------------------------------------------
-- Высотки за краем карты

local function skylineTower(out: Instance, cf: CFrame, w: number, d: number, h: number, rng: Random, center: Vector3)
	local cfg = Config.Skyline
	local color = cfg.Colors[rng:NextInteger(1, #cfg.Colors)]
	local function part(name: string, size: Vector3, at: CFrame, col: Color3, mat: Enum.Material, shadow: boolean)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = shadow
		p.Size = size
		p.CFrame = at
		p.Color = col
		p.Material = mat
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = out
		return p
	end
	part("Tower", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), color, Enum.Material.Concrete, true)
	part("TowerRoof", Vector3.new(w + 0.8, 1.2, d + 0.8), cf * CFrame.new(0, h + 0.6, 0), color:Lerp(Color3.new(1, 1, 1), 0.15), Enum.Material.Concrete, false)
	if rng:NextNumber() < 0.6 then
		part("TowerTech", Vector3.new(w * 0.35, 4, d * 0.35), cf * CFrame.new(rng:NextNumber(-w / 5, w / 5), h + 3.2, rng:NextNumber(-d / 5, d / 5)), Color3.fromRGB(110, 112, 115), Enum.Material.Metal, false)
	end
	-- Ленточные окна на сторонах, которые видно с карты.
	local floors = math.floor((h - 4) / cfg.FloorHeight)
	for _, face in {
		{ CFrame.new(0, 0, -d / 2), w },
		{ CFrame.new(0, 0, d / 2) * CFrame.Angles(0, math.pi, 0), w },
		{ CFrame.new(w / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), d },
		{ CFrame.new(-w / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), d },
	} do
		local fcf = cf * face[1]
		local outward = -fcf.LookVector
		local toCenter = (center - fcf.Position) * Vector3.new(1, 0, 1)
		if toCenter.Magnitude > 0 and outward:Dot(toCenter.Unit) > -0.2 then
			for f = 0, floors - 1 do
				local y = 4 + f * cfg.FloorHeight + 2.2
				part("TowerWindows", Vector3.new(face[2] - 2, 3.2, 0.2), fcf * CFrame.new(0, y, -0.1), cfg.Glass, Enum.Material.Glass, false).Reflectance = 0.15
			end
			-- Первый этаж: витрины.
			part("TowerShopfront", Vector3.new(face[2] - 3, 3, 0.2), fcf * CFrame.new(0, 2, -0.1), Color3.fromRGB(70, 74, 80), Enum.Material.Glass, false)
		end
	end
end

local function buildSkyline(geo: Instance, mapId: string)
	local cfg = Config.Skyline
	local mapCfg = MapsConfig.List[mapId]
	if not mapCfg then
		return
	end
	local S = mapCfg.Size
	local rng = Random.new(#mapId * 131 + 7)
	local out = Instance.new("Model")
	out.Name = "Skyline"
	local center = Vector3.zero
	-- Земля под горизонтом (чуть ниже земли карты, чтобы не мерцать с ней).
	local far = S + 2 * (cfg.Distance[2] + 120)
	local floor = Instance.new("Part")
	floor.Name = "SkylineGround"
	floor.Anchored = true
	floor.CanCollide = false
	floor.CanQuery = false
	floor.CanTouch = false
	floor.Size = Vector3.new(far, 1, far)
	floor.CFrame = CFrame.new(0, -0.65, 0)
	floor.Color = Color3.fromRGB(88, 90, 94)
	floor.Material = Enum.Material.Asphalt
	floor.Parent = out
	for row = 1, cfg.Rows do
		local t = (row - 1) / math.max(1, cfg.Rows - 1)
		local dist = cfg.Distance[1] + (cfg.Distance[2] - cfg.Distance[1]) * t
		local edge = S / 2 + dist
		local spacing = cfg.Spacing * (1 + (row - 1) * 0.6)
		for side = 0, 3 do
			local rot = CFrame.Angles(0, side * math.pi / 2, 0)
			local u = -edge
			while u <= edge do
				local w, d = rng:NextNumber(24, 44), rng:NextNumber(22, 40)
				-- Дальний ряд выше, чтобы выглядывал из-за ближнего.
				local h = rng:NextNumber(cfg.Height[1], cfg.Height[2]) * (1 + (row - 1) * 0.3)
				local pos = rot * Vector3.new(u + rng:NextNumber(-6, 6), 0, -(edge + d / 2 + rng:NextNumber(0, 15)))
				skylineTower(out, CFrame.new(pos) * rot * CFrame.Angles(0, math.rad(rng:NextNumber(-4, 4)), 0), w, d, h, rng, center)
				u += spacing + rng:NextNumber(-8, 8)
			end
		end
	end
	out.Parent = geo
end

------------------------------------------------------------------------
-- Свет в зданиях

local function buildInteriorLights(geo: Instance)
	local cfg = Config.InteriorLights
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { geo }
	for _, floor in geo:GetDescendants() do
		if floor:IsA("BasePart") and floor.Name == "Floor" then
			local origin = floor.Position + Vector3.new(0, floor.Size.Y / 2 + 0.5, 0)
			local hit = workspace:Raycast(origin, Vector3.new(0, 60, 0), params)
			if hit and hit.Instance.Name == "Roof" then
				local fixture = Instance.new("Part")
				fixture.Name = "CeilingLamp"
				fixture.Anchored = true
				fixture.Size = Vector3.new(2, 0.2, 2)
				fixture.CFrame = CFrame.new(floor.Position.X, hit.Position.Y - 0.15, floor.Position.Z)
				fixture.Color = cfg.Color
				fixture.Material = Enum.Material.Neon
				fixture.CanCollide = false
				fixture.CanQuery = false
				fixture.CanTouch = false
				local light = Instance.new("PointLight")
				light.Brightness = cfg.Brightness
				light.Range = math.min(60, math.max(cfg.Range, math.max(floor.Size.X, floor.Size.Z) * 0.75))
				light.Color = cfg.Color
				light.Shadows = true
				light.Parent = fixture
				fixture.Parent = geo
			end
		end
	end
end

------------------------------------------------------------------------

local function onMap(map: Instance)
	local geo = map:FindFirstChild("Geometry")
	if not map:GetAttribute("MapId") or not geo or map:GetAttribute("RealismDone") then
		return
	end
	map:SetAttribute("RealismDone", true)
	local t = os.clock()
	if (Config.Desaturate or 0) > 0 then
		local ok, err = pcall(desaturate, geo, Config.Desaturate)
		if not ok then
			warn("[Realism] Цвета:", err)
		end
	end
	if Config.Skyline and Config.Skyline.Enabled then
		local ok, err = pcall(buildSkyline, geo, map:GetAttribute("MapId"))
		if not ok then
			warn("[Realism] Высотки:", err)
		end
	end
	if Config.TerrainGround then
		local ok, err = pcall(buildTerrain, geo)
		if not ok then
			warn("[Realism] Terrain:", err)
		end
	end
	if Config.InteriorLights.Enabled then
		local ok, err = pcall(buildInteriorLights, geo)
		if not ok then
			warn("[Realism] Свет в зданиях:", err)
		end
	end
	print(string.format("[Realism] Цвета, горизонт и свет готовы за %.2f с", os.clock() - t))
end

function Realism.init(mapChanged: RBXScriptSignal)
	mapChanged:Connect(onMap)
	local existing = workspace:FindFirstChild("Map")
	if existing then
		task.spawn(onMap, existing)
	end
end

return Realism
