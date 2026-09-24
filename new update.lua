local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local VirtualUser       = game:GetService("VirtualUser")
local TweenService      = game:GetService("TweenService")
local CoreGui           = game:GetService("CoreGui")
local Stats             = game:GetService("Stats")

local LP = Players.LocalPlayer


local function getGuiParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    return LP:WaitForChild("PlayerGui")
end

pcall(function()
    local old = getGuiParent():FindFirstChild("TURZZ_SCRIPT_UI")
    if old then old:Destroy() end
end)


local function isMobile()
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function getViewport()
    local cam = workspace.CurrentCamera
    if cam then return cam.ViewportSize.X, cam.ViewportSize.Y end
    return 1920, 1080
end

local function getWindowSize()
    local vx, vy = getViewport()
    local mobile = isMobile()
    local w, h = 268, 342
    if mobile then w, h = 240, 308 end
    if vx < 500 then
        w = math.min(w, math.floor(vx * 0.80))
        h = math.min(h, math.floor(vy * 0.66))
    end
    return w, h
end


local CONFIG = {
    CheckpointID    = 20,
    CheckpointDelay = 0.5,
    Target1         = Vector3.new(-6764, 1342, -10101),
    Target1Delay    = 0.3,
    Target2         = Vector3.new(-6709, 1331, -10009),
    Target2Delay    = 0.3,
    LoopDelay       = 0.2,

    AntiAfkEnabled  = true,
    AntiAfkInterval = 60,
    AntiAfkJitter   = true,
    AntiAfkCamera   = true,
    AntiAfkMouse    = true,

    AutoReconnect   = true,
    ReconnectDelay  = 5,

    DebugMode       = false,
}


local TP_CONFIG = {
    MicroHopFrames      = 1,
    MicroHopDistance    = 1.5,
    ForceFrames         = 2,
    UseRenderStepped    = true,

    ResetVelocityBefore = true,
    ResetVelocityAfter  = true,
    PrecisionSnap       = true,
    AdaptiveHop         = true,

    ParallelReplicate   = true,
}


local HRP, Character, Humanoid
local isRunning   = false
local loopEnabled = false
local antiAfkOn   = CONFIG.AntiAfkEnabled
local connections = {}
local heartbeatConn, antiAfkConn
local tpLock      = false


local function log(...)
    if CONFIG.DebugMode then print("[TURZZ]", ...) end
end

local function track(conn)
    table.insert(connections, conn)
    return conn
end

local function getHRP()
    Character = LP.Character or LP.CharacterAdded:Wait()
    HRP       = Character:WaitForChild("HumanoidRootPart", 5)
    Humanoid  = Character:FindFirstChildOfClass("Humanoid")
    return HRP
end


local ZERO = Vector3.zero
local function nukeVelocity(hrp)
    if not hrp then return end
    pcall(function()
        hrp.AssemblyLinearVelocity  = ZERO
        hrp.AssemblyAngularVelocity = ZERO
    end)
end


local function microHop(hrp)
    if not hrp then return end
    local pos = hrp.Position
    local s = TP_CONFIG.MicroHopDistance
    local hopOffset = Vector3.new(
        math.random(-100, 100) / 100 * s,
        math.random(-50, 50) / 100 * s,
        math.random(-100, 100) / 100 * s
    )
    hrp.CFrame = CFrame.new(pos + hopOffset) * (hrp.CFrame - hrp.CFrame.Position)
end


