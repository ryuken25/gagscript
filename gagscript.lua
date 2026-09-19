--[[
    Grow a Garden 2 — Full Auto Script (Kenshi v3)
    Game: https://www.roblox.com/games/97598239454123/Grow-a-Garden-2

    Features: Auto Buy Seeds, Auto Harvest, Auto Sell, Auto Tame Pets, Auto Event, Anti-AFK
    Usage: loadstring(game:HttpGet("https://raw.githubusercontent.com/ryuken25/gagscript/main/gagscript.lua"))()
]]

local Players       = game:GetService("Players")
local RS            = game:GetService("ReplicatedStorage")
local WS            = game:GetService("Workspace")
local RunService    = game:GetService("RunService")
local VirtualUser   = game:GetService("VirtualUser")

local LP         = Players.LocalPlayer
local PGui       = LP:WaitForChild("PlayerGui")
local Backpack   = LP:WaitForChild("Backpack")
local LS         = LP:WaitForChild("leaderstats", 10)

--------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------
local CFG = {
    AUTO_BUY     = true,
    AUTO_HARVEST = true,
    AUTO_SELL    = true,
    AUTO_TAME    = true,
    AUTO_EVENT   = true,

    BUY_INTERVAL    = 5,
    HARVEST_INTERVAL= 2,
    SELL_THRESHOLD  = 3,
    LOOP_DELAY      = 1.5,

    SEEDS_TO_BUY = {
        "Bamboo", "Acorn", "Rainbow Seed", "Gold Seed",
        "Dragon's Breath", "Moon Bloom", "Dragon Fruit",
        "Coconut", "Mango", "Glow Mushroom", "Pineapple",
        "Cactus", "Mushroom", "Grape", "Banana",
        "Cherry", "Sunflower", "Pomegranate", "Poison Apple",
        "Ghost Pepper", "Venus Fly Trap", "Poison Ivy",
        "Horned Melon", "Baby Cactus", "Green Bean",
        "Corn", "Apple", "Tomato", "Tulip",
        "Blueberry", "Strawberry", "Carrot",
    },

    PETS_TO_TAME = {
        "Fat Cat", "Unicorn", "Bear", "Black Dragon",
        "Shadow Dragon", "Ice Serpent", "Golden Dragonfly",
        "Monkey", "Owl", "Deer", "Raccoon", "Frog",
    },
}

--------------------------------------------------------------
-- STATE
--------------------------------------------------------------
local Running = false
local S = { buy = 0, harv = 0, sell = 0, tame = 0, evt = 0, cyc = 0, err = 0 }
local GE -- GameEvents folder
local StatusText = "Idle"

--------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------
local function log(m) print("[GAG2] " .. m) end
local function wlog(m) warn("[GAG2] " .. m); S.err = S.err + 1 end
local function sw(t) task.wait(t + math.random() * 0.2) end

local function sheckles()
    if not LS then return 0 end
    local s = LS:FindFirstChild("Sheckles")
    return s and s.Value or 0
end

local function chr()
    return LP.Character or LP.CharacterAdded:Wait()
end

local function root()
    local c = chr()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function tp(pos)
    local r = root()
    if not r then return end
    if typeof(pos) == "Vector3" then
        r.CFrame = CFrame.new(pos)
    else
        r.CFrame = pos
    end
    task.wait(0.12)
end

local function fprompt(p)
    if not p or not p:IsA("ProximityPrompt") then return false end
    if typeof(fireproximityprompt) == "function" then
        local ok = pcall(fireproximityprompt, p)
        return ok
    end
    local ok = pcall(function()
        p.MaxActivationDistance = 9999
        p:InputHoldBegin()
        task.wait(p.HoldDuration + 0.1)
        p:InputHoldEnd()
    end)
    return ok
end

