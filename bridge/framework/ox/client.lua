local bridge = {
    framework = 'ox',
    playerLoaded = false,
}

local Ox = require '@ox_core.lib.init'

AddEventHandler('ox:playerLoaded', function()
    bridge.playerLoaded = true
    TriggerEvent('sleepless_grid:playerLoaded')
end)

AddEventHandler('ox:playerUnloaded', function()
    bridge.playerLoaded = false
    TriggerEvent('sleepless_grid:playerUnloaded')
end)

CreateThread(function()
    local player = Ox.GetPlayer()
    bridge.playerLoaded = player ~= nil and player.charId ~= nil

    if bridge.playerLoaded then
        TriggerEvent('sleepless_grid:playerLoaded')
    end
end)

return bridge
