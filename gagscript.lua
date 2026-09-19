--[[
    Grow a Garden 2 — Auto Farm Script (Kenshi Edition)
    Features: Auto Harvest, Auto Sell, Anti-AFK, Status Logging

    Usage: loadstring(game:HttpGet("https://raw.githubusercontent.com/ryuken25/gagscript/main/gagscript.lua"))()
]]

--------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------
local CONFIG = {
    HARVEST_DELAY     = 0.3,
    SELL_DELAY        = 1.5,
    LOOP_DELAY        = 2.0,
    ANTI_AFK_INTERVAL = 120,

    AUTO_HARVEST = true,
    AUTO_SELL    = true,
    AUTO_PLANT   = false,

    SELL_THRESHOLD    = 5,
    SELL_POSITION     = Vector3.new(62, 4, -26),

    MAX_HARVEST_DIST  = 50,
    MAX_SELL_DIST     = 200,
    HUMANLIKE_JITTER  = true,
}

--------------------------------------------------------------
-- SERVICES
--------------------------------------------------------------
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local VirtualUser        = game:GetService("VirtualUser")
local Workspace          = game:GetService("Workspace")

--------------------------------------------------------------
-- STATE
--------------------------------------------------------------
local LocalPlayer   = Players.LocalPlayer
local PlayerName    = LocalPlayer.Name
local Running       = false
local Stats         = { harvested = 0, sold = 0, cycles = 0, errors = 0 }
local SellRemote    = nil
local PlantRemote   = nil
local GameEvents    = nil
local FarmFolder    = nil
local SellPart      = nil

--------------------------------------------------------------
-- UTILITY
--------------------------------------------------------------
local function log(msg)
    print("[GAG2-AutoFarm] " .. msg)
end

local function warn_log(msg)
    warn("[GAG2-AutoFarm] " .. msg)
    Stats.errors = Stats.errors + 1
end

local function jitter(base)
    if CONFIG.HUMANLIKE_JITTER then
        return base + (math.random() * base * 0.5)
    end
    return base
end

local function safe_wait(seconds)
    task.wait(jitter(seconds))
end

local function get_character()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function get_hrp()
    local char = get_character()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function distance_to(position)
    local hrp = get_hrp()
    if not hrp then return math.huge end
    return (hrp.Position - position).Magnitude
end

local function teleport_to(cf)
    local hrp = get_hrp()
    if not hrp then return false end
    hrp.CFrame = cf
    task.wait(0.1)
    return true
end

