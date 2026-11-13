-- Карты и их ротация. Карты собираются кодом из Config/Maps (см. src/server/World/MapBuilder).
-- Структура Workspace.Map, которую читают MatchService и режимы:
--   Map/Spawns/<Team>           -- база команды на краю карты (капт: появляемся здесь и едем в зону)
--   Map/Spawns/<Team>_Forward   -- передовая точка ближе к центру (TDM: быстрее в бой)
--   Map/Spawns/Lobby
--   Map/CapturePoints/<Parts>   -- зоны капта
--   Map/Bases/<Team>            -- объём базы: чужим здесь наносится урон
--   Map/VehiclePads/<Team>/...  -- площадки автопарка
-- Если карту положили в Workspace.Map руками в Studio, ротация выключается и используется она.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapsConfig = require(Shared.Config.Maps)
local MapBuilder = require(script.Parent.Parent:WaitForChild("World"):WaitForChild("MapBuilder"))

local ENEMY_BASE_DPS = 25 -- урон в секунду чужаку на базе

local MapService = {}

local changed = Instance.new("BindableEvent")
-- Сигнал смены карты: MapService.Changed:Connect(function(map: Folder) ... end)
MapService.Changed = changed.Event

local current: Folder? = nil
local handmade = false
local index = 0
local fresh = false -- карта только что собрана и ещё не сыграна

local function setCurrent(map: Folder)
	current = map
	map.Parent = workspace
	ReplicatedStorage:SetAttribute("MapName", map:GetAttribute("MapName") or map.Name)
	ReplicatedStorage:SetAttribute("MapId", map:GetAttribute("MapId") or "")
	changed:Fire(map)
end

local function load(mapId: string): Folder
	if current then
		current:Destroy()
		current = nil
	end
	local t = os.clock()
	local map = MapBuilder.build(mapId)
	print(string.format("[MapService] Карта «%s» собрана за %.2f с", MapsConfig.List[mapId].Name, os.clock() - t))
	setCurrent(map)
	return map
end

-- Текущая карта (при первом вызове собирает первую карту из ротации).
function MapService.get(): Folder
	if current then
		return current
	end
	MapBuilder.ensureLobby()
	local existing = workspace:FindFirstChild("Map")
	if existing then
		handmade = true
		setCurrent(existing :: Folder)
		return existing :: Folder
	end
	index = 1
	fresh = true
	return load(MapsConfig.Order[index])
end

-- Следующая карта по кругу. Вызывается перед каждым матчем.
function MapService.nextMap(): Folder
	if handmade or #MapsConfig.Order <= 1 or fresh then
		fresh = false
		return MapService.get()
	end
	index = index % #MapsConfig.Order + 1
	return load(MapsConfig.Order[index])
end

-- Собрать конкретную карту (для голосования за карту и тестов).
function MapService.load(mapId: string): Folder
	MapBuilder.ensureLobby()
	local i = table.find(MapsConfig.Order, mapId)
	if i then
		index = i
	end
	return load(mapId)
end

-- Папка точек появления для команды в зависимости от режима:
-- режим с SpawnAtBase (капт) — база, иначе передовая точка, если она есть.
function MapService.spawnFolder(teamKey: string, modeDef): string
	if modeDef and not modeDef.SpawnAtBase and current then
		local spawns = current:FindFirstChild("Spawns")
		if spawns and spawns:FindFirstChild(teamKey .. "_Forward") then
			return teamKey .. "_Forward"
		end
	end
	return teamKey
end

-- Находится ли точка внутри базы команды.
function MapService.isInBase(position: Vector3, teamKey: string): boolean
	local bases = current and current:FindFirstChild("Bases")
	local volume = bases and bases:FindFirstChild(teamKey) :: BasePart?
	if not volume then
		return false
	end
	local rel = volume.CFrame:PointToObjectSpace(position)
	local s = volume.Size
	return math.abs(rel.X) <= s.X / 2 and math.abs(rel.Y) <= s.Y / 2 and math.abs(rel.Z) <= s.Z / 2
end

-- Защита баз: чужак на базе получает урон и предупреждение (атрибут InEnemyBase для HUD).
local function guardBases()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 or not current then
			return
		end
		local step = acc
		acc = 0
		local bases = current:FindFirstChild("Bases")
		if not bases then
			return
		end
		for _, player in Players:GetPlayers() do
			local team = player.Team and player.Team:GetAttribute("Key")
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local inEnemy = false
			if team and root and hum and hum.Health > 0 and not char:GetAttribute("InLobby") then
				for _, volume in bases:GetChildren() do
					local owner = volume:GetAttribute("Team")
					if owner and owner ~= team and MapService.isInBase(root.Position, owner) then
						inEnemy = true
						break
					end
				end
				if inEnemy then
					hum:TakeDamage(ENEMY_BASE_DPS * step)
				end
			end
			if char and char:GetAttribute("InEnemyBase") ~= inEnemy then
				char:SetAttribute("InEnemyBase", inEnemy)
			end
		end
	end)
end

guardBases()

return MapService
