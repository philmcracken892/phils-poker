local RSGCore = nil
local inPoker = false
local currentTable = nil
local playerChips = 0
local isMyTurn = false


CreateThread(function()
    while RSGCore == nil do
        local success, result = pcall(function()
            return exports['rsg-core']:GetCoreObject()
        end)
        if success and result then
            RSGCore = result
        end
        Wait(500)
    end
   
end)


local function GetTableId(coords)
    local x = math.floor(coords.x * 100)
    local y = math.floor(coords.y * 100)
    local z = math.floor(coords.z * 100)
    return string.format("poker_%d_%d_%d", x, y, z)
end


local function Notify(msg, msgType)
    if RSGCore and RSGCore.Functions and RSGCore.Functions.Notify then
        RSGCore.Functions.Notify(msg, msgType)
    else
        
    end
end


local function GetPlayerCash()
    if not RSGCore then 
       
        return 0 
    end
    
    local PlayerData = RSGCore.Functions.GetPlayerData()
    
    if Config.Debug then
       
        if PlayerData then
           
            if PlayerData.money then
                
                for k, v in pairs(PlayerData.money) do
                    
                end
            end
        end
    end
    
    if not PlayerData then 
      
        return 0 
    end
    
   
    local cash = 0
    
    if PlayerData.money then
        
        if PlayerData.money['cash'] then
            cash = tonumber(PlayerData.money['cash']) or 0
        
        elseif PlayerData.money['Cash'] then
            cash = tonumber(PlayerData.money['Cash']) or 0
        
        elseif PlayerData.money['money'] then
            cash = tonumber(PlayerData.money['money']) or 0
        
        else
            for k, v in pairs(PlayerData.money) do
                if type(v) == 'number' and v > 0 then
                    cash = v
                   
                    break
                end
            end
        end
    end
    
    
    if cash == 0 and PlayerData.charinfo then
        if PlayerData.charinfo.cash then
            cash = tonumber(PlayerData.charinfo.cash) or 0
        end
    end
    
   
    return cash
end


CreateThread(function()
    Wait(3000)
    
    local success, err = pcall(function()
        for _, model in ipairs(Config.PokerModels) do
            exports.ox_target:addModel(model, {
                {
                    name = 'poker_play_' .. tostring(model),
                    icon = 'fas fa-cards',
                    label = 'Play Poker',
                    canInteract = function()
                        return not inPoker
                    end,
                    onSelect = function(data)
                        local coords = GetEntityCoords(data.entity)
                        OpenPokerMenu(coords)
                    end,
                    distance = 2.5
                },
                {
                    name = 'poker_leave_' .. tostring(model),
                    icon = 'fas fa-door-open',
                    label = 'Leave Table',
                    canInteract = function()
                        return inPoker
                    end,
                    onSelect = function()
                        LeavePokerTable()
                    end,
                    distance = 2.5
                }
            })
        end
       
    end)
    
    if not success then
       
    end
end)


function OpenPokerMenu(coords)
    if inPoker then
        Notify('You are already playing poker!', 'error')
        return
    end
    
    local playerMoney = GetPlayerCash()
    
    
    
    
    
    currentTable = GetTableId(coords)
    
    
    
   
    if playerMoney < 1 then
        playerMoney = 1000
        
    end
    
    SendNUIMessage({
        action = 'openBuyIn',
        minBuyIn = Config.BuyInMin,
        maxBuyIn = math.max(Config.BuyInMax, playerMoney),
        playerMoney = playerMoney,
        aiEnabled = Config.AI.Enabled
    })
    SetNuiFocus(true, true)
end

function LeavePokerTable()
    if not inPoker then return end
    TriggerServerEvent('rsg-poker:server:leaveTable', currentTable)
end




RegisterNUICallback('uiReady', function(data, cb)
    
    cb('ok')
end)

