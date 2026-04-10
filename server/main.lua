local QBCore = exports['qb-core']:GetCoreObject()
local resourceName = GetCurrentResourceName()

local stations = {}
local activeCrafts = {}
local oxInventoryStarted = GetResourceState('ox_inventory') == 'started'
local oxmysqlStarted = GetResourceState('oxmysql') == 'started'
local db = oxmysqlStarted and exports.oxmysql or nil

local function notify(source, description, notifType)
    TriggerClientEvent('ox_lib:notify', source, {
        description = description,
        type = notifType or 'inform'
    })
end

local function getPersistenceMode()
    if Config.Persistence == 'sql' then
        return 'sql'
    end

    if Config.Persistence == 'json' then
        return 'json'
    end

    if oxmysqlStarted then
        return 'sql'
    end

    return 'json'
end

local function ensureSqlTable()
    if not db then
        return
    end

    db:query_async(([[ 
        CREATE TABLE IF NOT EXISTS `%s` (
            `data_key` varchar(64) NOT NULL,
            `data_value` longtext NOT NULL,
            `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            PRIMARY KEY (`data_key`)
        )
    ]]):format(Config.SqlTable))
end

local function loadStationsFromJson()
    local raw = LoadResourceFile(resourceName, Config.DataFile)

    if not raw or raw == '' then
        stations = {}
        return
    end

    local decoded = json.decode(raw)
    stations = type(decoded) == 'table' and decoded or {}
end

local function saveStationsToJson()
    SaveResourceFile(resourceName, Config.DataFile, json.encode(stations), -1)
end

local function loadStationsFromSql()
    ensureSqlTable()

    local row = db:single_async(('SELECT data_value FROM `%s` WHERE data_key = ?'):format(Config.SqlTable), {
        'stations'
    })

    if not row or not row.data_value or row.data_value == '' then
        stations = {}
        return
    end

    local decoded = json.decode(row.data_value)
    stations = type(decoded) == 'table' and decoded or {}
end

local function saveStationsToSql()
    ensureSqlTable()

    db:query_async(
        ('INSERT INTO `%s` (data_key, data_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE data_value = VALUES(data_value)'):format(Config.SqlTable),
        { 'stations', json.encode(stations) }
    )
end

local function loadStations()
    local mode = getPersistenceMode()

    if mode == 'sql' then
        loadStationsFromSql()
    else
        loadStationsFromJson()
    end
end

local function saveStations()
    local mode = getPersistenceMode()

    if mode == 'sql' then
        saveStationsToSql()
    else
        saveStationsToJson()
    end
end

local function cloneTable(tbl)
    return json.decode(json.encode(tbl))
end

local function normalizeId(value)
    if type(value) ~= 'string' then
        return nil
    end

    value = value:lower():gsub('[^%w_%-]', '_'):gsub('_+', '_'):gsub('^_', ''):gsub('_$', '')

    if value == '' then
        return nil
    end

    return value
end

local function normalizeNumber(value, fallback, min)
    value = tonumber(value) or fallback

    if min and value < min then
        value = min
    end

    return value
end

local function sanitizeIOEntries(entries)
    local sanitized = {}

    for index = 1, #(entries or {}) do
        local entry = entries[index]
        local itemName = normalizeId(entry and entry.name)
        local count = normalizeNumber(entry and entry.count, 1, 1)

        if itemName then
            sanitized[#sanitized + 1] = {
                name = itemName,
                count = math.floor(count)
            }
        end
    end

    return sanitized
end

local function sanitizeRecipe(recipe)
    local id = normalizeId(recipe and recipe.id)

    if not id then
        return nil, 'Recipe id is required.'
    end

    local label = type(recipe.label) == 'string' and recipe.label or id
    local duration = math.floor(normalizeNumber(recipe.duration, Config.DefaultDuration, 1000))
    local ingredients = sanitizeIOEntries(recipe.ingredients)
    local rewards = sanitizeIOEntries(recipe.rewards)
    local animation = type(recipe.animation) == 'table' and recipe.animation or {}

    local scenario = type(animation.scenario) == 'string' and animation.scenario or ''
    local dict = type(animation.dict) == 'string' and animation.dict or ''
    local clip = type(animation.clip) == 'string' and animation.clip or ''
    local flag = math.floor(normalizeNumber(animation.flag, 49, 0))

    return {
        id = id,
        label = label,
        description = type(recipe.description) == 'string' and recipe.description or '',
        icon = type(recipe.icon) == 'string' and recipe.icon or Config.DefaultIcon,
        image = type(recipe.image) == 'string' and recipe.image or '',
        duration = duration,
        progressLabel = type(recipe.progressLabel) == 'string' and recipe.progressLabel or label,
        animation = {
            scenario = scenario,
            dict = dict,
            clip = clip,
            flag = flag
        },
        ingredients = ingredients,
        rewards = rewards
    }
end

local function sanitizeStation(station)
    local id = normalizeId(station and station.id)

    if not id then
        return nil, 'Station id is required.'
    end

    local coords = station.coords or {}
    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)
    local w = tonumber(coords.w) or 0.0

    if not x or not y or not z then
        return nil, 'Station coordinates are invalid.'
    end

    local recipes = {}
    local seenRecipes = {}

    for index = 1, #(station.recipes or {}) do
        local recipe, err = sanitizeRecipe(station.recipes[index])

        if not recipe then
            return nil, err
        end

        if seenRecipes[recipe.id] then
            return nil, ('Duplicate recipe id "%s".'):format(recipe.id)
        end

        seenRecipes[recipe.id] = true
        recipes[#recipes + 1] = recipe
    end

    local job = station.job
    if type(job) ~= 'string' then
        job = ''
    end

    return {
        id = id,
        label = type(station.label) == 'string' and station.label or id,
        icon = type(station.icon) == 'string' and station.icon or Config.DefaultIcon,
        job = job,
        grade = math.floor(normalizeNumber(station.grade, 0, 0)),
        radius = normalizeNumber(station.radius, Config.DefaultRadius, 0.5),
        propModel = type(station.propModel) == 'string' and station.propModel or '',
        coords = {
            x = x,
            y = y,
            z = z,
            w = w
        },
        recipes = recipes
    }
end

local function isAdmin(source)
    for groupName in pairs(Config.AdminGroups) do
        if QBCore.Functions.HasPermission(source, groupName) then
            return true
        end
    end

    return IsPlayerAceAllowed(source, 'command.' .. Config.AdminCommand)
        or IsPlayerAceAllowed(source, 'nbrp_jobcrafting.admin')
end

local function getPlayer(source)
    return QBCore.Functions.GetPlayer(source)
end

local function getPlayerJobData(source)
    local player = getPlayer(source)

    if not player then
        return nil
    end

    return player.PlayerData.job
end

local function canAccessStation(source, station)
    if not station then
        return false, 'Crafting station not found.'
    end

    if station.job == '' then
        return true
    end

    local job = getPlayerJobData(source)

    if not job then
        return false, 'Your job data is unavailable right now.'
    end

    if job.name ~= station.job then
        return false, ('This station is for %s only.'):format(station.job)
    end

    local gradeLevel = tonumber(job.grade and job.grade.level) or 0

    if gradeLevel < station.grade then
        return false, ('You need grade %s or higher.'):format(station.grade)
    end

    return true
end

local function getRecipe(station, recipeId)
    for index = 1, #(station.recipes or {}) do
        local recipe = station.recipes[index]

        if recipe.id == recipeId then
            return recipe
        end
    end
end

local function getItemCount(source, itemName)
    if oxInventoryStarted then
        return exports.ox_inventory:GetItemCount(source, itemName)
    end

    local player = getPlayer(source)
    if not player then
        return 0
    end

    local item = player.Functions.GetItemByName(itemName)
    return item and item.amount or 0
end

local function canCarryItem(source, itemName, count)
    if oxInventoryStarted then
        return exports.ox_inventory:CanCarryItem(source, itemName, count)
    end

    return true
end

local function removeItem(source, itemName, count)
    if oxInventoryStarted then
        return exports.ox_inventory:RemoveItem(source, itemName, count)
    end

    local player = getPlayer(source)
    return player and player.Functions.RemoveItem(itemName, count)
end

local function addItem(source, itemName, count)
    if oxInventoryStarted then
        return exports.ox_inventory:AddItem(source, itemName, count)
    end

    local player = getPlayer(source)
    return player and player.Functions.AddItem(itemName, count)
end

local function hasIngredients(source, recipe, quantity)
    for index = 1, #recipe.ingredients do
        local ingredient = recipe.ingredients[index]
        local requiredCount = ingredient.count * quantity

        if getItemCount(source, ingredient.name) < requiredCount then
            return false, ('Not enough %s.'):format(ingredient.name)
        end
    end

    return true
end

local function canCarryRewards(source, recipe, quantity)
    for index = 1, #recipe.rewards do
        local reward = recipe.rewards[index]
        local rewardCount = reward.count * quantity

        if not canCarryItem(source, reward.name, rewardCount) then
            return false, ('You cannot carry %s x%s.'):format(reward.name, rewardCount)
        end
    end

    return true
end

local function getStationList()
    return cloneTable(stations)
end

local function getItemOptions()
    local items = {}

    if oxInventoryStarted then
        items = exports.ox_inventory:Items()
    else
        items = QBCore.Shared.Items or {}
    end

    local options = {}

    for itemName, itemData in pairs(items) do
        options[#options + 1] = {
            value = itemName,
            label = itemData.label or itemName,
            image = itemData.image or ''
        }
    end

    table.sort(options, function(a, b)
        return a.label < b.label
    end)

    return options
end

local function getMatchingItemOptions(searchTerm)
    local normalizedSearch = type(searchTerm) == 'string' and searchTerm:lower() or ''
    local allItems = getItemOptions()
    local startsWith = {}
    local contains = {}

    for index = 1, #allItems do
        local item = allItems[index]
        local label = (item.label or ''):lower()
        local value = (item.value or ''):lower()

        if normalizedSearch == '' then
            startsWith[#startsWith + 1] = item
        elseif label:find(normalizedSearch, 1, true) == 1 or value:find(normalizedSearch, 1, true) == 1 then
            startsWith[#startsWith + 1] = item
        elseif label:find(normalizedSearch, 1, true) or value:find(normalizedSearch, 1, true) then
            contains[#contains + 1] = item
        end
    end

    local matches = {}

    for index = 1, #startsWith do
        matches[#matches + 1] = startsWith[index]
    end

    for index = 1, #contains do
        matches[#matches + 1] = contains[index]
    end

    return matches
end

local function getJobOptions()
    local options = {
        { value = '', label = 'Public' }
    }

    for jobName, jobData in pairs(QBCore.Shared.Jobs or {}) do
        options[#options + 1] = {
            value = jobName,
            label = jobData.label or jobName
        }
    end

    table.sort(options, function(a, b)
        if a.value == '' then return true end
        if b.value == '' then return false end
        return a.label < b.label
    end)

    return options
end

local function syncStations(target)
    TriggerClientEvent('nbrp_jobcrafting:client:syncStations', target or -1, getStationList())
end

lib.callback.register('nbrp_jobcrafting:getInitialData', function(source)
    return {
        stations = getStationList(),
        isAdmin = isAdmin(source)
    }
end)

lib.callback.register('nbrp_jobcrafting:getBuilderData', function(source)
    if not isAdmin(source) then
        return nil
    end

    return {
        stations = getStationList(),
        items = getItemOptions(),
        jobs = getJobOptions()
    }
end)

lib.callback.register('nbrp_jobcrafting:searchItems', function(source, searchTerm)
    if not isAdmin(source) then
        return nil
    end

    local matches = getMatchingItemOptions(searchTerm)
    local limited = {}
    local maxResults = math.min(#matches, 100)

    for index = 1, maxResults do
        limited[#limited + 1] = matches[index]
    end

    return {
        total = #matches,
        items = limited
    }
end)

lib.callback.register('nbrp_jobcrafting:saveStation', function(source, station)
    if not isAdmin(source) then
        return {
            success = false,
            message = 'You do not have permission to edit crafting stations.'
        }
    end

    local sanitized, err = sanitizeStation(station)

    if not sanitized then
        return {
            success = false,
            message = err
        }
    end

    stations[sanitized.id] = sanitized
    saveStations()
    syncStations()

    return {
        success = true,
        station = cloneTable(sanitized)
    }
end)

lib.callback.register('nbrp_jobcrafting:deleteStation', function(source, stationId)
    if not isAdmin(source) then
        return {
            success = false,
            message = 'You do not have permission to delete crafting stations.'
        }
    end

    stationId = normalizeId(stationId)

    if not stationId or not stations[stationId] then
        return {
            success = false,
            message = 'Crafting station not found.'
        }
    end

    stations[stationId] = nil
    saveStations()
    syncStations()

    return {
        success = true
    }
end)

lib.callback.register('nbrp_jobcrafting:beginCraft', function(source, stationId, recipeId, quantity)
    stationId = normalizeId(stationId)
    recipeId = normalizeId(recipeId)
    quantity = math.floor(normalizeNumber(quantity, 0, 0))

    if not stationId or not recipeId then
        return {
            success = false,
            message = 'Crafting data is invalid.'
        }
    end

    if quantity < 1 or quantity > Config.MaxCraftQuantity then
        return {
            success = false,
            message = ('Quantity must be between 1 and %s.'):format(Config.MaxCraftQuantity)
        }
    end

    if activeCrafts[source] then
        return {
            success = false,
            message = 'Finish your current craft first.'
        }
    end

    local station = stations[stationId]
    local canAccess, accessMessage = canAccessStation(source, station)

    if not canAccess then
        return {
            success = false,
            message = accessMessage
        }
    end

    local recipe = getRecipe(station, recipeId)

    if not recipe then
        return {
            success = false,
            message = 'Recipe not found.'
        }
    end

    if #recipe.ingredients == 0 or #recipe.rewards == 0 then
        return {
            success = false,
            message = 'This recipe is incomplete.'
        }
    end

    local hasItems, ingredientMessage = hasIngredients(source, recipe, quantity)
    if not hasItems then
        return {
            success = false,
            message = ingredientMessage
        }
    end

    local canCarry, carryMessage = canCarryRewards(source, recipe, quantity)
    if not canCarry then
        return {
            success = false,
            message = carryMessage
        }
    end

    local duration = Config.ScaleDurationByQuantity and (recipe.duration * quantity) or recipe.duration
    local craftId = ('%s:%s:%s'):format(source, recipeId, GetGameTimer())

    activeCrafts[source] = {
        id = craftId,
        stationId = stationId,
        recipeId = recipeId,
        quantity = quantity,
        expiresAt = GetGameTimer() + duration + 15000
    }

    return {
        success = true,
        craftId = craftId,
        duration = duration,
        label = recipe.progressLabel ~= '' and recipe.progressLabel or Config.Text.progressFallback
    }
end)

RegisterNetEvent('nbrp_jobcrafting:server:cancelCraft', function(craftId)
    local source = source
    local activeCraft = activeCrafts[source]

    if activeCraft and activeCraft.id == craftId then
        activeCrafts[source] = nil
    end
end)

RegisterNetEvent('nbrp_jobcrafting:server:finishCraft', function(craftId)
    local source = source
    local activeCraft = activeCrafts[source]

    if not activeCraft or activeCraft.id ~= craftId then
        notify(source, 'This craft is no longer valid.', 'error')
        return
    end

    activeCrafts[source] = nil

    if activeCraft.expiresAt < GetGameTimer() then
        notify(source, 'This craft expired.', 'error')
        return
    end

    local station = stations[activeCraft.stationId]
    local canAccess, accessMessage = canAccessStation(source, station)

    if not canAccess then
        notify(source, accessMessage, 'error')
        return
    end

    local recipe = station and getRecipe(station, activeCraft.recipeId)
    if not recipe then
        notify(source, 'Recipe not found anymore.', 'error')
        return
    end

    if #recipe.ingredients == 0 or #recipe.rewards == 0 then
        notify(source, 'This recipe is incomplete.', 'error')
        return
    end

    local quantity = activeCraft.quantity
    local hasItems, ingredientMessage = hasIngredients(source, recipe, quantity)
    if not hasItems then
        notify(source, ingredientMessage, 'error')
        return
    end

    local canCarry, carryMessage = canCarryRewards(source, recipe, quantity)
    if not canCarry then
        notify(source, carryMessage, 'error')
        return
    end

    for index = 1, #recipe.ingredients do
        local ingredient = recipe.ingredients[index]
        removeItem(source, ingredient.name, ingredient.count * quantity)
    end

    for index = 1, #recipe.rewards do
        local reward = recipe.rewards[index]
        addItem(source, reward.name, reward.count * quantity)
    end

    notify(source, ('Crafted %s x%s.'):format(recipe.label, quantity), 'success')
end)

AddEventHandler('playerDropped', function()
    activeCrafts[source] = nil
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    syncStations(source)
end)

CreateThread(function()
    loadStations()
end)