local function instantTeleport(targetCF)
    if tpLock then return false end
    tpLock = true

    local hrp = HRP
    if not hrp or not hrp.Parent then hrp = getHRP() end
    if not hrp then tpLock = false; return false end


    if TP_CONFIG.ResetVelocityBefore then nukeVelocity(hrp) end

    local doHop = TP_CONFIG.MicroHopFrames > 0
    if TP_CONFIG.AdaptiveHop then
        local now = tick()
        local lastChange = hrp:GetAttribute("__lastTP") or 0
        if now - lastChange < 0.05 then doHop = false end
        hrp:SetAttribute("__lastTP", now)
    end

    if doHop then
        for _ = 1, TP_CONFIG.MicroHopFrames do
            if not hrp or not hrp.Parent then break end
            microHop(hrp)
            if TP_CONFIG.UseRenderStepped and RunService.RenderStepped then
                RunService.RenderStepped:Wait()
            else
                RunService.Heartbeat:Wait()
            end
        end
    end

    if hrp and hrp.Parent then hrp.CFrame = targetCF end

    if TP_CONFIG.ParallelReplicate then
        for _ = 1, (TP_CONFIG.ForceFrames or 2) do
            if not hrp or not hrp.Parent then break end
            hrp.CFrame = targetCF
            if TP_CONFIG.ResetVelocityAfter then nukeVelocity(hrp) end
            if TP_CONFIG.UseRenderStepped and RunService.RenderStepped then
                RunService.RenderStepped:Wait()
            else
                RunService.Heartbeat:Wait()
            end
        end
    else
        for _ = 1, (TP_CONFIG.ForceFrames or 2) do
            if not hrp or not hrp.Parent then break end
            hrp.CFrame = targetCF
            if TP_CONFIG.ResetVelocityAfter then nukeVelocity(hrp) end
            RunService.Heartbeat:Wait()
        end
    end

    if TP_CONFIG.PrecisionSnap and hrp and hrp.Parent then
        hrp.CFrame = targetCF
        nukeVelocity(hrp)
    end

    tpLock = false
    return true
end


local function forceTeleport(targetPosition)
    local targetCF
    local t = typeof(targetPosition)
    if t == "CFrame" then targetCF = targetPosition
    elseif t == "Vector3" then targetCF = CFrame.new(targetPosition)
    elseif t == "Instance" then targetCF = targetPosition.CFrame + Vector3.new(0, 3, 0)
    else return false end
    return instantTeleport(targetCF)
end


local function setupAntiAfk()
    if not antiAfkOn then return end

    track(LP.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end))

    if antiAfkConn then antiAfkConn:Disconnect() end
    antiAfkConn = RunService.Heartbeat:Connect(function()
        local hum = Humanoid
        if hum and hum.Health > 0 and CONFIG.AntiAfkCamera then
            local cam = workspace.CurrentCamera
            if cam then
                cam.CFrame = cam.CFrame * CFrame.Angles(0, math.rad(0.01), 0)
            end
        end
    end)
    track(antiAfkConn)

    task.spawn(function()
        while antiAfkOn do
            task.wait(CONFIG.AntiAfkInterval + (CONFIG.AntiAfkJitter and math.random(-10, 10) or 0))
            if not antiAfkOn then break end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
            if CONFIG.AntiAfkMouse then
                pcall(function()
                    local mouse = LP:GetMouse()
                    if mouse then
                        mouse.X = mouse.X + math.random(-5, 5)
                        mouse.Y = mouse.Y + math.random(-5, 5)
                    end
                end)
            end
            local hum, hrp = Humanoid, HRP
            if hum and hrp and hum.Health > 0 then
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    task.wait(0.1)
                    hum:ChangeState(Enum.HumanoidStateType.Landed)
                end)
            end
        end
    end)
end


local function runTeleportOnce()
    getHRP()
    pcall(function()
        ReplicatedStorage:WaitForChild("Remote", 3)
            :WaitForChild("Checkpoint", 3)
            :WaitForChild("TpToCheckpoint", 3)
            :FireServer(CONFIG.CheckpointID)
    end)
    task.wait(CONFIG.CheckpointDelay)
    forceTeleport(CONFIG.Target1)
    task.wait(CONFIG.Target1Delay)
    forceTeleport(CONFIG.Target2)
    task.wait(CONFIG.Target2Delay)
end

local function startLoop()
    if isRunning then return end
    isRunning   = true
    loopEnabled = true
    task.spawn(function()
        while loopEnabled do
            if not HRP or not HRP.Parent then getHRP() end
            pcall(runTeleportOnce)
            task.wait(CONFIG.LoopDelay)
        end
        isRunning = false
    end)
end

