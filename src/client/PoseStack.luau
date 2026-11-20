-- Общий стек процедурных поз поверх анимаций.
-- Несколько систем (Locomotion, BodyLife, DriverPose, WeaponPose) добавляют к одному и тому же
-- суставу свои повороты. Чтобы они не затирали друг друга и не «накручивались» кадр за кадром:
--   * в начале кадра стек запоминает позу анимации каждого сустава (base);
--   * каждая система добавляет поворот: Transform = pre₂ · pre₁ · base · post₁ · post₂;
--   * если в кадре сустав никто не тронул, ему возвращается поза анимации.
-- Все системы выполняются по очереди в одном Stepped (после анимаций, до физики) в порядке order.
local RunService = game:GetService("RunService")

local PoseStack = {}

type Rec = {
	inst: any,
	base: CFrame,
	written: CFrame?,
	frame: number,
	pre: CFrame,
	post: CFrame,
}

local recs: { [Instance]: Rec } = setmetatable({}, { __mode = "k" }) :: any
local frame = 0

-- Добавить поворот к суставу (Motor6D или AnimationConstraint). post — в системе сустава
-- после позы анимации (поворот самой детали), pre — до неё (поворот всего, что ниже по цепочке).
-- Возвращает итоговый Transform сустава на этот кадр.
function PoseStack.add(inst: Instance, post: CFrame?, pre: CFrame?): CFrame
	local r = recs[inst]
	if not r then
		r = { inst = inst, base = (inst :: any).Transform, written = nil, frame = -1, pre = CFrame.identity, post = CFrame.identity }
		recs[inst] = r
	end
	if r.frame ~= frame then
		local current: CFrame = r.inst.Transform
		-- Анимация в этом кадре переписала сустав — это новая поза анимации.
		-- Если не переписала, в Transform лежит наше значение: берём сохранённую позу.
		if r.written == nil or current ~= r.written then
			r.base = current
		end
		r.frame = frame
		r.pre = CFrame.identity
		r.post = CFrame.identity
	end
	if post then
		r.post = r.post * post
	end
	if pre then
		r.pre = pre * r.pre
	end
	local t = r.pre * r.base * r.post
	r.inst.Transform = t
	r.written = t
	return t
end

-- Текущий Transform сустава с учётом уже добавленного в этом кадре (или поза анимации).
function PoseStack.get(inst: Instance): CFrame
	local r = recs[inst]
	if r and r.frame == frame and r.written then
		return r.written
	end
	return (inst :: any).Transform
end

-- Поза анимации этого кадра (без наших добавок).
function PoseStack.base(inst: Instance): CFrame
	local r = recs[inst]
	if r and r.frame == frame then
		return r.base
	end
	if r and r.written and (inst :: any).Transform == r.written then
		return r.base
	end
	return (inst :: any).Transform
end

-- Сустав переписан целиком (например, IK рук): стек больше не считает его своим.
function PoseStack.forget(inst: Instance)
	recs[inst] = nil
end

-- Системы позы: fn(dt) вызывается каждый кадр в порядке order (меньше — раньше).
local layers: { { order: number, fn: (number) -> () } } = {}
local started = false
local warned: { [string]: boolean } = {}

function PoseStack.layer(order: number, fn: (dt: number) -> ())
	table.insert(layers, { order = order, fn = fn })
	table.sort(layers, function(a, b)
		return a.order < b.order
	end)
	if started then
		return
	end
	started = true
	RunService.Stepped:Connect(function(_, dt)
		frame += 1
		dt = math.clamp(dt, 1 / 240, 0.1)
		for _, l in layers do
			local ok, err = pcall(l.fn, dt)
			if not ok and not warned[tostring(err)] then
				warned[tostring(err)] = true
				warn("[PoseStack] " .. tostring(err))
			end
		end
		-- Суставы, которые в этом кадре никто не тронул, возвращаем позе анимации.
		for inst, r in recs do
			if r.frame ~= frame then
				if r.written and inst.Parent and r.inst.Transform == r.written then
					r.inst.Transform = r.base
				end
				recs[inst] = nil
			end
		end
	end)
end

-- Повторить позу сустава после физики, если её кто-то перезаписал (сидящий в машине персонаж:
-- поза таза приходит заново уже после Stepped).
function PoseStack.reapply(inst: Instance)
	local r = recs[inst]
	if not r or r.frame ~= frame or not r.written then
		return
	end
	local current: CFrame = r.inst.Transform
	if current ~= r.written then
		r.base = current
		local t = r.pre * r.base * r.post
		r.inst.Transform = t
		r.written = t
	end
end

-- Номер кадра (для систем, которым нужно понять, считали ли они уже в этом кадре).
function PoseStack.frame(): number
	return frame
end

return PoseStack
