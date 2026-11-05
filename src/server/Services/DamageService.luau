-- Урон, броня, ранения и поднятие.
-- Весь урон (пули, нож, гранаты) проходит через DamageService.apply.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage:WaitForChild("Shared").Config.Combat)

local DOWNED = Combat.Downed
local ARMOR = Combat.Armor

local DamageService = {}

local hooks = {
	getTeamKey = function(_entity): string?
		return nil
	end,
	fromCharacter = function(_model)
		return nil
	end,
	downedAllowed = function(): boolean
		return DOWNED.Enabled
	end,
	onDowned = function(_victim, _attacker) end,
}

function DamageService.setHooks(newHooks)
	for k, v in newHooks do
		hooks[k] = v
	end
end

function DamageService.isDowned(char: Model?): boolean
	return char ~= nil and char:GetAttribute("Downed") == true
end

-- Броня выдаётся при появлении, если игрок взял её в инвентарь.
function DamageService.giveArmor(char: Model)
	char:SetAttribute("Armor", ARMOR.Points)
end

local function removePrompt(char: Model)
	local root = char:FindFirstChild("HumanoidRootPart")
	local prompt = root and root:FindFirstChild("RevivePrompt")
	if prompt then
		prompt:Destroy()
	end
end

function DamageService.revive(hum: Humanoid)
	local char = hum.Parent :: Model
	if not char or not DamageService.isDowned(char) or hum.Health <= 0 then
		return
	end
	char:SetAttribute("Downed", false)
	char:SetAttribute("BleedOut", nil)
	removePrompt(char)
	hum.Health = math.min(hum.MaxHealth, DOWNED.ReviveHealth)
	hum.WalkSpeed = char:GetAttribute("NormalWalkSpeed") or 16
	hum.JumpPower = char:GetAttribute("NormalJumpPower") or 50
	hum.JumpHeight = char:GetAttribute("NormalJumpHeight") or 7.2
end

local function down(hum: Humanoid, victim, attacker)
	local char = hum.Parent :: Model
	char:SetAttribute("Downed", true)
	char:SetAttribute("NormalWalkSpeed", hum.WalkSpeed)
	char:SetAttribute("NormalJumpPower", hum.JumpPower)
	char:SetAttribute("NormalJumpHeight", hum.JumpHeight)
	hum.Health = DOWNED.Health
	hum.WalkSpeed = DOWNED.CrawlSpeed
	hum.JumpPower = 0
	hum.JumpHeight = 0
	hum:UnequipTools()

	-- Подсказка «Поднять» для союзников. Врагам клиент её скрывает, а сервер проверяет команду.
	local root = char:FindFirstChild("HumanoidRootPart")
	if root then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RevivePrompt"
		prompt.ActionText = "Поднять"
		prompt.ObjectText = char.Name
		prompt.HoldDuration = DOWNED.ReviveTime
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt:SetAttribute("TeamKey", hooks.getTeamKey(victim))
		prompt.Triggered:Connect(function(rescuer: Player)
			local rescuerTeam = hooks.getTeamKey(rescuer)
			local rescuerChar = rescuer.Character
			local rescuerHum = rescuerChar and rescuerChar:FindFirstChildOfClass("Humanoid")
			if rescuerTeam and rescuerTeam == hooks.getTeamKey(victim)
				and rescuerHum and rescuerHum.Health > 0
				and not DamageService.isDowned(rescuerChar)
			then
				DamageService.revive(hum)
			end
		end)
		prompt.Parent = root
	end

	-- Кровотечение: запас здоровья раненого тает за BleedOutTime секунд.
	local step = 0.25
	local perStep = DOWNED.Health / DOWNED.BleedOutTime * step
	task.spawn(function()
		local timeLeft = DOWNED.BleedOutTime
		while DamageService.isDowned(char) and hum.Health > 0 and char.Parent do
			task.wait(step)
			timeLeft -= step
			char:SetAttribute("BleedOut", math.max(0, timeLeft))
			if DamageService.isDowned(char) then
				hum.Health = math.max(0, hum.Health - perStep)
			end
		end
	end)

	hooks.onDowned(victim, attacker)
end

-- Нанести урон. isHead — попадание в голову (броня не защищает).
function DamageService.apply(attacker, victim, hum: Humanoid, damage: number, isHead: boolean?)
	local char = hum.Parent :: Model
	if not char or hum.Health <= 0 or char:FindFirstChildOfClass("ForceField") then
		return
	end

	if DamageService.isDowned(char) then
		hum:TakeDamage(damage) -- добивание
		return
	end

	local armor = char:GetAttribute("Armor") or 0
	if armor > 0 and not isHead then
		local absorbed = math.min(armor, damage * ARMOR.Absorb)
		char:SetAttribute("Armor", armor - absorbed)
		damage -= absorbed
	end

	local lethal = damage >= hum.Health
	local instantKill = damage >= hum.Health + DOWNED.InstantKillOverkill
	if lethal and not instantKill and hooks.downedAllowed() then
		down(hum, victim, attacker)
	else
		hum:TakeDamage(damage)
	end
end

return DamageService
