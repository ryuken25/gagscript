--[[
    Grow a Garden 2 — Auto Buy & Auto Tame Script (Kenshi Edition)
    Features: Auto Buy Seeds, Auto Tame Pets, Auto Collect Event Seeds, Anti-AFK

    Usage: loadstring(game:HttpGet("https://raw.githubusercontent.com/ryuken25/gagscript/main/gagscript.lua"))()
]]

--------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------
local CONFIG = {
    BUY_DELAY         = 0.4,
    SCAN_DELAY        = 2.0,
    PET_SCAN_DELAY    = 3.0,
    EVENT_SCAN_DELAY  = 5.0,
    ANTI_AFK_INTERVAL = 120,
    TAME_RANGE        = 200,

    AUTO_BUY_SEEDS  = true,
    AUTO_TAME_PETS  = true,
    AUTO_EVENT      = true,

    SEED_PRIORITY = {
        "Rainbow Seed", "Gold Seed", "Dragon's Breath", "Moon Bloom",
        "Dragon Fruit", "Acorn", "Bamboo",
    },

    PET_TARGETS = {
        ["Fat Cat"]        = { price = 0,          currency = "Sheckles",     method = "egg" },
        ["Unicorn"]        = { price = 4000000,    currency = "Sheckles",     method = "map" },
        ["Bear"]           = { price = 5000000,    currency = "Sheckles",     method = "map" },
        ["Black Dragon"]   = { price = 20000000,   currency = "Sheckles",     method = "guild" },
        ["Shadow Dragon"]  = { price = 30000000,   currency = "LeaveCurrency", method = "map" },
        ["Ice Serpent"]    = { price = 20000000,   currency = "Sheckles",     method = "guild" },
    },
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
local PlayerGui     = LocalPlayer:WaitForChild("PlayerGui")
local Leaderstats   = LocalPlayer:WaitForChild("leaderstats")
local Backpack      = LocalPlayer:WaitForChild("Backpack")
local Running       = false
local Stats         = { seeds_bought = 0, pets_tamed = 0, events_collected = 0, cycles = 0, errors = 0 }

local GameEvents    = nil
local BuyRemote     = nil

--------------------------------------------------------------
-- UTILITY
--------------------------------------------------------------
local function log(msg)
    print("[GAG2-Kenshi] " .. msg)
end

local function warn_log(msg)
    warn("[GAG2-Kenshi] " .. msg)
    Stats.errors = Stats.errors + 1
end

local function safe_wait(seconds)
    local jitter = seconds + (math.random() * seconds * 0.3)
    task.wait(jitter)
end

local function get_character()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function get_hrp()
    local char = get_character()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function teleport_to(cf)
    local hrp = get_hrp()
    if not hrp then return false end
    hrp.CFrame = cf
    task.wait(0.15)
    return true
end

local function get_currency(name)
    local stat = Leaderstats:FindFirstChild(name)
    if stat then return stat.Value end
    if name == "LeaveCurrency" then
        stat = Leaderstats:FindFirstChild("Leaves")
            or Leaderstats:FindFirstChild("LeafCurrency")
            or Leaderstats:FindFirstChild("Leave")
        if stat then return stat.Value end
    end
    return 0
end

local function safe_call(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        warn_log("Error: " .. tostring(err))
    end
    return ok
end

--------------------------------------------------------------
-- PROXIMITY PROMPT
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
-- INIT REMOTES
--------------------------------------------------------------
local function init_remotes()
    GameEvents = ReplicatedStorage:FindFirstChild("GameEvents")
    if not GameEvents then
        for _, child in ipairs(ReplicatedStorage:GetChildren()) do
            if child:IsA("Folder") then
                for _, sub in ipairs(child:GetChildren()) do
                    if (sub:IsA("RemoteEvent") or sub:IsA("RemoteFunction"))
                        and (sub.Name:lower():find("buy") or sub.Name:lower():find("seed") or sub.Name:lower():find("shop")) then
                        GameEvents = child
                        break
                    end
                end
            end
            if GameEvents then break end
        end
    end

    if not GameEvents then
        warn_log("GameEvents folder not found in ReplicatedStorage")
        return false
    end

    log("GameEvents: " .. GameEvents:GetFullName())

    local buy_names = {"BuySeedStock", "BuySeed", "Buy_Seed", "BuyStock", "Shop_Buy", "PurchaseSeed"}
    for _, name in ipairs(buy_names) do
        BuyRemote = GameEvents:FindFirstChild(name)
        if BuyRemote then
            log("Buy remote: " .. BuyRemote.Name)
            break
        end
    end

    if not BuyRemote then
        for _, child in ipairs(GameEvents:GetDescendants()) do
            if (child:IsA("RemoteEvent") or child:IsA("RemoteFunction"))
                and (child.Name:lower():find("buy") or child.Name:lower():find("seed")) then
                BuyRemote = child
                log("Buy remote (scan): " .. child:GetFullName())
                break
            end
        end
    end

    if not BuyRemote then
        warn_log("Buy remote not found — auto buy will use fallback")
    end

    return true
end

--------------------------------------------------------------
-- SEED SHOP SCANNER
--------------------------------------------------------------
local function get_seed_stock()
    local stock = {}

    local seed_shop = PlayerGui:FindFirstChild("Seed_Shop")
    if not seed_shop then
        for _, gui in ipairs(PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and (gui.Name:lower():find("seed") or gui.Name:lower():find("shop")) then
                seed_shop = gui
                break
            end
        end
    end

    if not seed_shop then return stock end

    for _, desc in ipairs(seed_shop:GetDescendants()) do
        if desc:IsA("Frame") or desc:IsA("ImageLabel") then
            local stock_text = desc:FindFirstChild("Stock_Text")
                or desc:FindFirstChild("StockText")
                or desc:FindFirstChild("Stock")
            local main_frame = desc:FindFirstChild("Main_Frame") or desc

            if stock_text and stock_text:IsA("TextLabel") then
                local count = tonumber(stock_text.Text:match("%d+"))
                if count and count > 0 then
                    stock[desc.Name] = count
                end
            end
        end
    end

    return stock
end

local function get_seed_price(seed_name)
    local seed_shop = PlayerGui:FindFirstChild("Seed_Shop")
    if not seed_shop then return nil end

    for _, desc in ipairs(seed_shop:GetDescendants()) do
        if desc.Name == seed_name then
            local price_label = desc:FindFirstChild("Price_Text", true)
                or desc:FindFirstChild("PriceText", true)
                or desc:FindFirstChild("Price", true)
                or desc:FindFirstChild("Cost", true)
            if price_label and price_label:IsA("TextLabel") then
                local price = tonumber(price_label.Text:gsub("[^%d]", ""))
                return price
            end
        end
    end
    return nil
end

--------------------------------------------------------------
-- AUTO BUY SEEDS
--------------------------------------------------------------
local function auto_buy_seeds()
    if not CONFIG.AUTO_BUY_SEEDS then return end

    local stock = get_seed_stock()
    if not next(stock) then return end

    local sheckles = get_currency("Sheckles")

    for _, seed_name in ipairs(CONFIG.SEED_PRIORITY) do
        if not Running then break end

        local count = stock[seed_name]
        if count and count > 0 then
            local price = get_seed_price(seed_name)

            if price and price > sheckles then
                log(seed_name .. " costs " .. tostring(price) .. " but only have " .. tostring(sheckles) .. " Sheckles — skipping")
            else
                if BuyRemote then
                    for i = 1, count do
                        if not Running then break end
                        local current = get_currency("Sheckles")
                        if price and current < price then
                            log("Not enough Sheckles for " .. seed_name .. " — stopping")
                            break
                        end

                        if BuyRemote:IsA("RemoteEvent") then
                            safe_call(function() BuyRemote:FireServer(seed_name) end)
                        elseif BuyRemote:IsA("RemoteFunction") then
                            safe_call(function() BuyRemote:InvokeServer(seed_name) end)
                        end

                        Stats.seeds_bought = Stats.seeds_bought + 1
                        safe_wait(CONFIG.BUY_DELAY)
                    end
                    log("Bought " .. seed_name .. " x" .. tostring(count) .. " | Total: " .. Stats.seeds_bought)
                else
                    log("No buy remote available for " .. seed_name)
                end
            end
        end
    end

    for seed_name, count in pairs(stock) do
        if not Running then break end

        local dominated = false
        for _, priority in ipairs(CONFIG.SEED_PRIORITY) do
            if seed_name == priority then dominated = true; break end
        end
        if dominated then continue end

        local rarity_keywords = {"divine", "godly", "mythical", "legendary", "epic"}
        local name_lower = seed_name:lower()
        local is_rare = false
        for _, kw in ipairs(rarity_keywords) do
            if name_lower:find(kw) then is_rare = true; break end
        end

        if is_rare and count > 0 and BuyRemote then
            local price = get_seed_price(seed_name)
            local sheckles_now = get_currency("Sheckles")

            if price and price > sheckles_now then
                log(seed_name .. " (rare) too expensive — " .. tostring(price) .. " vs " .. tostring(sheckles_now))
            else
                for i = 1, count do
                    if not Running then break end
                    local current = get_currency("Sheckles")
                    if price and current < price then break end

                    if BuyRemote:IsA("RemoteEvent") then
                        safe_call(function() BuyRemote:FireServer(seed_name) end)
                    elseif BuyRemote:IsA("RemoteFunction") then
                        safe_call(function() BuyRemote:InvokeServer(seed_name) end)
                    end

                    Stats.seeds_bought = Stats.seeds_bought + 1
                    safe_wait(CONFIG.BUY_DELAY)
                end
                log("Bought rare seed: " .. seed_name .. " x" .. tostring(count))
            end
        end
    end
end

--------------------------------------------------------------
-- AUTO TAME PETS
--------------------------------------------------------------
local function scan_wild_pets()
    local found = {}
    local search_folders = {
        Workspace:FindFirstChild("Pets"),
        Workspace:FindFirstChild("WildPets"),
        Workspace:FindFirstChild("SpawnedPets"),
        Workspace:FindFirstChild("MapPets"),
        Workspace:FindFirstChild("Animals"),
    }

    for _, folder in ipairs(search_folders) do
        if folder then
            for _, obj in ipairs(folder:GetDescendants()) do
                if obj:IsA("ProximityPrompt") then
                    local pet_model = obj.Parent
                    if pet_model:IsA("Model") then
                        pet_model = pet_model
                    elseif pet_model:IsA("BasePart") then
                        pet_model = pet_model.Parent
                    end

                    local pet_name = pet_model and pet_model.Name or ""
                    if CONFIG.PET_TARGETS[pet_name] then
                        table.insert(found, { name = pet_name, prompt = obj, model = pet_model })
                    end
                end
            end
        end
    end

    if #found == 0 then
        for _, desc in ipairs(Workspace:GetDescendants()) do
            if desc:IsA("Model") and CONFIG.PET_TARGETS[desc.Name] then
                local prompt = desc:FindFirstChildOfClass("ProximityPrompt")
                    or desc:FindFirstChild("ProximityPrompt", true)
                if prompt then
                    table.insert(found, { name = desc.Name, prompt = prompt, model = desc })
                end
            end
        end
    end

    return found
end

local function auto_tame_pets()
    if not CONFIG.AUTO_TAME_PETS then return end

    local pets = scan_wild_pets()
    if #pets == 0 then return end

    for _, pet in ipairs(pets) do
        if not Running then break end

        local cfg = CONFIG.PET_TARGETS[pet.name]
        if not cfg then continue end

        if cfg.method == "egg" then
            log(pet.name .. " is from eggs — can't auto-buy, skipping")
            continue
        end

        local currency_amount = get_currency(cfg.currency)
        if cfg.price > 0 and currency_amount < cfg.price then
            log(pet.name .. " costs " .. tostring(cfg.price) .. " " .. cfg.currency .. " but have " .. tostring(currency_amount) .. " — skipping")
            continue
        end

        local pet_part = pet.model.PrimaryPart or pet.model:FindFirstChildOfClass("BasePart")
        if pet_part then
            local dist = 0
            local hrp = get_hrp()
            if hrp then
                dist = (hrp.Position - pet_part.Position).Magnitude
            end

            if dist > CONFIG.TAME_RANGE then
                log(pet.name .. " found but too far (" .. math.floor(dist) .. " studs) — teleporting")
            end

            teleport_to(CFrame.new(pet_part.Position + Vector3.new(0, 2, 0)))
            safe_wait(0.3)
        end

        if fire_proximity_prompt(pet.prompt) then
            Stats.pets_tamed = Stats.pets_tamed + 1
            log("Tamed " .. pet.name .. "! | Total: " .. Stats.pets_tamed)
            safe_wait(1.0)
        else
            warn_log("Failed to tame " .. pet.name)
        end
    end
end

--------------------------------------------------------------
-- AUTO COLLECT EVENT SEEDS
--------------------------------------------------------------
local function auto_collect_events()
    if not CONFIG.AUTO_EVENT then return end

    local event_folders = {
        Workspace:FindFirstChild("Events"),
        Workspace:FindFirstChild("EventSeeds"),
        Workspace:FindFirstChild("EventItems"),
        Workspace:FindFirstChild("Collectibles"),
        Workspace:FindFirstChild("SeasonalItems"),
        Workspace:FindFirstChild("FallHarvest"),
        Workspace:FindFirstChild("SummerEvent"),
    }

    local collected = 0

    for _, folder in ipairs(event_folders) do
        if folder then
            for _, item in ipairs(folder:GetDescendants()) do
                if not Running then break end

                if item:IsA("ProximityPrompt") then
                    local part = item.Parent
                    if part and (part:IsA("BasePart") or part:IsA("Model")) then
                        local pos
                        if part:IsA("BasePart") then
                            pos = part.Position
                        else
                            pos = part:GetPivot().Position
                        end

                        teleport_to(CFrame.new(pos + Vector3.new(0, 2, 0)))
                        safe_wait(0.2)

                        if fire_proximity_prompt(item) then
                            collected = collected + 1
                            Stats.events_collected = Stats.events_collected + 1
                        end
                    end
                elseif item:IsA("ClickDetector") then
                    if fireclickdetector then
                        local part = item.Parent
                        if part and part:IsA("BasePart") then
                            teleport_to(CFrame.new(part.Position + Vector3.new(0, 2, 0)))
                            safe_wait(0.2)
                            safe_call(fireclickdetector, item)
                            collected = collected + 1
                            Stats.events_collected = Stats.events_collected + 1
                        end
                    end
                end
            end
        end
    end

    if #event_folders == 0 or collected == 0 then
        for _, desc in ipairs(Workspace:GetDescendants()) do
            if not Running then break end
            if desc:IsA("BasePart") or desc:IsA("Model") then
                local name_lower = desc.Name:lower()
                if name_lower:find("event") and (name_lower:find("seed") or name_lower:find("collect") or name_lower:find("pickup")) then
                    local prompt = desc:FindFirstChildOfClass("ProximityPrompt")
                        or desc:FindFirstChild("ProximityPrompt", true)
                    if prompt then
                        local pos
                        if desc:IsA("BasePart") then
                            pos = desc.Position
                        else
                            pos = desc:GetPivot().Position
                        end
                        teleport_to(CFrame.new(pos + Vector3.new(0, 2, 0)))
                        safe_wait(0.2)
                        if fire_proximity_prompt(prompt) then
                            collected = collected + 1
                            Stats.events_collected = Stats.events_collected + 1
                        end
                    end
                end
            end
        end
    end

    if collected > 0 then
        log("Collected " .. collected .. " event item(s) | Total: " .. Stats.events_collected)
    end
end

--------------------------------------------------------------
-- ANTI-AFK
--------------------------------------------------------------
local function setup_anti_afk()
    local conn = LocalPlayer.Idled:Connect(function()
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

    log("Anti-AFK enabled")
    return conn
end

--------------------------------------------------------------
-- STATUS
--------------------------------------------------------------
local function print_status()
    log(string.format(
        "--- Status --- Cycles: %d | Seeds Bought: %d | Pets Tamed: %d | Events: %d | Errors: %d",
        Stats.cycles, Stats.seeds_bought, Stats.pets_tamed, Stats.events_collected, Stats.errors
    ))
end

--------------------------------------------------------------
-- MAIN LOOP
--------------------------------------------------------------
local function main_loop()
    log("=== Grow a Garden 2 — Auto Buy & Tame Started ===")
    log("Player: " .. LocalPlayer.Name)
    log("Sheckles: " .. tostring(get_currency("Sheckles")))

    log("Scanning remotes...")
    init_remotes()

    local afk_conn = setup_anti_afk()

    while Running do
        Stats.cycles = Stats.cycles + 1

        if CONFIG.AUTO_BUY_SEEDS then
            auto_buy_seeds()
        end

        if CONFIG.AUTO_TAME_PETS then
            auto_tame_pets()
        end

        if CONFIG.AUTO_EVENT then
            auto_collect_events()
        end

        if Stats.cycles % 5 == 0 then print_status() end
        safe_wait(CONFIG.SCAN_DELAY)
    end

    if afk_conn then afk_conn:Disconnect() end
    log("=== Script Stopped ===")
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
    log("Stopping...")
end

--------------------------------------------------------------
-- GUI
--------------------------------------------------------------
local function create_gui()
    local ok, _ = pcall(function()
        local screen = Instance.new("ScreenGui")
        screen.Name = "GAG2_Kenshi"
        screen.ResetOnSpawn = false
        screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        pcall(function() screen.Parent = game:GetService("CoreGui") end)
        if not screen.Parent then
            screen.Parent = PlayerGui
        end

        local frame = Instance.new("Frame")
        frame.Name = "MainFrame"
        frame.Size = UDim2.new(0, 240, 0, 250)
        frame.Position = UDim2.new(0, 10, 0.5, -125)
        frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
        frame.BackgroundTransparency = 0.1
        frame.BorderSizePixel = 0
        frame.Parent = screen

        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 32)
        title.BackgroundColor3 = Color3.fromRGB(80, 40, 120)
        title.BackgroundTransparency = 0
        title.Text = "GAG2 Kenshi"
        title.TextColor3 = Color3.fromRGB(255, 255, 255)
        title.TextSize = 16
        title.Font = Enum.Font.GothamBold
        title.BorderSizePixel = 0
        title.Parent = frame
        Instance.new("UICorner", title).CornerRadius = UDim.new(0, 8)

        local function make_toggle(name, y, default_on, on_change)
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(0.9, 0, 0, 30)
            btn.Position = UDim2.new(0.05, 0, 0, y)
            btn.BackgroundColor3 = default_on and Color3.fromRGB(40, 120, 40) or Color3.fromRGB(100, 35, 35)
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
                btn.BackgroundColor3 = state and Color3.fromRGB(40, 120, 40) or Color3.fromRGB(100, 35, 35)
                on_change(state)
            end)
            return btn
        end

        make_toggle("Start/Stop", 38, false, function(on)
            if on then start() else stop() end
        end)

        make_toggle("Auto Buy Seeds", 73, CONFIG.AUTO_BUY_SEEDS, function(on)
            CONFIG.AUTO_BUY_SEEDS = on
        end)

        make_toggle("Auto Tame Pets", 108, CONFIG.AUTO_TAME_PETS, function(on)
            CONFIG.AUTO_TAME_PETS = on
        end)

        make_toggle("Auto Event Seeds", 143, CONFIG.AUTO_EVENT, function(on)
            CONFIG.AUTO_EVENT = on
        end)

        local money_label = Instance.new("TextLabel")
        money_label.Size = UDim2.new(0.9, 0, 0, 22)
        money_label.Position = UDim2.new(0.05, 0, 0, 180)
        money_label.BackgroundTransparency = 1
        money_label.Text = "Sheckles: ..."
        money_label.TextColor3 = Color3.fromRGB(255, 215, 0)
        money_label.TextSize = 12
        money_label.Font = Enum.Font.GothamBold
        money_label.TextXAlignment = Enum.TextXAlignment.Left
        money_label.Parent = frame

        local status_label = Instance.new("TextLabel")
        status_label.Size = UDim2.new(0.9, 0, 0, 20)
        status_label.Position = UDim2.new(0.05, 0, 0, 200)
        status_label.BackgroundTransparency = 1
        status_label.Text = "Ready"
        status_label.TextColor3 = Color3.fromRGB(180, 180, 180)
        status_label.TextSize = 11
        status_label.Font = Enum.Font.Gotham
        status_label.TextXAlignment = Enum.TextXAlignment.Left
        status_label.Parent = frame

        local credits = Instance.new("TextLabel")
        credits.Size = UDim2.new(1, 0, 0, 18)
        credits.Position = UDim2.new(0, 0, 0, 230)
        credits.BackgroundTransparency = 1
        credits.Text = "by ryuken25 | Kenshi Injector"
        credits.TextColor3 = Color3.fromRGB(120, 120, 140)
        credits.TextSize = 10
        credits.Font = Enum.Font.Gotham
        credits.Parent = frame

        task.spawn(function()
            while screen.Parent do
                local shk = get_currency("Sheckles")
                money_label.Text = "Sheckles: " .. tostring(shk)
                status_label.Text = string.format("S:%d P:%d E:%d C:%d",
                    Stats.seeds_bought, Stats.pets_tamed, Stats.events_collected, Stats.cycles)
                task.wait(1)
            end
        end)

        -- Draggable
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

    if ok then
        log("GUI created")
    else
        log("GUI failed — use GAG2_Start() / GAG2_Stop() from console")
    end
end

--------------------------------------------------------------
-- INIT
--------------------------------------------------------------
log("=== GAG2 Auto Buy & Tame v2.0 (Kenshi) ===")

getgenv().GAG2_Start  = start
getgenv().GAG2_Stop   = stop
getgenv().GAG2_Stats  = Stats
getgenv().GAG2_Config = CONFIG

create_gui()
log("GUI loaded. Click 'Start/Stop' to begin.")
