-- Реалистичная графика на сервере: то, что должно быть одинаковым у всех игроков.
--   * Земля из Terrain вместо большой детали (трава, тёплый свет от земли, мягкие переходы).
--   * Фонари вдоль дорог и свет внутри зданий.
--   * Фары машин светят по-настоящему (SpotLight).
-- Работает после того, как MapBuilder собрал карту. Карты, сделанные руками в Studio
-- (папка Workspace.Map без атрибута MapId), не трогаются.
-- Свет помечается тегом RealismLight: клиент гасит его, если игрок выключил реалистичную графику.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Graphics)
local MapsConfig = require(Shared.Config.Maps)

local LIGHT_TAG = "RealismLight"

local Realism = {}

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	if inst:IsA("BasePart") then
		inst.Anchored = true
		inst.TopSurface = Enum.SurfaceType.Smooth
		inst.BottomSurface = Enum.SurfaceType.Smooth
	end
	inst.Parent = parent
	return inst
end

local function tagLight(light: Light, on: boolean)
	light:SetAttribute("LampOn", on)
	light.Enabled = on
	CollectionService:AddTag(light, LIGHT_TAG)
end

-- Поворот детали только вокруг вертикали (для отпечатка на земле).
local function flatten(cf: CFrame): CFrame
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	local p = cf.Position
	return CFrame.lookAt(Vector3.new(p.X, 0, p.Z), Vector3.new(p.X, 0, p.Z) + flat.Unit)
end

------------------------------------------------------------------------
-- Земля

local TERRAIN_MATERIALS = {
	[Enum.Material.Grass] = true,
	[Enum.Material.Concrete] = true,
	[Enum.Material.Asphalt] = true,
	[Enum.Material.Sand] = true,
	[Enum.Material.Ground] = true,
	[Enum.Material.Pavement] = true,
	[Enum.Material.Mud] = true,
}

local function buildTerrain(geo: Instance, mapCfg)
	local groundPart = geo:FindFirstChild("Ground")
	local mat = mapCfg.Ground.Material
	if not groundPart or not TERRAIN_MATERIALS[mat] then
		return
	end
	local terrain = workspace.Terrain
	local S = mapCfg.Size
	terrain:Clear()
	pcall(function()
		terrain.Decoration = Config.GrassDecoration
	end)
	terrain:SetMaterialColor(mat, mapCfg.Ground.Color)
	-- Верх земли ровно на y = 0, как у прежней детали.
	terrain:FillBlock(CFrame.new(0, -4, 0), Vector3.new(S, 8, S), mat)

	-- На траве травинки пробивались бы сквозь дороги и полы: под ними кладём землю или асфальт.
	if mat == Enum.Material.Grass then
		for _, part in geo:GetDescendants() do
			if part:IsA("BasePart") and part ~= groundPart and part.Transparency < 1 then
				local bottom = part.Position.Y - part.Size.Y / 2
				if bottom < 0.6 and part.Size.X * part.Size.Z >= 4 then
					local under = if part.Name == "Road" then Enum.Material.Asphalt else Enum.Material.Ground
					terrain:FillBlock(flatten(part.CFrame) * CFrame.new(0, -2, 0), Vector3.new(part.Size.X + 1, 4, part.Size.Z + 1), under)
				end
			end
		end
	end

	groundPart:Destroy()
end

------------------------------------------------------------------------
-- Фонари вдоль дорог

local function insideOtherRoad(pos: Vector3, road: BasePart, roads: { BasePart }): boolean
	for _, other in roads do
		if other ~= road then
			local p = other.CFrame:PointToObjectSpace(pos)
			if math.abs(p.X) < other.Size.X / 2 + 2 and math.abs(p.Z) < other.Size.Z / 2 + 2 then
				return true
			end
		end
	end
	return false
end

local function lamp(geo: Instance, base: CFrame, lampsOn: boolean)
	local cfg = Config.StreetLamps
	local H = cfg.Height
	local dark = Color3.fromRGB(45, 47, 50)
	local model = make("Model", { Name = "StreetLamp" }, geo)
	make("Part", { Name = "Pole", Size = Vector3.new(0.5, H, 0.5), CFrame = base * CFrame.new(0, H / 2, 0), Color = dark, Material = Enum.Material.Metal }, model)
	-- Кронштейн тянется к дороге (по -X локально).
	make("Part", { Name = "Arm", Size = Vector3.new(3.5, 0.3, 0.3), CFrame = base * CFrame.new(-1.6, H - 0.2, 0), Color = dark, Material = Enum.Material.Metal, CanCollide = false }, model)
	local head = make("Part", {
		Name = "LampHead",
		Size = Vector3.new(1.6, 0.35, 0.9),
		CFrame = base * CFrame.new(-3.1, H - 0.4, 0),
		Color = if lampsOn then cfg.Color else Color3.fromRGB(200, 200, 195),
		Material = if lampsOn then Enum.Material.Neon else Enum.Material.Glass,
		CanCollide = false,
		CanQuery = false,
	}, model)
	local light = make("SpotLight", {
		Face = Enum.NormalId.Bottom,
		Angle = 110,
		Brightness = cfg.Brightness,
		Range = cfg.Range,
		Color = cfg.Color,
		Shadows = false,
	}, head)
	tagLight(light, lampsOn)
