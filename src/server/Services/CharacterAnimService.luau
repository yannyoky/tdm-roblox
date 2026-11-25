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

-- Хват оружия у сгенерированных тел (GeneratedBody): их GripAttachment стоит посреди длинной
-- кисти и повёрнут так, что ствол смотрит вдоль пальцев — с позой WeaponPose кисть выгибается.
-- Ставим хват как у пистолетной рукоятки: точка в ладони, ствол вперёд по большому пальцу,
-- пальцы обхватывают рукоятку под углом ~30° к стволу, запястье ровное.
local GRIP_ANGLE = math.rad(-120)
local function fixGrips(char: Model)
	if char:GetAttribute("GeneratedBody") == nil then
		return
	end
	for _, side in { "Right", "Left" } do
		local hand = char:FindFirstChild(side .. "Hand")
		local grip = hand and hand:FindFirstChild(side .. "GripAttachment")
		if hand and hand:IsA("BasePart") and grip and grip:IsA("Attachment") then
			grip.CFrame = CFrame.new(0, -hand.Size.Y * 0.18, 0) * CFrame.Angles(GRIP_ANGLE, 0, 0)
		end
	end
end

local function onCharacter(char: Model)
	fixGrips(char)
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
