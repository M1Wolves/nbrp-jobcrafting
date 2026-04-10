fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'M1Wolves'
description 'Standalone job crafting with ox_target, ox_lib, ox_inventory, and QBCore'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

files {
    'data/stations.json'
}

dependencies {
    'ox_lib',
    'ox_target',
    'qb-core',
    'oxmysql'
}
