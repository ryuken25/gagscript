--[[
    Grow a Garden 2 — BRUTAL MULTI-THREAD (Kenshi v5)
    Game: https://www.roblox.com/games/97598239454123/Grow-a-Garden-2

    All threads run independently via task.spawn:
      Thread 1: Harvest nonstop
      Thread 2: Sell every 100 harvests
      Thread 3: Buy Bamboo seed + Trowel gear (constant loop)
      Thread 4: Pet scanner — Unicorn, all Dragons, all Wyverns (constant)
      Thread 5: Event collector
      Thread 6: Anti-AFK

    AUTO-START. No button needed.
    Usage: loadstring(game:HttpGet("https://raw.githubusercontent.com/ryuken25/gagscript/main/gagscript.lua"))()
]]

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local WS      = game:GetService("Workspace")
local VU      = game:GetService("VirtualUser")
local LP      = Players.LocalPlayer
local PGui    = LP:WaitForChild("PlayerGui")
local Backpack= LP:WaitForChild("Backpack")
local LS      = LP:WaitForChild("leaderstats", 10)

--------------------------------------------------------------
-- STATE
--------------------------------------------------------------
local Running = true
local S = { harv = 0, sell = 0, buy = 0, gear = 0, tame = 0, evt = 0 }
local HarvBuf = 0
local SELL_AT = 100
local Threads = {}

--------------------------------------------------------------
-- CORE UTIL
--------------------------------------------------------------
local function shk()
    if not LS then return 0 end
    local s = LS:FindFirstChild("Sheckles")
    return s and s.Value or 0
end

local function chr() return LP.Character or LP.CharacterAdded:Wait() end
local function hrp()
    local c = chr()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function tp(pos)
    local r = hrp()
    if not r then return end
    r.CFrame = typeof(pos) == "Vector3" and CFrame.new(pos) or pos
    task.wait(0.05)
end

local function fp(p)
    if not p or not p:IsA("ProximityPrompt") then return false end
    if typeof(fireproximityprompt) == "function" then
        return pcall(fireproximityprompt, p)
    end
    return pcall(function()
        p.MaxActivationDistance = 9999
        p:InputHoldBegin()
        task.wait(math.max(p.HoldDuration, 0) + 0.05)
        p:InputHoldEnd()
    end)
end

local function fire(re, ...)
    if not re then return false end
    if re:IsA("RemoteEvent") then
        return pcall(function(...) re:FireServer(...) end, ...)
    elseif re:IsA("RemoteFunction") then
        return pcall(function(...) re:InvokeServer(...) end, ...)
    end
    return false
end

--------------------------------------------------------------
-- FIND REMOTES
--------------------------------------------------------------
local GE, BuySeedRE, BuyGearRE, SellRE

local function init_remotes()
    GE = RS:FindFirstChild("GameEvents")
    if not GE then
        for _, f in ipairs(RS:GetChildren()) do
            if f:IsA("Folder") then
                for _, c in ipairs(f:GetChildren()) do
                    if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
                        GE = f; break
                    end
                end
                if GE then break end
            end
        end
    end

    if GE then
        print("[GAG2] GameEvents: " .. GE:GetFullName())
        local n = {}
        for _, c in ipairs(GE:GetChildren()) do
            if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
                table.insert(n, c.Name)
            end
        end
        print("[GAG2] ALL remotes: " .. table.concat(n, ", "))

        BuySeedRE = GE:FindFirstChild("BuySeedStock") or GE:FindFirstChild("BuySeed")
        BuyGearRE = GE:FindFirstChild("BuyGearStock") or GE:FindFirstChild("BuyGear")
        SellRE = GE:FindFirstChild("Sell_Inventory") or GE:FindFirstChild("SellInventory")
            or GE:FindFirstChild("Sell_Item") or GE:FindFirstChild("Sell")

        -- Fallback scan
        if not BuySeedRE or not BuyGearRE or not SellRE then
            for _, c in ipairs(GE:GetChildren()) do
                local ln = c.Name:lower()
                if not BuySeedRE and ln:find("buy") and ln:find("seed") then BuySeedRE = c end
                if not BuyGearRE and ln:find("buy") and ln:find("gear") then BuyGearRE = c end
                if not SellRE and ln:find("sell") then SellRE = c end
            end
        end

        print("[GAG2] BuySeed: " .. (BuySeedRE and BuySeedRE.Name or "NOT FOUND"))
        print("[GAG2] BuyGear: " .. (BuyGearRE and BuyGearRE.Name or "NOT FOUND"))
        print("[GAG2] Sell: " .. (SellRE and SellRE.Name or "NOT FOUND"))
    else
        warn("[GAG2] GameEvents NOT FOUND — dumping RS:")
        for _, c in ipairs(RS:GetChildren()) do
            print("[GAG2]   " .. c.Name .. " [" .. c.ClassName .. "]")
        end
    end
