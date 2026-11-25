-- Сгенерированные персонажи: тело и голова одной моделью (Studio → Avatar → Build Avatar).
-- Модели лежат файлами в assets/characters/<Имя>.rbxm, Rojo кладёт их в
-- ReplicatedStorage.CharacterModels. Какое тело какой моделью — поле Model в
-- Config/Appearance (Options.Body). Пока файла нет, тело собирается из каталожных частей.
--
-- Лицо, причёска и цвет кожи у такой модели «впечены»: из внешности на неё идут только
-- очки, а одежда (3D-одежда и шляпы) переносится с модели, собранной по HumanoidDescription.
-- Сборка и одевание — только на сервере (CreateHumanoidModelFromDescription).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Appearance = require(script.Parent.Config.Appearance)

local GeneratedBody = {}

-- Атрибут на вещах, которые надела система внешности (их снимаем при переодевании).
local CLOTHES_ATTR = "LookClothes"
-- Атрибут на персонаже: id тела, из модели которого он собран.
GeneratedBody.ATTR = "GeneratedBody"

-- Модель-образец для тела или nil, если её нет в проекте.
function GeneratedBody.template(bodyId: string?): Model?
	local body = Appearance.option("Body", bodyId)
	local name = body and body.Model
	if not name then
		return nil
	end
	local folder = ReplicatedStorage:FindFirstChild("CharacterModels")
	if not folder then
		return nil
	end
	-- Имя файла без учёта регистра: male.rbxm и Male.rbxm — одно и то же.
	local wanted = string.lower(name)
	for _, child in folder:GetChildren() do
		if string.lower(child.Name) == wanted then
			-- Save to File может сохранить модель как Folder с моделью внутри.
			local model = if child:IsA("Model") then child else child:FindFirstChildWhichIsA("Model")
			if model and model:FindFirstChildOfClass("Humanoid") then
				return model
			end
		end
	end
	return nil
end

function GeneratedBody.has(bodyId: string?): boolean
	return GeneratedBody.template(bodyId) ~= nil
end

-- Для ботов и прохожих: по умолчанию у них каталожные тела, чтобы не были все на одно лицо.
function GeneratedBody.forNpc(bodyId: string?): boolean
	return Appearance.GeneratedForNpc == true and GeneratedBody.has(bodyId)
end

-- Переодеть персонажа: снять прошлую одежду и надеть вещи из описания.
-- Вещи берутся с временной модели, собранной по описанию: 3D-одежда сама
-- перетягивается по «клеткам» (WrapTarget) нового тела.
function GeneratedBody.dress(char: Model, desc: HumanoidDescription): boolean
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return false
	end
	local ok, dummy = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R15)
	if not ok or not dummy then
		warn("[GeneratedBody] Одежда не загрузилась: ", dummy)
		return false
	end
	for _, inst in char:GetChildren() do
		if inst:GetAttribute(CLOTHES_ATTR) then
			inst:Destroy()
		end
	end
	for _, inst in dummy:GetChildren() do
		if inst:IsA("Accessory") then
			local handle = inst:FindFirstChild("Handle")
			if handle then
				for _, joint in handle:GetChildren() do
					if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
						joint:Destroy()
					end
				end
			end
			inst:SetAttribute(CLOTHES_ATTR, true)
			inst.Parent = nil
			hum:AddAccessory(inst)
		elseif inst:IsA("Shirt") or inst:IsA("Pants") or inst:IsA("ShirtGraphic") then
			inst:SetAttribute(CLOTHES_ATTR, true)
			inst.Parent = char
		end
	end
	dummy:Destroy()
	return true
end

-- Новый персонаж из модели тела, одетый по описанию. nil — модели нет.
function GeneratedBody.build(bodyId: string?, desc: HumanoidDescription): Model?
	local template = GeneratedBody.template(bodyId)
	if not template then
		return nil
	end
	local model = template:Clone()
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored = false
		elseif inst:IsA("Script") or inst:IsA("LocalScript") then
			inst:Destroy() -- скрипты из генератора не нужны
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		model.PrimaryPart = root
	end
	model:SetAttribute(GeneratedBody.ATTR, bodyId)
	GeneratedBody.dress(model, desc)
	return model
end

return GeneratedBody
