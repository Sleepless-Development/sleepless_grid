local bridge = {
    framework = 'esx',
    playerLoaded = false,
}

local ESX = exports['es_extended']:getSharedObject()

RegisterNetEvent('esx:playerLoaded', function()
    bridge.playerLoaded = true
    TriggerEvent('sleepless_grid:playerLoaded')
end)

AddEventHandler('esx:onPlayerLogout', function()
    bridge.playerLoaded = false
    TriggerEvent('sleepless_grid:playerUnloaded')
end)

CreateThread(function()
    bridge.playerLoaded = ESX.IsPlayerLoaded()

    if bridge.playerLoaded then
        TriggerEvent('sleepless_grid:playerLoaded')
    end
end)

return bridge
