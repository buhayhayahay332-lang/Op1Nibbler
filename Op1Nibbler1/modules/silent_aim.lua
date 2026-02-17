return function(ctx)
    local GunModule = ctx.GunModule
    local Workspace = ctx.Services.Workspace
    local UserInputService = ctx.Services.UserInputService

    local M = {
        enabled = false,
        hooked = false,
        fov = 60,
        fovSq = 3600,
        smoothness = 1,
        targetPlayers = true,
        targetGadgets = true,
        targetCameras = true,
        original = nil
    }

    local targetParts = {
        "head", "torso", "shoulder1", "shoulder2", "arm1", "arm2", "hip1", "hip2", "leg1", "leg2"
    }

    local function pickClosest()
        local camera = Workspace.CurrentCamera
        if not camera then
            return nil
        end

        local mouse = UserInputService:GetMouseLocation()
        local bestPart, bestDist = nil, math.huge

        local function score(part)
            if not part or not part:IsA("BasePart") then
                return
            end

            local screen, onScreen = camera:WorldToViewportPoint(part.Position)
            if not onScreen then
                return
            end

            local dx, dy = screen.X - mouse.X, screen.Y - mouse.Y
            local dist = dx * dx + dy * dy

            if dist < bestDist and dist <= M.fovSq then
                bestPart, bestDist = part, dist
            end
        end

        if M.targetPlayers then
            local folder = Workspace:FindFirstChild("Viewmodels")
            if folder then
                for _, vm in ipairs(folder:GetChildren()) do
                    if vm.Name == "Viewmodel" then
                        local torso = vm:FindFirstChild("torso")
                        if not torso or torso.Transparency ~= 1 then
                            for _, name in ipairs(targetParts) do
                                score(vm:FindFirstChild(name))
                            end
                        end
                    end
                end
            end
        end

        if M.targetGadgets then
            for _, model in ipairs(Workspace:GetChildren()) do
                if model:IsA("Model") then
                    score(model:FindFirstChild("HumanoidRootPart")
                        or model:FindFirstChild("Laser")
                        or model:FindFirstChild("RedDot")
                        or model:FindFirstChild("Cam")
                        or model:FindFirstChild("Screen"))
                end
            end
        end

        return bestPart
    end

    function M:SetFov(value)
        self.fov = value
        self.fovSq = value * value
    end

    function M:Init()
        if self.hooked or not GunModule then
            return
        end

        self.original = GunModule.get_shoot_look

        GunModule.get_shoot_look = newcclosure(function(gunSelf)
            local originalCF = M.original(gunSelf)
            if not M.enabled then
                return originalCF
            end

            local target = pickClosest()
            if not target then
                return originalCF
            end

            local origin = originalCF.Position
            local targetCF = CFrame.lookAt(origin, origin + (target.Position - origin).Unit)
            return M.smoothness < 1 and originalCF:Lerp(targetCF, M.smoothness) or targetCF
        end)

        self.hooked = true
    end

    return M
end