local function fire(remote, ...)
    if not remote then return false end
    local ok, err
    if remote:IsA("RemoteEvent") then
        ok, err = pcall(function(...) remote:FireServer(...) end, ...)
    elseif remote:IsA("RemoteFunction") then
        ok, err = pcall(function(...) remote:InvokeServer(...) end, ...)
    end
    if not ok then wlog("Remote err: " .. tostring(err)) end
    return ok
end

--------------------------------------------------------------
-- FIND REMOTES — scan once, log everything
--------------------------------------------------------------
local function find_remotes()
    GE = RS:FindFirstChild("GameEvents")

    if not GE then
        for _, f in ipairs(RS:GetChildren()) do
            if f:IsA("Folder") then
                for _, c in ipairs(f:GetChildren()) do
                    if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
                        GE = f
                        break
                    end
                end
                if GE then break end
            end
        end
    end

    if GE then
        log("GameEvents: " .. GE:GetFullName())
        local names = {}
        for _, c in ipairs(GE:GetChildren()) do
            if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
                table.insert(names, c.Name .. "(" .. c.ClassName .. ")")
            end
        end
        log("Remotes: " .. table.concat(names, ", "))
    else
        wlog("GameEvents NOT FOUND — listing all RS children:")
        for _, c in ipairs(RS:GetChildren()) do
            log("  RS." .. c.Name .. " [" .. c.ClassName .. "]")
        end
    end
end

local function get_remote(name)
    if GE then
        return GE:FindFirstChild(name)
    end
    return RS:FindFirstChild(name, true)
end

--------------------------------------------------------------
-- AUTO BUY SEEDS
-- Direct approach: fire BuySeedStock for each seed, server
-- rejects if out of stock. No UI scanning needed.
--------------------------------------------------------------
local function do_buy()
    if not CFG.AUTO_BUY then return end
    StatusText = "Buying seeds..."

    local remote = get_remote("BuySeedStock")
        or get_remote("BuySeed")
        or get_remote("Buy_Seed")
        or get_remote("BuyStock")
        or get_remote("PurchaseSeed")

    if not remote then
        -- Fallback: scan all remotes for anything with "buy" + "seed"
        if GE then
            for _, c in ipairs(GE:GetChildren()) do
                if (c:IsA("RemoteEvent") or c:IsA("RemoteFunction")) then
                    local n = c.Name:lower()
                    if n:find("buy") and (n:find("seed") or n:find("stock")) then
                        remote = c
                        break
                    end
                end
            end
        end
    end

    if not remote then
        -- Still nothing? Try ANY remote with "buy" in RS
        for _, c in ipairs(RS:GetDescendants()) do
            if (c:IsA("RemoteEvent") or c:IsA("RemoteFunction")) and c.Name:lower():find("buy") then
                remote = c
                log("Fallback buy remote: " .. c:GetFullName())
                break
            end
        end
    end

    if not remote then
        if S.cyc <= 3 then wlog("No buy remote found anywhere") end
        return
    end

    local cur = sheckles()
    local bought_this = 0

    for _, seed in ipairs(CFG.SEEDS_TO_BUY) do
        if not Running then break end
        local before = sheckles()
        fire(remote, seed)
        sw(0.3)
        local after = sheckles()
        if after < before then
            bought_this = bought_this + 1
            S.buy = S.buy + 1
            log("Bought: " .. seed .. " (" .. tostring(before - after) .. " Sheckles)")
        end
    end

    if bought_this > 0 then
        log("Bought " .. bought_this .. " seed(s) this cycle | Total: " .. S.buy)
    end
end

--------------------------------------------------------------
-- AUTO HARVEST — find ProximityPrompts in player's farm
--------------------------------------------------------------
local function find_farm()
    local farm = WS:FindFirstChild("Farm") or WS:FindFirstChild("Farms")
    if not farm then return nil end

    for _, f in ipairs(farm:GetChildren()) do
        local imp = f:FindFirstChild("Important")
        if imp then
            local d = imp:FindFirstChild("Data")
            if d then
                local o = d:FindFirstChild("Owner")
                if o and tostring(o.Value) == LP.Name then
                    return f
                end
            end
        end
    end

    return farm:FindFirstChild(LP.Name)
