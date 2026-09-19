--[[
    Grow a Garden 2 — v8 DIRECT INJECT (Kenshi)
    No GUI clicking — hooks __namecall to spy remotes, brute-forces ReplicaRequestData

    SELL = direct remote inject + NPC proximity fallback
    BUY  = direct remote inject + NPC proximity fallback
    HARVEST = ProximityPrompt scan (proven working)

    loadstring(game:HttpGet("https://raw.githubusercontent.com/ryuken25/gagscript/main/gagscript.lua"))()
]]

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local WS      = game:GetService("Workspace")
local VU      = game:GetService("VirtualUser")
local LP      = Players.LocalPlayer
local PGui    = LP:WaitForChild("PlayerGui")
local LS      = LP:WaitForChild("leaderstats", 10)

local Running = true
local S = { harv = 0, sell = 0, buy = 0, gear = 0, tame = 0, evt = 0 }
local HarvBuf = 0
local DbgMsg = "INIT"
local ThreadInfo = {}
local SpyLog = {}
local MAX_SPY = 50

--------------------------------------------------------------
-- UTILS
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
    r.CFrame = typeof(pos) == "CFrame" and pos or CFrame.new(pos)
    task.wait(0.1)
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

--------------------------------------------------------------
-- REMOTE SPY — hooks __namecall to log ALL remote traffic
--------------------------------------------------------------
local function setup_spy()
    if typeof(hookmetamethod) ~= "function" then
        warn("[GAG2] hookmetamethod not available — spy disabled")
        return
    end

    local old
    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if (method == "FireServer" or method == "InvokeServer")
            and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
            local args = {...}
            local argStr = ""
            for i, v in ipairs(args) do
                if i > 1 then argStr = argStr .. ", " end
                argStr = argStr .. tostring(v)
            end
            local entry = self.Name .. ":" .. method .. "(" .. argStr .. ")"
            print("[SPY] " .. entry)
            table.insert(SpyLog, 1, entry)
            if #SpyLog > MAX_SPY then table.remove(SpyLog) end
        end
        return old(self, ...)
    end))

    print("[GAG2] Remote spy ACTIVE — all FireServer/InvokeServer calls will be logged")
end

--------------------------------------------------------------
-- COLLECT ALL REMOTES
--------------------------------------------------------------
local AllRemotes = {}
local RemoteNames = {}