end

--------------------------------------------------------------
-- FIND PLAYER FARM
--------------------------------------------------------------
local MyFarm
local function find_farm()
    if MyFarm and MyFarm.Parent then return MyFarm end
    local farm = WS:FindFirstChild("Farm") or WS:FindFirstChild("Farms")
    if not farm then return nil end
    for _, f in ipairs(farm:GetChildren()) do
        local imp = f:FindFirstChild("Important")
        if imp then
            local d = imp:FindFirstChild("Data")
            if d then
                local o = d:FindFirstChild("Owner")
                if o and tostring(o.Value) == LP.Name then
                    MyFarm = f; return f
                end
            end
        end
    end
    local pf = farm:FindFirstChild(LP.Name)
    if pf then MyFarm = pf end
    return MyFarm
end

--------------------------------------------------------------
-- THREAD 1: HARVEST (nonstop)
--------------------------------------------------------------
local function thread_harvest()
    print("[GAG2] Thread HARVEST started")
    while Running do
        local farm = find_farm()
        local count = 0

        if farm then
            local pp = farm:FindFirstChild("Important")
            if pp then pp = pp:FindFirstChild("Plants_Physical") or pp end
            if not pp then pp = farm end

            for _, d in ipairs(pp:GetDescendants()) do
                if not Running then break end
                if d:IsA("ProximityPrompt") and d.Enabled then
                    local par = d.Parent
                    local pos
                    if par:IsA("BasePart") then pos = par.Position
                    elseif par:IsA("Model") then
                        local p = par.PrimaryPart or par:FindFirstChildOfClass("BasePart")
                        if p then pos = p.Position end
                    end
                    if pos then tp(pos + Vector3.new(0, 2, 0)) end
                    if fp(d) then count = count + 1 end
                    task.wait(0.05)
                end
            end
        end

        -- Ground drops near player
        local r = hrp()
        if r then
            for _, d in ipairs(WS:GetDescendants()) do
                if not Running then break end
                if d:IsA("ProximityPrompt") and d.Enabled then
                    local par = d.Parent
                    if par and par:IsA("BasePart") and (par.Position - r.Position).Magnitude < 40 then
                        tp(par.Position + Vector3.new(0, 2, 0))
                        if fp(d) then count = count + 1 end
                        task.wait(0.05)
                    end
                end
            end
        end

        S.harv = S.harv + count
        HarvBuf = HarvBuf + count
        if count > 0 then print("[GAG2] Harvest: +" .. count .. " (buf:" .. HarvBuf .. "/" .. SELL_AT .. ")") end
        task.wait(0.5)
    end
end

--------------------------------------------------------------
-- THREAD 2: SELL (triggered at 100 harvests)
--------------------------------------------------------------
local function thread_sell()
    print("[GAG2] Thread SELL started (every " .. SELL_AT .. " harvests)")
    while Running do
        if HarvBuf >= SELL_AT then
            print("[GAG2] === SELL TRIGGERED (" .. HarvBuf .. " harvests) ===")
            local prev = hrp() and hrp().CFrame

            local npcs = WS:FindFirstChild("NPCS") or WS:FindFirstChild("NPCs")
            if npcs then
                local steven = npcs:FindFirstChild("Steven") or npcs:FindFirstChild("Sell")
                if steven then
                    local part = steven:FindFirstChildOfClass("BasePart") or steven.PrimaryPart
                    if part then tp(part.Position + Vector3.new(0, 3, 0)) end
                    task.wait(0.15)
                end
            else
                tp(Vector3.new(62, 4, -26))
                task.wait(0.15)
            end

            if SellRE then
                local before = shk()
                fire(SellRE); task.wait(0.15)
                fire(SellRE); task.wait(0.15)
                fire(SellRE); task.wait(0.15)
                local after = shk()
                S.sell = S.sell + 1
                print("[GAG2] SOLD +" .. tostring(after - before) .. " Sheckles | Balance: " .. tostring(after))
            else
                -- Prompt fallback
                if npcs then
                    for _, d in ipairs(npcs:GetDescendants()) do
                        if d:IsA("ProximityPrompt") then
                            fp(d); S.sell = S.sell + 1
                            break
                        end
                    end
                end
            end

            HarvBuf = 0
            if prev then tp(prev) end
        end
        task.wait(1)
    end
end

