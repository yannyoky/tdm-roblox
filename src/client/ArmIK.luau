-- Рука из двух костей для настоящих суставов персонажа R15 (как в Viewmodel).
-- Используют WeaponPose (руки на оружии), DriverPose (руки на руле) и BodyLife (рука тянется к предмету).
local ArmIK = {}

local v = Vector3.new
local rad = math.rad
local CF = CFrame.new
local ANG = CFrame.Angles

-- Сустав: Motor6D (C0/C1) у старых ригов или AnimationConstraint (Attachment0/1) у новых.
-- У обоих Part1 = Part0 * c0 * Transform * c1⁻¹.
export type Joint = { inst: Instance, c0: CFrame, c1: CFrame }

function ArmIK.joint(inst: Instance?): Joint?
	if inst and inst:IsA("Motor6D") then
		return { inst = inst, c0 = inst.C0, c1 = inst.C1 }
	elseif inst and inst:IsA("AnimationConstraint") and inst.Attachment0 and inst.Attachment1 then
		return { inst = inst, c0 = inst.Attachment0.CFrame, c1 = inst.Attachment1.CFrame }
	end
	return nil
end

export type Arm = {
	upper: BasePart,
	lower: BasePart,
	hand: BasePart,
	shoulder: Joint,
	elbow: Joint,
	wrist: Joint,
	shoulderU: Vector3,
	boneU: Vector3,
	elbowL: Vector3,
	boneL: Vector3, -- локоть→запястье в предплечье
	wristH: Vector3, -- запястье в кисти
	gripH: CFrame, -- точка хвата в кисти
	handOffset: CFrame, -- кисть относительно предплечья в исходной позе
	a: number,
	b: number,
}

function ArmIK.attCf(part: Instance, name: string, fallback: CFrame): CFrame
	local a = part:FindFirstChild(name)
	return if a and a:IsA("Attachment") then a.CFrame else fallback
end

function ArmIK.buildArm(char: Model, side: string): Arm?
	local upper = char:FindFirstChild(side .. "UpperArm")
	local lower = char:FindFirstChild(side .. "LowerArm")
	local hand = char:FindFirstChild(side .. "Hand")
	if not (upper and lower and hand and upper:IsA("BasePart") and lower:IsA("BasePart") and hand:IsA("BasePart")) then
		return nil
	end
	local shoulder = ArmIK.joint(upper:FindFirstChild(side .. "Shoulder"))
	local elbow = ArmIK.joint(lower:FindFirstChild(side .. "Elbow"))
	local wrist = ArmIK.joint(hand:FindFirstChild(side .. "Wrist"))
	if not (shoulder and elbow and wrist) then
		return nil
	end
	local shoulderU = ArmIK.attCf(upper, side .. "ShoulderRigAttachment", CF(0, 0.4, 0)).Position
	local elbowU = ArmIK.attCf(upper, side .. "ElbowRigAttachment", CF(0, -0.3, 0)).Position
	local elbowL = ArmIK.attCf(lower, side .. "ElbowRigAttachment", CF(0, 0.3, 0)).Position
	local wristL = ArmIK.attCf(lower, side .. "WristRigAttachment", CF(0, -0.45, 0)).Position
	local wristH = ArmIK.attCf(hand, side .. "WristRigAttachment", CF(0, 0.2, 0)).Position
	local gripH = ArmIK.attCf(hand, side .. "GripAttachment", CF(0, -0.1, 0) * ANG(rad(-90), 0, 0))
	return {
		upper = upper,
		lower = lower,
		hand = hand,
		shoulder = shoulder,
		elbow = elbow,
		wrist = wrist,
		shoulderU = shoulderU,
		boneU = elbowU - shoulderU,
		elbowL = elbowL,
		boneL = wristL - elbowL,
		wristH = wristH,
		gripH = gripH,
		handOffset = CF(wristL - wristH),
		a = (elbowU - shoulderU).Magnitude,
		b = (wristL - elbowL).Magnitude,
	}
end

function ArmIK.basis(bone: Vector3, ref: Vector3): CFrame
	local y = -bone.Unit
	local x = ref - y * ref:Dot(y)
	if x.Magnitude < 1e-3 then
		x = Vector3.zAxis:Cross(y)
	end
	return CFrame.fromMatrix(Vector3.zero, x.Unit, y)
end

-- Плечо и предплечье так, чтобы запястье оказалось в точке wrist. Возвращает CFrame деталей.
function ArmIK.solve(arm: Arm, shoulder: Vector3, wrist: Vector3, pole: Vector3, roll: Vector3): (CFrame, CFrame)
	local a, b = arm.a, arm.b
	local toT = wrist - shoulder
	local d = math.clamp(toT.Magnitude, math.abs(a - b) + 0.05, (a + b) * 0.999)
	local dir = if toT.Magnitude > 1e-4 then toT.Unit else v(0, 0, -1)
	local cosA = math.clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local perp = pole - dir * pole:Dot(dir)
	perp = if perp.Magnitude > 1e-4 then perp.Unit else v(0, -1, 0)
	local elbow = shoulder + dir * (a * cosA) + perp * (a * sinA)
	-- если не дотягивается, предплечье просто тянется в сторону цели
	local reach = elbow + (wrist - elbow).Unit * b
	local rU = ArmIK.basis(elbow - shoulder, roll) * ArmIK.basis(arm.boneU, Vector3.xAxis):Inverse()
	local upperCf = CF(shoulder - rU:VectorToWorldSpace(arm.shoulderU)) * rU
	local rL = ArmIK.basis(reach - elbow, roll) * ArmIK.basis(arm.boneL, Vector3.xAxis):Inverse()
	local lowerCf = CF(elbow - rL:VectorToWorldSpace(arm.elbowL)) * rL
	return upperCf, lowerCf
end

-- Transform сустава, чтобы деталь part1 встала в cf1 при детали part0 в cf0.
function ArmIK.setJoint(j: Joint, cf0: CFrame, cf1: CFrame, weight: number)
	local m = j.inst :: any
	local t = j.c0:Inverse() * cf0:Inverse() * cf1 * j.c1
	m.Transform = if weight >= 1 then t else m.Transform:Lerp(t, weight)
end

return ArmIK
