return function(ctx)
    local Lighting = ctx.Services.Lighting

    local M = {
        enabled = false,
        original = nil,
        full = {
            Brightness = 1,
            ClockTime = 12,
            FogEnd = 786543,
            GlobalShadows = false,
            Ambient = Color3.fromRGB(178, 178, 178)
        }
    }

    local function apply(settings)
        for property, value in pairs(settings) do
            Lighting[property] = value
        end
    end

    function M:Init()
        if self.original then
            return
        end

        self.original = {
            Brightness = Lighting.Brightness,
            ClockTime = Lighting.ClockTime,
            FogEnd = Lighting.FogEnd,
            GlobalShadows = Lighting.GlobalShadows,
            Ambient = Lighting.Ambient
        }
    end

    function M:SetEnabled(state)
        self:Init()
        self.enabled = state and true or false
        apply(self.enabled and self.full or self.original)
    end

    return M
end
