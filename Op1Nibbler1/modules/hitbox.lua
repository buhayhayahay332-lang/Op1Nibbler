return function(ctx)
    local Workspace = ctx.Services.Workspace

    local M = {
        enabled = false,
        size = 5,
        transparency = 0.9,
        color = Color3.fromRGB(255, 0, 0),
        teamCheck = true,
        vmFolder = nil,
        vmConns = {},
        original = {},
        modified = {}
    }

    local function isEnemy(viewmodel)
        if not M.teamCheck then
            return true
        end

        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Highlight") and child.Adornee == viewmodel then
                return false
            end
        end

        return true
    end

    function M:Apply(head)
        if not head or head.Name ~= "head" or not head:IsA("BasePart") then
            return
        end

        if not self.original[head] then
            self.original[head] = {
                Size = head.Size,
                Transparency = head.Transparency,
                Color = head.Color
            }
        end

        head.Size = Vector3.new(self.size, self.size, self.size)
        head.Transparency = self.transparency
        head.Color = self.color
        self.modified[head] = true
    end

    function M:Reset(head)
        local original = self.original[head]
        if not original or not head then
            return
        end

        head.Size = original.Size
        head.Transparency = original.Transparency
        head.Color = original.Color
        self.original[head], self.modified[head] = nil, nil
    end

    function M:ProcessVm(vm)
        if not self.enabled or vm.Name == "LocalViewmodel" or not isEnemy(vm) then
            return
        end

        local torso = vm:FindFirstChild("torso")
        if not torso or torso.Transparency == 1 then
            return
        end

        local head = vm:FindFirstChild("head")
        if head then
            self:Apply(head)
        end

        self.vmConns[vm] = self.vmConns[vm] or {}

        table.insert(self.vmConns[vm], vm.ChildAdded:Connect(function(child)
            if child.Name == "head" and self.enabled then
                self:Apply(child)
            end
        end))

        table.insert(self.vmConns[vm], vm.AncestryChanged:Connect(function(_, parent)
            if not parent and self.vmConns[vm] then
                for _, conn in ipairs(self.vmConns[vm]) do
                    pcall(function() conn:Disconnect() end)
                end
                self.vmConns[vm] = nil
            end
        end))
    end

    function M:SetEnabled(state)
        self.enabled = state and true or false

        if self.enabled then
            self.vmFolder = self.vmFolder
                or Workspace:FindFirstChild("Viewmodels")
                or Workspace:WaitForChild("Viewmodels", 10)

            if not self.vmFolder then
                return
            end

            for _, vm in ipairs(self.vmFolder:GetChildren()) do
                if vm:IsA("Model") then
                    self:ProcessVm(vm)
                end
            end
        else
            for head in pairs(self.modified) do
                self:Reset(head)
            end
        end
    end

    function M:SetSize(value)
        self.size = value
        for head in pairs(self.modified) do
            if head.Parent then
                head.Size = Vector3.new(value, value, value)
            end
        end
    end

    function M:SetTransparency(value)
        self.transparency = value
        for head in pairs(self.modified) do
            if head.Parent then
                head.Transparency = value
            end
        end
    end

    function M:SetColor(value)
        self.color = value
        for head in pairs(self.modified) do
            if head.Parent then
                head.Color = value
            end
        end
    end

    return M
end
