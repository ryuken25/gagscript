--[[
    Grow a Garden 2 — BRUTAL v7 (Kenshi)
    ProximityPrompt + GUI dialog automation

    SELL = TP to Steven → fire ProximityPrompt → click "Sell Inventory" dialog
    BUY  = TP to Sam → fire ProximityPrompt → click Bamboo in shop GUI
    GEAR = TP to George → fire ProximityPrompt → click Trowel in gear GUI

    Usage: loadstring(game:HttpGet("https://raw.githubusercontent.com/ryuken25/gagscript/main/gagscript.lua"))()
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
-- GUI CLICK — firesignal > getconnections > manual
--------------------------------------------------------------
local function click_gui(btn)
    if not btn then return false end
    local ok = false
    if typeof(firesignal) == "function" then
        pcall(firesignal, btn.MouseButton1Click)
        pcall(firesignal, btn.Activated)
        ok = true
    end
    if typeof(getconnections) == "function" then
        local function fc(sig)
            for _, c in ipairs(getconnections(sig)) do
                pcall(function() c:Fire() end)
                ok = true
            end
        end
        pcall(fc, btn.MouseButton1Click)
        pcall(fc, btn.Activated)
    end
    if not ok then
        pcall(function() btn.MouseButton1Click:Fire() end)
    end
    return true
end

--------------------------------------------------------------
-- GUI SEARCH
--------------------------------------------------------------
local function find_btns(keywords, parent)
    parent = parent or PGui
    local results = {}
    for _, d in ipairs(parent:GetDescendants()) do
        if (d:IsA("TextButton") or d:IsA("ImageButton")) then
            local name = d.Name:lower()
            local text = d:IsA("TextButton") and (d.Text or ""):lower() or ""
            for _, kw in ipairs(keywords) do
                if name:find(kw) or text:find(kw) then
                    table.insert(results, d)
                    break
                end
            end
        end
    end
    return results
end

local function find_btn(keywords, parent)
    local r = find_btns(keywords, parent)
    return r[1]
end

local function find_label(keywords, parent)
    parent = parent or PGui
    for _, d in ipairs(parent:GetDescendants()) do
        if d:IsA("TextLabel") then
            local text = (d.Text or ""):lower()
            for _, kw in ipairs(keywords) do
                if text:find(kw) then return d end
            end
        end
    end
    return nil
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
    for _, d in ipairs(WS:GetChildren()) do
        if d:IsA("Model") and d.Name == name then return d end
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
-- INVENTORY FULL CHECK
--------------------------------------------------------------
local function is_inv_full()
    local lbl = find_label({"inventory is full", "inventory full"})
    if lbl then return true end
    return false
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
-- SELL — ProximityPrompt → Dialog → "Sell Inventory"
--------------------------------------------------------------
local function do_sell()
    local before = shk()
    local savedPos = hrp() and hrp().CFrame
    DbgMsg = "SELLING..."

    -- METHOD 1: Top bar Sell button shortcut
    local topSell = find_btn({"sell"})
    if topSell then
        print("[GAG2] Clicking top bar Sell button: " .. topSell:GetFullName())
        click_gui(topSell)
        task.wait(0.8)
    end

    -- METHOD 2: Teleport to Steven + ProximityPrompt
    local steven = find_npc("Steven")
    if steven then
        local pos = npc_pos(steven)
        if pos then
            tp(pos + Vector3.new(0, 3, 0))
            task.wait(0.3)
        end
        local prompt = npc_prompt(steven)
        if prompt then
            print("[GAG2] Firing Steven ProximityPrompt")
            fp(prompt)
            task.wait(0.8)
        end
    else
        tp(Vector3.new(62, 4, -26))
        task.wait(0.3)
        local r = hrp()
        if r then
            for _, d in ipairs(WS:GetDescendants()) do
                if d:IsA("ProximityPrompt") then
                    local par = d.Parent
                    local pos = par and par:IsA("BasePart") and par.Position
                    if not pos and par:IsA("Model") then
                        local pp = par.PrimaryPart or par:FindFirstChildOfClass("BasePart")
                        if pp then pos = pp.Position end
                    end
                    if pos and (pos - r.Position).Magnitude < 20 then
                        fp(d)
                        task.wait(0.5)
                    end
                end
            end
        end
    end

    -- STEP 2: Find and click "Sell Inventory" in the dialog
    task.wait(0.3)
    local sellInvBtn = find_btn({"sell inventory", "sellinventory", "sell_inventory"})
    if sellInvBtn then
        print("[GAG2] Found 'Sell Inventory' button: " .. sellInvBtn:GetFullName())
        click_gui(sellInvBtn)
        task.wait(0.5)
    else
        -- Broader search: any button with "sell" that appeared
        local sellBtns = find_btns({"sell"})
        for _, btn in ipairs(sellBtns) do
            local txt = btn:IsA("TextButton") and (btn.Text or ""):lower() or btn.Name:lower()
            -- Skip the top bar sell button, click dialog ones
            if txt:find("inventory") or txt:find("all") or txt == "sell" then
                print("[GAG2] Clicking sell dialog button: " .. btn:GetFullName() .. " text=" .. tostring(btn:IsA("TextButton") and btn.Text))
                click_gui(btn)
                task.wait(0.3)
            end
        end
    end

    -- STEP 3: Click any confirm/accept buttons
    task.wait(0.3)
    local confirmBtn = find_btn({"confirm", "accept", "yes", "ok"})
    if confirmBtn then
        print("[GAG2] Clicking confirm: " .. confirmBtn:GetFullName())
        click_gui(confirmBtn)
        task.wait(0.3)
    end

    task.wait(0.5)
    local after = shk()
    local gained = after - before

    if gained > 0 then
        S.sell = S.sell + 1
        print("[GAG2] SOLD! +" .. gained .. " | Total: " .. after)
        DbgMsg = "SOLD +" .. gained
    else
        print("[GAG2] Sell attempt — no change. Before=" .. before .. " After=" .. after)
        -- Debug: dump all visible buttons
        print("[GAG2] == CURRENT BUTTONS ==")
        for _, d in ipairs(PGui:GetDescendants()) do
            if d:IsA("TextButton") and d.Visible ~= false then
                print("[GAG2] BTN: \"" .. (d.Text or "?") .. "\" @ " .. d:GetFullName())
            end
        end
        DbgMsg = "SELL MISS"
    end

    HarvBuf = 0
    if savedPos then tp(savedPos) end
    return gained > 0
end

--------------------------------------------------------------
-- BUY SEEDS — ProximityPrompt on Sam → shop GUI → Bamboo
--------------------------------------------------------------
local function do_buy_bamboo()
    local before = shk()

    -- Find Sam NPC
    local sam = find_npc("Sam")
    if sam then
        local pos = npc_pos(sam)
        if pos then
            tp(pos + Vector3.new(0, 3, 0))
            task.wait(0.3)
        end
        local prompt = npc_prompt(sam)
        if prompt then
            fp(prompt)
            task.wait(0.8)
        end
    end

    -- Also try clicking Seeds button in top bar
    local seedBtn = find_btn({"seed"})
    if seedBtn then
        click_gui(seedBtn)
        task.wait(0.5)
    end

    -- Find Bamboo in shop GUI and click buy
    task.wait(0.3)
    local bambooBtn = find_btn({"bamboo"})
    if bambooBtn then
        print("[GAG2] Clicking Bamboo button: " .. bambooBtn:GetFullName())
        click_gui(bambooBtn)
        task.wait(0.3)
        -- Look for a buy/confirm after clicking bamboo
        local buyBtn = find_btn({"buy", "purchase", "confirm", "yes"})
        if buyBtn then
            click_gui(buyBtn)
            task.wait(0.2)
        end
    else
        -- Try finding bamboo label and clicking nearby buy button
        local lbl = find_label({"bamboo"})
        if lbl then
            print("[GAG2] Found Bamboo label: " .. lbl:GetFullName())
            local parent = lbl.Parent
            if parent then
                local buyBtn = find_btn({"buy", "purchase", "get"}, parent)
                if buyBtn then
                    click_gui(buyBtn)
                    task.wait(0.3)
                end
            end
        end
    end

    -- Close shop if open (press cancel/close/X)
    task.wait(0.2)
    local closeBtn = find_btn({"close", "cancel", "exit", "x"})
    if closeBtn then click_gui(closeBtn) end

    local after = shk()
    if after < before then
        S.buy = S.buy + 1
        print("[GAG2] BOUGHT Bamboo! -" .. (before - after))
        return true
    end
    return false
end

--------------------------------------------------------------
-- BUY GEAR — ProximityPrompt on George → gear GUI → Trowel
--------------------------------------------------------------
local function do_buy_trowel()
    local before = shk()

    local george = find_npc("George")
    if george then
        local pos = npc_pos(george)
        if pos then
            tp(pos + Vector3.new(0, 3, 0))
            task.wait(0.3)
        end
        local prompt = npc_prompt(george)
        if prompt then
            fp(prompt)
            task.wait(0.8)
        end
    end

    -- Also try Gear button in top bar
    local gearBtn = find_btn({"gear"})
    if gearBtn then
        click_gui(gearBtn)
        task.wait(0.5)
    end

    -- Find Trowel and click buy
    task.wait(0.3)
    local trowelBtn = find_btn({"trowel"})
    if trowelBtn then
        click_gui(trowelBtn)
        task.wait(0.3)
        local buyBtn = find_btn({"buy", "purchase", "confirm"})
        if buyBtn then click_gui(buyBtn); task.wait(0.2) end
    else
        local lbl = find_label({"trowel"})
        if lbl and lbl.Parent then
            local buyBtn = find_btn({"buy", "purchase"}, lbl.Parent)
            if buyBtn then click_gui(buyBtn); task.wait(0.3) end
        end
    end

    local closeBtn = find_btn({"close", "cancel", "exit"})
    if closeBtn then click_gui(closeBtn) end

    local after = shk()
    if after < before then
        S.gear = S.gear + 1
        print("[GAG2] BOUGHT Trowel! -" .. (before - after))
        return true
    end
    return false
end

--------------------------------------------------------------
-- T1: HARVEST
--------------------------------------------------------------
local function thread_harvest()
    while Running do
        ThreadInfo["harv"] = "scan"
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

        S.harv = S.harv + count
        HarvBuf = HarvBuf + count
        ThreadInfo["harv"] = "+" .. count
        task.wait(0.3)
    end
end

--------------------------------------------------------------
-- T2: SELL — on inventory full OR buffer >= 50
--------------------------------------------------------------
local function thread_sell()
    while Running do
        local invFull = is_inv_full()
        local bufReady = HarvBuf >= 50

        if invFull or bufReady then
            ThreadInfo["sell"] = invFull and "INV FULL!" or "buf:" .. HarvBuf
            print("[GAG2] Sell trigger: " .. (invFull and "INVENTORY FULL" or "buffer=" .. HarvBuf))
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
-- T4: PET SCANNER — Unicorn + *Dragon* + *Wyvern*
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
                    print("[GAG2] PET FOUND: " .. d.Name)
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
-- GUI
--------------------------------------------------------------
pcall(function() game:GetService("CoreGui"):FindFirstChild("GAG2K"):Destroy() end)
pcall(function() PGui:FindFirstChild("GAG2K"):Destroy() end)

local scr = Instance.new("ScreenGui")
scr.Name = "GAG2K"; scr.ResetOnSpawn = false
pcall(function() scr.Parent = game:GetService("CoreGui") end)
if not scr.Parent then scr.Parent = PGui end

local fr = Instance.new("Frame")
fr.Size = UDim2.new(0, 220, 0, 255)
fr.Position = UDim2.new(0, 8, 0.5, -128)
fr.BackgroundColor3 = Color3.fromRGB(10, 10, 18)
fr.BackgroundTransparency = 0.05
fr.BorderSizePixel = 0; fr.Parent = scr
Instance.new("UICorner", fr).CornerRadius = UDim.new(0, 8)

local hdr = Instance.new("TextLabel")
hdr.Size = UDim2.new(1, 0, 0, 22)
hdr.BackgroundColor3 = Color3.fromRGB(180, 20, 20)
hdr.Text = "GAG2 v7 — ProximityPrompt + GUI"
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
local l_harv    = lbl(40, Color3.fromRGB(100, 255, 100))
local l_stats   = lbl(55, Color3.fromRGB(100, 200, 255))
local l_stats2  = lbl(70, Color3.fromRGB(200, 100, 255))
local l_dbg     = lbl(85, Color3.fromRGB(255, 80, 80))
local l_threads = lbl(100, Color3.fromRGB(90, 90, 110))
local l_npcs    = lbl(115, Color3.fromRGB(80, 80, 100))

-- Toggle START/STOP
local togbtn = Instance.new("TextButton")
togbtn.Size = UDim2.new(0.45, 0, 0, 26)
togbtn.Position = UDim2.new(0.03, 0, 0, 133)
togbtn.BackgroundColor3 = Color3.fromRGB(30, 100, 30)
togbtn.TextColor3 = Color3.new(1, 1, 1)
togbtn.TextSize = 11; togbtn.Font = Enum.Font.GothamBold
togbtn.Text = "STOP"
togbtn.BorderSizePixel = 0; togbtn.Parent = fr
Instance.new("UICorner", togbtn).CornerRadius = UDim.new(0, 5)

-- Manual SELL NOW
local sellbtn = Instance.new("TextButton")
sellbtn.Size = UDim2.new(0.45, 0, 0, 26)
sellbtn.Position = UDim2.new(0.52, 0, 0, 133)
sellbtn.BackgroundColor3 = Color3.fromRGB(30, 60, 130)
sellbtn.TextColor3 = Color3.new(1, 1, 1)
sellbtn.TextSize = 11; sellbtn.Font = Enum.Font.GothamBold
sellbtn.Text = "SELL NOW"
sellbtn.BorderSizePixel = 0; sellbtn.Parent = fr
Instance.new("UICorner", sellbtn).CornerRadius = UDim.new(0, 5)

-- Info
local l_info1 = lbl(165, Color3.fromRGB(60, 60, 75))
local l_info2 = lbl(179, Color3.fromRGB(60, 60, 75))

local cr = Instance.new("TextLabel")
cr.Size = UDim2.new(1, 0, 0, 10)
cr.Position = UDim2.new(0, 0, 1, -12)
cr.BackgroundTransparency = 1
cr.Text = "ryuken25 | Kenshi v7"
cr.TextColor3 = Color3.fromRGB(40, 40, 50)
cr.TextSize = 8; cr.Font = Enum.Font.Gotham; cr.Parent = fr

sellbtn.MouseButton1Click:Connect(function()
    task.spawn(function()
        print("[GAG2] Manual SELL NOW")
        do_sell()
    end)
end)

togbtn.MouseButton1Click:Connect(function()
    Running = not Running
    if Running then
        togbtn.Text = "STOP"
        togbtn.BackgroundColor3 = Color3.fromRGB(30, 100, 30)
        safe_thread("harv", thread_harvest)
        safe_thread("sell", thread_sell)
        safe_thread("buy", thread_buy)
        safe_thread("pets", thread_pets)
        safe_thread("evt", thread_events)
        print("[GAG2] RESTARTED")
    else
        togbtn.Text = "START"
        togbtn.BackgroundColor3 = Color3.fromRGB(100, 25, 25)
    end
end)

-- GUI update loop
task.spawn(function()
    while scr.Parent do
        l_money.Text = "Sheckles: " .. tostring(shk())
        l_harv.Text = "Harvest: " .. S.harv .. " | buf: " .. HarvBuf
        l_stats.Text = "Sell: " .. S.sell .. " | Buy: " .. S.buy .. " bamboo"
        l_stats2.Text = "Gear: " .. S.gear .. " | Tame: " .. S.tame .. " | Evt: " .. S.evt
        l_dbg.Text = (is_inv_full() and "!! INVENTORY FULL !!" or DbgMsg)
        local ts = {}
        for k, v in pairs(ThreadInfo) do table.insert(ts, k .. ":" .. v) end
        l_threads.Text = table.concat(ts, " | ")
        -- NPC check
        local stevenOk = find_npc("Steven") and "Y" or "N"
        local samOk = find_npc("Sam") and "Y" or "N"
        local georgeOk = find_npc("George") and "Y" or "N"
        l_npcs.Text = "NPC Steven:" .. stevenOk .. " Sam:" .. samOk .. " George:" .. georgeOk
        l_info1.Text = "Buy: Bamboo + Trowel"
        l_info2.Text = "Pets: Unicorn+Dragon+Wyvern"
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
print("[GAG2]  v7 — ProximityPrompt + GUI Dialog")
print("[GAG2]  Sell: Steven prompt → 'Sell Inventory'")
print("[GAG2]  Buy: Sam prompt → shop GUI → Bamboo")
print("[GAG2] ═══════════════════════════════════════")

-- Debug: show NPCs found
local steven = find_npc("Steven")
local sam = find_npc("Sam")
local george = find_npc("George")
print("[GAG2] NPCs: Steven=" .. tostring(steven ~= nil) .. " Sam=" .. tostring(sam ~= nil) .. " George=" .. tostring(george ~= nil))
if steven then
    local pos = npc_pos(steven)
    print("[GAG2] Steven pos: " .. (pos and tostring(pos) or "nil"))
    print("[GAG2] Steven prompt: " .. tostring(npc_prompt(steven) ~= nil))
end

-- Debug: dump remotes
print("[GAG2] === REMOTES ===")
for _, c in ipairs(RS:GetDescendants()) do
    if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
        print("[GAG2] RE: " .. c.Name .. " @ " .. c:GetFullName())
    end
end

safe_thread("harv", thread_harvest)
safe_thread("sell", thread_sell)
safe_thread("buy", thread_buy)
safe_thread("pets", thread_pets)
safe_thread("evt", thread_events)

DbgMsg = "5 THREADS ACTIVE"
print("[GAG2] Launched 5 threads")
getgenv().GAG2_Stop = function() Running = false end
getgenv().GAG2_Sell = do_sell
getgenv().GAG2_Stats = S
