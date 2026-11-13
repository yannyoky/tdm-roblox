-- Экран смерти: кто убил, из чего, сколько у него здоровья и когда возрождение.
-- Камера на это время смотрит на убийцу.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Weapons = require(Shared.Config.Weapons)
local Ui = require(script.Parent.Ui)

local player = Players.LocalPlayer
local C = Ui.Colors

local DeathScreen = {}

function DeathScreen.init()
	local gui = Ui.make("ScreenGui", { Name = "DeathScreen", ResetOnSpawn = false, DisplayOrder = 6, IgnoreGuiInset = true })
	local vignette = Ui.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(60, 0, 0),
		BackgroundTransparency = 0.75,
		Visible = false,
		Parent = gui,
	})
	local card = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -140),
		Size = UDim2.new(0, 380, 0, 110),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		Parent = vignette,
	}, { Ui.corner(10), Ui.padding(10) })
	local killedBy = Ui.label({ Size = UDim2.new(1, 0, 0, 30), Parent = card })
	local detail = Ui.label({ Position = UDim2.new(0, 0, 0, 34), Size = UDim2.new(1, 0, 0, 22), Font = Enum.Font.Gotham, TextColor3 = C.Grey, Parent = card })
	local countdown = Ui.label({ Position = UDim2.new(0, 0, 0, 62), Size = UDim2.new(1, 0, 0, 26), TextColor3 = C.Accent, Parent = card })

	local respawnAt: number? = nil
	local active = false

	local function hide()
		active = false
		vignette.Visible = false
		respawnAt = nil
	end

	Net.get("Died").OnClientEvent:Connect(function(killerName: string?, weaponId: string?, respawnIn: number?, killerHealth: number?, killerChar: Model?)
		active = true
		vignette.Visible = true
		local weapon = weaponId and Weapons.List[weaponId]
		if killerName then
			killedBy.Text = "Вас убил " .. killerName
			local parts = {}
			if weapon then
				table.insert(parts, weapon.DisplayName)
			end
			if killerHealth then
				table.insert(parts, string.format("у него %d HP", killerHealth))
			end
			detail.Text = table.concat(parts, "  •  ")
		else
			killedBy.Text = "Вы погибли"
			detail.Text = ""
		end
		respawnAt = if respawnIn then os.clock() + respawnIn else nil
		countdown.Text = if respawnIn then "" else "В этом раунде без возрождения"

		-- Камера на убийцу.
		local hum = killerChar and killerChar:FindFirstChildOfClass("Humanoid")
		if hum then
			workspace.CurrentCamera.CameraSubject = hum
		end
	end)

	RunService.RenderStepped:Connect(function()
		if active and respawnAt then
			local left = math.max(0, respawnAt - os.clock())
			countdown.Text = string.format("Возрождение через %.1f", left)
		end
	end)

	player.CharacterAdded:Connect(function(char)
		hide()
		local hum = char:WaitForChild("Humanoid", 5)
		if hum then
			workspace.CurrentCamera.CameraSubject = hum
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return DeathScreen