local function init_remotes()
    AllRemotes = {}
    RemoteNames = {}
    for _, c in ipairs(RS:GetDescendants()) do
        if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
            AllRemotes[c.Name] = c
            table.insert(RemoteNames, c.Name)
        end
    end
    print("[GAG2] Found " .. #RemoteNames .. " remotes: " .. table.concat(RemoteNames, ", "))
end

--------------------------------------------------------------
-- NPC FINDER
--------------------------------------------------------------
local function find_npc(name)
    local npcs = WS:FindFirstChild("NPCS") or WS:FindFirstChild("NPCs") or WS:FindFirstChild("Npcs")
    if npcs then
        local npc = npcs:FindFirstChild(name)
        if npc then return npc end
        for _, c in ipairs(npcs:GetChildren()) do
            if c.Name:lower() == name:lower() then return c end
        end
    end
    return nil
end

local function npc_pos(npc)
    if not npc then return nil end
    local p = npc.PrimaryPart or npc:FindFirstChildOfClass("BasePart")
    return p and p.Position
end

local function npc_prompt(npc)
    if not npc then return nil end
    return npc:FindFirstChild("ProximityPrompt", true)
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
-- INVENTORY FULL CHECK
--------------------------------------------------------------
local function is_inv_full()
    for _, d in ipairs(PGui:GetDescendants()) do
        if d:IsA("TextLabel") then
            local t = d.Text or ""
            if t:find("Inventory is full") or t:find("inventory full") then
                return true
            end
        end
    end
    return false
end

--------------------------------------------------------------
-- SAFE THREAD
--------------------------------------------------------------
local function safe_thread(name, fn)
    task.spawn(function()
        while Running do
            ThreadInfo[name] = "run"
            local ok, err = pcall(fn)
            if not ok then
                ThreadInfo[name] = "ERR"
                warn("[GAG2] " .. name .. " crash: " .. tostring(err))
                task.wait(2)
            end
        end
        ThreadInfo[name] = "off"
    end)
end

--------------------------------------------------------------
-- SELL — direct inject + proximity fallback
--------------------------------------------------------------
local function do_sell()
    local before = shk()
    local savedPos = hrp() and hrp().CFrame
    DbgMsg = "SELLING..."
    print("[GAG2] === SELL START === Sheckles: " .. before)

    -- STEP 1: TP to Steven for proximity-based sell
    local steven = find_npc("Steven")
    if steven then
        local pos = npc_pos(steven)
        if pos then tp(pos + Vector3.new(0, 3, 0)); task.wait(0.3) end
        local prompt = npc_prompt(steven)
        if prompt then
            print("[GAG2] Firing Steven prompt")
            fp(prompt)
            task.wait(0.5)
        end
    else
        tp(Vector3.new(62, 4, -26))
        task.wait(0.3)
        -- Fire ANY prompt near sell area
        local r = hrp()
        if r then
            for _, d in ipairs(WS:GetDescendants()) do
                if d:IsA("ProximityPrompt") then
                    local par = d.Parent
                    local pos
                    if par:IsA("BasePart") then pos = par.Position
                    elseif par:IsA("Model") then
                        local pp = par.PrimaryPart or par:FindFirstChildOfClass("BasePart")
                        if pp then pos = pp.Position end
                    end
                    if pos and (pos - r.Position).Magnitude < 25 then
                        fp(d); task.wait(0.2)
                    end
                end
            end
        end
    end

    -- STEP 2: After opening dialog, try clicking "Sell Inventory" via firesignal
    task.wait(0.5)
    for _, d in ipairs(PGui:GetDescendants()) do
        if d:IsA("TextButton") then
            local txt = (d.Text or ""):lower()
            if txt:find("sell inventory") or txt:find("sell all") then
                print("[GAG2] Clicking: " .. d.Text .. " @ " .. d:GetFullName())
                if typeof(firesignal) == "function" then
                    pcall(firesignal, d.MouseButton1Click)
                    pcall(firesignal, d.Activated)
                elseif typeof(getconnections) == "function" then
                    for _, c in ipairs(getconnections(d.MouseButton1Click)) do
                        pcall(function() c:Fire() end)
                    end
                    for _, c in ipairs(getconnections(d.Activated)) do
                        pcall(function() c:Fire() end)
                    end
                end
                task.wait(0.3)
                break
            end
        end
    end

    -- STEP 3: Brute force ReplicaRequestData with sell patterns
    local rrd = AllRemotes["ReplicaRequestData"]
    if rrd then
        print("[GAG2] Trying ReplicaRequestData sell patterns...")
        local patterns = {
            {"Sell"}, {"SellAll"}, {"SellInventory"}, {"Sell_Inventory"},
            {"sell"}, {"sell_all"}, {"sell_inventory"},
            {"Sell", "All"}, {"Sell", "Inventory"},
            {"Shop", "Sell"}, {"Shop", "SellAll"},
            {"Action", "Sell"}, {"Actions", "SellInventory"},
            {"Player", "Sell"}, {"Inventory", "Sell"},
        }
        for _, args in ipairs(patterns) do
            pcall(function() rrd:FireServer(unpack(args)) end)
            task.wait(0.05)
        end
    end

    -- STEP 4: Try all other remotes too
    for name, re in pairs(AllRemotes) do
        if name:lower():find("sell") then
            pcall(function() re:FireServer() end)
            task.wait(0.05)
        end
    end

    task.wait(0.5)
    local after = shk()
    local gained = after - before

    if gained > 0 then
        S.sell = S.sell + 1
        DbgMsg = "SOLD +" .. gained
        print("[GAG2] SOLD! +" .. gained .. " | Total: " .. after)
    else
        DbgMsg = "SELL: no change"
        print("[GAG2] Sell — no Sheckles change")
        -- Dump what spy caught
        if #SpyLog > 0 then
            print("[GAG2] Recent spy log:")
            for i = 1, math.min(5, #SpyLog) do
                print("[GAG2]   " .. SpyLog[i])
            end
        end
    end

    HarvBuf = 0
    if savedPos then tp(savedPos) end
    return gained > 0
end

--------------------------------------------------------------
-- BUY BAMBOO — direct inject + NPC prompt fallback
--------------------------------------------------------------
local function do_buy_bamboo()
    local before = shk()

    -- Direct inject via ReplicaRequestData
    local rrd = AllRemotes["ReplicaRequestData"]
    if rrd then
        local patterns = {
            {"Buy", "Bamboo"}, {"BuySeed", "Bamboo"}, {"BuySeedStock", "Bamboo"},
            {"buy", "Bamboo"}, {"buy_seed", "Bamboo"},
            {"Shop", "Buy", "Bamboo"}, {"Shop", "BuySeed", "Bamboo"},
            {"Seeds", "Buy", "Bamboo"}, {"Action", "BuySeed", "Bamboo"},
            {"Purchase", "Bamboo"}, {"Buy", "Bamboo Seed"},
            {"BuySeed", "Bamboo Seed"}, {"buy", "bamboo"},
        }
        for _, args in ipairs(patterns) do
            pcall(function() rrd:FireServer(unpack(args)) end)
            task.wait(0.05)
        end
    end

    -- Try legacy remotes
    for _, name in ipairs({"BuySeedStock", "BuySeed", "Buy_Seed", "BuyStock"}) do
        local re = AllRemotes[name]
        if re then pcall(function() re:FireServer("Bamboo") end); task.wait(0.05) end
    end

    -- NPC fallback: Sam proximity prompt
    local sam = find_npc("Sam")
    if sam then
        local pos = npc_pos(sam)
        if pos then tp(pos + Vector3.new(0, 3, 0)); task.wait(0.3) end
        local prompt = npc_prompt(sam)
        if prompt then fp(prompt); task.wait(0.5) end
    end

    -- Click Bamboo in shop GUI if it opened
    for _, d in ipairs(PGui:GetDescendants()) do
        if d:IsA("TextButton") then
            local txt = (d.Text or ""):lower()
            if txt:find("bamboo") then
                if typeof(firesignal) == "function" then
                    pcall(firesignal, d.MouseButton1Click)
                elseif typeof(getconnections) == "function" then
                    for _, c in ipairs(getconnections(d.MouseButton1Click)) do
                        pcall(function() c:Fire() end)
                    end
                end
                task.wait(0.3)
                -- Click buy/confirm
                for _, d2 in ipairs(PGui:GetDescendants()) do
                    if d2:IsA("TextButton") then
                        local t2 = (d2.Text or ""):lower()
                        if t2:find("buy") or t2:find("purchase") or t2:find("confirm") then
                            if typeof(firesignal) == "function" then
                                pcall(firesignal, d2.MouseButton1Click)
                            end
                            task.wait(0.2)
                            break
                        end
                    end
                end
                break
            end
        end
    end

    local after = shk()
    if after < before then
        S.buy = S.buy + 1
        print("[GAG2] BOUGHT Bamboo! -" .. (before - after))
        return true
    end
    return false
end

--------------------------------------------------------------
-- BUY TROWEL — direct inject + NPC prompt fallback
--------------------------------------------------------------
local function do_buy_trowel()
    local before = shk()

    local rrd = AllRemotes["ReplicaRequestData"]
    if rrd then
        local patterns = {
            {"Buy", "Trowel"}, {"BuyGear", "Trowel"}, {"BuyGearStock", "Trowel"},
            {"buy", "Trowel"}, {"buy_gear", "Trowel"},
            {"Shop", "Buy", "Trowel"}, {"Shop", "BuyGear", "Trowel"},
            {"Gear", "Buy", "Trowel"}, {"Purchase", "Trowel"},
        }
        for _, args in ipairs(patterns) do
            pcall(function() rrd:FireServer(unpack(args)) end)
            task.wait(0.05)
        end
    end

    for _, name in ipairs({"BuyGearStock", "BuyGear", "Buy_Gear"}) do
        local re = AllRemotes[name]
        if re then pcall(function() re:FireServer("Trowel") end); task.wait(0.05) end
    end

    -- George NPC fallback
    local george = find_npc("George")
    if george then
        local pos = npc_pos(george)
        if pos then tp(pos + Vector3.new(0, 3, 0)); task.wait(0.3) end
        local prompt = npc_prompt(george)
        if prompt then fp(prompt); task.wait(0.5) end
    end

    -- Click Trowel in gear GUI
    for _, d in ipairs(PGui:GetDescendants()) do
        if d:IsA("TextButton") and (d.Text or ""):lower():find("trowel") then
            if typeof(firesignal) == "function" then
                pcall(firesignal, d.MouseButton1Click)
            end
            task.wait(0.3)
            for _, d2 in ipairs(PGui:GetDescendants()) do
                if d2:IsA("TextButton") and ((d2.Text or ""):lower():find("buy") or (d2.Text or ""):lower():find("confirm")) then
                    if typeof(firesignal) == "function" then pcall(firesignal, d2.MouseButton1Click) end
                    break
                end
            end
            break
        end
    end

    local after = shk()
    if after < before then
        S.gear = S.gear + 1
        print("[GAG2] BOUGHT Trowel! -" .. (before - after))
        return true
    end
    return false
end

--------------------------------------------------------------
-- T1: HARVEST — scan farm + nearby prompts
--------------------------------------------------------------
local function thread_harvest()
    while Running do
        ThreadInfo["harv"] = "scan"
        local farm = find_farm()
        local count = 0

        -- Scan farm plots
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

        -- Also scan nearby workspace prompts (catches plants outside farm folder)
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
        ThreadInfo["harv"] = "+" .. count
        task.wait(0.3)
    end
end

--------------------------------------------------------------
-- T2: SELL — inventory full OR buffer >= 50
--------------------------------------------------------------
local function thread_sell()
    while Running do
        local invFull = is_inv_full()
        local bufReady = HarvBuf >= 50

        if invFull or bufReady then
            ThreadInfo["sell"] = invFull and "INV FULL" or "buf>" .. HarvBuf
            do_sell()
            task.wait(2)
        else
            ThreadInfo["sell"] = "buf:" .. HarvBuf
        end
        task.wait(1)
    end
end

--------------------------------------------------------------
-- T3: BUY BAMBOO + TROWEL
--------------------------------------------------------------
local function thread_buy()
    while Running do
        ThreadInfo["buy"] = "bamboo"
        do_buy_bamboo()
        task.wait(2)
        ThreadInfo["buy"] = "trowel"
        do_buy_trowel()
        ThreadInfo["buy"] = "wait"
        task.wait(8)
    end
end

--------------------------------------------------------------
-- T4: PET SCANNER
--------------------------------------------------------------
local function is_wanted(name)
    if name == "Unicorn" then return true end
    local l = name:lower()
    return l:find("dragon") or l:find("wyvern")
end

local function thread_pets()
    while Running do
        ThreadInfo["pets"] = "scan"
        for _, d in ipairs(WS:GetDescendants()) do
            if not Running then return end
            if d:IsA("Model") and is_wanted(d.Name) then
                local prompt = d:FindFirstChild("ProximityPrompt", true)
                if prompt and prompt:IsA("ProximityPrompt") then
                    ThreadInfo["pets"] = d.Name
                    print("[GAG2] PET: " .. d.Name)
                    local part = d.PrimaryPart or d:FindFirstChildOfClass("BasePart")
                    if part then tp(part.Position + Vector3.new(0, 2, 0)); task.wait(0.1) end
                    if fp(prompt) then
                        S.tame = S.tame + 1
                        print("[GAG2] TAMED: " .. d.Name)
                    end
                    task.wait(0.3)
                end
            end
        end
        ThreadInfo["pets"] = "idle"
        task.wait(3)
    end
end

--------------------------------------------------------------
-- T5: EVENTS
--------------------------------------------------------------
local function thread_events()
    while Running do
        ThreadInfo["evt"] = "scan"
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
                        task.wait(0.1)
                    end
                end
            end
        end
        ThreadInfo["evt"] = "idle"
        task.wait(5)
    end
end

--------------------------------------------------------------
-- ANTI-AFK
--------------------------------------------------------------
LP.Idled:Connect(function()
    if VU then VU:CaptureController(); VU:ClickButton2(Vector2.new()) end
end)

--------------------------------------------------------------
-- GUI (compact)
--------------------------------------------------------------
pcall(function() game:GetService("CoreGui"):FindFirstChild("GAG2K"):Destroy() end)
pcall(function() PGui:FindFirstChild("GAG2K"):Destroy() end)

local scr = Instance.new("ScreenGui")
scr.Name = "GAG2K"; scr.ResetOnSpawn = false
pcall(function() scr.Parent = game:GetService("CoreGui") end)
if not scr.Parent then scr.Parent = PGui end

local fr = Instance.new("Frame")
fr.Size = UDim2.new(0, 230, 0, 270)
fr.Position = UDim2.new(0, 8, 0.5, -135)
fr.BackgroundColor3 = Color3.fromRGB(10, 10, 18)
fr.BackgroundTransparency = 0.05
fr.BorderSizePixel = 0; fr.Parent = scr
Instance.new("UICorner", fr).CornerRadius = UDim.new(0, 8)

local hdr = Instance.new("TextLabel")
hdr.Size = UDim2.new(1, 0, 0, 22)
hdr.BackgroundColor3 = Color3.fromRGB(120, 0, 180)
hdr.Text = "GAG2 v8 — DIRECT INJECT + SPY"
hdr.TextColor3 = Color3.new(1, 1, 1)
hdr.TextSize = 10; hdr.Font = Enum.Font.GothamBold
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
    l.TextWrapped = true
    l.Text = ""; l.Parent = fr; return l
end

local l_money   = lbl(25, Color3.fromRGB(255, 215, 0))
local l_harv    = lbl(39, Color3.fromRGB(100, 255, 100))
local l_stats   = lbl(53, Color3.fromRGB(100, 200, 255))
local l_stats2  = lbl(67, Color3.fromRGB(200, 100, 255))
local l_dbg     = lbl(81, Color3.fromRGB(255, 80, 80))
local l_threads = lbl(95, Color3.fromRGB(90, 90, 110))
local l_npcs    = lbl(109, Color3.fromRGB(80, 100, 80))
local l_spy     = lbl(123, Color3.fromRGB(255, 200, 50))

-- Buttons
local togbtn = Instance.new("TextButton")
togbtn.Size = UDim2.new(0.45, 0, 0, 26)
togbtn.Position = UDim2.new(0.03, 0, 0, 140)
togbtn.BackgroundColor3 = Color3.fromRGB(30, 100, 30)
togbtn.TextColor3 = Color3.new(1, 1, 1)
togbtn.TextSize = 11; togbtn.Font = Enum.Font.GothamBold
togbtn.Text = "STOP"; togbtn.BorderSizePixel = 0; togbtn.Parent = fr
Instance.new("UICorner", togbtn).CornerRadius = UDim.new(0, 5)

local sellbtn = Instance.new("TextButton")
sellbtn.Size = UDim2.new(0.45, 0, 0, 26)
sellbtn.Position = UDim2.new(0.52, 0, 0, 140)
sellbtn.BackgroundColor3 = Color3.fromRGB(30, 60, 130)
sellbtn.TextColor3 = Color3.new(1, 1, 1)
sellbtn.TextSize = 11; sellbtn.Font = Enum.Font.GothamBold
sellbtn.Text = "SELL NOW"; sellbtn.BorderSizePixel = 0; sellbtn.Parent = fr
Instance.new("UICorner", sellbtn).CornerRadius = UDim.new(0, 5)

-- Spy display area
local l_spy2 = lbl(172, Color3.fromRGB(200, 180, 40))
local l_spy3 = lbl(186, Color3.fromRGB(200, 180, 40))

local l_info1 = lbl(204, Color3.fromRGB(60, 60, 75))
local l_info2 = lbl(218, Color3.fromRGB(60, 60, 75))

local cr = Instance.new("TextLabel")
cr.Size = UDim2.new(1, 0, 0, 10)
cr.Position = UDim2.new(0, 0, 1, -12)
cr.BackgroundTransparency = 1
cr.Text = "ryuken25 | Kenshi v8"
cr.TextColor3 = Color3.fromRGB(40, 40, 50)
cr.TextSize = 8; cr.Font = Enum.Font.Gotham; cr.Parent = fr

sellbtn.MouseButton1Click:Connect(function()
    task.spawn(function() do_sell() end)
end)

togbtn.MouseButton1Click:Connect(function()
    Running = not Running
    if Running then
        togbtn.Text = "STOP"; togbtn.BackgroundColor3 = Color3.fromRGB(30, 100, 30)
        safe_thread("harv", thread_harvest)
        safe_thread("sell", thread_sell)
        safe_thread("buy", thread_buy)
        safe_thread("pets", thread_pets)
        safe_thread("evt", thread_events)
    else
        togbtn.Text = "START"; togbtn.BackgroundColor3 = Color3.fromRGB(100, 25, 25)
    end
end)

-- GUI update
task.spawn(function()
    while scr.Parent do
        l_money.Text = "Sheckles: " .. tostring(shk())
        l_harv.Text = "Harvest: " .. S.harv .. " | buf: " .. HarvBuf
        l_stats.Text = "Sell: " .. S.sell .. " | Buy: " .. S.buy .. " bamboo"
        l_stats2.Text = "Gear: " .. S.gear .. " | Tame: " .. S.tame .. " | Evt: " .. S.evt
        l_dbg.Text = is_inv_full() and "!! INVENTORY FULL !!" or DbgMsg
        local ts = {}
        for k, v in pairs(ThreadInfo) do table.insert(ts, k .. ":" .. v) end
        l_threads.Text = table.concat(ts, " | ")
        local stevenOk = find_npc("Steven") and "Y" or "N"
        local samOk = find_npc("Sam") and "Y" or "N"
        l_npcs.Text = "Steven:" .. stevenOk .. " Sam:" .. samOk
        -- Spy log display
        l_spy.Text = "SPY: " .. (#SpyLog > 0 and SpyLog[1] or "waiting...")
        l_spy2.Text = #SpyLog > 1 and SpyLog[2] or ""
        l_spy3.Text = #SpyLog > 2 and SpyLog[3] or ""
        l_info1.Text = "Buy: Bamboo+Trowel | Pets: Uni+Dragon+Wyvern"
        l_info2.Text = "Remotes: " .. string.sub(table.concat(RemoteNames, ","), 1, 60)
        togbtn.Text = Running and "STOP" or "START"
        togbtn.BackgroundColor3 = Running and Color3.fromRGB(30, 100, 30) or Color3.fromRGB(100, 25, 25)
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
print("[GAG2]  v8 — DIRECT INJECT + REMOTE SPY")
print("[GAG2]  hookmetamethod logs ALL remote calls")
print("[GAG2] ═══════════════════════════════════════")

init_remotes()
setup_spy()

-- Debug dump
local steven = find_npc("Steven")
local sam = find_npc("Sam")
print("[GAG2] NPCs: Steven=" .. tostring(steven ~= nil) .. " Sam=" .. tostring(sam ~= nil))
if steven then
    print("[GAG2] Steven pos: " .. tostring(npc_pos(steven)))
    print("[GAG2] Steven prompt: " .. tostring(npc_prompt(steven) ~= nil))
end

safe_thread("harv", thread_harvest)
safe_thread("sell", thread_sell)
safe_thread("buy", thread_buy)
safe_thread("pets", thread_pets)
safe_thread("evt", thread_events)

DbgMsg = "5 THREADS + SPY ACTIVE"
print("[GAG2] 5 threads + remote spy launched")
print("[GAG2] TIP: Sell manually once — spy will capture the exact remote call!")
getgenv().GAG2_Stop = function() Running = false end
getgenv().GAG2_Sell = do_sell
getgenv().GAG2_Spy = SpyLog
getgenv().GAG2_Stats = S