RegisterNUICallback('buyIn', function(data, cb)
    if not currentTable then
        Notify('Error: No table selected!', 'error')
        SetNuiFocus(false, false)
        cb('ok')
        return
    end
    
    local amount = tonumber(data.amount) or 100
    local withAI = data.withAI or false
    local aiCount = tonumber(data.aiCount) or 2
    
   
    
    TriggerServerEvent('rsg-poker:server:joinTable', currentTable, amount, withAI, aiCount)
    cb('ok')
end)

RegisterNUICallback('closeBuyIn', function(data, cb)
    SetNuiFocus(false, false)
    currentTable = nil
    cb('ok')
end)

RegisterNUICallback('pokerAction', function(data, cb)
    if not isMyTurn then
        cb('ok')
        return
    end
    
    TriggerServerEvent('rsg-poker:server:playerAction', currentTable, data.action, tonumber(data.amount) or 0)
    isMyTurn = false
    cb('ok')
end)

RegisterNUICallback('closePoker', function(data, cb)
    LeavePokerTable()
    cb('ok')
end)

RegisterNUICallback('addAI', function(data, cb)
    TriggerServerEvent('rsg-poker:server:addAI', currentTable)
    cb('ok')
end)

RegisterNUICallback('removeAI', function(data, cb)
    TriggerServerEvent('rsg-poker:server:removeAI', currentTable)
    cb('ok')
end)


RegisterNetEvent('rsg-poker:client:joinedTable', function(tableId, chips, players, tableData)
    inPoker = true
    playerChips = chips
    currentTable = tableId

    SendNUIMessage({
        action = 'openPoker',
        chips = chips,
        players = players,
        smallBlind = Config.SmallBlind,
        bigBlind = Config.BigBlind,
        aiEnabled = Config.AI.Enabled
    })
    SetNuiFocus(true, true)
    Notify('Joined table with $' .. chips, 'success')
end)

RegisterNetEvent('rsg-poker:client:leftTable', function()
    inPoker = false
    currentTable = nil
    playerChips = 0
    isMyTurn = false
    SendNUIMessage({ action = 'closePoker' })
    SetNuiFocus(false, false)
end)

RegisterNetEvent('rsg-poker:client:yourTurn', function(callAmount, minRaise, maxRaise)
    isMyTurn = true
    SendNUIMessage({
        action = 'yourTurn',
        callAmount = callAmount,
        minRaise = minRaise,
        maxRaise = maxRaise
    })
end)

RegisterNetEvent('rsg-poker:client:dealCards', function(cards)
    SendNUIMessage({ action = 'dealCards', cards = cards })
end)

RegisterNetEvent('rsg-poker:client:showCommunityCards', function(cards, stage)
    SendNUIMessage({ action = 'communityCards', cards = cards, stage = stage })
end)

RegisterNetEvent('rsg-poker:client:showWinner', function(winnerData)
    SendNUIMessage({ action = 'showWinner', winner = winnerData })
end)

RegisterNetEvent('rsg-poker:client:updateChips', function(chips)
    playerChips = chips
    SendNUIMessage({ action = 'updateChips', chips = chips })
end)

RegisterNetEvent('rsg-poker:client:playerAction', function(playerName, action, amount, isAI)
    SendNUIMessage({
        action = 'playerAction',
        playerName = playerName,
        playerAction = action,
        amount = amount,
        isAI = isAI
    })
end)

RegisterNetEvent('rsg-poker:client:newRound', function()
    SendNUIMessage({ action = 'newRound' })
end)

RegisterNetEvent('rsg-poker:client:updatePot', function(pot)
    SendNUIMessage({ action = 'updatePot', pot = pot })
end)

RegisterNetEvent('rsg-poker:client:updatePlayers', function(players)
    SendNUIMessage({ action = 'updatePlayers', players = players })
end)

RegisterNetEvent('rsg-poker:client:notification', function(msg, msgType)
    Notify(msg, msgType)
end)

RegisterNetEvent('rsg-poker:client:aiThinking', function(aiName)
    SendNUIMessage({ action = 'aiThinking', name = aiName })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        SetNuiFocus(false, false)
    end
end)