end

local function buildLamps(geo: Instance, lampsOn: boolean)
	local cfg = Config.StreetLamps
	local roads: { BasePart } = {}
	for _, part in geo:GetChildren() do
		if part:IsA("BasePart") and part.Name == "Road" then
			table.insert(roads, part)
		end
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { geo }

	for _, road in roads do
		local halfW = road.Size.X / 2
		local halfLen = road.Size.Z / 2 - halfW -- длина без скруглений на концах
		local n = math.floor(halfLen * 2 / cfg.Spacing)
		for i = 0, n do
			local z = -halfLen + i * cfg.Spacing
			local side = if i % 2 == 0 then 1 else -1 -- фонари в шахматном порядке
			local pos = road.CFrame:PointToWorldSpace(Vector3.new(side * (halfW + 1.5), 0, z))
			pos = Vector3.new(pos.X, 0, pos.Z)
			if not insideOtherRoad(pos, road, roads) then
				local hits = workspace:GetPartBoundsInBox(CFrame.new(pos + Vector3.new(0, cfg.Height / 2 + 0.5, 0)), Vector3.new(3, cfg.Height - 1, 3), overlap)
				if #hits == 0 then
					-- Локальная ось -X кронштейна смотрит на дорогу.
					local across = road.CFrame.RightVector * -side
					local flatAcross = Vector3.new(across.X, 0, across.Z).Unit
					lamp(geo, CFrame.fromMatrix(pos, -flatAcross, Vector3.yAxis), lampsOn)
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Свет в зданиях

local function buildInteriorLights(geo: Instance)
	local cfg = Config.InteriorLights
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { geo }
	for _, floor in geo:GetChildren() do
		if floor:IsA("BasePart") and floor.Name == "Floor" then
			local origin = floor.Position + Vector3.new(0, floor.Size.Y / 2 + 0.5, 0)
			local hit = workspace:Raycast(origin, Vector3.new(0, 60, 0), params)
			if hit and hit.Instance.Name == "Roof" then
				local y = hit.Position.Y - 0.15
				local fixture = make("Part", {
					Name = "CeilingLamp",
					Size = Vector3.new(2, 0.2, 2),
					CFrame = CFrame.new(floor.Position.X, y, floor.Position.Z),
					Color = cfg.Color,
					Material = Enum.Material.Neon,
					CanCollide = false,
					CanQuery = false,
					CanTouch = false,
				}, geo)
				local light = make("PointLight", {
					Brightness = cfg.Brightness,
					Range = math.min(60, math.max(cfg.Range, math.max(floor.Size.X, floor.Size.Z) * 0.75)),
					Color = cfg.Color,
					Shadows = true,
				}, fixture)
				tagLight(light, true)
			end
		end
	end
end

------------------------------------------------------------------------
-- Фары

local function addHeadlight(part: Instance)
	if not part:IsA("BasePart") or part.Name ~= "Headlight" or part:FindFirstChildOfClass("SpotLight") then
		return
	end
	local cfg = Config.Headlights
	local light = make("SpotLight", {
		Face = Enum.NormalId.Front,
		Angle = cfg.Angle,
		Brightness = cfg.Brightness,
		Range = cfg.Range,
		Color = cfg.Color,
		Shadows = true,
	}, part)
	tagLight(light, true)
end

------------------------------------------------------------------------

local function onMap(map: Instance)
	local mapId = map:GetAttribute("MapId")
	local mapCfg = mapId and MapsConfig.List[mapId]
	local geo = map:FindFirstChild("Geometry")
	if not mapCfg or not geo or map:GetAttribute("RealismDone") then
		return
	end
	map:SetAttribute("RealismDone", true)
	local mood = Config.Moods[mapId] or Config.Moods.Default
	local t = os.clock()
	-- Каждый шаг в pcall: если что-то пойдёт не так, игра просто останется без украшения.
	if Config.TerrainGround then
		local ok, err = pcall(buildTerrain, geo, mapCfg)
		if not ok then
			warn("[Realism] Terrain:", err)
		end
	end
	if Config.StreetLamps.Enabled then
		local ok, err = pcall(buildLamps, geo, mood.LampsOn == true)
		if not ok then
			warn("[Realism] Фонари:", err)
		end
	end
	if Config.InteriorLights.Enabled then
		local ok, err = pcall(buildInteriorLights, geo)
		if not ok then
			warn("[Realism] Свет в зданиях:", err)
		end
	end
	print(string.format("[Realism] Графика карты готова за %.2f с", os.clock() - t))
end

function Realism.init(mapChanged: RBXScriptSignal)
	mapChanged:Connect(onMap)
	local existing = workspace:FindFirstChild("Map")
	if existing then
		task.spawn(onMap, existing)
	end
	for _, inst in workspace:GetDescendants() do
		addHeadlight(inst)
	end
	workspace.DescendantAdded:Connect(addHeadlight)
end

return Realism
