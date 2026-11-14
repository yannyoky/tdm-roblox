-- Оружие. Попадания и урон считает сервер: игрок сообщает только «выстрелил отсюда туда».
-- Сервер проверяет скорострельность и патроны, добавляет разброс, учитывает зоны тела,
-- падение урона с дистанцией и пробитие тонких стен. Боты стреляют через тот же код.
--
-- «Боец» (combatant) — это Player или таблица бота. MatchService подключает хуки:
--   canDamage(attacker, victim) -> boolean
--   fromCharacter(model) -> боец или nil
--   idOf(combatant) -> строка для атрибута LastAttacker
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared.Config.Weapons)
local Net = require(Shared.Net)

local DamageService = require(script.Parent.DamageService)
local GrenadeService = require(script.Parent.GrenadeService)
local WeaponModels = require(script.Parent.WeaponModels)

local MAX_ORIGIN_OFFSET = 8 -- насколько точка выстрела может отличаться от головы
local FIRE_RATE_TOLERANCE = 0.8 -- запас на сетевые задержки
local MAX_PENETRATIONS = 1

-- Транспорт (src/server/World/VehicleService) подключается, если он есть в проекте.
local function getVehicleService()
	local world = script.Parent.Parent:FindFirstChild("World")
	local module = world and world:FindFirstChild("VehicleService")
	return if module then require(module) :: any else nil
end

local TORSO_PARTS = { UpperTorso = true, LowerTorso = true, Torso = true, HumanoidRootPart = true }

local WeaponService = {}

local hooks = {
	canDamage = function(_a, _v)
		return false
	end,
	fromCharacter = function(model: Model)
		return Players:GetPlayerFromCharacter(model)
	end,
	idOf = function(c)
		return "p" .. tostring(c.UserId)
	end,
}

local lastShot = setmetatable({}, { __mode = "k" }) -- [боец] = { [weaponId] = время }

function WeaponService.setHooks(newHooks)
	for k, v in newHooks do
		hooks[k] = v
	end
	GrenadeService.setHooks(hooks)
end

function WeaponService.makeTool(id: string): Tool?
	local def = Weapons.List[id]
	if not def then
		return nil
	end
	local tool = Instance.new("Tool")
	tool.Name = def.DisplayName
	tool.ToolTip = def.DisplayName
	tool.CanBeDropped = false
	tool:SetAttribute("WeaponId", id)
	tool:SetAttribute("Reloading", false)
	if def.MagSize then
		tool:SetAttribute("Ammo", def.MagSize)
	end
	if def.Count then
		tool:SetAttribute("Count", def.Count)
		tool.Name = string.format("%s x%d", def.DisplayName, def.Count)
	end

	WeaponModels.build(tool, id, def)
	return tool
end

-- Выдаёт игроку всё, что он взял в инвентарь.
function WeaponService.giveInventory(player: Player, items: { string })
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	backpack:ClearAllChildren()
	for _, id in items do
		local def = Weapons.List[id]
		-- Броня не оружие: её надевает MatchService при появлении.
		if def and def.Kind ~= "Armor" then
			local tool = WeaponService.makeTool(id)
			if tool then
				tool.Parent = backpack
			end
		end
	end
end

local function getEquipped(char: Model?, weaponId: string): Tool?
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("WeaponId") == weaponId then
		return tool
	end
	return nil
end

local function applySpread(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local angle = math.rad(degrees) * math.sqrt(math.random())
	local roll = math.random() * 2 * math.pi
	local cf = CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)
	return cf.LookVector
end

local function falloff(def, distance: number): number
	local start = def.FalloffStart or def.Range
	if distance <= start then
		return 1
	end
	local t = math.clamp((distance - start) / math.max(def.Range - start, 1), 0, 1)
	local minMult = def.MinDamageMultiplier or 1
	return 1 + (minMult - 1) * t
end

-- Множитель урона по зоне тела. Шапки и аксессуары считаются той частью, к которой прикреплены.
local function partMultiplier(def, part: BasePart): (number, boolean)
	local bodyPart = part
	if part.Parent and part.Parent:IsA("Accessory") then
		local weld = part:FindFirstChildWhichIsA("Weld") or part:FindFirstChild("AccessoryWeld")
		if weld and (weld :: any).Part1 then
			bodyPart = (weld :: any).Part1
		end
	end
	if bodyPart.Name == "Head" then
		return def.HeadshotMultiplier or 1, true
	elseif TORSO_PARTS[bodyPart.Name] then
		return 1, false
	end
	return def.LimbMultiplier or 1, false
end

-- Толщина детали вдоль луча: ищем точку выхода обратным лучом.
local function exitPoint(part: BasePart, entry: Vector3, dir: Vector3, maxThickness: number): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { part }
	local far = entry + dir * (maxThickness + 0.05)
	local back = workspace:Raycast(far, -dir * (maxThickness + 0.05), params)
	if back then
		return back.Position
	end
	return nil
end

