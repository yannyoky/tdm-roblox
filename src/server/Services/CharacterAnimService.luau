-- Реалистичные анимации движения у игроков (Config/Character.Animations).
-- Тело и одежду делает система внешности; здесь только скрипт Animate.
-- Боты получают те же анимации в BotService.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterLook = require(ReplicatedStorage:WaitForChild("Shared").CharacterLook)

local CharacterAnimService = {}

local function onCharacter(char: Model)
	CharacterLook.applyAnimations(char)
end

function CharacterAnimService.init()
	local function watch(player: Player)
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			task.spawn(onCharacter, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return CharacterAnimService
