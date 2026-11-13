-- Общие помощники интерфейса: цвета, кнопки, надписи и окно с заголовком.
local Ui = {}

Ui.Colors = {
	Panel = Color3.fromRGB(20, 20, 26),
	Card = Color3.fromRGB(38, 38, 48),
	Button = Color3.fromRGB(45, 45, 55),
	Accent = Color3.fromRGB(230, 170, 50),
	Good = Color3.fromRGB(60, 140, 80),
	Bad = Color3.fromRGB(170, 50, 45),
	Locked = Color3.fromRGB(30, 30, 34),
	White = Color3.new(1, 1, 1),
	Grey = Color3.fromRGB(190, 190, 200),
}

function Ui.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			(inst :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.corner(radius: number?): UICorner
	return Ui.make("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

function Ui.padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return Ui.make("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function Ui.label(props: { [string]: any }): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		TextColor3 = Ui.Colors.White,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextStrokeTransparency = 0.7,
		Text = "",
	}
	for key, value in props do
		base[key] = value
	end
	return Ui.make("TextLabel", base)
end

function Ui.button(text: string, props: { [string]: any }?): TextButton
	local base: { [string]: any } = {
		BackgroundColor3 = Ui.Colors.Button,
		TextColor3 = Ui.Colors.White,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = text,
		AutoButtonColor = true,
	}
	for key, value in props or {} do
		base[key] = value
	end
	local b = Ui.make("TextButton", base, {
		Ui.corner(6),
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }),
	})
	return b
end

-- Окно по центру экрана: заголовок, кнопка «×» и прокручиваемое содержимое со списком.
-- Возвращает (окно, содержимое, кнопка закрытия).
function Ui.window(title: string, size: UDim2): (Frame, ScrollingFrame, TextButton)
	local frame = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = Ui.Colors.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 10,
	}, {
		Ui.corner(10),
		Ui.make("UISizeConstraint", { MaxSize = Vector2.new(size.X.Offset > 0 and size.X.Offset or 900, 2000) }),
	})
	Ui.label({
		Position = UDim2.new(0, 14, 0, 8),
		Size = UDim2.new(1, -70, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
		ZIndex = 11,
		Parent = frame,
	})
	local close = Ui.button("×", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.new(0, 34, 0, 30),
		BackgroundColor3 = Ui.Colors.Bad,
		ZIndex = 11,
		Parent = frame,
	})
	local content = Ui.make("ScrollingFrame", {
		Position = UDim2.new(0, 0, 0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		BackgroundTransparency = 1,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
		ZIndex = 11,
		Parent = frame,
	}, {
		Ui.make("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 16),
		}),
		Ui.make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	return frame, content, close
end

function Ui.formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Ui
