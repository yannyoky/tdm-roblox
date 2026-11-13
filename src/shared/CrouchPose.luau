-- Поза приседа для R15: сгибает бёдра, колени и голеностопы и слегка наклоняет корпус.
-- Сервер ставит позу, чтобы её видели все и чтобы хитбоксы опускались,
-- клиент ставит её у себя сразу, без задержки сети, и опускает HipHeight.
local CrouchPose = {}

local HIP = math.rad(70)
local KNEE = math.rad(-110)
local ANKLE = math.rad(40)
local WAIST = math.rad(-15)

local JOINTS = {
	{ part = "LeftUpperLeg", motor = "LeftHip", angle = HIP },
	{ part = "RightUpperLeg", motor = "RightHip", angle = HIP },
	{ part = "LeftLowerLeg", motor = "LeftKnee", angle = KNEE },
	{ part = "RightLowerLeg", motor = "RightKnee", angle = KNEE },
	{ part = "LeftFoot", motor = "LeftAnkle", angle = ANKLE },
	{ part = "RightFoot", motor = "RightAnkle", angle = ANKLE },
	{ part = "UpperTorso", motor = "Waist", angle = WAIST },
}

function CrouchPose.supported(char: Model): boolean
	return char:FindFirstChild("LowerTorso") ~= nil and char:FindFirstChild("LeftUpperLeg") ~= nil
end

-- На сколько опускается таз, чтобы ступни остались на земле.
function CrouchPose.drop(char: Model): number
	local upper = char:FindFirstChild("LeftUpperLeg") :: BasePart?
	local lower = char:FindFirstChild("LeftLowerLeg") :: BasePart?
	if not upper or not lower then
		return 0
	end
	local thigh, shin = upper.Size.Y, lower.Size.Y
	return thigh * (1 - math.cos(HIP)) + shin * (1 - math.cos(HIP + KNEE))
end

-- Включить или выключить позу. Исходные C0 запоминаются в атрибутах моторов.
function CrouchPose.set(char: Model, on: boolean)
	if not CrouchPose.supported(char) then
		return
	end
	for _, j in JOINTS do
		local part = char:FindFirstChild(j.part)
		local motor = part and part:FindFirstChild(j.motor)
		if motor and motor:IsA("Motor6D") then
			local base = motor:GetAttribute("BaseC0")
			if typeof(base) ~= "CFrame" then
				base = motor.C0
				motor:SetAttribute("BaseC0", base)
			end
			motor.C0 = if on then base * CFrame.Angles(j.angle, 0, 0) else base
		end
	end
	char:SetAttribute("Crouching", on)
end

return CrouchPose
