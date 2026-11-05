-- Физика персонажей: группа столкновений и рэгдолл при смерти.
local PhysicsService = game:GetService("PhysicsService")

local CHARACTER_GROUP = "Characters"

local PhysicsSetup = {}

function PhysicsSetup.init()
	PhysicsService:RegisterCollisionGroup(CHARACTER_GROUP)
	-- Бойцы не толкают и не блокируют друг друга телами, но сталкиваются с миром.
	PhysicsService:CollisionGroupSetCollidable(CHARACTER_GROUP, CHARACTER_GROUP, false)
end

local function setGroup(inst: Instance)
	if inst:IsA("BasePart") then
		inst.CollisionGroup = CHARACTER_GROUP
	end
end

-- Вызывается при каждом появлении персонажа (игрока или бота).
function PhysicsSetup.prepareCharacter(char: Model)
	for _, inst in char:GetDescendants() do
		setGroup(inst)
	end
	char.DescendantAdded:Connect(setGroup)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		-- Суставы не рвутся при смерти: вместо этого тело обмякает (рэгдолл).
		hum.BreakJointsOnDeath = false
	end
end

-- Рэгдолл: моторы суставов заменяются шарнирами с ограничениями.
function PhysicsSetup.ragdoll(char: Model)
	for _, motor in char:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 50
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -40
			socket.TwistUpperAngle = 40
			socket.Parent = motor.Part0
			motor.Enabled = false
		end
	end
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = part.Name ~= "HumanoidRootPart"
		end
	end
end

return PhysicsSetup
