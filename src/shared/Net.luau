-- Сетевые события между клиентом и сервером.
-- Сервер создаёт их при старте, клиент ждёт, пока они появятся.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTES = {
	"FireWeapon", -- клиент → сервер: выстрел (weaponId, origin, direction)
	"Reload", -- клиент → сервер: перезарядка (weaponId)
	"VoteMode", -- клиент → сервер: голос за режим (modeId)
	"KillFeed", -- сервер → все: (killerName?, victimName, weaponId?)
	"HitMarker", -- сервер → стрелок: попадание (isHeadshot)
	"ShotFx", -- сервер → все: трассер (origin, endPos, isMelee, hitSomething)
	"Flash", -- сервер → игрок: ослепление светошумовой (intensity 0..1)
	"SetInventoryItem", -- клиент → сервер: взять/убрать предмет (itemId, enabled)
	"EquipSkin", -- клиент → сервер: выбрать скин (skinId)
	"BuySkin", -- клиент → сервер: купить скин за монеты (skinId)
	"SaveSettings", -- клиент → сервер: настройки ({ [key] = value })
	"Play", -- клиент → сервер: нажал «Играть» в главном меню (preferredTeam: "Bandits" | "Gov" | "Any")
	"Crouch", -- клиент → сервер: присесть или встать (on)
	"Died", -- сервер → игрок: экран смерти (killerName?, weaponId?, respawnIn?, killerHealth?)
}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
	end
	for _, name in REMOTES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local Net = {}

function Net.get(name: string): RemoteEvent
	local remote
	if RunService:IsServer() then
		remote = folder:FindFirstChild(name)
	else
		remote = folder:WaitForChild(name)
	end
	assert(remote, "Неизвестное сетевое событие: " .. name)
	return remote
end

return Net
