--[[
    Grow a Garden 2 — BRUTAL v6 (Kenshi)
    6 threads, error recovery, auto-start, shows remotes in GUI
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

local Running = true
local S = { harv = 0, sell = 0, buy = 0, gear = 0, tame = 0, evt = 0 }
local HarvBuf = 0
local SELL_AT = 100
local RemoteInfo = "scanning..."
local ThreadStatus = {}

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
-- SAFE THREAD — wraps in pcall, auto-restarts on crash
--------------------------------------------------------------
local function safe_thread(name, fn)
    task.spawn(function()
        while Running do
            ThreadStatus[name] = "running"
            local ok, err = pcall(fn)
            if not ok then
                ThreadStatus[name] = "ERROR: " .. tostring(err)
                warn("[GAG2] Thread " .. name .. " crashed: " .. tostring(err))
                task.wait(2)
            end
        end
        ThreadStatus[name] = "stopped"
    end)
end

--------------------------------------------------------------
-- REMOTES
--------------------------------------------------------------
local GE
local AllRemotes = {}

local function find_remote(...)
    local names = {...}
    for _, n in ipairs(names) do
        if GE then
            local r = GE:FindFirstChild(n)
            if r then return r end
        end
        local r = RS:FindFirstChild(n, true)
        if r and (r:IsA("RemoteEvent") or r:IsA("RemoteFunction")) then return r end
    end
    return nil
end

local function find_remote_pattern(pattern)
    for _, r in pairs(AllRemotes) do
        if r.Name:lower():find(pattern) then return r end
    end
    return nil
end

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

    AllRemotes = {}
    local names = {}
    local search = GE or RS
    for _, c in ipairs(search:GetDescendants()) do
        if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
            AllRemotes[c.Name] = c
            table.insert(names, c.Name)
        end
    end

    if #names > 0 then
        RemoteInfo = table.concat(names, ", ")
        print("[GAG2] Found " .. #names .. " remotes: " .. RemoteInfo)
    else
        RemoteInfo = "NONE FOUND"
        warn("[GAG2] NO REMOTES FOUND")
        for _, c in ipairs(RS:GetChildren()) do
            print("[GAG2] RS." .. c.Name .. " [" .. c.ClassName .. "]")
        end
    end
end

--------------------------------------------------------------
-- FIND FARM
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
    MyFarm = farm:FindFirstChild(LP.Name)
    return MyFarm
end

--------------------------------------------------------------
-- T1: HARVEST
--------------------------------------------------------------
local function thread_harvest()
    while Running do
        ThreadStatus["harvest"] = "scanning"
        local farm = find_farm()
        local count = 0

        if farm then
            local pp = farm:FindFirstChild("Important")
            if pp then pp = pp:FindFirstChild("Plants_Physical") or pp end
            if not pp then pp = farm end

            for _, d in ipairs(pp:GetDescendants()) do
                if not Running then return end
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

        local r = hrp()
        if r then
            for _, d in ipairs(WS:GetDescendants()) do
                if not Running then return end
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
        ThreadStatus["harvest"] = "H+" .. count
        task.wait(0.3)
    end
end

--------------------------------------------------------------
-- T2: SELL (every 100 harvests)
--------------------------------------------------------------
local function thread_sell()
    while Running do
        if HarvBuf >= SELL_AT then
            ThreadStatus["sell"] = "SELLING"
            print("[GAG2] SELL triggered at " .. HarvBuf .. " harvests")
            local prev = hrp() and hrp().CFrame

            -- Try teleport to sell NPC
            local npcs = WS:FindFirstChild("NPCS") or WS:FindFirstChild("NPCs") or WS:FindFirstChild("Npcs")
            if npcs then
                local npc = npcs:FindFirstChild("Steven") or npcs:FindFirstChild("Sell")
                    or npcs:FindFirstChild("sell") or npcs:FindFirstChild("Merchant")
                if npc then
                    local part = npc.PrimaryPart or npc:FindFirstChildOfClass("BasePart")
                    if part then tp(part.Position + Vector3.new(0, 3, 0)); task.wait(0.2) end
                end
            else
                tp(Vector3.new(62, 4, -26)); task.wait(0.2)
            end

            -- Try ALL sell-like remotes
            local sold = false
            local sell_names = {"Sell_Inventory", "SellInventory", "Sell_Item", "SellAll", "Sell", "SellCrops"}
            for _, name in ipairs(sell_names) do
                local re = find_remote(name)
                if re then
                    local before = shk()
                    fire(re); task.wait(0.1)
                    fire(re); task.wait(0.1)
                    fire(re); task.wait(0.1)
                    local after = shk()
                    if after > before then
                        S.sell = S.sell + 1
                        print("[GAG2] SOLD via " .. name .. "! +" .. (after-before) .. " | Bal: " .. after)
                        sold = true
                        break
                    end
                end
            end

            -- Pattern fallback
            if not sold then
                local re = find_remote_pattern("sell")
                if re then
                    fire(re); task.wait(0.1)
                    fire(re); task.wait(0.1)
                    fire(re); task.wait(0.1)
                    S.sell = S.sell + 1
                    print("[GAG2] Sold via pattern: " .. re.Name)
                    sold = true
                end
            end

            -- Proximity prompt fallback
            if not sold then
                local r = hrp()
                if r then
                    for _, d in ipairs(WS:GetDescendants()) do
                        if d:IsA("ProximityPrompt") then
                            local par = d.Parent
                            if par and par:IsA("BasePart") and (par.Position - r.Position).Magnitude < 20 then
                                local n = (d.ActionText or d.ObjectText or d.Parent.Name or ""):lower()
                                if n:find("sell") or n:find("trade") or n:find("exchange") or n == "" then
                                    fp(d)
                                    S.sell = S.sell + 1
                                    print("[GAG2] Sold via proximity prompt")
                                    sold = true
                                    break
                                end
                            end
                        end
                    end
                end
            end

            if not sold then
                -- Nuclear: fire EVERY remote and check if sheckles went up
                local before = shk()
                for _, re in pairs(AllRemotes) do
                    if re.Name:lower():find("sell") then
                        fire(re)
                        task.wait(0.05)
                    end
                end
                task.wait(0.3)
                local after = shk()
                if after > before then
                    S.sell = S.sell + 1
                    print("[GAG2] Sold via nuclear scan! +" .. (after-before))
                else
                    print("[GAG2] SELL FAILED — no sell remote worked. Remotes: " .. RemoteInfo)
                end
            end

            HarvBuf = 0
            if prev then tp(prev) end
        end
        ThreadStatus["sell"] = "buf:" .. HarvBuf .. "/" .. SELL_AT
        task.wait(0.5)
    end
end

--------------------------------------------------------------
-- T3: BUY BAMBOO + TROWEL
--------------------------------------------------------------
local function thread_buy()
    while Running do
        ThreadStatus["buy"] = "checking"

        -- Try buying Bamboo
        local buy_re = find_remote("BuySeedStock", "BuySeed", "Buy_Seed", "BuyStock")
            or find_remote_pattern("buy.*seed") or find_remote_pattern("seed.*buy")
            or find_remote_pattern("buy")
        if buy_re then
            local before = shk()
            fire(buy_re, "Bamboo")
            task.wait(0.1)
            local after = shk()
            if after < before then
                S.buy = S.buy + 1
                ThreadStatus["buy"] = "BAMBOO!"
                print("[GAG2] BOUGHT Bamboo via " .. buy_re.Name .. "! -" .. (before-after))
                for i = 1, 30 do
                    if not Running then return end
                    local b = shk()
                    fire(buy_re, "Bamboo")
                    task.wait(0.06)
                    if shk() >= b then break end
                    S.buy = S.buy + 1
                end
                print("[GAG2] Bamboo total: " .. S.buy)
            end
        else
            ThreadStatus["buy"] = "no buy remote"
        end

        -- Try buying Trowel
        local gear_re = find_remote("BuyGearStock", "BuyGear", "Buy_Gear")
            or find_remote_pattern("gear") or find_remote_pattern("buy.*gear")
        if gear_re then
            local before = shk()
            fire(gear_re, "Trowel")
            task.wait(0.1)
            local after = shk()
            if after < before then
                S.gear = S.gear + 1
                print("[GAG2] BOUGHT Trowel via " .. gear_re.Name .. "!")
            end
        end

        task.wait(3)
    end
end

--------------------------------------------------------------
-- T4: PET SCANNER — Unicorn + *Dragon* + *Wyvern*
--------------------------------------------------------------
local function is_wanted(name)
    if name == "Unicorn" then return true end
    local l = name:lower()
    return l:find("dragon") or l:find("wyvern")
end

local function thread_pets()
    while Running do
        ThreadStatus["pets"] = "scanning"
        for _, d in ipairs(WS:GetDescendants()) do
            if not Running then return end
            if d:IsA("Model") and is_wanted(d.Name) then
                local prompt = d:FindFirstChild("ProximityPrompt", true)
                if prompt and prompt:IsA("ProximityPrompt") then
                    ThreadStatus["pets"] = "FOUND: " .. d.Name
                    print("[GAG2] PET: " .. d.Name .. " FOUND!")
                    local part = d.PrimaryPart or d:FindFirstChildOfClass("BasePart")
                    if part then tp(part.Position + Vector3.new(0, 2, 0)); task.wait(0.1) end
                    if fp(prompt) then
                        S.tame = S.tame + 1
                        print("[GAG2] TAMED: " .. d.Name .. "!")
                    end
                    task.wait(0.2)
                end
            end
        end
        ThreadStatus["pets"] = "idle"
        task.wait(2)
    end
end

--------------------------------------------------------------
-- T5: EVENTS
--------------------------------------------------------------
local function thread_events()
    while Running do
        ThreadStatus["events"] = "scanning"
        for _, d in ipairs(WS:GetDescendants()) do
            if not Running then return end
            if d:IsA("ProximityPrompt") and d.Enabled then
                local n = d.Parent and d.Parent.Name:lower() or ""
                local pn = d.Parent and d.Parent.Parent and d.Parent.Parent.Name:lower() or ""
                if n:find("event") or n:find("weather") or n:find("seasonal") or n:find("drop")
                    or pn:find("event") or pn:find("weather") or pn:find("drop") then
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
        ThreadStatus["events"] = "idle"
        task.wait(5)
    end
end

--------------------------------------------------------------
-- T6: ANTI-AFK
--------------------------------------------------------------
LP.Idled:Connect(function()
    if VU then VU:CaptureController(); VU:ClickButton2(Vector2.new()) end
end)

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
fr.Size = UDim2.new(0, 210, 0, 280)
fr.Position = UDim2.new(0, 8, 0.5, -140)
fr.BackgroundColor3 = Color3.fromRGB(10, 10, 18)
fr.BackgroundTransparency = 0.05
fr.BorderSizePixel = 0; fr.Parent = scr
Instance.new("UICorner", fr).CornerRadius = UDim.new(0, 8)

local hdr = Instance.new("TextLabel")
hdr.Size = UDim2.new(1, 0, 0, 22)
hdr.BackgroundColor3 = Color3.fromRGB(160, 10, 10)
hdr.Text = "GAG2 BRUTAL v6"; hdr.TextColor3 = Color3.new(1, 1, 1)
hdr.TextSize = 12; hdr.Font = Enum.Font.GothamBold
hdr.BorderSizePixel = 0; hdr.Parent = fr
Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 8)

local function lbl(yp, col)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0.94, 0, 0, 13)
    l.Position = UDim2.new(0.03, 0, 0, yp)
    l.BackgroundTransparency = 1
    l.TextColor3 = col; l.TextSize = 9
    l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = ""; l.Parent = fr; return l
end

local l_money   = lbl(25, Color3.fromRGB(255, 215, 0))
local l_harv    = lbl(40, Color3.fromRGB(100, 255, 100))
local l_sell    = lbl(55, Color3.fromRGB(100, 200, 255))
local l_buy     = lbl(70, Color3.fromRGB(255, 150, 50))
local l_pet     = lbl(85, Color3.fromRGB(200, 100, 255))
local l_evt     = lbl(100, Color3.fromRGB(150, 255, 200))
local l_status  = lbl(115, Color3.fromRGB(255, 80, 80))
local l_remote  = lbl(132, Color3.fromRGB(120, 120, 140))
local l_tstat   = lbl(147, Color3.fromRGB(90, 90, 110))

-- Toggle button
local togbtn = Instance.new("TextButton")
togbtn.Size = UDim2.new(0.94, 0, 0, 26)
togbtn.Position = UDim2.new(0.03, 0, 0, 165)
togbtn.BackgroundColor3 = Color3.fromRGB(30, 100, 30)
togbtn.TextColor3 = Color3.new(1, 1, 1)
togbtn.TextSize = 12; togbtn.Font = Enum.Font.GothamBold
togbtn.Text = "RUNNING — tap to STOP"
togbtn.BorderSizePixel = 0; togbtn.Parent = fr
Instance.new("UICorner", togbtn).CornerRadius = UDim.new(0, 5)

togbtn.MouseButton1Click:Connect(function()
    Running = not Running
    if Running then
        togbtn.Text = "RUNNING — tap to STOP"
        togbtn.BackgroundColor3 = Color3.fromRGB(30, 100, 30)
        -- Relaunch threads
        init_remotes()
        safe_thread("harvest", thread_harvest)
        safe_thread("sell", thread_sell)
        safe_thread("buy", thread_buy)
        safe_thread("pets", thread_pets)
        safe_thread("events", thread_events)
        print("[GAG2] RESTARTED all threads")
    else
        togbtn.Text = "STOPPED — tap to START"
        togbtn.BackgroundColor3 = Color3.fromRGB(100, 25, 25)
    end
end)

-- Info labels
local l_info1 = lbl(198, Color3.fromRGB(70, 70, 85))
local l_info2 = lbl(212, Color3.fromRGB(70, 70, 85))
local l_info3 = lbl(226, Color3.fromRGB(70, 70, 85))

local cr = Instance.new("TextLabel")
cr.Size = UDim2.new(1, 0, 0, 10)
cr.Position = UDim2.new(0, 0, 1, -12)
cr.BackgroundTransparency = 1
cr.Text = "ryuken25 | Kenshi"
cr.TextColor3 = Color3.fromRGB(45, 45, 55)
cr.TextSize = 8; cr.Font = Enum.Font.Gotham; cr.Parent = fr

task.spawn(function()
    while scr.Parent do
        l_money.Text = "Sheckles: " .. tostring(shk())
        l_harv.Text = "Harvest: " .. S.harv .. " | buf: " .. HarvBuf .. "/" .. SELL_AT
        l_sell.Text = "Sell: " .. S.sell .. " | Buy: " .. S.buy .. " bamboo"
        l_buy.Text = "Gear: " .. S.gear .. " trowel | Tame: " .. S.tame
        l_pet.Text = "Events: " .. S.evt
        l_status.Text = Running and "ALL THREADS ACTIVE" or "STOPPED"
        l_remote.Text = "Remotes: " .. (string.sub(RemoteInfo, 1, 60))
        local ts = {}
        for k, v in pairs(ThreadStatus) do table.insert(ts, k .. ":" .. tostring(v)) end
        l_tstat.Text = table.concat(ts, " | ")
        l_info1.Text = "Buy: Bamboo + Trowel"
        l_info2.Text = "Pets: Unicorn + Dragon + Wyvern"
        l_info3.Text = "Sell every " .. SELL_AT .. " harvests"
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
-- LAUNCH
--------------------------------------------------------------
print("[GAG2] ═══════════════════════════════════════")
print("[GAG2]  BRUTAL v6 — ERROR RECOVERY + TOGGLE")
print("[GAG2] ═══════════════════════════════════════")

init_remotes()

safe_thread("harvest", thread_harvest)
safe_thread("sell", thread_sell)
safe_thread("buy", thread_buy)
safe_thread("pets", thread_pets)
safe_thread("events", thread_events)

print("[GAG2] 5 threads launched")
getgenv().GAG2_Stop = function() Running = false end
getgenv().GAG2_Stats = S
