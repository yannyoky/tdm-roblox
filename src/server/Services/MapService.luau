-- Карта. Ожидаемая структура в Workspace (её можно построить в Studio):
--   Map/
--     Spawns/Bandits, Spawns/Gov, Spawns/Lobby  -- детали-точки появления
--     CapturePoints/                             -- плоские детали-зоны для капта
-- Если Map нет, строим простую тестовую арену, чтобы игра запускалась сразу.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = require(ReplicatedStorage:WaitForChild("Shared").Config.Teams)

local MapService = {}

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Concrete
	p.Color = Color3.fromRGB(150, 150, 150)
	if props then
		for key, value in props do
			(p :: any)[key] = value
		end
	end
	p.Parent = parent
	return p
end

-- Невидимая для пуль точка появления.
local function marker(parent: Instance, name: string, position: Vector3, color: Color3)
	return part(parent, name, Vector3.new(6, 0.4, 6), CFrame.new(position), {
		Color = color,
		Transparency = 0.6,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Material = Enum.Material.Neon,
	})
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function build(): Folder
	warn("[MapService] Workspace.Map не найден, строю тестовую арену")
	local map = Instance.new("Folder")
	map.Name = "Map"
	local geo = folder(map, "Geometry")

	local W, D, H = 240, 160, 20
	part(geo, "Floor", Vector3.new(W, 2, D), CFrame.new(0, -1, 0), { Color = Color3.fromRGB(90, 95, 100) })
	part(geo, "Wall", Vector3.new(W, H, 2), CFrame.new(0, H / 2, D / 2 + 1))
	part(geo, "Wall", Vector3.new(W, H, 2), CFrame.new(0, H / 2, -D / 2 - 1))
	part(geo, "Wall", Vector3.new(2, H, D), CFrame.new(W / 2 + 1, H / 2, 0))
	part(geo, "Wall", Vector3.new(2, H, D), CFrame.new(-W / 2 - 1, H / 2, 0))

	-- Укрытия, симметрично для обеих сторон.
	local covers = {
		{ Vector3.new(12, 8, 4), Vector3.new(40, 4, 30) },
		{ Vector3.new(12, 8, 4), Vector3.new(40, 4, -30) },
		{ Vector3.new(4, 6, 16), Vector3.new(70, 3, 0) },
		{ Vector3.new(8, 4, 8), Vector3.new(85, 2, 50) },
		{ Vector3.new(8, 4, 8), Vector3.new(85, 2, -50) },
		{ Vector3.new(2, 6, 14), Vector3.new(18, 3, 0) },
		{ Vector3.new(20, 10, 4), Vector3.new(20, 5, 55) },
		{ Vector3.new(20, 10, 4), Vector3.new(20, 5, -55) },
	}
	for _, c in covers do
		local size, pos = c[1], c[2]
		part(geo, "Cover", size, CFrame.new(pos), { Color = Color3.fromRGB(120, 110, 100) })
		part(geo, "Cover", size, CFrame.new(-pos.X, pos.Y, -pos.Z), { Color = Color3.fromRGB(120, 110, 100) })
	end
	-- Центральные укрытия у точки захвата.
	part(geo, "Cover", Vector3.new(6, 4, 2), CFrame.new(0, 2, 18), { Color = Color3.fromRGB(110, 100, 90) })
	part(geo, "Cover", Vector3.new(6, 4, 2), CFrame.new(0, 2, -18), { Color = Color3.fromRGB(110, 100, 90) })

	-- Точки появления команд.
	local spawns = folder(map, "Spawns")
	local teamA, teamB = Teams.Order[1], Teams.Order[2]
	local spawnA = folder(spawns, teamA)
	local spawnB = folder(spawns, teamB)
	for i, z in { -30, -10, 10, 30 } do
		marker(spawnA, "Spawn" .. i, Vector3.new(-105, 0.2, z), Teams.List[teamA].Color)
		marker(spawnB, "Spawn" .. i, Vector3.new(105, 0.2, z), Teams.List[teamB].Color)
	end

	-- Лобби: площадка над ареной, оттуда видно бой.
	local lobbyY = 80
	part(geo, "LobbyFloor", Vector3.new(40, 2, 40), CFrame.new(0, lobbyY - 1, 0), { Color = Color3.fromRGB(70, 70, 80) })
	part(geo, "LobbyRail", Vector3.new(40, 6, 1), CFrame.new(0, lobbyY + 3, 20))
	part(geo, "LobbyRail", Vector3.new(40, 6, 1), CFrame.new(0, lobbyY + 3, -20))
	part(geo, "LobbyRail", Vector3.new(1, 6, 40), CFrame.new(20, lobbyY + 3, 0))
	part(geo, "LobbyRail", Vector3.new(1, 6, 40), CFrame.new(-20, lobbyY + 3, 0))
	local lobby = folder(spawns, "Lobby")
	for i, offset in { Vector3.new(-8, 0, -8), Vector3.new(8, 0, -8), Vector3.new(-8, 0, 8), Vector3.new(8, 0, 8) } do
		marker(lobby, "Spawn" .. i, Vector3.new(0, lobbyY + 0.2, 0) + offset, Color3.fromRGB(230, 230, 230))
	end

	-- Точка захвата в центре.
	local points = folder(map, "CapturePoints")
	part(points, "Район А", Vector3.new(24, 1, 24), CFrame.new(0, 0.5, 0), {
		Transparency = 0.6,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(240, 240, 240),
	})

	map.Parent = workspace
	return map
end

function MapService.get(): Folder
	local map = workspace:FindFirstChild("Map")
	if map then
		return map :: Folder
	end
	return build()
end

return MapService
