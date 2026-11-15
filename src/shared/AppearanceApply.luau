-- Собирает HumanoidDescription персонажа из внешности игрока (Look) и одежды стороны (Outfit).
-- Вызывается только на сервере: ApplyDescription и LoadCharacterWithHumanoidDescription
-- клиенту недоступны. Форма стороны (цвета, снаряжение Gear_*) надевается после этого через SkinApply.
local Appearance = require(script.Parent.Config.Appearance)

local AppearanceApply = {}

local BODY_PARTS = { "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local COLOR_PROPS = { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }
-- Аксессуары аватара, которые в бою не нужны: крылья, сумки, хвосты, шарфы.
local EXTRA_PROPS = { "BackAccessory", "WaistAccessory", "ShouldersAccessory", "FrontAccessory", "NeckAccessory" }
-- Анимации из аватара не берём: движения у всех одинаковые (Config/Character.Animations).
local ANIM_PROPS = { "IdleAnimation", "WalkAnimation", "RunAnimation", "JumpAnimation", "FallAnimation", "ClimbAnimation", "SwimAnimation" }
-- Порядок слоёв 3D-одежды: чем больше, тем ближе к поверхности.
local LAYER_ORDER = { TShirt = 1, Shirt = 2, Pants = 3, Shorts = 3, DressSkirt = 3, Sweater = 4, Jacket = 5, LeftShoe = 6, RightShoe = 6 }

-- Пропорции тела (реалистичные, общий рост для всех) задаёт CharacterLook.
local CharacterLook = require(script.Parent.CharacterLook)

local function accessoryType(name: string): Enum.AccessoryType?
	local ok, item = pcall(function()
		return (Enum.AccessoryType :: any)[name]
	end)
	return if ok then item else nil
end

-- Убрать из look/outfit всё, чего нет в конфиге. Возвращает новые таблицы.
function AppearanceApply.sanitizeLook(look: any): { [string]: any }
	local clean = table.clone(Appearance.DefaultLook)
	if type(look) ~= "table" then
		return clean
	end
	if type(look.Tone) == "number" and look.Tone == math.floor(look.Tone) and look.Tone >= 0 and look.Tone <= #Appearance.Tones then
		clean.Tone = look.Tone
	end
	for _, slot in Appearance.LookSlots do
		local value = look[slot.Key]
		if type(value) == "string" and Appearance.option(slot.Key, value) then
			clean[slot.Key] = value
		end
	end
	return clean
end

function AppearanceApply.sanitizeOutfit(faction: string, outfit: any): { [string]: string }
	local clean = {}
	local pieces = Appearance.Clothing[faction]
	for _, slot in Appearance.ClothingSlots do
		local value = type(outfit) == "table" and outfit[slot.Key]
		local ok = type(value) == "string" and pieces and Appearance.findIn(pieces[slot.Key], value)
		clean[slot.Key] = if ok then value else Appearance.UNIFORM
	end
	return clean
end

-- Выбрана ли своя шапка вместо головного убора формы.
function AppearanceApply.hasOwnHat(outfit: { [string]: string }?): boolean
	return outfit ~= nil and outfit.Hat ~= nil and outfit.Hat ~= Appearance.UNIFORM
end

-- base — описание аватара игрока (или nil). faction = nil — лобби: своя одежда аватара остаётся.
function AppearanceApply.describe(base: HumanoidDescription?, look: { [string]: any }, faction: string?, outfit: { [string]: string }?): HumanoidDescription
	local desc = if base then base:Clone() else Instance.new("HumanoidDescription")

	for _, prop in EXTRA_PROPS do
		(desc :: any)[prop] = ""
	end
	for _, prop in ANIM_PROPS do
		(desc :: any)[prop] = 0
	end

	-- Цвет кожи.
	local tone = Appearance.Tones[look.Tone or 0]
	if tone then
		for _, prop in COLOR_PROPS do
			(desc :: any)[prop] = tone
		end
	end

	-- Телосложение (меши частей тела).
	local body = Appearance.option("Body", look.Body)
	if body and body.Parts then
		for _, part in BODY_PARTS do
			(desc :: any)[part] = body.Parts[part] or 0
		end
	end

	-- Голова и лицо.
	local head = Appearance.option("Head", look.Head)
	if head and head.Id ~= Appearance.AVATAR then
		desc.Head = head.Asset or 0
		desc.Face = head.Face or 0
	end

	-- Причёска.
	local hair = Appearance.option("Hair", look.Hair)
	if hair and hair.Id ~= Appearance.AVATAR then
		desc.HairAccessory = if hair.Asset then tostring(hair.Asset) else ""
	end

	-- Борода и очки — оба в слоте лица.
	local faceItems = {}
	for _, key in { "Beard", "Glasses" } do
		local opt = Appearance.option(key, look[key])
		if opt and opt.Asset then
			table.insert(faceItems, tostring(opt.Asset))
		end
	end

	if faction then
		-- В бою одежда аватара заменяется формой стороны и выбранными вещами.
		desc.Shirt = 0
		desc.Pants = 0
		desc.GraphicTShirt = 0
		desc.HatAccessory = ""
		local layered = {}
		local pieces = Appearance.Clothing[faction] or {}
		for _, slot in Appearance.ClothingSlots do
			local piece = outfit and Appearance.findIn(pieces[slot.Key], outfit[slot.Key])
			if piece and piece.Hat then
				desc.HatAccessory = tostring(piece.Hat)
			end
			if piece and piece.Face then
				table.insert(faceItems, tostring(piece.Face))
			end
			for _, item in (piece and piece.Layers) or {} do
				local kind = accessoryType(item.Type)
				if kind then
					table.insert(layered, {
						AssetId = item.Id,
						AccessoryType = kind,
						IsLayered = true,
						Order = LAYER_ORDER[item.Type] or 3,
					})
				end
			end
		end
		pcall(function()
			desc:SetAccessories(layered, false)
		end)
	end

	desc.FaceAccessory = table.concat(faceItems, ",")
	CharacterLook.applyToDescription(desc)
	return desc
end

-- Пометить аксессуары, надетые по описанию, чтобы SkinApply их не снимал.
function AppearanceApply.tag(model: Model)
	for _, inst in model:GetChildren() do
		if inst:IsA("Accessory") then
			inst:SetAttribute("Look", true)
		end
	end
end

-- Случайная внешность для бота.
function AppearanceApply.randomLook(): { [string]: any }
	local gender = if math.random() < 0.8 then "M" else "F"
	local look = { Tone = math.random(#Appearance.Tones) }
	for _, slot in Appearance.LookSlots do
		local pool = {}
		for _, opt in Appearance.Options[slot.Key] do
			if opt.Id ~= Appearance.AVATAR and (opt.Gender == nil or opt.Gender == gender) then
				table.insert(pool, opt.Id)
			end
		end
		look[slot.Key] = if #pool > 0 then pool[math.random(#pool)] else Appearance.DefaultLook[slot.Key]
	end
	if gender == "F" or math.random() < 0.4 then
		look.Beard = "none"
	end
	if math.random() < 0.6 then
		look.Glasses = "none"
	end
	return look
end

function AppearanceApply.randomOutfit(faction: string): { [string]: string }
	local outfit = {}
	local pieces = Appearance.Clothing[faction] or {}
	for _, slot in Appearance.ClothingSlots do
		local list = pieces[slot.Key] or {}
		outfit[slot.Key] = if #list > 0 and math.random() < 0.7 then list[math.random(#list)].Id else Appearance.UNIFORM
	end
	return outfit
end

return AppearanceApply