end

local function do_harvest()
    if not CFG.AUTO_HARVEST then return 0 end
    StatusText = "Harvesting..."

    local farm = find_farm()
    local count = 0

    if farm then
        local plants = farm:FindFirstChild("Important")
        if plants then
            plants = plants:FindFirstChild("Plants_Physical") or plants
        else
            plants = farm
        end

        for _, desc in ipairs(plants:GetDescendants()) do
            if not Running then break end
            if desc:IsA("ProximityPrompt") and desc.Enabled then
                local par = desc.Parent
                local pos = nil
                if par:IsA("BasePart") then
                    pos = par.Position
                elseif par:IsA("Model") then
                    local pp = par.PrimaryPart or par:FindFirstChildOfClass("BasePart")
                    if pp then pos = pp.Position end
                end
                if pos then
                    tp(pos + Vector3.new(0, 2, 0))
                    sw(0.1)
                end
                if fprompt(desc) then
                    count = count + 1
                    S.harv = S.harv + 1
                end
                sw(0.2)
            end
        end
    end

    -- Also check nearby prompts (fruits on ground etc)
    local r = root()
    if r then
        for _, desc in ipairs(WS:GetDescendants()) do
            if not Running then break end
            if desc:IsA("ProximityPrompt") and desc.Enabled then
                local par = desc.Parent
                if par and par:IsA("BasePart") then
                    local dist = (par.Position - r.Position).Magnitude
                    if dist < 30 then
                        local at = (desc.ActionText or ""):lower()
                        local ot = (desc.ObjectText or ""):lower()
                        if at:find("harvest") or at:find("pick") or at:find("collect")
                            or ot:find("fruit") or ot:find("crop") or at == "" then
                            tp(par.Position + Vector3.new(0, 2, 0))
                            sw(0.1)
                            if fprompt(desc) then
                                count = count + 1
                                S.harv = S.harv + 1
                            end
                            sw(0.2)
                        end
                    end
                end
            end
        end
    end

    if count > 0 then
        log("Harvested: " .. count .. " | Total: " .. S.harv)
    end
    return count
end

--------------------------------------------------------------
-- AUTO SELL
--------------------------------------------------------------
local function do_sell()
    if not CFG.AUTO_SELL then return end
    StatusText = "Selling..."

    -- Count crops in inventory
    local crops = 0
    for _, item in ipairs(Backpack:GetChildren()) do
        if item:IsA("Tool") then
            if item:FindFirstChild("Item_String") or item:FindFirstChild("Crop") then
                crops = crops + 1
            end
        end
    end
    local c = chr()
    if c then
        for _, item in ipairs(c:GetChildren()) do
            if item:IsA("Tool") and (item:FindFirstChild("Item_String") or item:FindFirstChild("Crop")) then
                crops = crops + 1
            end
        end
    end

    if crops < CFG.SELL_THRESHOLD then return end

    local prev = root() and root().CFrame

    -- Try sell remote
    local sell_remote = get_remote("Sell_Inventory")
        or get_remote("SellInventory")
        or get_remote("Sell_Item")
        or get_remote("SellAll")
        or get_remote("Sell")

    if not sell_remote and GE then
        for _, c in ipairs(GE:GetChildren()) do
            if (c:IsA("RemoteEvent") or c:IsA("RemoteFunction")) and c.Name:lower():find("sell") then
                sell_remote = c
                break
            end
        end
    end

    if sell_remote then
        -- Teleport to sell NPC (Steven) first
        local steven = nil
        local npcs = WS:FindFirstChild("NPCS") or WS:FindFirstChild("NPCs") or WS:FindFirstChild("Npcs")
        if npcs then
            steven = npcs:FindFirstChild("Steven") or npcs:FindFirstChild("Sell")
        end
        if steven then
            local part = steven:FindFirstChildOfClass("BasePart") or steven.PrimaryPart
            if part then tp(part.Position + Vector3.new(0, 3, 0)) end
            sw(0.3)
        else
            tp(Vector3.new(62, 4, -26))
            sw(0.3)
        end

        local before = sheckles()
        fire(sell_remote)
        sw(0.8)
        local after = sheckles()
        S.sell = S.sell + 1
        local earned = after - before
        if earned > 0 then
            log("Sold! +" .. tostring(earned) .. " Sheckles | Total sells: " .. S.sell)
        else
            log("Sell fired | Total: " .. S.sell)
        end
    else
        -- Fallback: teleport to sell area and use proximity prompt
        local npcs = WS:FindFirstChild("NPCS") or WS:FindFirstChild("NPCs")
        if npcs then
            local steven = npcs:FindFirstChild("Steven")
            if steven then
                local part = steven:FindFirstChildOfClass("BasePart") or steven.PrimaryPart
                if part then
                    tp(part.Position + Vector3.new(0, 3, 0))
                    sw(0.5)
                    for _, d in ipairs(steven:GetDescendants()) do
                        if d:IsA("ProximityPrompt") then
                            fprompt(d)
                            S.sell = S.sell + 1
                            log("Sold via NPC prompt | Total: " .. S.sell)
                            break
                        end
                    end
                end
            end
        end
        sw(0.5)
    end

    if prev then tp(prev) end
