-- Реалистичная графика на сервере (то, что не делает Detailer):
--   * земля из Terrain вместо большой детали Ground: трава шевелится, лучше свет;
--   * свет под потолком в зданиях с интерьером.
-- Работает после сборки карты (MapService.Changed). Карты, сделанные руками в Studio
-- (Workspace.Map без атрибута MapId), не трогаются.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Graphics)

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
	print(string.format("[Realism] Земля и свет готовы за %.2f с", os.clock() - t))
end

function Realism.init(mapChanged: RBXScriptSignal)
	mapChanged:Connect(onMap)
	local existing = workspace:FindFirstChild("Map")
	if existing then
		task.spawn(onMap, existing)
	end
end

return Realism