--------------------------------------------------------------
-- THREAD 3: BUY BAMBOO + TROWEL (constant loop)
--------------------------------------------------------------
local function thread_buy()
    print("[GAG2] Thread BUY started (Bamboo + Trowel)")
    while Running do
        -- Buy Bamboo seed
        if BuySeedRE then
            local before = shk()
            fire(BuySeedRE, "Bamboo")
            task.wait(0.1)
            local after = shk()
            if after < before then
                S.buy = S.buy + 1
                print("[GAG2] BOUGHT Bamboo! (-" .. tostring(before - after) .. ") | Total: " .. S.buy)
                -- Try buying more while in stock
                for i = 1, 20 do
                    if not Running then break end
                    local b = shk()
                    fire(BuySeedRE, "Bamboo")
                    task.wait(0.08)
                    local a = shk()
                    if a >= b then break end -- out of stock
                    S.buy = S.buy + 1
                end
                print("[GAG2] Bamboo buying done | Total seeds: " .. S.buy)
            end
        end

        -- Buy Trowel gear
        if BuyGearRE then
            local before = shk()
            fire(BuyGearRE, "Trowel")
            task.wait(0.1)
            local after = shk()
            if after < before then
                S.gear = S.gear + 1
                print("[GAG2] BOUGHT Trowel! (-" .. tostring(before - after) .. ")")
            end
        end

        -- Shop restocks ~5 min, check every 3s
        task.wait(3)
    end
end

--------------------------------------------------------------
-- THREAD 4: PET SCANNER (constant)
-- Targets: Unicorn, anything with Dragon/Wyvern in name
--------------------------------------------------------------
local function is_wanted_pet(name)
    if name == "Unicorn" then return true end
    local lower = name:lower()
    if lower:find("dragon") then return true end
    if lower:find("wyvern") then return true end
    return false
end

local function thread_pets()
    print("[GAG2] Thread PETS started (Unicorn + Dragons + Wyverns)")
    while Running do
        for _, d in ipairs(WS:GetDescendants()) do
            if not Running then break end
            if d:IsA("Model") and is_wanted_pet(d.Name) then
                local prompt = d:FindFirstChild("ProximityPrompt", true)
                if prompt and prompt:IsA("ProximityPrompt") then
                    print("[GAG2] !!! PET FOUND: " .. d.Name .. " — GOING FOR IT !!!")
                    local part = d.PrimaryPart or d:FindFirstChildOfClass("BasePart")
                    if part then
                        tp(part.Position + Vector3.new(0, 2, 0))
                        task.wait(0.1)
                    end
                    if fp(prompt) then
                        S.tame = S.tame + 1
                        print("[GAG2] ★★★ TAMED: " .. d.Name .. "! ★★★ Total: " .. S.tame)
                    else
                        print("[GAG2] Failed to tame " .. d.Name .. " — might need more money")
                    end
                    task.wait(0.3)
                end
            end
        end
        task.wait(2)
    end
end

--------------------------------------------------------------
-- THREAD 5: EVENTS
--------------------------------------------------------------
local function thread_events()
    print("[GAG2] Thread EVENTS started")
    while Running do
        for _, d in ipairs(WS:GetDescendants()) do
            if not Running then break end
            if d:IsA("ProximityPrompt") and d.Enabled then
                local n = d.Parent and d.Parent.Name:lower() or ""
                local pn = d.Parent and d.Parent.Parent and d.Parent.Parent.Name:lower() or ""
                if n:find("event") or n:find("weather") or n:find("seasonal") or n:find("drop")
                    or pn:find("event") or pn:find("weather") or pn:find("seasonal") or pn:find("drop") then
                    local par = d.Parent
                    local pos = par:IsA("BasePart") and par.Position
                        or (par:IsA("Model") and par.PrimaryPart and par.PrimaryPart.Position)
                    if pos then
                        tp(pos + Vector3.new(0, 2, 0))
                        if fp(d) then S.evt = S.evt + 1 end
                        task.wait(0.05)
                    end
                end
            end
        end
        task.wait(5)
    end
end

--------------------------------------------------------------
-- THREAD 6: ANTI-AFK
--------------------------------------------------------------
LP.Idled:Connect(function()
    if VU then VU:CaptureController(); VU:ClickButton2(Vector2.new()) end
end)
local function thread_afk()
    while true do
        task.wait(60)
        if VU then pcall(function() VU:CaptureController(); VU:ClickButton2(Vector2.new()) end) end
    end
end

--------------------------------------------------------------
-- GUI
--------------------------------------------------------------
pcall(function() game:GetService("CoreGui"):FindFirstChild("GAG2K"):Destroy() end)
pcall(function() PGui:FindFirstChild("GAG2K"):Destroy() end)

local scr = Instance.new("ScreenGui")
scr.Name = "GAG2K"; scr.ResetOnSpawn = false
pcall(function() scr.Parent = game:GetService("CoreGui") end)
if not scr.Parent then scr.Parent = PGui end

local fr = Instance.new("Frame")
fr.Size = UDim2.new(0, 200, 0, 220)
fr.Position = UDim2.new(0, 8, 0.5, -110)
fr.BackgroundColor3 = Color3.fromRGB(12, 12, 20)
fr.BackgroundTransparency = 0.05
fr.BorderSizePixel = 0; fr.Parent = scr
Instance.new("UICorner", fr).CornerRadius = UDim.new(0, 8)