end

--------------------------------------------------------------
-- AUTO TAME PETS — scan workspace for target pets
--------------------------------------------------------------
local function do_tame()
    if not CFG.AUTO_TAME then return end

    local want = {}
    for _, name in ipairs(CFG.PETS_TO_TAME) do want[name] = true end

    for _, desc in ipairs(WS:GetDescendants()) do
        if not Running then break end
        if desc:IsA("Model") and want[desc.Name] then
            local prompt = desc:FindFirstChild("ProximityPrompt", true)
            if prompt and prompt:IsA("ProximityPrompt") then
                StatusText = "Taming " .. desc.Name .. "..."
                local part = desc.PrimaryPart or desc:FindFirstChildOfClass("BasePart")
                if part then
                    tp(part.Position + Vector3.new(0, 2, 0))
                    sw(0.3)
                end
                if fprompt(prompt) then
                    S.tame = S.tame + 1
                    log("TAMED: " .. desc.Name .. "! | Total: " .. S.tame)
                end
                sw(0.8)
            end
        end
    end
end

--------------------------------------------------------------
-- AUTO EVENT — collect event/weather drops
--------------------------------------------------------------
local function do_event()
    if not CFG.AUTO_EVENT then return end
    local count = 0

    for _, desc in ipairs(WS:GetDescendants()) do
        if not Running then break end
        local n = desc.Name:lower()
        local pn = desc.Parent and desc.Parent.Name:lower() or ""

        local is_event = n:find("event") or n:find("seasonal") or n:find("weather")
            or n:find("drop") or n:find("special")
            or pn:find("event") or pn:find("seasonal") or pn:find("weather") or pn:find("drop")

        if is_event and desc:IsA("ProximityPrompt") and desc.Enabled then
            local par = desc.Parent
            local pos = par:IsA("BasePart") and par.Position
                or (par:IsA("Model") and par.PrimaryPart and par.PrimaryPart.Position)
            if pos then
                tp(pos + Vector3.new(0, 2, 0))
                sw(0.2)
                if fprompt(desc) then
                    count = count + 1
                    S.evt = S.evt + 1
                end
            end
        end
    end

    if count > 0 then log("Events collected: " .. count .. " | Total: " .. S.evt) end
end

--------------------------------------------------------------
-- ANTI-AFK
--------------------------------------------------------------
local afk_conn
local function setup_afk()
    afk_conn = LP.Idled:Connect(function()
        if VirtualUser then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end
    end)