-- Один луч (пуля или дробина). Возвращает конечную точку для трассера.
local function traceBullet(shooter, char: Model, def, weaponId: string, origin: Vector3, dir: Vector3): (Vector3, boolean)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }

	local from = origin
	local remaining = def.Range
	local damageMult = 1
	local penetrations = 0
	while remaining > 0 do
		local result = workspace:Raycast(from, dir * remaining, params)
		if not result then
			return from + dir * remaining, false
		end
		local traveled = (result.Position - origin).Magnitude
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		local targetHum = model and model:FindFirstChildOfClass("Humanoid")
		if targetHum then
			local target = hooks.fromCharacter(model)
			if target and targetHum.Health > 0 and hooks.canDamage(shooter, target) then
				local mult, isHead = partMultiplier(def, result.Instance)
				local damage = def.Damage * mult * falloff(def, traveled) * damageMult
				targetHum:SetAttribute("LastAttacker", hooks.idOf(shooter))
				targetHum:SetAttribute("LastWeapon", weaponId)
				targetHum:SetAttribute("LastHeadshot", isHead)
				DamageService.apply(shooter, target, targetHum, damage, isHead)
				if typeof(shooter) == "Instance" then
					Net.get("HitMarker"):FireClient(shooter, isHead)
				end
			end
			return result.Position, true
		end

		-- Попадание в машину: урон транспорту (дружественный огонь проверяет VehicleService).
		local vehicles = getVehicleService()
		local vehicle = vehicles and vehicles.fromPart(result.Instance)
		if vehicle then
			local damage = def.Damage * falloff(def, traveled) * damageMult
			vehicles.damage(vehicle, damage, shooter)
			return result.Position, true
		end

		-- Пробитие тонкой стены.
		local part = result.Instance
		local canPen = (def.Penetration or 0) > 0
			and penetrations < MAX_PENETRATIONS
			and part:IsA("BasePart")
			and Weapons.PenetrableMaterials[result.Material]
		if not canPen then
			return result.Position, true
		end
		local exit = exitPoint(part :: BasePart, result.Position, dir, def.Penetration)
		if not exit then
			return result.Position, true -- слишком толсто
		end
		penetrations += 1
		damageMult *= Weapons.PenetrationDamageMultiplier
		from = exit + dir * 0.05
		remaining = def.Range - (from - origin).Magnitude
	end
	return from, false
end

-- Выстрел бойца из экипированного оружия. Возвращает true, если выстрел засчитан.
function WeaponService.fire(shooter, char: Model?, weaponId: string, origin: Vector3, direction: Vector3): boolean
	local def = Weapons.List[weaponId]
	if not def or not char then
		return false
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local head = char:FindFirstChild("Head") :: BasePart?
	if not hum or hum.Health <= 0 or not head or DamageService.isDowned(char) then
		return false
	end
	local tool = getEquipped(char, weaponId)
	if not tool or tool:GetAttribute("Reloading") then
		return false
	end

	-- Защита от подмены данных (NaN не проходит сравнения, поэтому через not).
	if not ((origin - head.Position).Magnitude <= MAX_ORIGIN_OFFSET) then
		return false
	end
	local len = direction.Magnitude
	if not (len > 0.01 and len < math.huge) then
		return false
	end

	local shots = lastShot[shooter]
	if not shots then
		shots = {}
		lastShot[shooter] = shots
	end
	local now = os.clock()
	if now - (shots[weaponId] or 0) < (1 / def.FireRate) * FIRE_RATE_TOLERANCE then
		return false
	end
	shots[weaponId] = now

	if def.MagSize then
		local ammo = tool:GetAttribute("Ammo") or 0
		if ammo <= 0 then
			return false
		end
		tool:SetAttribute("Ammo", ammo - 1)
	end

	local unit = direction.Unit

	if def.Kind == "Grenade" then
		local count = tool:GetAttribute("Count") or 0
		if count <= 0 then
			return false
		end
		count -= 1
		tool:SetAttribute("Count", count)
		tool.Name = string.format("%s x%d", def.DisplayName, count)
		GrenadeService.throw(shooter, char, def, origin, unit)
		if count <= 0 then
			tool:Destroy()
		end
		return true
	end

	-- Попадание считается от головы, а трассер рисуется от дула модели, если оно есть.
	local handle = tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	local fxOrigin = if muzzle and muzzle:IsA("Attachment") then muzzle.WorldPosition else origin
	local fx = Net.get("ShotFx")
	for i = 1, def.Pellets or 1 do
		local dir = applySpread(unit, def.Spread or 0)
		local endPos, hitSomething = traceBullet(shooter, char, def, weaponId, origin, dir)
		fx:FireAllClients(fxOrigin, endPos, def.Melee == true, hitSomething, i == 1)
	end
	return true
end

function WeaponService.reload(char: Model?, weaponId: string)
	local def = Weapons.List[weaponId]
	if not def or not def.MagSize then
		return
	end
	local tool = getEquipped(char, weaponId)
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
	Net.get("FireWeapon").OnServerEvent:Connect(function(player, weaponId, origin, direction)
		if typeof(weaponId) ~= "string" or typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
			return
		end
		WeaponService.fire(player, player.Character, weaponId, origin, direction)
	end)
	Net.get("Reload").OnServerEvent:Connect(function(player, weaponId)
		if typeof(weaponId) == "string" then
			WeaponService.reload(player.Character, weaponId)
		end
	end)
end

return WeaponService
