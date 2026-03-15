local RSGCore = nil

CreateThread(function()
    while RSGCore == nil do
        pcall(function() RSGCore = exports['rsg-core']:GetCoreObject() end)
        Wait(100)
    end
    print('[RSG-Poker] RSGCore loaded!')
end)

local Tables = {}
local PlayerTable = {}
local AINum = 0

local SUITS = {'hearts', 'diamonds', 'clubs', 'spades'}
local VALUES = {'2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'}


local function Log(msg)
    if Config.Debug then print('[POKER] ' .. msg) end
end


local function NewDeck()
    local d = {}
    for _, s in ipairs(SUITS) do
        for _, v in ipairs(VALUES) do
            d[#d+1] = {suit=s, value=v}
        end
    end
    for i = #d, 2, -1 do
        local j = math.random(i)
        d[i], d[j] = d[j], d[i]
    end
    return d
end


local function CardVal(c)
    if not c then return 0 end
    local m = {['2']=2,['3']=3,['4']=4,['5']=5,['6']=6,['7']=7,['8']=8,['9']=9,['10']=10,['J']=11,['Q']=12,['K']=13,['A']=14}
    return m[c.value] or 0
end


local function EvalHand(cards)
    if not cards or #cards < 5 then return 0, 'Nothing' end
    local vals, suits, cnt = {}, {}, {}
    for _, c in ipairs(cards) do
        local v = CardVal(c)
        vals[#vals+1] = v
        suits[#suits+1] = c.suit
        cnt[v] = (cnt[v] or 0) + 1
    end
    table.sort(vals, function(a,b) return a > b end)
    
    local sc = {}
    for _, s in ipairs(suits) do sc[s] = (sc[s] or 0) + 1 end
    local flush = false
    for _, c in pairs(sc) do if c >= 5 then flush = true end end
    
    local uniq = {}
    local seen = {}
    for _, v in ipairs(vals) do
        if not seen[v] then uniq[#uniq+1] = v seen[v] = true end
    end
    
    local straight = false
    if #uniq >= 5 then
        for i = 1, #uniq - 4 do
            if uniq[i] - uniq[i+4] == 4 then straight = true end
        end
    end
    if seen[14] and seen[2] and seen[3] and seen[4] and seen[5] then straight = true end
    
    local p, t, q = 0, 0, 0
    for _, c in pairs(cnt) do
        if c == 2 then p = p + 1
        elseif c == 3 then t = t + 1
        elseif c == 4 then q = q + 1 end
    end
    
    if flush and straight then return 9, 'Straight Flush' end
    if q > 0 then return 8, 'Four of a Kind' end
    if t > 0 and p > 0 then return 7, 'Full House' end
    if flush then return 6, 'Flush' end
    if straight then return 5, 'Straight' end
    if t > 0 then return 4, 'Three of a Kind' end
    if p >= 2 then return 3, 'Two Pair' end
    if p == 1 then return 2, 'Pair' end
    return 1, 'High Card'
end

local function GetName(src)
    if not RSGCore then return 'Player' end
    local P = RSGCore.Functions.GetPlayer(src)
    if P and P.PlayerData and P.PlayerData.charinfo then
        return (P.PlayerData.charinfo.firstname or '') .. ' ' .. (P.PlayerData.charinfo.lastname or '')
    end
    return 'Player'
end

local function Broadcast(tid, evt, ...)
    local t = Tables[tid]
    if not t then return end
    for _, p in ipairs(t.players) do
        if not p.ai and p.src then
            TriggerClientEvent(evt, p.src, ...)
        end
    end
end

local function PlayerList(tid)
    local t = Tables[tid]
    if not t then return {} end
    local list = {}
    for i, p in ipairs(t.players) do
        list[#list+1] = {
            id = p.src,
            name = p.name,
            chips = p.chips,
            bet = p.bet,
            folded = p.fold,
            isDealer = i == t.dealer,
            isCurrentTurn = i == t.turn and t.phase ~= 'wait',
            isAI = p.ai
        }
    end
    return list
end

local function MakeAI()
    AINum = AINum + 1
    local pers = Config.AI.Personalities[math.random(#Config.AI.Personalities)]
    return {
        src = -AINum,
        name = pers.name,
        chips = math.random(Config.AI.StartingChips[1], Config.AI.StartingChips[2]),
        cards = {},
        bet = 0,
        fold = false,
        acted = false,
        ai = true,
        pers = pers,
        id = AINum
    }
end


local function AIAction(p, t)
    if p.fold or p.chips <= 0 then return 'check', 0 end
    
    local toCall = (t.bet or 0) - (p.bet or 0)
    if toCall < 0 then toCall = 0 end
    
    local r = math.random()
    local agg = p.pers and p.pers.aggression or 0.5
    
    Log(string.format("AI %s: toCall=%d, chips=%d, rand=%.2f", p.name, toCall, p.chips, r))
    
    if toCall == 0 then
        
        if r < 0.3 * agg then
            local amt = math.min(math.floor(t.pot * 0.5), p.chips, 50)
            if amt >= 10 then return 'raise', amt end
        end
        return 'check', 0
    else
        
        if toCall >= p.chips then
           
            if r < 0.6 then return 'call', p.chips end
            return 'fold', 0
        elseif r < 0.25 then
            return 'fold', 0
        elseif r < 0.85 then
            return 'call', toCall
        else
            local amt = math.min(math.floor(t.pot * 0.3), p.chips - toCall, 30)
            if amt >= 10 then return 'raise', amt end
            return 'call', toCall
        end
    end
end


local DoAction, RunTurn, NextPhase, Showdown, NewRound


DoAction = function(tid, idx, act, amt)
    local t = Tables[tid]
    if not t then return end
    local p = t.players[idx]
    if not p then return end
    
    if p.fold then return end
    
    local toCall = math.max(0, (t.bet or 0) - (p.bet or 0))
    
    Log(string.format("DO: %s #%d -> %s (%d)", p.name, idx, act, amt or 0))
    
    if act == 'fold' then
        p.fold = true
        Broadcast(tid, 'rsg-poker:client:playerAction', p.name, 'fold', 0, p.ai)
        
    elseif act == 'check' then
        if toCall > 0 then
            p.fold = true
            Broadcast(tid, 'rsg-poker:client:playerAction', p.name, 'fold', 0, p.ai)
        else
            Broadcast(tid, 'rsg-poker:client:playerAction', p.name, 'check', 0, p.ai)
        end
        
    elseif act == 'call' then
        local pay = math.min(toCall, p.chips)
        p.chips = p.chips - pay
        p.bet = p.bet + pay
        t.pot = t.pot + pay
        Broadcast(tid, 'rsg-poker:client:playerAction', p.name, 'call', pay, p.ai)
        Broadcast(tid, 'rsg-poker:client:updatePot', t.pot)
        if not p.ai and p.src then
            TriggerClientEvent('rsg-poker:client:updateChips', p.src, p.chips)
        end
        
    elseif act == 'raise' then
        local raise = math.max(amt or 10, 10)
        local total = math.min(toCall + raise, p.chips)
        p.chips = p.chips - total
        p.bet = p.bet + total
        t.pot = t.pot + total
        if p.bet > t.bet then t.bet = p.bet end
        
        
        for i, pl in ipairs(t.players) do
            if i ~= idx and not pl.fold and pl.chips > 0 then
                pl.acted = false
            end
        end
        
        Broadcast(tid, 'rsg-poker:client:playerAction', p.name, 'raise', total, p.ai)
        Broadcast(tid, 'rsg-poker:client:updatePot', t.pot)
        if not p.ai and p.src then
            TriggerClientEvent('rsg-poker:client:updateChips', p.src, p.chips)
        end
        
    elseif act == 'allin' then
        local pay = p.chips
        p.bet = p.bet + pay
        t.pot = t.pot + pay
        p.chips = 0
        if p.bet > t.bet then
            t.bet = p.bet
            for i, pl in ipairs(t.players) do
                if i ~= idx and not pl.fold and pl.chips > 0 then
                    pl.acted = false
                end
            end
        end
        Broadcast(tid, 'rsg-poker:client:playerAction', p.name, 'allin', pay, p.ai)
        Broadcast(tid, 'rsg-poker:client:updatePot', t.pot)
        if not p.ai and p.src then
            TriggerClientEvent('rsg-poker:client:updateChips', p.src, p.chips)
        end
    end
    
    p.acted = true
    Broadcast(tid, 'rsg-poker:client:updatePlayers', PlayerList(tid))
end


RunTurn = function(tid)
    local t = Tables[tid]
    if not t or t.phase == 'wait' or t.phase == 'end' then return false end
    
    
    local active = 0
    for _, p in ipairs(t.players) do
        if not p.fold then active = active + 1 end
    end
    
    Log(string.format("RunTurn: phase=%s, active=%d, turn=%d", t.phase, active, t.turn or 0))
    
    if active <= 1 then
        Showdown(tid)
        return false
    end
    
    
    local count = #t.players
    local checked = 0
    local startTurn = t.turn
    
    while checked < count do
        t.turn = (t.turn % count) + 1
        checked = checked + 1
        
        local p = t.players[t.turn]
        
        if p and not p.fold then
            
            if p.chips <= 0 then
                p.acted = true
                Log(string.format("  Skip %s (no chips)", p.name))
            
            elseif p.acted and p.bet >= t.bet then
                Log(string.format("  Skip %s (acted, matched)", p.name))
            else
               
                Log(string.format("  >> %s needs to act", p.name))
                Broadcast(tid, 'rsg-poker:client:updatePlayers', PlayerList(tid))
                
                if p.ai then
                   
                    local act, amt = AIAction(p, t)
                    Log(string.format("  AI %s: %s %d", p.name, act, amt))
                    DoAction(tid, t.turn, act, amt)
                    return true 
                else
                   
                    local toCall = math.max(0, t.bet - p.bet)
                    TriggerClientEvent('rsg-poker:client:yourTurn', p.src, toCall, 10, p.chips)
                    return false 
                end
            end
        end
    end
    
    
    Log("All players acted, next phase")
    NextPhase(tid)
    return false
end


NextPhase = function(tid)
    local t = Tables[tid]
    if not t then return end
    
    Log("NextPhase from: " .. (t.phase or "?"))
    
   
    for _, p in ipairs(t.players) do
        p.bet = 0
        p.acted = false
    end
    t.bet = 0
    
   
    local active = 0
    local canBet = 0
    for _, p in ipairs(t.players) do
        if not p.fold then
            active = active + 1
            if p.chips > 0 then canBet = canBet + 1 end
        end
    end
    
    if active <= 1 then
        Showdown(tid)
        return
    end
    
  
    if t.phase == 'preflop' then
        t.phase = 'flop'
        table.remove(t.deck, 1) -- burn
        for i = 1, 3 do
            local c = table.remove(t.deck, 1)
            if c then t.comm[#t.comm+1] = c end
        end
        Broadcast(tid, 'rsg-poker:client:showCommunityCards', t.comm, 'flop')
        
    elseif t.phase == 'flop' then
        t.phase = 'turn'
        table.remove(t.deck, 1) -- burn
        local c = table.remove(t.deck, 1)
        if c then t.comm[#t.comm+1] = c end
        Broadcast(tid, 'rsg-poker:client:showCommunityCards', t.comm, 'turn')
        
    elseif t.phase == 'turn' then
        t.phase = 'river'
        table.remove(t.deck, 1) -- burn
        local c = table.remove(t.deck, 1)
        if c then t.comm[#t.comm+1] = c end
        Broadcast(tid, 'rsg-poker:client:showCommunityCards', t.comm, 'river')
        
    elseif t.phase == 'river' then
        Showdown(tid)
        return
    end
    
    Log("Phase now: " .. t.phase .. ", canBet: " .. canBet)
    
    
    if canBet <= 1 then
        Log("Not enough can bet, auto-advance")
        SetTimeout(1000, function()
            if Tables[tid] then NextPhase(tid) end
        end)
        return
    end
    
   
    t.turn = t.dealer
    
    SetTimeout(1000, function()
        if Tables[tid] then
            
            local cont = true
            local safety = 0
            while cont and safety < 20 do
                safety = safety + 1
                cont = RunTurn(tid)
            end
        end
    end)
end


Showdown = function(tid)
    local t = Tables[tid]
    if not t then return end
    
    t.phase = 'end'
    Log("=== SHOWDOWN === Pot: $" .. t.pot)
    
    local active = {}
    for _, p in ipairs(t.players) do
        if not p.fold then active[#active+1] = p end
    end
    
    local winner, handName = nil, 'Winner'
    
    if #active == 0 then
        Log("ERROR: No active players")
    elseif #active == 1 then
        winner = active[1]
        handName = 'Last Standing'
    else
        local best = -1
        for _, p in ipairs(active) do
            local all = {}
            for _, c in ipairs(p.cards or {}) do all[#all+1] = c end
            for _, c in ipairs(t.comm or {}) do all[#all+1] = c end
            local r, n = EvalHand(all)
            Log(string.format("  %s: %s (%d)", p.name, n, r))
            if r > best then
                best = r
                winner = p
                handName = n
            end
        end
    end
    
    if winner then
        winner.chips = winner.chips + t.pot
        Log(string.format("WINNER: %s wins $%d with %s", winner.name, t.pot, handName))
        
        Broadcast(tid, 'rsg-poker:client:showWinner', {
            name = winner.name,
            chips = winner.chips,
            pot = t.pot,
            handName = handName,
            cards = winner.cards,
            isAI = winner.ai
        })
        
        if not winner.ai and winner.src then
            TriggerClientEvent('rsg-poker:client:updateChips', winner.src, winner.chips)
        end
    end
    
   
    SetTimeout(5000, function()
        if Tables[tid] then NewRound(tid) end
    end)
end


NewRound = function(tid)
    local t = Tables[tid]
    if not t then return end
    
    Log("=== NEW ROUND ===")
    
   
    local i = 1
    while i <= #t.players do
        local p = t.players[i]
        if p.chips <= 0 then
            Log("Removing: " .. p.name)
            if not p.ai and p.src then
                PlayerTable[p.src] = nil
                TriggerClientEvent('rsg-poker:client:leftTable', p.src)
                TriggerClientEvent('rsg-poker:client:notification', p.src, 'Out of chips!', 'error')
            end
            table.remove(t.players, i)
        else
            i = i + 1
        end
    end
    
   
    local hasHuman = false
    for _, p in ipairs(t.players) do
        if not p.ai then hasHuman = true break end
    end
    if not hasHuman then
        Log("No humans, closing table")
        Tables[tid] = nil
        return
    end
    
    
    if #t.players < 2 then
        Log("Not enough players")
        t.phase = 'wait'
        Broadcast(tid, 'rsg-poker:client:notification', 'Waiting for players...', 'info')
        Broadcast(tid, 'rsg-poker:client:updatePlayers', PlayerList(tid))
        return
    end
    
    Log("Players: " .. #t.players)
    
    
    t.deck = NewDeck()
    t.comm = {}
    t.pot = 0
    t.bet = 0
    t.phase = 'preflop'
    
    
    if t.dealer < 1 or t.dealer > #t.players then
        t.dealer = 1
    else
        t.dealer = (t.dealer % #t.players) + 1
    end
    
    
    for _, p in ipairs(t.players) do
        p.cards = {}
        p.bet = 0
        p.fold = false
        p.acted = false
    end
    
    Broadcast(tid, 'rsg-poker:client:newRound')
    
    
    local n = #t.players
    local sb = n == 2 and t.dealer or ((t.dealer % n) + 1)
    local bb = (sb % n) + 1
    
    local sbP = t.players[sb]
    local bbP = t.players[bb]
    
    local sbAmt = math.min(Config.SmallBlind, sbP.chips)
    sbP.chips = sbP.chips - sbAmt
    sbP.bet = sbAmt
    t.pot = sbAmt
    
    local bbAmt = math.min(Config.BigBlind, bbP.chips)
    bbP.chips = bbP.chips - bbAmt
    bbP.bet = bbAmt
    t.pot = t.pot + bbAmt
    t.bet = bbAmt
    
    Log(string.format("Dealer:%d SB:%s($%d) BB:%s($%d)", t.dealer, sbP.name, sbAmt, bbP.name, bbAmt))
    
    Broadcast(tid, 'rsg-poker:client:updatePot', t.pot)
    
  
    for _, p in ipairs(t.players) do
        p.cards = {table.remove(t.deck, 1), table.remove(t.deck, 1)}
        if not p.ai and p.src then
            TriggerClientEvent('rsg-poker:client:dealCards', p.src, p.cards)
            TriggerClientEvent('rsg-poker:client:updateChips', p.src, p.chips)
        end
    end
    
    Broadcast(tid, 'rsg-poker:client:updatePlayers', PlayerList(tid))
    
  
    t.turn = bb
    
    Log("Dealing done, start betting")
    
    SetTimeout(1500, function()
        if Tables[tid] then
            local cont = true
            local safety = 0
            while cont and safety < 20 do
                safety = safety + 1
                cont = RunTurn(tid)
            end
        end
    end)
end



RegisterNetEvent('rsg-poker:server:joinTable', function(tid, buyIn, withAI, aiCount)
    local src = source
    
    Log('Join: ' .. src .. ' at ' .. tostring(tid) .. ' buyIn:' .. tostring(buyIn))
    
    if not RSGCore then return end
    local P = RSGCore.Functions.GetPlayer(src)
    if not P then return end
    
    if PlayerTable[src] then
        TriggerClientEvent('rsg-poker:client:notification', src, 'Already at table!', 'error')
        return
    end
    
    buyIn = math.max(Config.BuyInMin, math.min(Config.BuyInMax, tonumber(buyIn) or 100))
    
    local cash = tonumber(P.PlayerData.money and P.PlayerData.money['cash']) or 0
    if cash < buyIn then
        TriggerClientEvent('rsg-poker:client:notification', src, 'Not enough cash!', 'error')
        return
    end
    
    if not Tables[tid] then
        Tables[tid] = {
            players = {},
            deck = {},
            comm = {},
            pot = 0,
            bet = 0,
            dealer = 0,
            turn = 0,
            phase = 'wait'
        }
    end
    
    local t = Tables[tid]
    
    if #t.players >= Config.MaxPlayers then
        TriggerClientEvent('rsg-poker:client:notification', src, 'Table full!', 'error')
        return
    end
    
    P.Functions.RemoveMoney('cash', buyIn, 'poker')
    
    t.players[#t.players+1] = {
        src = src,
        name = GetName(src),
        chips = buyIn,
        cards = {},
        bet = 0,
        fold = false,
        acted = false,
        ai = false
    }
    PlayerTable[src] = tid
    
    Log('Joined: ' .. GetName(src) .. ' $' .. buyIn)
    
  
    if withAI and Config.AI.Enabled then
        local num = math.min(tonumber(aiCount) or 2, Config.AI.MaxBots, Config.MaxPlayers - #t.players)
        for j = 1, num do
            t.players[#t.players+1] = MakeAI()
        end
        Log('Added ' .. num .. ' AI')
    end
    
    TriggerClientEvent('rsg-poker:client:joinedTable', src, tid, buyIn, PlayerList(tid), {phase = t.phase, pot = t.pot})
    Broadcast(tid, 'rsg-poker:client:updatePlayers', PlayerList(tid))
    
    if #t.players >= 2 and t.phase == 'wait' then
        Log('Starting in 3s...')
        SetTimeout(3000, function()
            if Tables[tid] and Tables[tid].phase == 'wait' then
                NewRound(tid)
            end
        end)
    end
end)

RegisterNetEvent('rsg-poker:server:leaveTable', function(tid)
    local src = source
    local t = Tables[tid]
    if not t then return end
    
    local P = RSGCore and RSGCore.Functions.GetPlayer(src)
    
    for i, p in ipairs(t.players) do
        if p.src == src then
            if P and p.chips > 0 then
                P.Functions.AddMoney('cash', p.chips, 'poker')
            end
            
            local wasTurn = (t.turn == i)
            table.remove(t.players, i)
            PlayerTable[src] = nil
            
            TriggerClientEvent('rsg-poker:client:leftTable', src)
            
            if t.dealer > #t.players then t.dealer = math.max(1, #t.players) end
            if t.turn > #t.players then t.turn = math.max(1, #t.players) end
            
            local hasHuman = false
            for _, pl in ipairs(t.players) do
                if not pl.ai then hasHuman = true break end
            end
            
            if not hasHuman then
                Tables[tid] = nil
                return
            end
            
            Broadcast(tid, 'rsg-poker:client:updatePlayers', PlayerList(tid))
            
            -- Continue game
            if t.phase ~= 'wait' and t.phase ~= 'end' and #t.players > 0 then
                local active = 0
                for _, pl in ipairs(t.players) do
                    if not pl.fold then active = active + 1 end
                end
                if active <= 1 then
                    Showdown(tid)
                elseif wasTurn then
                    RunTurn(tid)
                end
            end
            break
        end
    end
end)

RegisterNetEvent('rsg-poker:server:playerAction', function(tid, act, amt)
    local src = source
    local t = Tables[tid]
    if not t then return end
    
    for i, p in ipairs(t.players) do
        if p.src == src then
            if t.turn ~= i then
                TriggerClientEvent('rsg-poker:client:notification', src, 'Not your turn!', 'error')
                return
            end
            
            DoAction(tid, i, act, tonumber(amt) or 0)
            
            
            SetTimeout(300, function()
                if Tables[tid] and Tables[tid].phase ~= 'end' then
                    local cont = true
                    local safety = 0
                    while cont and safety < 20 do
                        safety = safety + 1
                        cont = RunTurn(tid)
                    end
                end
            end)
            return
        end
    end
end)

RegisterNetEvent('rsg-poker:server:addAI', function(tid)
    local src = source
    local t = Tables[tid]
    if not t or not Config.AI.Enabled then return end
    
    if #t.players >= Config.MaxPlayers then
        TriggerClientEvent('rsg-poker:client:notification', src, 'Table full!', 'error')
        return
    end
    
    local ai = MakeAI()
    t.players[#t.players+1] = ai
    
    Broadcast(tid, 'rsg-poker:client:updatePlayers', PlayerList(tid))
    Broadcast(tid, 'rsg-poker:client:notification', ai.name .. ' joined!', 'info')
    
    if #t.players >= 2 and t.phase == 'wait' then
        SetTimeout(2000, function()
            if Tables[tid] and Tables[tid].phase == 'wait' then
                NewRound(tid)
            end
        end)
    end
end)

RegisterNetEvent('rsg-poker:server:removeAI', function(tid)
    local t = Tables[tid]
    if not t then return end
    
    for i = #t.players, 1, -1 do
        if t.players[i].ai and i ~= t.turn then
            local p = table.remove(t.players, i)
            Broadcast(tid, 'rsg-poker:client:notification', p.name .. ' left.', 'info')
            break
        end
    end
    
    Broadcast(tid, 'rsg-poker:client:updatePlayers', PlayerList(tid))
end)

AddEventHandler('playerDropped', function()
    local src = source
    local tid = PlayerTable[src]
    if tid and Tables[tid] then
        for i, p in ipairs(Tables[tid].players) do
            if p.src == src then
                table.remove(Tables[tid].players, i)
                break
            end
        end
        local hasHuman = false
        for _, p in ipairs(Tables[tid].players) do
            if not p.ai then hasHuman = true break end
        end
        if not hasHuman then
            Tables[tid] = nil
        else
            Broadcast(tid, 'rsg-poker:client:updatePlayers', PlayerList(tid))
        end
    end
    PlayerTable[src] = nil
end)

math.randomseed(os.time())