end

--------------------------------------------------------------
-- MAIN LOOP
--------------------------------------------------------------
local buy_timer = 0

local function main()
    log("=== GAG2 Kenshi v3.0 Started ===")
    log("Player: " .. LP.Name)
    log("Sheckles: " .. tostring(sheckles()))
    log("Game PlaceId: " .. tostring(game.PlaceId))

    find_remotes()
    setup_afk()

    while Running do
        S.cyc = S.cyc + 1
        StatusText = "Running (cycle " .. S.cyc .. ")"

        -- Buy seeds every few cycles (shop restocks every 5 min)
        buy_timer = buy_timer + CFG.LOOP_DELAY
        if buy_timer >= CFG.BUY_INTERVAL then
            do_buy()
            buy_timer = 0
        end

        -- Harvest
        local h = do_harvest()

        -- Sell if enough crops
        if h and h > 0 then
            do_sell()
        end

        -- Tame pets
        do_tame()

        -- Events
        do_event()

        -- Re-scan remotes if we haven't found GameEvents yet
        if not GE and S.cyc % 15 == 0 then
            find_remotes()
        end

        if S.cyc % 5 == 0 then
            log(string.format("[%d] Buy:%d Harv:%d Sell:%d Tame:%d Evt:%d Err:%d | %d Sheckles",
                S.cyc, S.buy, S.harv, S.sell, S.tame, S.evt, S.err, sheckles()))
        end

        StatusText = "Waiting..."
        sw(CFG.LOOP_DELAY)
    end

    if afk_conn then afk_conn:Disconnect() end
    log("=== Stopped ===")
end

--------------------------------------------------------------
local function start()
    if Running then return end
    Running = true
    task.spawn(main)
end
local function stop()
    Running = false
end

--------------------------------------------------------------
-- GUI
--------------------------------------------------------------
pcall(function()
    local old = game:GetService("CoreGui"):FindFirstChild("GAG2K")
    if old then old:Destroy() end
end)
pcall(function()
    local old = PGui:FindFirstChild("GAG2K")
    if old then old:Destroy() end
end)

local scr = Instance.new("ScreenGui")
scr.Name = "GAG2K"
scr.ResetOnSpawn = false
scr.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() scr.Parent = game:GetService("CoreGui") end)
if not scr.Parent then scr.Parent = PGui end

local fr = Instance.new("Frame")
fr.Size = UDim2.new(0, 220, 0, 340)
fr.Position = UDim2.new(0, 10, 0.5, -170)
fr.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
fr.BackgroundTransparency = 0.05
fr.BorderSizePixel = 0
fr.Parent = scr
Instance.new("UICorner", fr).CornerRadius = UDim.new(0, 8)

local tt = Instance.new("TextLabel")
tt.Size = UDim2.new(1, 0, 0, 28)
tt.BackgroundColor3 = Color3.fromRGB(100, 50, 150)
tt.Text = "GAG2 Kenshi v3"
tt.TextColor3 = Color3.new(1, 1, 1)
tt.TextSize = 14
tt.Font = Enum.Font.GothamBold
tt.BorderSizePixel = 0
tt.Parent = fr
Instance.new("UICorner", tt).CornerRadius = UDim.new(0, 8)

local y = 34
local function mkbtn(label, def, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.9, 0, 0, 26)
    b.Position = UDim2.new(0.05, 0, 0, y)
    b.BackgroundColor3 = def and Color3.fromRGB(35, 110, 35) or Color3.fromRGB(110, 30, 30)
    b.TextColor3 = Color3.new(1, 1, 1)
    b.TextSize = 12
    b.Font = Enum.Font.Gotham
    b.Text = label .. ": " .. (def and "ON" or "OFF")
    b.BorderSizePixel = 0
    b.Parent = fr
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    local st = def
    b.MouseButton1Click:Connect(function()
        st = not st
        b.Text = label .. ": " .. (st and "ON" or "OFF")
        b.BackgroundColor3 = st and Color3.fromRGB(35, 110, 35) or Color3.fromRGB(110, 30, 30)
        cb(st)
    end)
    y = y + 30
