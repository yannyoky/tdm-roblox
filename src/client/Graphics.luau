-- Реалистичная графика на клиенте. Свет, атмосферу и облака ставит сервер (World/Ambience.luau),
-- здесь только то, что удобнее делать у игрока:
--   * подмена стандартных материалов на PBR MaterialVariant из MaterialService;
--   * размытие в прицеле (фокус на цели), выключается настройкой «Размытие в прицеле».
-- Значения — src/shared/Config/Graphics.luau.
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Graphics)
local PlayerSettings = require(script.Parent.PlayerSettings)

local player = Players.LocalPlayer

local Graphics = {}

------------------------------------------------------------------------
-- Материалы

local function findVariant(material: Enum.Material, preferred: string?): string?
	if preferred then
		local v = MaterialService:FindFirstChild(preferred, true)
		if v and v:IsA("MaterialVariant") and v.BaseMaterial == material then
			return v.Name
		end
	end
	if Config.AutoPickMaterialVariants then
		for _, v in MaterialService:GetDescendants() do
			if v:IsA("MaterialVariant") and v.BaseMaterial == material then
				return v.Name
			end
		end
	end
	return nil
end

local function applyMaterials()
	local materials: { [Enum.Material]: string | false } = {}
	for material, name in Config.MaterialOverrides do
		materials[material] = name
	end
	if Config.AutoPickMaterialVariants then
		for _, v in MaterialService:GetDescendants() do
			if v:IsA("MaterialVariant") and materials[v.BaseMaterial] == nil then
				materials[v.BaseMaterial] = false
			end
		end
	end
	for material, preferred in materials do
		local name = findVariant(material, if preferred then preferred else nil)
		if name then
			pcall(function()
				MaterialService:SetBaseMaterialOverride(material, name)
			end)
		end
	end
end

------------------------------------------------------------------------
-- Размытие в прицеле

local dof: DepthOfFieldEffect? = nil
local connection: RBXScriptConnection? = nil

local function lowEndDevice(): boolean
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if not ok or level == Enum.SavedQualitySetting.Automatic then
		return false
	end
	return level.Value <= 3
end

local function stopBlur()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if dof then
		dof.Enabled = false
	end
end

local function startBlur()
	if connection or PlayerSettings.get("AimBlur") == false or lowEndDevice() then
		return
	end
	if not dof or not dof.Parent then
		local d = Instance.new("DepthOfFieldEffect")
		d.Name = "AimBlur"
		d.Enabled = false
		d.Parent = Lighting
		dof = d
	end
	local effect = dof :: DepthOfFieldEffect
	local cfg = Config.AimBlur
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	effect.FocusDistance = 50
	effect.NearIntensity = cfg.NearIntensity
	effect.FarIntensity = cfg.FarIntensity
	effect.Enabled = true
	connection = RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		params.FilterDescendantsInstances = { player.Character :: Instance, camera }
		local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 1000, params)
		local distance = math.min(if hit then hit.Distance else 200, 200)
		effect.FocusDistance += (distance - effect.FocusDistance) * 0.25
		effect.InFocusRadius = math.clamp(distance * 0.3, cfg.MinInFocusRadius, 50)
	end)
end

------------------------------------------------------------------------

function Graphics.init()
	applyMaterials()
	MaterialService.DescendantAdded:Connect(function(inst)
		if inst:IsA("MaterialVariant") then
			applyMaterials()
		end
	end)

	PlayerSettings.onAimingChanged(function(on)
		if on then
			startBlur()
		else
			stopBlur()
		end
	end)
	PlayerSettings.onChanged(function(key, value)
		if key == "AimBlur" and value == false then
			stopBlur()
		end
	end)
end

return Graphics
