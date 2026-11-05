-- Оружие. Клиент только сообщает о выстреле, а попадание и урон считает сервер:
-- так читер не может «попасть» сквозь стену или стрелять чаще, чем позволяет оружие.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared.Config.Weapons)
local Net = require(Shared.Net)

local MAX_ORIGIN_OFFSET = 8 -- насколько точка выстрела может отличаться от головы
local FIRE_RATE_TOLERANCE = 0.8 -- запас на сетевые задержки

local WeaponService = {}

local canDamage: (Player, Player) -> boolean = function()
	return false
end
local lastShot: { [Player]: { [string]: number } } = {}

-- MatchService решает, кому можно наносить урон (команды, фаза матча).
function WeaponService.setDamageFilter(fn: (Player, Player) -> boolean)
	canDamage = fn
end

local function makeTool(id: string, def): Tool
	local tool = Instance.new("Tool")
	tool.Name = def.DisplayName
	tool.ToolTip = def.DisplayName
	tool.CanBeDropped = false
	tool:SetAttribute("WeaponId", id)
	tool:SetAttribute("Reloading", false)
	if def.MagSize then
		tool:SetAttribute("Ammo", def.MagSize)
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = def.HandleSize or Vector3.new(0.4, 0.8, 2)
	handle.Color = def.Color or Color3.fromRGB(40, 40, 40)
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Parent = tool
	return tool
end

function WeaponService.giveLoadout(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	backpack:ClearAllChildren()
	for _, id in Weapons.DefaultLoadout do
		local def = Weapons.List[id]
		if def then
			makeTool(id, def).Parent = backpack
		end
	end
end

local function getEquipped(player: Player, weaponId: string): Tool?
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("WeaponId") == weaponId then
		return tool
	end
	return nil
end

local function onFire(player: Player, weaponId: unknown, origin: unknown, direction: unknown)
	if typeof(weaponId) ~= "string" or typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	local def = Weapons.List[weaponId]
	if not def then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not hum or hum.Health <= 0 or not head then
		return
	end
	local tool = getEquipped(player, weaponId)
	if not tool or tool:GetAttribute("Reloading") then
		return
	end

	-- Проверки на подмену данных (NaN не проходит сравнения, поэтому через not).
	local offset = (origin - head.Position).Magnitude
	if not (offset <= MAX_ORIGIN_OFFSET) then
		return
	end
	local len = direction.Magnitude
	if not (len > 0.01 and len < math.huge) then
		return
	end

	-- Скорострельность.
	local shots = lastShot[player]
	if not shots then
		shots = {}
		lastShot[player] = shots
	end
	local now = os.clock()
	if now - (shots[weaponId] or 0) < (1 / def.FireRate) * FIRE_RATE_TOLERANCE then
		return
	end
	shots[weaponId] = now

	-- Патроны.
	if def.MagSize then
		local ammo = tool:GetAttribute("Ammo") or 0
		if ammo <= 0 then
			return
		end
		tool:SetAttribute("Ammo", ammo - 1)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local unit = direction.Unit
	local result = workspace:Raycast(origin, unit * def.Range, params)
	local endPos = if result then result.Position else origin + unit * def.Range

	Net.get("ShotFx"):FireAllClients(player, origin, endPos, def.Melee == true)

	if not result then
		return
	end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	local targetHum = model and model:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then
		return
	end
	local target = Players:GetPlayerFromCharacter(model)
	if not target or not canDamage(player, target) then
		return
	end

	local isHead = result.Instance.Name == "Head"
	local damage = def.Damage * (if isHead then def.HeadshotMultiplier else 1)
	targetHum:SetAttribute("LastAttacker", player.UserId)
	targetHum:SetAttribute("LastWeapon", weaponId)
	targetHum:TakeDamage(damage) -- ForceField (защита на спавне) блокирует урон
	Net.get("HitMarker"):FireClient(player, isHead)
end

local function onReload(player: Player, weaponId: unknown)
	if typeof(weaponId) ~= "string" then
		return
	end
	local def = Weapons.List[weaponId]
	if not def or not def.MagSize then
		return
	end
	local tool = getEquipped(player, weaponId)
	if not tool or tool:GetAttribute("Reloading") or tool:GetAttribute("Ammo") == def.MagSize then
		return
	end
	tool:SetAttribute("Reloading", true)
	task.delay(def.ReloadTime, function()
		if tool.Parent then
			tool:SetAttribute("Ammo", def.MagSize)
			tool:SetAttribute("Reloading", false)
		end
	end)
end

function WeaponService.init()
	Net.get("FireWeapon").OnServerEvent:Connect(onFire)
	Net.get("Reload").OnServerEvent:Connect(onReload)
	Players.PlayerRemoving:Connect(function(player)
		lastShot[player] = nil
	end)
end

return WeaponService