end

mkbtn("START / STOP", false, function(v) if v then start() else stop() end end)
mkbtn("Auto Buy Seeds", CFG.AUTO_BUY, function(v) CFG.AUTO_BUY = v end)
mkbtn("Auto Harvest", CFG.AUTO_HARVEST, function(v) CFG.AUTO_HARVEST = v end)
mkbtn("Auto Sell", CFG.AUTO_SELL, function(v) CFG.AUTO_SELL = v end)
mkbtn("Auto Tame Pets", CFG.AUTO_TAME, function(v) CFG.AUTO_TAME = v end)
mkbtn("Auto Event", CFG.AUTO_EVENT, function(v) CFG.AUTO_EVENT = v end)

local ml = Instance.new("TextLabel")
ml.Size = UDim2.new(0.9, 0, 0, 16)
ml.Position = UDim2.new(0.05, 0, 0, y + 4)
ml.BackgroundTransparency = 1
ml.TextColor3 = Color3.fromRGB(255, 215, 0)
ml.TextSize = 11
ml.Font = Enum.Font.GothamBold
ml.TextXAlignment = Enum.TextXAlignment.Left
ml.Text = "Sheckles: ..."
ml.Parent = fr

local sl = Instance.new("TextLabel")
sl.Size = UDim2.new(0.9, 0, 0, 14)
sl.Position = UDim2.new(0.05, 0, 0, y + 22)
sl.BackgroundTransparency = 1
sl.TextColor3 = Color3.fromRGB(160, 160, 170)
sl.TextSize = 10
sl.Font = Enum.Font.Gotham
sl.TextXAlignment = Enum.TextXAlignment.Left
sl.Text = "Ready"
sl.Parent = fr

local stl = Instance.new("TextLabel")
stl.Size = UDim2.new(0.9, 0, 0, 14)
stl.Position = UDim2.new(0.05, 0, 0, y + 38)
stl.BackgroundTransparency = 1
stl.TextColor3 = Color3.fromRGB(130, 200, 255)
stl.TextSize = 10
stl.Font = Enum.Font.Gotham
stl.TextXAlignment = Enum.TextXAlignment.Left
stl.Text = ""
stl.Parent = fr

local cr = Instance.new("TextLabel")
cr.Size = UDim2.new(1, 0, 0, 14)
cr.Position = UDim2.new(0, 0, 1, -16)
cr.BackgroundTransparency = 1
cr.Text = "ryuken25 | Kenshi"
cr.TextColor3 = Color3.fromRGB(80, 80, 90)
cr.TextSize = 9
cr.Font = Enum.Font.Gotham
cr.Parent = fr

task.spawn(function()
    while scr.Parent do
        ml.Text = "Sheckles: " .. tostring(sheckles())
        sl.Text = string.format("Buy:%d Harv:%d Sell:%d Tame:%d Evt:%d",
            S.buy, S.harv, S.sell, S.tame, S.evt)
        stl.Text = StatusText
        task.wait(0.6)
    end
end)

-- Drag
local drag, ds, sp
fr.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        drag = true; ds = i.Position; sp = fr.Position
        i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then drag = false end end)
    end
end)
fr.InputChanged:Connect(function(i)
    if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - ds
        fr.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
    end
end)

--------------------------------------------------------------
-- INIT
--------------------------------------------------------------
log("=== GAG2 Kenshi v3.0 ===")
log("PlaceId: " .. tostring(game.PlaceId))

getgenv().GAG2_Start  = start
getgenv().GAG2_Stop   = stop
getgenv().GAG2_Stats  = S
getgenv().GAG2_Config = CFG

log("GUI loaded — click START to run")
