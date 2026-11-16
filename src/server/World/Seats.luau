-- Где можно сесть: скамейки города (тег SitPoint, Seat без посадки по касанию, см. CityBuilder).
-- Подойти и нажать E «Сесть»; встать — прыжок. Анимацию сидения играет скрипт Animate персонажа.
local CollectionService = game:GetService("CollectionService")

local Seats = {}

local function setup(seat: Instance)
	if not seat:IsA("Seat") or seat:FindFirstChild("SitPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SitPrompt"
	prompt.ActionText = "Сесть"
	prompt.ObjectText = "Скамейка"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 6
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Parent = seat
	prompt.Triggered:Connect(function(player: Player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or not root or hum.Health <= 0 or hum.SeatPart or seat.Occupant or char:GetAttribute("Downed") then
			return
		end
		if (root.Position - seat.Position).Magnitude > 9 then
			return
		end
		seat:Sit(hum)
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		prompt.Enabled = seat.Occupant == nil
	end)
end

function Seats.init()
	CollectionService:GetInstanceAddedSignal("SitPoint"):Connect(setup)
	for _, seat in CollectionService:GetTagged("SitPoint") do
		setup(seat)
	end
end

return Seats
