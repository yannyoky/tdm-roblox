-- Собирает HumanoidDescription персонажа из внешности игрока (Look), скина стороны
-- (комплект 3D-одежды из Config/Skins) и вещей, которые игрок заменил (Outfit).
-- Вызывается только на сервере: ApplyDescription и LoadCharacterWithHumanoidDescription
-- клиенту недоступны.
local Appearance = require(script.Parent.Config.Appearance)
local Skins = require(script.Parent.Config.Skins)

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
	if type(look.Tone) == "number" and look.Tone == math.floor(look.Tone) and look.Tone >= 1 and look.Tone <= #Appearance.Tones then
		clean.Tone = look.Tone
	end
	-- Тело: только одно из двух. Старые сохранения («avatar», кубические тела) — мужское.
	local body = type(look.Body) == "string" and Appearance.option("Body", look.Body)
	if body then
		clean.Body = body.Id
	end
	local gender = Appearance.genderOf(clean.Body)
	local defaults = Appearance.GenderDefaults[gender]
	for key, value in defaults do
		clean[key] = value
	end
	for _, slot in Appearance.LookSlots do
		local value = look[slot.Key]
		local opt = type(value) == "string" and Appearance.option(slot.Key, value)
		if opt and Appearance.fits(opt, gender) and (slot.Gender == nil or slot.Gender == gender) then
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

-- Персонаж собирается с нуля: аватар игрока Roblox не используется.
-- faction = nil — лобби: простая одежда из Appearance.LobbyOutfit.
-- skinId — скин стороны: его вещи надеваются в слоты, где игрок оставил «как в скине».
function AppearanceApply.describe(
	look: { [string]: any },
	faction: string?,
	outfit: { [string]: string }?,
	skinId: string?
): HumanoidDescription
	look = AppearanceApply.sanitizeLook(look)
	local desc = Instance.new("HumanoidDescription")

	for _, prop in EXTRA_PROPS do
		(desc :: any)[prop] = ""
	end
	for _, prop in ANIM_PROPS do
		(desc :: any)[prop] = 0
	end

	-- Тело (меши частей тела одного из двух реалистичных тел).
	local body = Appearance.option("Body", look.Body) or Appearance.Options.Body[1]
	for _, part in BODY_PARTS do
		(desc :: any)[part] = body.Parts[part] or 0
	end

	-- Голова и лицо.
	local head = Appearance.option("Head", look.Head) or Appearance.option("Head", body.Head)
	if head then
		desc.Head = head.Asset or 0
		desc.Face = 0
	end

	-- Цвет кожи. У головы с кожей в текстуре (SkinTone) тело красится под голову.
	local tone = (head and head.SkinTone) or Appearance.Tones[look.Tone] or Appearance.Tones[Appearance.DefaultLook.Tone]
	for _, prop in COLOR_PROPS do
		(desc :: any)[prop] = tone
	end

	-- Причёска.
	local hair = Appearance.option("Hair", look.Hair)
	desc.HairAccessory = if hair and hair.Asset then tostring(hair.Asset) else ""

	-- Борода и очки — оба в слоте лица.
	local faceItems = {}
	for _, key in { "Beard", "Glasses" } do
		local opt = Appearance.option(key, look[key])
		if opt and opt.Asset then
			table.insert(faceItems, tostring(opt.Asset))
		end
	end

	do
		-- Одежда: в бою — форма стороны и выбранные вещи, в лобби — простой комплект.
		desc.Shirt = 0
		desc.Pants = 0
		desc.GraphicTShirt = 0
		desc.HatAccessory = ""
		local layered = {}
		local preset
		if not faction then
			faction = Appearance.LobbyOutfit.Faction
			preset = Appearance.LobbyOutfit
			outfit = nil
		else
			local skin = skinId and Skins.List[skinId]
			preset = if skin and skin.Faction == faction then skin.Outfit or {} else {}
		end
		local pieces = Appearance.Clothing[faction] or {}
		for _, slot in Appearance.ClothingSlots do
			local choice = outfit and outfit[slot.Key]
			if choice == nil or choice == Appearance.UNIFORM then
				choice = preset[slot.Key]
			end
			local piece = Appearance.findIn(pieces[slot.Key], choice)
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

-- Случайная внешность для бота.
function AppearanceApply.randomLook(): { [string]: any }
	local gender = if math.random() < 0.8 then "M" else "F"
	local look = { Tone = math.random(#Appearance.Tones) }
	for _, opt in Appearance.Options.Body do
		if opt.Gender == gender then
			look.Body = opt.Id
		end
	end
	for _, slot in Appearance.LookSlots do
		local pool = Appearance.optionsFor(slot.Key, gender)
		look[slot.Key] = if #pool > 0 then pool[math.random(#pool)].Id else Appearance.DefaultLook[slot.Key]
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
		-- Чаще всего бот носит комплект скина целиком, иногда меняет одну-две вещи.
		outfit[slot.Key] = if #list > 0 and math.random() < 0.3 then list[math.random(#list)].Id else Appearance.UNIFORM
	end
	return outfit
end

return AppearanceApply