local function safe_call(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        warn_log("Error: " .. tostring(err))
    end
    return ok
end

--------------------------------------------------------------
-- FIREPROXIMITYPROMPT
--------------------------------------------------------------
local function fire_proximity_prompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end

    if fireproximityprompt then
        safe_call(fireproximityprompt, prompt)
        return true
    end

    local ok = pcall(function()
        prompt.MaxActivationDistance = 9999
        prompt:InputHoldBegin()
        task.wait(prompt.HoldDuration + 0.1)
        prompt:InputHoldEnd()
    end)
    if ok then return true end

    local click = prompt.Parent and prompt.Parent:FindFirstChildOfClass("ClickDetector")
    if click and fireclickdetector then
        safe_call(fireclickdetector, click)
        return true
    end

    return false
end

--------------------------------------------------------------
-- DYNAMIC SCANNER
--------------------------------------------------------------
local function scan_game_events()
    GameEvents = ReplicatedStorage:FindFirstChild("GameEvents")
        or ReplicatedStorage:FindFirstChild("Events")
        or ReplicatedStorage:FindFirstChild("Remotes")

    if not GameEvents then
        for _, child in ipairs(ReplicatedStorage:GetChildren()) do
            if child:IsA("Folder") then
                for _, sub in ipairs(child:GetChildren()) do
                    if sub:IsA("RemoteEvent") or sub:IsA("RemoteFunction") then
                        GameEvents = child
                        log("Found events folder: " .. child.Name)
                        break
                    end
                end
            end
            if GameEvents then break end
        end
    end

    if not GameEvents then
        warn_log("Could not find GameEvents folder")
        return false
    end

    log("GameEvents folder: " .. GameEvents:GetFullName())

    local sell_names = {"Sell_Inventory", "SellInventory", "Sell", "SellAll", "SellCrops", "Sell_RE"}
    for _, name in ipairs(sell_names) do
        SellRemote = GameEvents:FindFirstChild(name)
        if SellRemote then
            log("Sell remote found: " .. SellRemote.Name)
            break
        end
    end

    if not SellRemote then
        for _, child in ipairs(GameEvents:GetDescendants()) do
            if (child:IsA("RemoteEvent") or child:IsA("RemoteFunction"))
                and child.Name:lower():find("sell") then
                SellRemote = child
                log("Sell remote found (scan): " .. child:GetFullName())
                break
            end
        end
    end

    local plant_names = {"Plant_RE", "PlantSeed", "Plant", "PlantCrop"}
    for _, name in ipairs(plant_names) do
        PlantRemote = GameEvents:FindFirstChild(name)
        if PlantRemote then
            log("Plant remote found: " .. PlantRemote.Name)
            break
        end
    end

    return true
end

local function scan_farm_folder()
    local farm_root = Workspace:FindFirstChild("Farm")
        or Workspace:FindFirstChild("Farms")
        or Workspace:FindFirstChild("Plots")
        or Workspace:FindFirstChild("Gardens")

    if not farm_root then
        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") then
                local player_folder = child:FindFirstChild(PlayerName)
                if player_folder then
                    farm_root = child
                    log("Farm root found: " .. child.Name)
                    break
                end
            end
        end
    end

    if not farm_root then
        warn_log("Could not find farm root in Workspace")
        return false
    end

    FarmFolder = farm_root:FindFirstChild(PlayerName)

    if not FarmFolder then
        for _, child in ipairs(farm_root:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") then
                local data = child:FindFirstChild("Data") or child:FindFirstChild("Important")
                if data then
                    local owner = data:FindFirstChild("Owner")
                    if owner and owner.Value == PlayerName then
                        FarmFolder = child
                        break
                    end
                end
                local owner = child:FindFirstChild("Owner")
                if owner and (owner:IsA("StringValue") or owner:IsA("ObjectValue")) then
                    if tostring(owner.Value) == PlayerName then
                        FarmFolder = child
                        break
                    end
                end
            end
        end
    end

    if FarmFolder then
        log("Player farm folder: " .. FarmFolder:GetFullName())
        return true
    end

    warn_log("Could not find player's farm folder")
    return false
end

local function scan_sell_location()
    local sell_keywords = {"sell", "shop", "merchant", "vendor", "npc", "cashier", "register"}
    local best_part = nil
    local best_priority = math.huge

    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc:IsA("BasePart") or desc:IsA("Model") then
            local name_lower = desc.Name:lower()
            for priority, keyword in ipairs(sell_keywords) do
                if name_lower:find(keyword) then
                    if priority < best_priority then
                        best_priority = priority
                        if desc:IsA("Model") then
                            best_part = desc:FindFirstChildOfClass("BasePart") or desc.PrimaryPart
                        else
                            best_part = desc
                        end
                    end
                    break
                end
            end
        end
    end

    if best_part then
        SellPart = best_part
        CONFIG.SELL_POSITION = best_part.Position
        log("Sell location found: " .. best_part:GetFullName() .. " at " .. tostring(best_part.Position))
        return true
    end

    log("Using default sell position: " .. tostring(CONFIG.SELL_POSITION))
    return false
end

--------------------------------------------------------------
-- HARVEST LOGIC
--------------------------------------------------------------
local function get_harvestable_plants()
    local plants = {}
    if not FarmFolder then scan_farm_folder() end
    if not FarmFolder then return plants end

    for _, child in ipairs(FarmFolder:GetDescendants()) do
        if child:IsA("ProximityPrompt") then
            table.insert(plants, child)
        end
    end

    if #plants == 0 then
        local hrp = get_hrp()
        if hrp then
            for _, desc in ipairs(Workspace:GetDescendants()) do
                if desc:IsA("ProximityPrompt") then
                    local parent = desc.Parent
                    if parent and parent:IsA("BasePart") then
                        local dist = (parent.Position - hrp.Position).Magnitude
                        if dist < CONFIG.MAX_HARVEST_DIST then
                            table.insert(plants, desc)
                        end
                    elseif parent and parent:IsA("Model") then
                        local pp = parent.PrimaryPart or parent:FindFirstChildOfClass("BasePart")
                        if pp and (pp.Position - hrp.Position).Magnitude < CONFIG.MAX_HARVEST_DIST then
                            table.insert(plants, desc)
                        end
                    end
                end
            end
        end
    end

    return plants
end

local function harvest_all()
    local plants = get_harvestable_plants()
    local count = 0
    if #plants == 0 then return 0 end

    log("Found " .. #plants .. " harvestable prompt(s)")

    for _, prompt in ipairs(plants) do
        if not Running then break end
        local target_part = prompt.Parent
        if target_part then
            local pos
            if target_part:IsA("BasePart") then
                pos = target_part.Position
            elseif target_part:IsA("Model") then
                local pp = target_part.PrimaryPart or target_part:FindFirstChildOfClass("BasePart")
                pos = pp and pp.Position
            end

            if pos and distance_to(pos) <= CONFIG.MAX_HARVEST_DIST then
                teleport_to(CFrame.new(pos + Vector3.new(0, 2, 0)))
                safe_wait(0.15)
                if fire_proximity_prompt(prompt) then
                    count = count + 1
                    Stats.harvested = Stats.harvested + 1
                    safe_wait(CONFIG.HARVEST_DELAY)
                end
            end
        end
    end

    if count > 0 then
        log("Harvested " .. count .. " crop(s) | Total: " .. Stats.harvested)
    end
    return count
end

--------------------------------------------------------------
-- SELL LOGIC
--------------------------------------------------------------
local function sell_inventory()
    if not CONFIG.AUTO_SELL then return false end
    local prev_pos = get_hrp() and get_hrp().CFrame

    if SellRemote then
        log("Selling via remote: " .. SellRemote.Name)
        if SellRemote:IsA("RemoteEvent") then
            safe_call(function() SellRemote:FireServer() end)
        elseif SellRemote:IsA("RemoteFunction") then
            safe_call(function() SellRemote:InvokeServer() end)
        end
        Stats.sold = Stats.sold + 1
        safe_wait(CONFIG.SELL_DELAY)
        if prev_pos then teleport_to(prev_pos) end
        log("Sell complete | Total sells: " .. Stats.sold)
        return true
    end

    log("No sell remote found, teleporting to sell area...")
    teleport_to(CFrame.new(CONFIG.SELL_POSITION + Vector3.new(0, 3, 0)))
    safe_wait(0.5)

    local found_sell = false
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Parent then
            local part = desc.Parent
            if part:IsA("BasePart") then
                local dist = (part.Position - CONFIG.SELL_POSITION).Magnitude
                if dist < 20 then
                    local name = (desc.ObjectText or desc.ActionText or desc.Name or ""):lower()
                    if name:find("sell") or name:find("shop") or dist < 10 then
                        fire_proximity_prompt(desc)
                        found_sell = true
                        Stats.sold = Stats.sold + 1
                        safe_wait(CONFIG.SELL_DELAY)
                        break
                    end
                end
            end
        end
    end

    if prev_pos then teleport_to(prev_pos) end
    if found_sell then
        log("Sell complete (proximity) | Total sells: " .. Stats.sold)
    else
        warn_log("Could not find sell interaction point")
    end
    return found_sell
end

--------------------------------------------------------------
-- ANTI-AFK
--------------------------------------------------------------
local function setup_anti_afk()
    local conn = Players.LocalPlayer.Idled:Connect(function()
        if VirtualUser then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end
        log("Anti-AFK triggered")
    end)

    task.spawn(function()
        while Running do
            task.wait(CONFIG.ANTI_AFK_INTERVAL)
            if Running and VirtualUser then
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                end)
            end
        end
    end)

    log("Anti-AFK enabled (interval: " .. CONFIG.ANTI_AFK_INTERVAL .. "s)")
    return conn
end

--------------------------------------------------------------
-- STATUS
--------------------------------------------------------------
local function print_status()
    log(string.format(
        "--- Status --- Cycles: %d | Harvested: %d | Sold: %d | Errors: %d | Running: %s",
        Stats.cycles, Stats.harvested, Stats.sold, Stats.errors, tostring(Running)
    ))
end

--------------------------------------------------------------
-- MAIN LOOP
--------------------------------------------------------------
local function main_loop()
    log("=== Grow a Garden 2 Auto Farm Started ===")
    log("Player: " .. PlayerName)

    log("Scanning game structure...")
    scan_game_events()
    scan_farm_folder()
    scan_sell_location()

    local afk_conn = setup_anti_afk()
    local harvest_buffer = 0

    while Running do
        Stats.cycles = Stats.cycles + 1

        if Stats.cycles % 10 == 0 then scan_farm_folder() end

        if CONFIG.AUTO_HARVEST then
            harvest_buffer = harvest_buffer + harvest_all()
        end

        if CONFIG.AUTO_SELL and harvest_buffer >= CONFIG.SELL_THRESHOLD then
            sell_inventory()
            harvest_buffer = 0
        end

        if Stats.cycles % 5 == 0 then print_status() end
        safe_wait(CONFIG.LOOP_DELAY)
    end

    if afk_conn then afk_conn:Disconnect() end
    log("=== Auto Farm Stopped ===")
    print_status()
end

--------------------------------------------------------------
-- CONTROLS
--------------------------------------------------------------
local function start()
    if Running then log("Already running!") return end
    Running = true
    task.spawn(main_loop)
end

local function stop()
    Running = false
    log("Stopping... (will halt after current cycle)")
end

local function toggle()
    if Running then stop() else start() end
end

--------------------------------------------------------------
-- GUI
--------------------------------------------------------------
local function create_gui()
    local ok, _ = pcall(function()
        local screen = Instance.new("ScreenGui")
        screen.Name = "GAG2_AutoFarm"
        screen.ResetOnSpawn = false
        screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        pcall(function() screen.Parent = game:GetService("CoreGui") end)
        if not screen.Parent then
            screen.Parent = LocalPlayer:WaitForChild("PlayerGui")
        end

        local frame = Instance.new("Frame")
        frame.Name = "MainFrame"
        frame.Size = UDim2.new(0, 220, 0, 160)
        frame.Position = UDim2.new(0, 10, 0.5, -80)
        frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        frame.BackgroundTransparency = 0.15
        frame.BorderSizePixel = 0
        frame.Parent = screen

        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 30)
        title.BackgroundTransparency = 1
        title.Text = "GAG2 Auto Farm"
        title.TextColor3 = Color3.fromRGB(100, 255, 100)
        title.TextSize = 16
        title.Font = Enum.Font.GothamBold
        title.Parent = frame

        local function make_btn(name, y, default_on, cb)
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(0.9, 0, 0, 28)
            btn.Position = UDim2.new(0.05, 0, 0, y)
            btn.BackgroundColor3 = default_on and Color3.fromRGB(40, 120, 40) or Color3.fromRGB(120, 40, 40)
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.TextSize = 13
            btn.Font = Enum.Font.Gotham
            btn.Text = name .. ": " .. (default_on and "ON" or "OFF")
            btn.BorderSizePixel = 0
            btn.Parent = frame
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
            local state = default_on
            btn.MouseButton1Click:Connect(function()
                state = not state
                btn.Text = name .. ": " .. (state and "ON" or "OFF")
                btn.BackgroundColor3 = state and Color3.fromRGB(40, 120, 40) or Color3.fromRGB(120, 40, 40)
                cb(state)
            end)
        end

        make_btn("Auto Farm", 35, false, function(on) if on then start() else stop() end end)
        make_btn("Auto Harvest", 68, CONFIG.AUTO_HARVEST, function(on) CONFIG.AUTO_HARVEST = on end)
        make_btn("Auto Sell", 101, CONFIG.AUTO_SELL, function(on) CONFIG.AUTO_SELL = on end)

        local status = Instance.new("TextLabel")
        status.Size = UDim2.new(1, 0, 0, 20)
        status.Position = UDim2.new(0, 0, 0, 134)
        status.BackgroundTransparency = 1
        status.Text = "Ready"
        status.TextColor3 = Color3.fromRGB(180, 180, 180)
        status.TextSize = 11
        status.Font = Enum.Font.Gotham
        status.Parent = frame

        task.spawn(function()
            while screen.Parent do
                status.Text = string.format("H:%d S:%d C:%d E:%d",
                    Stats.harvested, Stats.sold, Stats.cycles, Stats.errors)
                task.wait(1)
            end
        end)

        local dragging, dragStart, startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or
               input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        frame.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or
                             input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                                           startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
    end)

    if ok then log("GUI created") else log("Use GAG2_Start()/GAG2_Stop() from console") end
end

--------------------------------------------------------------
-- INIT
--------------------------------------------------------------
log("=== Grow a Garden 2 Auto Farm v1.0 (Kenshi) ===")

getgenv().GAG2_Start  = start
getgenv().GAG2_Stop   = stop
getgenv().GAG2_Toggle = toggle
getgenv().GAG2_Stats  = Stats
getgenv().GAG2_Config = CONFIG

create_gui()
log("GUI loaded. Click 'Auto Farm: OFF' to start.")
