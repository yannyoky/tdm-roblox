-- Реалистичные анимации движения у игроков (Config/Character.Animations).
-- Анимации своего персонажа играет клиент (AnimDirector); сервер лишь ставит id в Animate
-- (запасной вариант, если AnimDirector выключен) и отмечает взаимодействия (рука к предмету).
-- Тело и одежду делает система внешности; здесь только скрипт Animate.
-- Боты получают те же анимации в BotService.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterLook = require(ReplicatedStorage:WaitForChild("Shared").CharacterLook)

local CharacterAnimService = {}

local function onCharacter(char: Model)
	CharacterLook.applyAnimations(char)
end

-- Где предмет, с которым взаимодействуют (точка, к которой тянется рука).
local function promptPosition(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Model") then
		return parent:GetPivot().Position
	end
	return nil
end

-- Взаимодействие (E): клиенты по этим атрибутам тянут руку персонажа к предмету и поворачивают голову.
local function markInteraction(prompt: ProximityPrompt, player: Player, holding: boolean?)
	local char = player.Character
	local pos = promptPosition(prompt)
	if not char or not pos then
		return
	end
	char:SetAttribute("InteractPos", pos)
	char:SetAttribute("InteractAt", workspace:GetServerTimeNow())
	if holding ~= nil then
		char:SetAttribute("Interacting", holding)
	end
end

function CharacterAnimService.init()
	local function watch(player: Player)
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			task.spawn(onCharacter, player.Character)
		end
	end
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		markInteraction(prompt, player, false)
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
		markInteraction(prompt, player, true)
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(_prompt, player)
		if player.Character then
			player.Character:SetAttribute("Interacting", false)
		end
	end)
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return CharacterAnimService
