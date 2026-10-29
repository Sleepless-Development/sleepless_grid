local bridge = {
    framework = 'qb',
    playerLoaded = false,
}

local QBCore = exports['qb-core']:GetCoreObject()

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    bridge.playerLoaded = true
    TriggerEvent('sleepless_grid:playerLoaded')
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    bridge.playerLoaded = false
    TriggerEvent('sleepless_grid:playerUnloaded')
end)

local function isCharacterLoaded()
    if LocalPlayer.state.isLoggedIn == true then
        return true
    end

    local data = QBCore.Functions.GetPlayerData()
    return type(data) == 'table' and type(data.citizenid) == 'string' and data.citizenid ~= ''
end

CreateThread(function()
    bridge.playerLoaded = isCharacterLoaded()

    if bridge.playerLoaded then
        TriggerEvent('sleepless_grid:playerLoaded')
    end
end)

return bridge
