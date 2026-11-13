-- Реалистичная графика на клиенте: освещение, атмосфера, облака, пост-эффекты,
-- свои PBR-материалы и глубина резкости в прицеле. Всё ставится только у этого игрока,
-- поэтому каждый может выключить это в настройках («Реалистичная графика»).
-- Значения — в src/shared/Config/Graphics.luau.
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config.Graphics)
local PlayerSettings = require(script.Parent.PlayerSettings)

local player = Players.LocalPlayer

local Graphics = {}

local EFFECT_TAG = "RealismEffect"
local LIGHT_TAG = "RealismLight" -- свет, который ставит сервер (World/Realism.luau)

-- Исходные значения Lighting, чтобы вернуть обычный вид.
local original: { [string]: any } = {}
local LIGHTING_KEYS = {
	"ClockTime", "GeographicLatitude", "Brightness", "ExposureCompensation", "Ambient", "OutdoorAmbient",
	"ColorShift_Top", "ColorShift_Bottom", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "ShadowSoftness",
}

local effects: {
	atmosphere: Atmosphere?,
	color: ColorCorrectionEffect?,
	bloom: BloomEffect?,
	rays: SunRaysEffect?,
	dof: DepthOfFieldEffect?,
	clouds: Clouds?,
} = {}

local enabled = false
local aiming = false
local dofConnection: RBXScriptConnection? = nil

local function lowEndDevice(): boolean
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if not ok or level == Enum.SavedQualitySetting.Automatic then
		return false
	end
	return level.Value <= 3
end

local function currentMood()
	local id = ReplicatedStorage:GetAttribute("MapId")
	return Config.Moods[id] or Config.Moods.Default
end

local function assign(inst: Instance, props: { [string]: any }?)
	for key, value in props or {} do
		pcall(function()
			(inst :: any)[key] = value
		end)
	end
end

-- Находит свой эффект (с тегом RealismEffect) или создаёт его. Эффекты, поставленные руками
-- в Studio без тега, не трогаются: их лучше убрать, чтобы не накладывались.
local function ensure(className: string, parent: Instance): any
	for _, child in parent:GetChildren() do
		if child.ClassName == className and CollectionService:HasTag(child, EFFECT_TAG) then
			return child
		end
	end
	local inst = Instance.new(className)
	inst.Name = "Realism" .. className
	CollectionService:AddTag(inst, EFFECT_TAG)
	inst.Parent = parent
	return inst
end

-- Для каждого материала: вариант с именем из Config.MaterialOverrides, а если такого нет —
-- первый попавшийся MaterialVariant с тем же BaseMaterial (так работает любой пак из Toolbox,
-- который просто вставили в MaterialService).
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

local function setMaterialOverrides(on: boolean)
	local materials = {}
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
		local name = if on then findVariant(material, preferred or nil) else nil
		pcall(function()
			MaterialService:SetBaseMaterialOverride(material, name or "")
		end)
	end
end

local function setServerLights(on: boolean)
	for _, light in CollectionService:GetTagged(LIGHT_TAG) do
		if light:IsA("Light") then
			-- Сервер решает, горит ли свет на этой карте (атрибут LampOn), клиент может только погасить.
			light.Enabled = on and light:GetAttribute("LampOn") ~= false
		end
	end
end

------------------------------------------------------------------------
-- Глубина резкости

local function updateDof()
	local dof = effects.dof
	if not dof then
		return
	end
	local cfg = Config.DepthOfField
	local allowed = enabled and PlayerSettings.get("DepthBlur") and not lowEndDevice()
	dof.Enabled = allowed
	if not allowed then
		return
	end
	if not aiming then
		dof.FarIntensity = cfg.FarIntensity
		dof.NearIntensity = 0
		dof.FocusDistance = cfg.FocusDistance
		dof.InFocusRadius = cfg.InFocusRadius
		return
	end
	-- Фокус на том, куда смотрит прицел.
	local camera = workspace.CurrentCamera
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, camera }
	local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 1000, params)
	local distance = math.min(if hit then hit.Distance else 200, 200)
	dof.FocusDistance = dof.FocusDistance + (distance - dof.FocusDistance) * 0.25
	dof.InFocusRadius = math.clamp(distance * 0.3, cfg.AimInFocusRadius, 50)
	dof.NearIntensity = cfg.AimNearIntensity
	dof.FarIntensity = cfg.AimFarIntensity
end

local function setAimTracking(on: boolean)
	if on and not dofConnection then
		dofConnection = RunService.RenderStepped:Connect(updateDof)
	elseif not on and dofConnection then
		dofConnection:Disconnect()
		dofConnection = nil
	end
end

------------------------------------------------------------------------

local function applyRealistic()
	local mood = currentMood()
	local low = lowEndDevice()

	assign(Lighting, mood.Lighting)

	effects.atmosphere = ensure("Atmosphere", Lighting)
	assign(effects.atmosphere, mood.Atmosphere)

	effects.color = ensure("ColorCorrectionEffect", Lighting)
	assign(effects.color, mood.ColorCorrection)
	effects.color.Enabled = true

	effects.bloom = ensure("BloomEffect", Lighting)
	assign(effects.bloom, mood.Bloom)
	effects.bloom.Enabled = true

	effects.rays = ensure("SunRaysEffect", Lighting)
	assign(effects.rays, mood.SunRays)
	effects.rays.Enabled = not low

	effects.dof = ensure("DepthOfFieldEffect", Lighting)

	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		effects.clouds = ensure("Clouds", terrain)
		assign(effects.clouds, mood.Clouds)
		effects.clouds.Enabled = mood.Clouds ~= nil
	end

	setMaterialOverrides(true)
	setServerLights(true)
	updateDof()
end

local function applyClassic()
	for key, value in original do
		pcall(function()
			(Lighting :: any)[key] = value
		end)
	end
	for _, inst in CollectionService:GetTagged(EFFECT_TAG) do
		if inst:IsA("PostEffect") or inst:IsA("Clouds") then
			inst.Enabled = false
		elseif inst:IsA("Atmosphere") then
			inst.Density = 0
			inst.Haze = 0
			inst.Glare = 0
		end
	end
	setMaterialOverrides(false)
	setServerLights(false)
end

local function apply()
	enabled = PlayerSettings.get("RealisticGraphics") ~= false
	if enabled then
		applyRealistic()
	else
		applyClassic()
	end
	setAimTracking(enabled and aiming)
end

function Graphics.init()
	for _, key in LIGHTING_KEYS do
		original[key] = (Lighting :: any)[key]
	end

	PlayerSettings.onChanged(function(key)
		if key == "RealisticGraphics" then
			apply()
		elseif key == "DepthBlur" then
			updateDof()
		end
	end)
	PlayerSettings.onAimingChanged(function(on)
		aiming = on
		setAimTracking(enabled and on)
		if not on then
			updateDof()
		end
	end)
	ReplicatedStorage:GetAttributeChangedSignal("MapId"):Connect(apply)

	-- Новый свет от сервера (фонари новой карты, фары машин) слушается текущего режима.
	CollectionService:GetInstanceAddedSignal(LIGHT_TAG):Connect(function(light)
		if light:IsA("Light") then
			light.Enabled = enabled and light:GetAttribute("LampOn") ~= false
		end
	end)

	apply()
end

return Graphics
