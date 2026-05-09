--[[
    SignBoard.lua
    A reusable component to create educational boards that can either
    follow the camera (Billboard) or be fixed to a surface (SurfaceGui).
]]

local SignBoard = {}

local COLORS = {
    dark = Color3.fromRGB(8, 16, 42),
    panel = Color3.fromRGB(16, 28, 68),
    border = Color3.fromRGB(90, 150, 255),
}

function SignBoard.create(parentPart, options)
    options = options or {}
    local isFixed = options.isFixed or false
    local title = options.title or "Información"
    local text = options.text or ""
    
    local gui
    if isFixed then
        gui = Instance.new("SurfaceGui")
        gui.Face = options.face or Enum.NormalId.Front
        gui.CanvasSize = Vector2.new(800, 600)
    else
        gui = Instance.new("BillboardGui")
        gui.Size = UDim2.new(options.width or 10, 0, options.height or 5, 0)
        gui.StudsOffset = options.offset or Vector3.new(0, 5, 0)
        gui.AlwaysOnTop = true
    end
    
    gui.LightInfluence = 0
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    gui.Parent = parentPart

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = COLORS.dark
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0.08, 0)

    local stroke = Instance.new("UIStroke")
    stroke.Color = COLORS.border
    stroke.Thickness = 2
    stroke.Transparency = 0.2
    stroke.Parent = frame

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(0.9, 0, 0.25, 0)
    titleLabel.Position = UDim2.new(0.05, 0, 0.05, 0)
    titleLabel.Text = title:upper()
    titleLabel.TextColor3 = COLORS.border
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 24
    titleLabel.Parent = frame

    local contentLabel = Instance.new("TextLabel")
    contentLabel.Size = UDim2.new(0.9, 0, 0.6, 0)
    contentLabel.Position = UDim2.new(0.05, 0, 0.35, 0)
    contentLabel.Text = text
    contentLabel.TextColor3 = Color3.new(1, 1, 1)
    contentLabel.BackgroundTransparency = 1
    contentLabel.Font = Enum.Font.GothamMedium
    contentLabel.TextSize = 32
    contentLabel.TextWrapped = true
    contentLabel.Parent = frame

    return {
        gui = gui,
        update = function(newText)
            contentLabel.Text = newText
        end
    }
end

return SignBoard
