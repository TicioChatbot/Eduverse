--[[
    LabelEngine.lua — EduVerse Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > LabelEngine (ModuleScript)

    Responsible for the visual labels attached to every workshop object.

    Two-tier label system:
      • TITLE — small, compact, always visible from a generous distance.
      • DESC  — larger educational tooltip, hidden until the player approaches.

    Why this lives in its own module:
      The previous renderer-side `createLabel` function created billboards
      with sizes proportional to the object size, which produced massive
      overlapping signs in the gallery. Centralising label rules here means:
        - One source of truth for typography, spacing, MaxDistance.
        - Renderers only call LabelEngine.attach(...).
        - Future skinning (themes, accessibility) lives in one place.

    Public API:
        LabelEngine.attach(objData, anchorPart, color)
            objData    : table  { name, label, description, ... }
            anchorPart : BasePart that the billboards attach to
            color      : Color3 used for the title accent
            returns    : { title = BillboardGui, desc = BillboardGui? }
]]

local LabelEngine = {}

-- ── Tunables (single source of truth) ────────────────────────────────────────
local CFG = {
    TITLE_WIDTH_STUDS    = 6,    -- billboard width (uniform)
    TITLE_HEIGHT_STUDS   = 1.6,
    TITLE_MAX_DISTANCE   = 90,   -- always visible from far
    TITLE_FONT           = Enum.Font.GothamBold,
    TITLE_TEXT_SIZE      = 18,

    DESC_WIDTH_STUDS     = 9,
    DESC_HEIGHT_STUDS    = 4,
    DESC_MAX_DISTANCE    = 22,   -- only shows when player is close
    DESC_FONT            = Enum.Font.Gotham,
    DESC_TEXT_SIZE       = 14,

    BG_TITLE             = Color3.fromRGB(10, 16, 38),
    BG_DESC              = Color3.fromRGB(8, 14, 32),
    BG_TRANSPARENCY      = 0.18,
    STROKE_THICKNESS     = 1.4,

    OFFSET_GAP           = 1.2,  -- studs between part top and title
    DESC_GAP             = 0.6,  -- studs between title and description
}

-- Build a small UI corner+stroke combo for the billboards.
local function decorate(frame, accent)
    local corner = Instance.new("UICorner", frame)
    corner.CornerRadius = UDim.new(0.18, 0)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = accent
    stroke.Thickness = CFG.STROKE_THICKNESS
    stroke.Transparency = 0.25
end

local function makeBillboard(parent, sizeXStuds, sizeYStuds, studsOffsetY, maxDist, name)
    local bb = Instance.new("BillboardGui", parent)
    bb.Name           = name
    bb.Size           = UDim2.new(sizeXStuds, 0, sizeYStuds, 0)
    bb.StudsOffset    = Vector3.new(0, studsOffsetY, 0)
    bb.MaxDistance    = maxDist
    bb.LightInfluence = 0
    bb.AlwaysOnTop    = false
    return bb
end

local function makeTextLabel(parent, text, font, textSize, color)
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size                   = UDim2.new(1, -10, 1, -6)
    lbl.Position               = UDim2.new(0, 5, 0, 3)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = text
    lbl.TextColor3             = color
    lbl.Font                   = font
    lbl.TextSize               = textSize
    lbl.TextScaled             = false
    lbl.TextWrapped            = true
    lbl.TextXAlignment         = Enum.TextXAlignment.Center
    lbl.TextYAlignment         = Enum.TextYAlignment.Center
    return lbl
end

-- ── Public API ───────────────────────────────────────────────────────────────
function LabelEngine.attach(objData, anchorPart, color)
    if not anchorPart or not anchorPart:IsA("BasePart") then return nil end

    local title = objData.label or objData.name or "?"
    local desc  = objData.description or ""
    local partH = anchorPart.Size.Y

    -- Title billboard (always visible, compact)
    local titleY  = partH / 2 + CFG.OFFSET_GAP
    local titleBB = makeBillboard(
        anchorPart,
        CFG.TITLE_WIDTH_STUDS, CFG.TITLE_HEIGHT_STUDS,
        titleY, CFG.TITLE_MAX_DISTANCE, "EduTitle"
    )
    local titleFrame = Instance.new("Frame", titleBB)
    titleFrame.Size                   = UDim2.new(1, 0, 1, 0)
    titleFrame.BackgroundColor3       = CFG.BG_TITLE
    titleFrame.BackgroundTransparency = CFG.BG_TRANSPARENCY
    titleFrame.BorderSizePixel        = 0
    decorate(titleFrame, color)
    makeTextLabel(titleFrame, title, CFG.TITLE_FONT, CFG.TITLE_TEXT_SIZE, color)

    if desc == "" then
        return { title = titleBB }
    end

    -- Description billboard (proximity only)
    local descY  = titleY + CFG.TITLE_HEIGHT_STUDS + CFG.DESC_GAP
    local descBB = makeBillboard(
        anchorPart,
        CFG.DESC_WIDTH_STUDS, CFG.DESC_HEIGHT_STUDS,
        descY, CFG.DESC_MAX_DISTANCE, "EduDesc"
    )
    local descFrame = Instance.new("Frame", descBB)
    descFrame.Size                   = UDim2.new(1, 0, 1, 0)
    descFrame.BackgroundColor3       = CFG.BG_DESC
    descFrame.BackgroundTransparency = CFG.BG_TRANSPARENCY
    descFrame.BorderSizePixel        = 0
    decorate(descFrame, Color3.new(1, 1, 1))
    local descLbl = makeTextLabel(
        descFrame, desc, CFG.DESC_FONT, CFG.DESC_TEXT_SIZE,
        Color3.fromRGB(235, 240, 255)
    )
    descLbl.TextXAlignment = Enum.TextXAlignment.Left
    descLbl.TextYAlignment = Enum.TextYAlignment.Top
    descLbl.TextWrapped    = true

    return { title = titleBB, desc = descBB }
end

return LabelEngine
