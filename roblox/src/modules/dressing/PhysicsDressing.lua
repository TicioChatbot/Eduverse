--[[
    PhysicsDressing.lua — industrial/warehouse vibe for physics, atom,
    solar_system, building. Used most by obby_tower.

    Builds:
      • Concrete-like wide floor base
      • Vertical I-beam columns at the corners (dark metal)
      • Caution stripes on the floor edges
      • Spotlights pointing up to highlight the tower
]]

local PhysicsDressing = {}

local SCENE_CENTER = Vector3.new(0, 0, -90)

local function makePart(folder, name, position, size, color, material)
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.Size = size
    part.Position = position
    part.Color = color
    part.Material = material or Enum.Material.SmoothPlastic
    part.Parent = folder
    return part
end

function PhysicsDressing.apply(folder, ctx)
    local dressing = Instance.new("Folder")
    dressing.Name = "PhysicsDressing"
    dressing.Parent = folder

    local isTower = ctx and ctx.interaction_template == "obby_tower"

    -- Wide concrete floor base.
    local base = makePart(dressing, "PhysicsBase",
        SCENE_CENTER + Vector3.new(0, -1.8, 0),
        Vector3.new(140, 1.0, 110),
        Color3.fromRGB(80, 85, 92),
        Enum.Material.Concrete)
    base.CanCollide = true

    -- Caution stripe perimeter (yellow + black slabs).
    -- Skipped on tower (you're 20+ studs up; floor stripes are not visible
    -- and the corner I-beams visually clash with the answer pads).
    if not isTower then
        local stripeY = -1.1
        local stripeColor = Color3.fromRGB(245, 200, 50)
        local darkColor = Color3.fromRGB(35, 35, 35)
        local function stripeRow(name, position, size, color)
            makePart(dressing, name, position, size, color, Enum.Material.SmoothPlastic)
        end
        for sideZ = -55, 55, 110 do
            for i = -6, 6 do
                local x = i * 11
                local color = (i % 2 == 0) and stripeColor or darkColor
                stripeRow("CautionStripeBack_" .. sideZ .. "_" .. i,
                    SCENE_CENTER + Vector3.new(x, stripeY, sideZ),
                    Vector3.new(10, 0.2, 1.5), color)
            end
        end
        for sideX = -69, 69, 138 do
            for i = -4, 4 do
                local z = i * 11
                local color = (i % 2 == 0) and stripeColor or darkColor
                stripeRow("CautionStripeSide_" .. sideX .. "_" .. i,
                    SCENE_CENTER + Vector3.new(sideX, stripeY, z),
                    Vector3.new(1.5, 0.2, 10), color)
            end
        end
    end

    -- 4 vertical I-beam columns. Pushed FAR out laterally so they sit at
    -- the visible perimeter and don't intersect with the answer pads, and
    -- on tower mode the horizontal cap is removed entirely (it was a
    -- floating slab visible at every stage). The post is also extended
    -- so it reads as a structural column rather than a half-height stub.
    local cornerH = isTower and 110 or 64
    local cornerX = isTower and 90 or 64
    local cornerZ = isTower and 70 or 50
    for _, sx in ipairs({ -1, 1 }) do
        for _, sz in ipairs({ -1, 1 }) do
            local cx = sx * cornerX
            local cz = sz * cornerZ
            makePart(dressing, "IBeamPost_" .. sx .. sz,
                SCENE_CENTER + Vector3.new(cx, cornerH / 2 - 1, cz),
                Vector3.new(2.4, cornerH, 2.4),
                Color3.fromRGB(50, 60, 80),
                Enum.Material.Metal)
            -- Cap only on the non-tower variant.
            if not isTower then
                makePart(dressing, "IBeamCap_" .. sx .. sz,
                    SCENE_CENTER + Vector3.new(cx, cornerH - 1, cz),
                    Vector3.new(8, 1.2, 8),
                    Color3.fromRGB(70, 80, 100),
                    Enum.Material.Metal)
            end
            -- Spotlight pointing up — only at floor level, not all the way up.
            if not isTower or (sx == 1 and sz == 1) then
                local spot = makePart(dressing, "PhysicsSpot_" .. sx .. sz,
                    SCENE_CENTER + Vector3.new(cx, 4.5, cz),
                    Vector3.new(2.5, 1.5, 2.5),
                    Color3.fromRGB(220, 230, 255),
                    Enum.Material.Neon)
                spot.Transparency = 0.2
                local light = Instance.new("SpotLight", spot)
                light.Face = Enum.NormalId.Top
                light.Brightness = 5
                light.Range = 80
                light.Angle = 110
                light.Color = Color3.fromRGB(180, 210, 255)
            end
        end
    end

    -- Subtle ambient point light in the middle.
    local ambient = makePart(dressing, "PhysicsAmbient",
        SCENE_CENTER + Vector3.new(0, 35, 0),
        Vector3.new(1, 1, 1),
        Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
    ambient.Transparency = 1
    local pl = Instance.new("PointLight", ambient)
    pl.Brightness = 1.2
    pl.Range = 80
    pl.Color = Color3.fromRGB(200, 220, 255)
end

return PhysicsDressing