local function stopLoop()
    loopEnabled = false
    isRunning   = false
    if heartbeatConn then heartbeatConn:Disconnect() end
end


local THEME = {
    Bg          = Color3.fromRGB(18, 20, 28),
    BgElevated  = Color3.fromRGB(26, 29, 40),
    BgCard      = Color3.fromRGB(34, 38, 52),
    BgCardHover = Color3.fromRGB(42, 48, 64),
    Border      = Color3.fromRGB(55, 62, 82),
    BorderHi    = Color3.fromRGB(90, 100, 128),
    Text        = Color3.fromRGB(240, 243, 250),
    TextDim     = Color3.fromRGB(150, 158, 180),
    TextFaint   = Color3.fromRGB(95, 104, 128),
    AccentOn    = Color3.fromRGB(80, 210, 135),
    AccentOnGlow= Color3.fromRGB(80, 210, 135),
    AccentOff   = Color3.fromRGB(60, 66, 84),
    AccentBlue  = Color3.fromRGB(95, 145, 225),
    AccentRed   = Color3.fromRGB(225, 95, 110),
    Gold        = Color3.fromRGB(235, 195, 95),
    GoldDim     = Color3.fromRGB(180, 148, 70),
}


local function buildGUI()
    local parent = getGuiParent()
    local MOBILE = isMobile()

    local WIN_W, WIN_H = getWindowSize()
    local TITLE_H = MOBILE and 46 or 50

    local function centerPosition(w, h)
        return UDim2.new(0.5, -math.floor(w/2), 0.5, -math.floor(h/2))
    end

    local screen = Instance.new("ScreenGui")
    screen.Name           = "TURZZ_SCRIPT_UI"
    screen.ResetOnSpawn   = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent         = parent


    local main = Instance.new("Frame")
    main.Name              = "Window"
    main.Size              = UDim2.new(0, WIN_W, 0, WIN_H)
    main.Position          = centerPosition(WIN_W, WIN_H)
    main.BackgroundColor3  = THEME.Bg
    main.BorderSizePixel   = 0
    main.ClipsDescendants  = false
    main.Parent            = screen

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 16)
    mainCorner.Parent       = main

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color        = THEME.Border
    mainStroke.Thickness    = 1
    mainStroke.Transparency = 0
    mainStroke.Parent       = main


    local shadow = Instance.new("ImageLabel")
    shadow.Name              = "Shadow"
    shadow.Size              = UDim2.new(1, 60, 1, 60)
    shadow.Position          = UDim2.new(0, -30, 0, -30)
    shadow.BackgroundTransparency = 1
    shadow.Image             = "rbxassetid://6014261993"
    shadow.ImageColor3       = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.55
    shadow.ScaleType         = Enum.ScaleType.Slice
    shadow.SliceCenter       = Rect.new(49, 49, 450, 450)
    shadow.ZIndex            = -1
    shadow.Parent            = main


    local titleBar = Instance.new("Frame")
    titleBar.Name             = "TitleBar"
    titleBar.Size             = UDim2.new(1, 0, 0, TITLE_H)
    titleBar.BackgroundColor3 = THEME.BgElevated
    titleBar.BorderSizePixel  = 0
    titleBar.Parent           = main

    local titleBarCorner = Instance.new("UICorner")
    titleBarCorner.CornerRadius = UDim.new(0, 16)
    titleBarCorner.Parent       = titleBar

    local titleBarMask = Instance.new("Frame")
    titleBarMask.Size             = UDim2.new(1, 0, 0, 16)
    titleBarMask.Position         = UDim2.new(0, 0, 1, -16)
    titleBarMask.BackgroundColor3 = THEME.BgElevated
    titleBarMask.BorderSizePixel  = 0
    titleBarMask.Parent           = titleBar


    local titleGradient = Instance.new("Frame")
    titleGradient.Size             = UDim2.new(1, 0, 1, 0)
    titleGradient.BackgroundColor3 = THEME.Gold
    titleGradient.BackgroundTransparency = 0.94
    titleGradient.BorderSizePixel  = 0
    titleGradient.ZIndex           = 0
    titleGradient.Parent           = titleBar

    local titleGradCorner = Instance.new("UICorner")
    titleGradCorner.CornerRadius = UDim.new(0, 16)
    titleGradCorner.Parent       = titleGradient

    local titleGrad = Instance.new("UIGradient")
    titleGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.55, 1),
        NumberSequenceKeypoint.new(1, 1),
    })
    titleGrad.Rotation = 0
    titleGrad.Parent   = titleGradient


    local logoSize = MOBILE and 28 or 32
    local logo = Instance.new("Frame")
    logo.Size             = UDim2.new(0, logoSize, 0, logoSize)
    logo.Position         = UDim2.new(0, 14, 0.5, -logoSize/2)
    logo.BackgroundColor3 = THEME.Gold
    logo.BorderSizePixel  = 0
    logo.ZIndex           = 2
    logo.Parent           = titleBar

    local logoCorner = Instance.new("UICorner")
    logoCorner.CornerRadius = UDim.new(0, 9)
    logoCorner.Parent       = logo

    local logoStroke = Instance.new("UIStroke")
    logoStroke.Color        = Color3.fromRGB(255, 230, 160)
    logoStroke.Thickness    = 1
    logoStroke.Transparency = 0.4
    logoStroke.Parent       = logo

    local logoGrad = Instance.new("UIGradient")
    logoGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 130)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 165, 75)),
    })
    logoGrad.Rotation = 45
    logoGrad.Parent   = logo

    local logoLabel = Instance.new("TextLabel")
    logoLabel.Size             = UDim2.new(1, 0, 1, 0)
    logoLabel.BackgroundTransparency = 1
    logoLabel.Text             = "T"
    logoLabel.TextColor3       = Color3.fromRGB(35, 28, 10)
    logoLabel.TextSize         = MOBILE and 17 or 19
    logoLabel.Font             = Enum.Font.GothamBlack
    logoLabel.ZIndex           = 3
    logoLabel.Parent           = logo


    local brand = Instance.new("TextLabel")
    brand.Size             = UDim2.new(1, -100, 0, 16)
    brand.Position         = UDim2.new(0, logoSize + 24, 0, MOBILE and 8 or 9)
    brand.BackgroundTransparency = 1
    brand.Text             = "TURZZ SCRIPT"
    brand.TextColor3       = THEME.Text
    brand.TextSize         = MOBILE and 13 or 14
    brand.Font             = Enum.Font.GothamBold
    brand.TextXAlignment   = Enum.TextXAlignment.Left
    brand.ZIndex           = 2
    brand.Parent           = titleBar

    local subtitle = Instance.new("TextLabel")
    subtitle.Size             = UDim2.new(1, -100, 0, 12)
    subtitle.Position         = UDim2.new(0, logoSize + 24, 0, MOBILE and 25 or 27)
    subtitle.BackgroundTransparency = 1
    subtitle.Text             = "HyperInstant · v5.0"
    subtitle.TextColor3       = THEME.TextDim
    subtitle.TextSize         = 10
    subtitle.Font             = Enum.Font.Gotham
    subtitle.TextXAlignment   = Enum.TextXAlignment.Left
    subtitle.ZIndex           = 2
    subtitle.Parent           = titleBar


    local minBtnSize = MOBILE and 26 or 24
    local minBtn = Instance.new("TextButton")
    minBtn.Size             = UDim2.new(0, minBtnSize, 0, minBtnSize)
    minBtn.Position         = UDim2.new(1, -(minBtnSize + 12), 0.5, -minBtnSize/2)
    minBtn.BackgroundColor3 = Color3.fromRGB(46, 52, 70)
    minBtn.BorderSizePixel  = 0
    minBtn.Text             = "–"
    minBtn.TextColor3       = THEME.TextDim
    minBtn.TextSize         = MOBILE and 16 or 15
    minBtn.Font             = Enum.Font.GothamBold
    minBtn.AutoButtonColor  = false
    minBtn.ZIndex           = 3
    minBtn.Parent           = titleBar

    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = UDim.new(0, 7)
    minCorner.Parent       = minBtn

    minBtn.MouseEnter:Connect(function()
        TweenService:Create(minBtn, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(60, 68, 88),
            TextColor3 = THEME.Text,
        }):Play()
    end)
    minBtn.MouseLeave:Connect(function()
        TweenService:Create(minBtn, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(46, 52, 70),
            TextColor3 = THEME.TextDim,
        }):Play()
    end)


    local content = Instance.new("Frame")
    content.Name             = "Content"
    content.Size             = UDim2.new(1, 0, 1, -TITLE_H)
    content.Position         = UDim2.new(0, 0, 0, TITLE_H)
    content.BackgroundTransparency = 1
    content.Parent           = main

    local function makeSectionLabel(text, yPos)
        local lbl = Instance.new("TextLabel")
        lbl.Size             = UDim2.new(1, -32, 0, 14)
        lbl.Position         = UDim2.new(0, 16, 0, yPos)
        lbl.BackgroundTransparency = 1
        lbl.Text             = text
        lbl.TextColor3       = THEME.TextFaint
        lbl.TextSize         = 10
        lbl.Font             = Enum.Font.GothamBold
        lbl.TextXAlignment   = Enum.TextXAlignment.Left
        lbl.Parent           = content
        return lbl
    end


    local function attachRipple(btn)
        btn.MouseButton1Down:Connect(function(x, y)
            local ripple = Instance.new("Frame")
            ripple.Size             = UDim2.new(0, 0, 0, 0)
            ripple.Position         = UDim2.new(0, x - btn.AbsolutePosition.X, 0, y - btn.AbsolutePosition.Y)
            ripple.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            ripple.BackgroundTransparency = 0.7
            ripple.BorderSizePixel  = 0
            ripple.ZIndex           = 5
            ripple.Parent           = btn

            local rc = Instance.new("UICorner")
            rc.CornerRadius = UDim.new(1, 0)
            rc.Parent       = ripple

            local sizeTween = TweenService:Create(ripple, TweenInfo.new(0.5, Enum.EasingStyle.Quart), {
                Size = UDim2.new(0, btn.AbsoluteSize.X * 2, 0, btn.AbsoluteSize.X * 2),
                Position = UDim2.new(0, x - btn.AbsolutePosition.X - btn.AbsoluteSize.X,
                                     0, y - btn.AbsolutePosition.Y - btn.AbsoluteSize.X),
            })
            local fadeTween = TweenService:Create(ripple, TweenInfo.new(0.55), {
                BackgroundTransparency = 1
            })
            sizeTween:Play()
            fadeTween:Play()
            fadeTween.Completed:Connect(function()
                ripple:Destroy()
            end)
        end)
    end


    local function makeToggle(title, subtitleText, yPos, initialOn, accentColor, cardH)
        cardH = cardH or (MOBILE and 50 or 56)

        local card = Instance.new("TextButton")
        card.Size             = UDim2.new(1, -32, 0, cardH)
        card.Position         = UDim2.new(0, 16, 0, yPos)
        card.BackgroundColor3 = THEME.BgCard
        card.BorderSizePixel  = 0
        card.Text             = ""
        card.AutoButtonColor  = false
        card.ClipsDescendants = true
        card.Parent           = content

        local cardCorner = Instance.new("UICorner")
        cardCorner.CornerRadius = UDim.new(0, 12)
        cardCorner.Parent       = card

        local cardStroke = Instance.new("UIStroke")
        cardStroke.Color        = THEME.Border
        cardStroke.Thickness    = 1
        cardStroke.Transparency = 0.3
        cardStroke.Parent       = card


        local accentBar = Instance.new("Frame")
        accentBar.Size             = UDim2.new(0, 3, 0.55, 0)
        accentBar.Position         = UDim2.new(0, 0, 0.5, 0)
        accentBar.AnchorPoint      = Vector2.new(0, 0.5)
        accentBar.BackgroundColor3 = THEME.AccentOff
        accentBar.BorderSizePixel  = 0
        accentBar.Parent           = card

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Size             = UDim2.new(1, -80, 0, 18)
        titleLbl.Position         = UDim2.new(0, 16, 0, MOBILE and 8 or 10)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Text             = title
        titleLbl.TextColor3       = THEME.Text
        titleLbl.TextSize         = MOBILE and 13 or 14
        titleLbl.Font             = Enum.Font.GothamBold
        titleLbl.TextXAlignment   = Enum.TextXAlignment.Left
        titleLbl.Parent           = card

        local subLbl = Instance.new("TextLabel")
        subLbl.Size             = UDim2.new(1, -80, 0, 14)
        subLbl.Position         = UDim2.new(0, 16, 0, MOBILE and 25 or 29)
        subLbl.BackgroundTransparency = 1
        subLbl.Text             = subtitleText
        subLbl.TextColor3       = THEME.TextDim
        subLbl.TextSize         = 10
        subLbl.Font             = Enum.Font.Gotham
        subLbl.TextXAlignment   = Enum.TextXAlignment.Left
        subLbl.Parent           = card


        local pillW = MOBILE and 38 or 42
        local pillH = MOBILE and 22 or 24
        local knobSize = MOBILE and 16 or 18

        local track = Instance.new("Frame")
        track.Size             = UDim2.new(0, pillW, 0, pillH)
        track.Position         = UDim2.new(1, -(pillW + 14), 0.5, -pillH/2)
        track.BackgroundColor3 = THEME.AccentOff
        track.BorderSizePixel  = 0
        track.Parent           = card

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(1, 0)
        trackCorner.Parent       = track

        local knob = Instance.new("Frame")
        knob.Size             = UDim2.new(0, knobSize, 0, knobSize)
        knob.Position         = UDim2.new(0, 3, 0.5, -knobSize/2)
        knob.BackgroundColor3 = Color3.fromRGB(230, 234, 245)
        knob.BorderSizePixel  = 0
        knob.ZIndex           = 2
        knob.Parent           = track

        local knobCorner = Instance.new("UICorner")
        knobCorner.CornerRadius = UDim.new(1, 0)
        knobCorner.Parent       = knob

        local state = { on = initialOn }

        local function render(anim)
            local tInfo = TweenInfo.new(anim and 0.25 or 0, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
            if state.on then
                TweenService:Create(track, tInfo, { BackgroundColor3 = accentColor }):Play()
                TweenService:Create(knob, tInfo, {
                    Position = UDim2.new(1, -(knobSize + 3), 0.5, -knobSize/2)
                }):Play()
                TweenService:Create(accentBar, tInfo, {
                    BackgroundColor3 = accentColor
                }):Play()
            else
                TweenService:Create(track, tInfo, { BackgroundColor3 = THEME.AccentOff }):Play()
                TweenService:Create(knob, tInfo, {
                    Position = UDim2.new(0, 3, 0.5, -knobSize/2)
                }):Play()
                TweenService:Create(accentBar, tInfo, {
                    BackgroundColor3 = THEME.AccentOff
                }):Play()
            end
        end

        render(false)


        card.MouseEnter:Connect(function()
            TweenService:Create(card, TweenInfo.new(0.18), {
                BackgroundColor3 = THEME.BgCardHover
            }):Play()
            TweenService:Create(cardStroke, TweenInfo.new(0.18), {
                Transparency = 0,
                Color = THEME.BorderHi,
            }):Play()
        end)
        card.MouseLeave:Connect(function()
            TweenService:Create(card, TweenInfo.new(0.18), {
                BackgroundColor3 = THEME.BgCard
            }):Play()
            TweenService:Create(cardStroke, TweenInfo.new(0.18), {
                Transparency = 0.3,
                Color = THEME.Border,
            }):Play()
        end)

        attachRipple(card)

        return card, state, render
    end


    local tpCard, tpState, tpRender = makeToggle(
        "Teleport",
        "Hyper instant · anti-patch",
        MOBILE and 30 or 34,
        false,
        THEME.AccentOn
    )
    tpCard.MouseButton1Click:Connect(function()
        if tpState.on then
            stopLoop()
            tpState.on = false
        else
            startLoop()
            tpState.on = true
        end
        tpRender(true)
    end)


    local afkCard, afkState, afkRender = makeToggle(
        "Anti-AFK",
        "Keep session alive",
        MOBILE and 88 or 98,
        antiAfkOn,
        THEME.AccentBlue
    )
    afkCard.MouseButton1Click:Connect(function()
        antiAfkOn = not antiAfkOn
        CONFIG.AntiAfkEnabled = antiAfkOn
        afkState.on = antiAfkOn
        afkRender(true)
        if antiAfkOn then setupAntiAfk() else
            if antiAfkConn then antiAfkConn:Disconnect() end
        end
    end)


    local qaLabelY = MOBILE and 152 or 168
    makeSectionLabel("QUICK ACTIONS", qaLabelY)

    local quickY = MOBILE and 170 or 190
    local quickRow = Instance.new("Frame")
    quickRow.Size             = UDim2.new(1, -32, 0, MOBILE and 32 or 36)
    quickRow.Position         = UDim2.new(0, 16, 0, quickY)
    quickRow.BackgroundTransparency = 1
    quickRow.Parent           = content

    local function makeMiniButton(text, xOffset, width, accent)
        local btn = Instance.new("TextButton")
        btn.Size             = UDim2.new(0, width, 1, 0)
        btn.Position         = UDim2.new(0, xOffset, 0, 0)
        btn.BackgroundColor3 = THEME.BgCard
        btn.BorderSizePixel  = 0
        btn.Text             = text
        btn.TextColor3       = THEME.Text
        btn.TextSize         = MOBILE and 11 or 12
        btn.Font             = Enum.Font.GothamBold
        btn.AutoButtonColor  = false
        btn.ClipsDescendants = true
        btn.Parent           = quickRow

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 10)
        c.Parent       = btn

        local s = Instance.new("UIStroke")
        s.Color        = THEME.Border
        s.Thickness    = 1
        s.Transparency = 0.3
        s.Parent       = btn

        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15), {
                BackgroundColor3 = accent or THEME.BgCardHover,
                TextColor3 = accent and THEME.Text or THEME.Text,
            }):Play()
            TweenService:Create(s, TweenInfo.new(0.15), {
                Transparency = 0, Color = THEME.BorderHi
            }):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15), {
                BackgroundColor3 = THEME.BgCard
            }):Play()
            TweenService:Create(s, TweenInfo.new(0.15), {
                Transparency = 0.3, Color = THEME.Border
            }):Play()
        end)

        attachRipple(btn)
        return btn
    end

    local totalQuickW = WIN_W - 32
    local gap = 8
    local halfW = math.floor((totalQuickW - gap) / 2)

    local btnNow = makeMiniButton("Teleport Now", 0, halfW)
    btnNow.MouseButton1Click:Connect(function()
        task.spawn(function() pcall(runTeleportOnce) end)
    end)

    local btnHide = makeMiniButton("Hide UI", halfW + gap, halfW, THEME.AccentRed)
    btnHide.MouseButton1Click:Connect(function()
        TweenService:Create(main, TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, WIN_W, 0, TITLE_H)
        }):Play()
        content.Visible = false
        minBtn.Text = "+"
    end)


    local minimized = false
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        content.Visible = not minimized
        minBtn.Text = minimized and "+" or "–"
        TweenService:Create(main, TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = minimized and UDim2.new(0, WIN_W, 0, TITLE_H) or UDim2.new(0, WIN_W, 0, WIN_H)
        }):Play()
    end)


    local footer = Instance.new("Frame")
    footer.Size             = UDim2.new(1, -32, 0, 22)
    footer.Position         = UDim2.new(0, 16, 1, -30)
    footer.BackgroundTransparency = 1
    footer.Parent           = content

    local creditLeft = Instance.new("TextLabel")
    creditLeft.Size             = UDim2.new(0, 55, 1, 0)
    creditLeft.BackgroundTransparency = 1
    creditLeft.Text             = "Made by"
    creditLeft.TextColor3       = THEME.TextFaint
    creditLeft.TextSize         = MOBILE and 9 or 10
    creditLeft.Font             = Enum.Font.Gotham
    creditLeft.TextXAlignment   = Enum.TextXAlignment.Left
    creditLeft.Parent           = footer

    local creditBrand = Instance.new("TextLabel")
    creditBrand.Size             = UDim2.new(0, 120, 1, 0)
    creditBrand.Position         = UDim2.new(0, 46, 0, 0)
    creditBrand.BackgroundTransparency = 1
    creditBrand.Text             = "TURZZ SCRIPT"
    creditBrand.TextColor3       = THEME.Gold
    creditBrand.TextSize         = MOBILE and 9 or 10
    creditBrand.Font             = Enum.Font.GothamBold
    creditBrand.TextXAlignment   = Enum.TextXAlignment.Left
    creditBrand.Parent           = footer

    local fpsLbl = Instance.new("TextLabel")
    fpsLbl.Size             = UDim2.new(0.5, -5, 1, 0)
    fpsLbl.Position         = UDim2.new(0.5, 5, 0, 0)
    fpsLbl.BackgroundTransparency = 1
    fpsLbl.Text             = "60 FPS"
    fpsLbl.TextColor3       = THEME.TextFaint
    fpsLbl.TextSize         = MOBILE and 9 or 10
    fpsLbl.Font             = Enum.Font.Gotham
    fpsLbl.TextXAlignment   = Enum.TextXAlignment.Right
    fpsLbl.Parent           = footer


    local dragging, dragStart, startPos
    local function beginDrag(input)
        dragging  = true
        dragStart = input.Position
        startPos  = main.Position
    end

    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            beginDrag(input)
        end
    end)
    titleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)


    local finalPos  = centerPosition(WIN_W, WIN_H)
    local finalSize = UDim2.new(0, WIN_W, 0, WIN_H)
    main.Size     = UDim2.new(0, 0, 0, 0)
    main.Position = UDim2.new(0.5, 0, 0.5, 0)
    TweenService:Create(main, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size     = finalSize,
        Position = finalPos,
    }):Play()

    --== RESPONSIVE ==--
    local cam = workspace.CurrentCamera
    if cam then
        track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            local nw, nh = getWindowSize()
            if not minimized then
                TweenService:Create(main, TweenInfo.new(0.2), {
                    Size     = UDim2.new(0, nw, 0, nh),
                    Position = UDim2.new(0.5, -math.floor(nw/2), 0.5, -math.floor(nh/2)),
                }):Play()
            end
        end))
    end

    --== FPS MONITOR ==--
    task.spawn(function()
        local frames = 0
        local lastT = tick()
        while screen.Parent do
            frames += 1
            local now = tick()
            if now - lastT >= 1 then
                local fps = math.floor(frames / (now - lastT))
                if fpsLbl and fpsLbl.Parent then
                    fpsLbl.Text = fps .. " FPS"
                end
                frames = 0
                lastT = now
            end
            RunService.RenderStepped:Wait()
        end
    end)

    return screen, main, tpState, afkState
end


local function setupReconnect()
    if not CONFIG.AutoReconnect then return end
    track(LP.AncestryChanged:Connect(function(_, parent)
        if not parent and CONFIG.AutoReconnect then
            task.wait(CONFIG.ReconnectDelay)
            pcall(function()
                game:GetService("TeleportService"):Teleport(game.PlaceId, LP)
            end)
        end
    end))
end


track(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.T then
        if not loopEnabled then startLoop() end
    elseif input.KeyCode == Enum.KeyCode.Y then
        stopLoop()
    end
end))


track(LP.CharacterAdded:Connect(function(char)
    Character = char
    HRP       = char:WaitForChild("HumanoidRootPart", 5)
    Humanoid  = char:FindFirstChildOfClass("Humanoid")
end))


task.spawn(function()
    task.wait(0.1)
    getHRP()
    setupAntiAfk()
    setupReconnect()
    buildGUI()
end)