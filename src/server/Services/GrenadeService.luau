-- Гранаты: осколочная, дымовая, светошумовая.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local DamageService = require(script.Parent.DamageService)

local GrenadeService = {}

local hooks = {
	canDamage = function(_a, _v)
		return false
	end,
	fromCharacter = function(_model)
		return nil
	end,
	idOf = function(_c)
		return ""
	end,
}

-- Активные облака дыма: { position, radius, untilTime }.
local smokes = {}

function GrenadeService.setHooks(newHooks)
	for k, v in newHooks do
		hooks[k] = v
	end
end

-- Закрывает ли дым линию между точками a и b (для зрения ботов).
function GrenadeService.blocksSight(a: Vector3, b: Vector3): boolean
	local now = os.clock()
	local seg = b - a
	local len2 = seg:Dot(seg)
	for i = #smokes, 1, -1 do
		local s = smokes[i]
		if s.untilTime < now then
			table.remove(smokes, i)
		else
			local t = if len2 > 0 then math.clamp((s.position - a):Dot(seg) / len2, 0, 1) else 0
			local closest = a + seg * t
			if (closest - s.position).Magnitude < s.radius then
				return true
			end
		end
	end
	return false
end

-- Персонажи в радиусе, которых видно из точки взрыва.
local function charactersInBlast(position: Vector3, radius: number, ignore: { Instance })
	local found = {}
	local seen = {}
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	for _, part in workspace:GetPartBoundsInRadius(position, radius, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum and root and not seen[model] then
			seen[model] = true
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = ignore
			local offset = root.Position - position
			local hit = workspace:Raycast(position, offset, rayParams)
			if not hit or hit.Instance:IsDescendantOf(model) then
				table.insert(found, { model = model, hum = hum, root = root, distance = offset.Magnitude })
			end
		end
	end
	return found
end

local function explodeFrag(thrower, def, position: Vector3, grenade: BasePart)
	local boom = Instance.new("Explosion")
	boom.Position = position
	boom.BlastRadius = def.Radius
	boom.BlastPressure = 0
	boom.DestroyJointRadiusPercent = 0
	boom.Parent = workspace
	for _, hit in charactersInBlast(position, def.Radius, { grenade }) do
		local target = hooks.fromCharacter(hit.model)
		if target and hooks.canDamage(thrower, target) then
			local damage = def.Damage * (1 - math.clamp(hit.distance / def.Radius, 0, 1)) ^ 0.6
			hit.hum:SetAttribute("LastAttacker", hooks.idOf(thrower))
			hit.hum:SetAttribute("LastWeapon", def.Id)
			hit.hum:SetAttribute("LastHeadshot", false)
			DamageService.apply(thrower, target, hit.hum, damage, false)
		end
	end
end

local function explodeSmoke(def, position: Vector3)
	local cloud = Instance.new("Part")
	cloud.Name = "SmokeCloud"
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.Transparency = 1
	cloud.Size = Vector3.new(1, 1, 1)
	cloud.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 14) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(5, 7)
	emitter.Rate = 30
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = cloud
	cloud.Parent = workspace
	table.insert(smokes, { position = position, radius = def.Radius, untilTime = os.clock() + def.Duration })
	task.delay(def.Duration - 5, function()
		emitter.Enabled = false
	end)
	Debris:AddItem(cloud, def.Duration + 2)
end

local function explodeFlash(def, position: Vector3, grenade: BasePart)
	local flash = Instance.new("Explosion")
	flash.Position = position
	flash.BlastRadius = 1
	flash.BlastPressure = 0
	flash.DestroyJointRadiusPercent = 0
	flash.Parent = workspace
	for _, hit in charactersInBlast(position, def.Radius, { grenade }) do
		local head = hit.model:FindFirstChild("Head") :: BasePart?
		local facing = if head then head.CFrame.LookVector:Dot((position - head.Position).Unit) else 0
		local intensity = (1 - math.clamp(hit.distance / def.Radius, 0, 1)) * (if facing > 0 then 1 else 0.4)
		local player = Players:GetPlayerFromCharacter(hit.model)
		if player then
			Net.get("Flash"):FireClient(player, intensity)
		else
			-- Бот ослеплён: не видит врагов.
			hit.model:SetAttribute("BlindUntil", os.clock() + def.Duration * intensity)
		end
	end
end

-- Бросок гранаты из точки origin в направлении direction.
function GrenadeService.throw(thrower, char: Model, def, origin: Vector3, direction: Vector3)
	local grenade = Instance.new("Part")
	grenade.Name = "Grenade"
	grenade.Shape = Enum.PartType.Ball
	grenade.Size = Vector3.new(0.8, 0.8, 0.8)
	grenade.Color = def.Color or Color3.fromRGB(60, 70, 50)
	grenade.CanCollide = true
	grenade.CustomPhysicalProperties = PhysicalProperties.new(2, 0.6, 0.3)
	grenade.Position = origin + direction * 2
	grenade.AssemblyLinearVelocity = direction * def.ThrowSpeed + Vector3.new(0, 12, 0)
	grenade.Parent = workspace
	grenade:SetNetworkOwner(nil)

	-- Чтобы граната не цеплялась за самого бросающего.
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") then
			local noCollide = Instance.new("NoCollisionConstraint")
			noCollide.Part0 = grenade
			noCollide.Part1 = part
			noCollide.Parent = grenade
		end
	end

	task.delay(def.Fuse, function()
		if not grenade.Parent then
			return
		end
		local position = grenade.Position
		if def.GrenadeType == "Frag" then
			explodeFrag(thrower, def, position, grenade)
		elseif def.GrenadeType == "Smoke" then
			explodeSmoke(def, position)
		elseif def.GrenadeType == "Flash" then
			explodeFlash(def, position, grenade)
		end
		grenade:Destroy()
	end)
end

return GrenadeService
