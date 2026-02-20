return function(ctx)
    local cloneref = cloneref or function(obj)
        return obj
    end
    local newcclosure = newcclosure or function(fn)
        return fn
    end

    local Workspace = (ctx and ctx.Services and ctx.Services.Workspace) or cloneref(game:GetService("Workspace"))
    local Players = cloneref(game:GetService("Players"))
    local LocalPlayer = Players.LocalPlayer

    local M = {
        enabled = false,
        noSmoke = true,
        noFlash = true
    }

    local initialized = false
    local smokeConnection = nil
    local flashConnection = nil
    local flashHooked = false
    local flashGui = nil

    local modifiedParts = {}
    local modifiedEmitters = {}

    local function getFlashGui()
        if not LocalPlayer then
            return nil
        end
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then
            return nil
        end
        return playerGui:FindFirstChild("Flash")
    end

    local function applyPart(part)
        if modifiedParts[part] then
            return
        end
        modifiedParts[part] = {
            LocalTransparencyModifier = part.LocalTransparencyModifier,
            Size = part.Size
        }
        part.LocalTransparencyModifier = 1
        part.Size = Vector3.new(0.001, 0.001, 0.001)
    end

    local function restorePart(part)
        local original = modifiedParts[part]
        if not original then
            return
        end
        if part and part.Parent then
            part.LocalTransparencyModifier = original.LocalTransparencyModifier
            part.Size = original.Size
        end
        modifiedParts[part] = nil
    end

    local function applyEmitter(emitter)
        if modifiedEmitters[emitter] ~= nil then
            return
        end
        modifiedEmitters[emitter] = emitter.Enabled
        emitter.Enabled = false
    end

    local function restoreEmitter(emitter)
        local original = modifiedEmitters[emitter]
        if original == nil then
            return
        end
        if emitter and emitter.Parent then
            emitter.Enabled = original
        end
        modifiedEmitters[emitter] = nil
    end

    local function visitSmokeObject(obj, apply)
        pcall(function()
            if obj:IsA("BasePart") then
                if apply then
                    applyPart(obj)
                else
                    restorePart(obj)
                end
            end

            for _, part in ipairs(obj:GetDescendants()) do
                if part:IsA("BasePart") then
                    if apply then
                        applyPart(part)
                    else
                        restorePart(part)
                    end
                elseif part:IsA("ParticleEmitter") or part:IsA("Smoke") then
                    if apply then
                        applyEmitter(part)
                    else
                        restoreEmitter(part)
                    end
                end
            end
        end)
    end

    local function refreshSmoke()
        local shouldApply = M.enabled and M.noSmoke

        for _, obj in ipairs(Workspace:GetChildren()) do
            if obj.Name == "SmokePart" then
                visitSmokeObject(obj, shouldApply)
            end
        end

        if not shouldApply then
            for part in pairs(modifiedParts) do
                restorePart(part)
            end
            for emitter in pairs(modifiedEmitters) do
                restoreEmitter(emitter)
            end
        end
    end

    local function refreshFlash()
        if not flashGui or not flashGui.Parent then
            flashGui = getFlashGui()
        end
        if flashGui and M.enabled and M.noFlash then
            flashGui.Enabled = false
        end
    end

    function M:Init()
        if initialized then
            return
        end
        initialized = true

        smokeConnection = Workspace.ChildAdded:Connect(newcclosure(function(obj)
            if obj.Name == "SmokePart" and M.enabled and M.noSmoke then
                visitSmokeObject(obj, true)
            end
        end))

        flashGui = getFlashGui()
        if flashGui then
            local hookmetamethod = hookmetamethod
            if hookmetamethod then
                local oldNewIndex
                oldNewIndex = hookmetamethod(flashGui, "__newindex", newcclosure(function(self, key, value)
                    if self == flashGui and key == "Enabled" and M.enabled and M.noFlash then
                        return
                    end
                    return oldNewIndex(self, key, value)
                end))
                flashHooked = true
            else
                flashConnection = flashGui:GetPropertyChangedSignal("Enabled"):Connect(newcclosure(function()
                    if M.enabled and M.noFlash and flashGui.Enabled then
                        flashGui.Enabled = false
                    end
                end))
            end
        end

        refreshSmoke()
        refreshFlash()
    end

    function M:SetEnabled(state)
        self.enabled = state and true or false
        if self.enabled and not initialized then
            self:Init()
        end
        refreshSmoke()
        refreshFlash()
    end

    function M:SetNoSmoke(state)
        self.noSmoke = state and true or false
        refreshSmoke()
    end

    function M:SetNoFlash(state)
        self.noFlash = state and true or false
        refreshFlash()
    end

    return M
end

