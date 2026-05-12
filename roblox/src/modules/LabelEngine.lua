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
-- v13: PIXEL-sized billboards instead of stud-sized.
--   Stud-sized billboards scale with distance: at 12 studs they fill the
--   screen, at 50 studs they're a tiny dot. Truncation appears because text
--   wrap is computed on stud size, not pixel size.
--   Pixel-sized billboards stay the same screen size regardless of distance.
--   Combined with a fixed TextSize, text is always readable and never
--   truncates. SizeOffset/StudsOffset still position the billboard in 3D.
local CFG = {
    TITLE_W_PX           = 200,
    TITLE_H_PX           = 32,
    TITLE_MAX_DISTANCE   = 90,
    TITLE_FONT           = Enum.Font.GothamBold,
    TITLE_TEXT_SIZE      = 15,

    DESC_W_PX            = 340,
    DESC_H_PX            = 130,
    DESC_MAX_DISTANCE    = 14,
    DESC_FONT            = Enum.Font.Gotham,
    DESC_TEXT_SIZE       = 14,

    BG_TITLE             = Color3.fromRGB(10, 16, 38),
    BG_DESC              = Color3.fromRGB(8, 14, 32),
    BG_TRANSPARENCY      = 0.10,
    STROKE_THICKNESS     = 1.2,

    OFFSET_GAP           = 1.8,
    DESC_GAP             = 0.4,
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

local function makeBillboard(parent, sizeWpx, sizeHpx, studsOffsetY, maxDist, name)
    local bb = Instance.new("BillboardGui", parent)
    bb.Name           = name
    -- Pixel-sized: stays the same on-screen regardless of distance.
    bb.Size           = UDim2.fromOffset(sizeWpx, sizeHpx)
    bb.StudsOffset    = Vector3.new(0, studsOffsetY, 0)
    bb.MaxDistance    = maxDist
    bb.LightInfluence = 0
    bb.AlwaysOnTop    = false
    return bb
end

local function makeTextLabel(parent, text, font, color, textSize)
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size                   = UDim2.new(1, -16, 1, -10)
    lbl.Position               = UDim2.new(0, 8, 0, 5)
    lbl.BackgroundTransparency = 1
    lbl.Text                   = text
    lbl.TextColor3             = color
    lbl.Font                   = font
    -- v13: BillboardGui sized in PIXELS (UDim2.fromOffset), TextSize fixed.
    -- Pixel sizing means the box is the same on screen no matter how close
    -- you stand → no more giant labels when you walk up to an object, and
    -- no truncation because the wrap budget is the actual screen size.
    lbl.TextSize               = textSize or 16
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
        CFG.TITLE_W_PX, CFG.TITLE_H_PX,
        titleY, CFG.TITLE_MAX_DISTANCE, "EduTitle"
    )
    local titleFrame = Instance.new("Frame", titleBB)
    titleFrame.Size                   = UDim2.new(1, 0, 1, 0)
    titleFrame.BackgroundColor3       = CFG.BG_TITLE
    titleFrame.BackgroundTransparency = CFG.BG_TRANSPARENCY
    titleFrame.BorderSizePixel        = 0
    decorate(titleFrame, color)
    makeTextLabel(titleFrame, title, CFG.TITLE_FONT, color, CFG.TITLE_TEXT_SIZE)

    if desc == "" then
        return { title = titleBB }
    end

    -- Description billboard (proximity only). StudsOffset stays in studs
    -- because it positions the billboard above the part in world space; only
    -- the on-screen Size is pixel-based.
    local descY  = titleY + 1.4 + CFG.DESC_GAP
    local descBB = makeBillboard(
        anchorPart,
        CFG.DESC_W_PX, CFG.DESC_H_PX,
        descY, CFG.DESC_MAX_DISTANCE, "EduDesc"
    )
    local descFrame = Instance.new("Frame", descBB)
    descFrame.Size                   = UDim2.new(1, 0, 1, 0)
    descFrame.BackgroundColor3       = CFG.BG_DESC
    descFrame.BackgroundTransparency = CFG.BG_TRANSPARENCY
    descFrame.BorderSizePixel        = 0
    decorate(descFrame, Color3.new(1, 1, 1))
    local descLbl = makeTextLabel(
        descFrame, desc, CFG.DESC_FONT, Color3.fromRGB(235, 240, 255), CFG.DESC_TEXT_SIZE
    )
    descLbl.TextXAlignment = Enum.TextXAlignment.Left
    descLbl.TextYAlignment = Enum.TextYAlignment.Top
    descLbl.TextWrapped    = true

    return { title = titleBB, desc = descBB }
end

return LabelEngine
