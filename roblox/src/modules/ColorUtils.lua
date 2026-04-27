--[[
    ColorUtils.lua — EduVerse Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > ColorUtils (ModuleScript)

    Converts CSS-style color strings (hex or named) to Roblox Color3 values.
    Named colors mirror common Tailwind / CSS names for designer-friendly usage.
]]

local ColorUtils = {}

-- Named color aliases → hex
local CSS_COLORS = {
    red     = "#FF4444", green   = "#44CC66", blue    = "#4488FF",
    yellow  = "#FFEE00", orange  = "#FF8800", purple  = "#9B59B6",
    white   = "#FFFFFF", cyan    = "#00FFFF", gold    = "#FFD700",
    magenta = "#FF00FF", coral   = "#FF7F50", lime    = "#32CD32",
    brown   = "#8B4513", gray    = "#808080", silver  = "#C0C0C0",
    pink    = "#FF69B4", teal    = "#008080", navy    = "#001F5B",
}

-- Convert a hex string or named alias to a Color3.
-- Falls back to mid-gray if the input is invalid.
function ColorUtils.fromHex(str)
    if not str or str == "" then return Color3.fromRGB(170, 170, 170) end
    local hex = CSS_COLORS[str:lower()] or str
    hex = hex:gsub("#", "")
    if #hex ~= 6 then return Color3.fromRGB(170, 170, 170) end
    local r = tonumber(hex:sub(1, 2), 16) or 170
    local g = tonumber(hex:sub(3, 4), 16) or 170
    local b = tonumber(hex:sub(5, 6), 16) or 170
    return Color3.fromRGB(r, g, b)
end

return ColorUtils