local hdr = Instance.new("TextLabel")
hdr.Size = UDim2.new(1, 0, 0, 24)
hdr.BackgroundColor3 = Color3.fromRGB(160, 10, 10)
hdr.Text = "GAG2 BRUTAL v5"
hdr.TextColor3 = Color3.new(1, 1, 1)
hdr.TextSize = 12; hdr.Font = Enum.Font.GothamBold
hdr.BorderSizePixel = 0; hdr.Parent = fr
Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 8)

local function lbl(yp, color)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0.92, 0, 0, 14)
    l.Position = UDim2.new(0.04, 0, 0, yp)
    l.BackgroundTransparency = 1
    l.TextColor3 = color
    l.TextSize = 10; l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = ""; l.Parent = fr
    return l
end

local l1 = lbl(28, Color3.fromRGB(255, 215, 0))
local l2 = lbl(44, Color3.fromRGB(100, 255, 100))
local l3 = lbl(60, Color3.fromRGB(100, 200, 255))
local l4 = lbl(76, Color3.fromRGB(255, 150, 50))
local l5 = lbl(92, Color3.fromRGB(200, 100, 255))
local l6 = lbl(108, Color3.fromRGB(255, 80, 80))

-- Stop button
local stopbtn = Instance.new("TextButton")
stopbtn.Size = UDim2.new(0.92, 0, 0, 24)
stopbtn.Position = UDim2.new(0.04, 0, 0, 126)
stopbtn.BackgroundColor3 = Color3.fromRGB(110, 20, 20)
stopbtn.TextColor3 = Color3.new(1, 1, 1)
stopbtn.TextSize = 11; stopbtn.Font = Enum.Font.GothamBold
stopbtn.Text = "STOP ALL THREADS"
stopbtn.BorderSizePixel = 0; stopbtn.Parent = fr
Instance.new("UICorner", stopbtn).CornerRadius = UDim.new(0, 5)
stopbtn.MouseButton1Click:Connect(function()
    Running = false
    stopbtn.Text = "STOPPED"
    stopbtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    print("[GAG2] ALL THREADS STOPPED")
end)

-- Thread status labels
local t1l = lbl(156, Color3.fromRGB(80, 80, 90))
local t2l = lbl(170, Color3.fromRGB(80, 80, 90))
local t3l = lbl(184, Color3.fromRGB(80, 80, 90))
local t4l = lbl(198, Color3.fromRGB(80, 80, 90))

local cr = Instance.new("TextLabel")
cr.Size = UDim2.new(1, 0, 0, 10)
cr.Position = UDim2.new(0, 0, 1, -12)
cr.BackgroundTransparency = 1
cr.Text = "ryuken25 | Kenshi"
cr.TextColor3 = Color3.fromRGB(50, 50, 60)
cr.TextSize = 8; cr.Font = Enum.Font.Gotham; cr.Parent = fr

task.spawn(function()
    while scr.Parent do
        l1.Text = "Sheckles: " .. tostring(shk())
        l2.Text = "Harvest: " .. S.harv .. " (buf: " .. HarvBuf .. "/" .. SELL_AT .. ")"
        l3.Text = "Sell: " .. S.sell .. " | Buy: " .. S.buy .. " seeds"
        l4.Text = "Gear: " .. S.gear .. " | Tame: " .. S.tame
        l5.Text = "Events: " .. S.evt
        l6.Text = Running and "RUNNING" or "STOPPED"
        t1l.Text = "T1:Harvest T2:Sell T3:Buy"
        t2l.Text = "T4:Pets T5:Events T6:AFK"
        t3l.Text = "Buy: Bamboo + Trowel"
        t4l.Text = "Pets: Unicorn+Dragon+Wyvern"
        task.wait(0.4)
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
-- LAUNCH ALL THREADS
--------------------------------------------------------------
print("[GAG2] ═══════════════════════════════════════")
print("[GAG2]  BRUTAL MULTI-THREAD v5 — AUTO START")
print("[GAG2]  Buy: Bamboo + Trowel")
print("[GAG2]  Pets: Unicorn + ALL Dragons + ALL Wyverns")
print("[GAG2]  Sell every " .. SELL_AT .. " harvests")
print("[GAG2] ═══════════════════════════════════════")

init_remotes()

task.spawn(thread_harvest)
task.spawn(thread_sell)
task.spawn(thread_buy)
task.spawn(thread_pets)
task.spawn(thread_events)
task.spawn(thread_afk)

print("[GAG2] 6 threads launched — ALL SYSTEMS GO")

getgenv().GAG2_Stop = function() Running = false end
getgenv().GAG2_Stats = S
