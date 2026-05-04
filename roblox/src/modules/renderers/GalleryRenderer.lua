--[[
    GalleryRenderer.lua — EduVerse Renderer Module
    Location in Studio: ReplicatedStorage > EduVerse_Modules > renderers > GalleryRenderer (ModuleScript)

    Renders the default 3D exploration experience.
    Objects drop from the sky with a Back-easing tween and animate based on
    their `behavior` (orbit, float, pulse, rotate, flow, grow_shrink).

    Adds in v8:
      • Compact two-tier labels via ctx.attachLabel (LabelEngine).
      • Sets a clear objective in the HUD: "Encuentra los X elementos".

    Public API:
        GalleryRenderer.render(data, folder, ctx)
]]

local GalleryRenderer = {}

function GalleryRenderer.render(data, folder, ctx)
    local objects = data.objects or {}
    local pending = {}

    -- Phase 1: build all objects and register them in the shared registry
    for _, obj in ipairs(objects) do
        local inst, anchorPart, color = ctx.buildObject(obj, folder)
        if anchorPart then
            ctx.attachLabel(obj, anchorPart, color)
            ctx.addProximityGlow(inst, color)

            -- Particle effects: sparkle for neon materials, trail for orbiters
            local bType = obj.behavior and obj.behavior.type or "static"
            local mat   = ctx.getMaterial(obj.name)
            if mat == Enum.Material.Neon then
                ctx.ParticleEngine.addSparkle(anchorPart, color)
            elseif bType == "orbit" then
                ctx.ParticleEngine.addOrbitTrail(anchorPart, color)
            end
        end

        table.insert(pending, {
            obj      = inst,
            behavior = obj.behavior or { type = "static", params = {} },
            name     = obj.name,
            color    = obj.color,
        })
    end

    -- Phase 2: start behaviors once the full registry is populated
    for _, item in ipairs(pending) do
        local selfRot = ctx.getSelfRot(item.name, item.behavior and item.behavior.type or "static")
        ctx.startBehavior(item.obj, item.behavior, selfRot)
    end

    -- Phase 3: draw orbit beams now that all instances exist
    ctx.BeamEngine.processObjects(data.objects or {}, ctx.objectRegistry, ctx.colorFrom)

    -- HUD guidance — student knows what to do without reading floating text
    ctx.Objective.set(string.format(
        "Recorre la escena y descubre los %d elementos. Acércate para leer cada concepto.",
        #objects
    ))
    ctx.Objective.setProgress("Modo Galería · sin tiempo límite")

    print("[GalleryRenderer] ✅ Scene built — " .. #objects .. " objects")
end

return GalleryRenderer
