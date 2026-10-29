fx_version 'cerulean'
use_experimental_fxv2_oal 'yes'
lua54 'yes'
game 'gta5'

name 'sleepless_grid'
author 'DemiAutomatic'
description 'Spatial grid for streaming cells and routing-bucket membership'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/version.lua',
    'server/main.lua',
}

files {
    'config.lua',
    'shared/*.lua',
    'bridge/*.lua',
    'bridge/**/*.lua',
}

dependency 'ox_lib'
