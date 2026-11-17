-- Подсказки городских сервисов, которые открывают меню у игрока (World/CityServices на сервере):
-- у подсказки атрибут OpenMenu = имя меню (например, киоск → «Магазин»).
local ProximityPromptService = game:GetService("ProximityPromptService")

local Menus = require(script.Parent:WaitForChild("Menus"))

local CityInteract = {}

function CityInteract.init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local menu = prompt:GetAttribute("OpenMenu")
		if type(menu) == "string" then
			Menus.open(menu)
		end
	end)
end

return CityInteract
