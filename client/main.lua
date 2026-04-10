local QBCore = exports['qb-core']:GetCoreObject()

local stations = {}
local zoneHandles = {}
local spawnedProps = {}
local builderData = {
    isAdmin = false,
    items = {},
    itemLookup = {},
    jobs = {},
}

local playerJob = ''
local playerGrade = 0

local function notify(description, notifType)
    lib.notify({
        description = description,
        type = notifType or 'inform'
    })
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

local function updatePlayerJobData()
    local playerData = QBCore.Functions.GetPlayerData()
    local job = playerData.job or {}

    playerJob = job.name or ''
    playerGrade = tonumber(job.grade and job.grade.level) or 0
end

local function canAccessStation(station)
    if not station then
        return false
    end

    if not station.job or station.job == '' then
        return true
    end

    return playerJob == station.job and playerGrade >= (tonumber(station.grade) or 0)
end

local function deleteSpawnedProps()
    for stationId, entity in pairs(spawnedProps) do
        if DoesEntityExist(entity) then
            DeleteObject(entity)
        end

        spawnedProps[stationId] = nil
    end
end

local function removeZones()
    for stationId, zoneId in pairs(zoneHandles) do
        exports.ox_target:removeZone(zoneId)
        zoneHandles[stationId] = nil
    end
end

local function spawnStationProp(station)
    if not station.propModel or station.propModel == '' then
        return
    end

    local model = joaat(station.propModel)

    if not IsModelInCdimage(model) then
        return
    end

    lib.requestModel(model, 5000)

    local coords = station.coords
    local entity = CreateObjectNoOffset(model, coords.x, coords.y, coords.z - 1.0, false, false, false)

    if entity and entity ~= 0 then
        SetEntityHeading(entity, coords.w or 0.0)
        PlaceObjectOnGroundProperly(entity)
        FreezeEntityPosition(entity, true)
        SetEntityInvincible(entity, true)
        SetEntityAsMissionEntity(entity, true, true)
        spawnedProps[station.id] = entity
    end

    SetModelAsNoLongerNeeded(model)
end

local function summarizeEntries(entries)
    local labels = {}

    for index = 1, #(entries or {}) do
        local entry = entries[index]
        labels[#labels + 1] = ('%sx %s'):format(entry.count, entry.name)
    end

    return table.concat(labels, ', ')
end

local function rebuildItemLookup()
    builderData.itemLookup = {}

    for index = 1, #(builderData.items or {}) do
        local item = builderData.items[index]
        builderData.itemLookup[item.value] = item
    end
end

local function getItemImage(itemName)
    local item = builderData.itemLookup[itemName]
    return item and item.image or nil
end

local function getRecipeImage(recipe)
    if recipe.image and recipe.image ~= '' then
        return recipe.image
    end

    local firstReward = recipe.rewards and recipe.rewards[1]

    if firstReward then
        return getItemImage(firstReward.name)
    end

    return nil
end

local function chooseItemOption(currentValue)
    local searchInput = lib.inputDialog('Find Item', {
        {
            type = 'input',
            label = 'Search',
            description = 'Type something like co to match coffee and other ox_inventory items.',
            required = false,
            default = currentValue or ''
        }
    })

    if not searchInput then
        return nil
    end

    local response = lib.callback.await('nbrp_jobcrafting:searchItems', false, searchInput[1] or '')

    if not response then
        notify('Item search failed.', 'error')
        return nil
    end

    local matches = response.items or {}

    if #matches == 0 then
        notify('No matching items found.', 'error')
        return nil
    end

    local selectedItem
    local menuId = ('nbrp_jobcrafting_item_results_%s'):format(GetGameTimer())
    local options = {}

    for index = 1, #matches do
        local item = matches[index]

        options[#options + 1] = {
            title = item.label or item.value,
            description = item.value,
            image = item.image ~= '' and item.image or nil,
            onSelect = function()
                selectedItem = item.value
            end
        }
    end

    lib.registerContext({
        id = menuId,
        title = ('Matching Items (%s)'):format(response.total or #matches),
        options = options
    })

    lib.showContext(menuId)

    while lib.getOpenContextMenu() == menuId do
        Wait(0)
    end

    return selectedItem
end

local function getNearestStation(maxDistance)
    local ped = cache.ped
    local coords = GetEntityCoords(ped)
    local closestStation
    local closestDistance = maxDistance or 3.0

    for _, station in pairs(stations) do
        local stationCoords = vec3(station.coords.x, station.coords.y, station.coords.z)
        local distance = #(coords - stationCoords)

        if distance <= closestDistance then
            closestDistance = distance
            closestStation = station
        end
    end

    return closestStation, closestDistance
end

local function getStationById(stationId)
    return stations[stationId]
end

local function getRecipeById(stationId, recipeId)
    local station = getStationById(stationId)

    if not station then
        return nil, nil, nil
    end

    for index = 1, #(station.recipes or {}) do
        local recipe = station.recipes[index]

        if recipe.id == recipeId then
            return station, recipe, index
        end
    end

    return station, nil, nil
end

local function pickPlacementCoords(prompt)
    local helpText = prompt or 'Aim at a spot and press E to place. Press Backspace to cancel.'
    local markerType = 2

    notify(helpText, 'inform')

    while true do
        Wait(0)

        local hit, _, endCoords = lib.raycast.cam(511, 4, 25)

        if hit and endCoords then
            DrawMarker(
                markerType,
                endCoords.x, endCoords.y, endCoords.z + 0.05,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                0.2, 0.2, 0.2,
                0, 180, 255, 180,
                false, true, 2, false, nil, nil, false
            )

            if IsControlJustPressed(0, 38) then
                local heading = GetEntityHeading(cache.ped)

                return {
                    x = endCoords.x,
                    y = endCoords.y,
                    z = endCoords.z,
                    w = heading
                }
            end
        end

        if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 200) then
            notify('Placement cancelled.', 'error')
            return nil
        end
    end
end

local openAdminMenu
local openStationAdminMenu
local openRecipeAdminMenu
local openEntriesMenu

local function openCraftQuantityPrompt(station, recipe)
    local input = lib.inputDialog(Config.Text.quantityTitle, {
        {
            type = 'number',
            label = recipe.label,
            description = 'Type any amount you want to craft.',
            required = true,
            default = 1,
            min = 1,
            max = Config.MaxCraftQuantity
        }
    })

    if not input then
        return
    end

    local quantity = math.floor(tonumber(input[1]) or 0)

    if quantity < 1 then
        notify('Enter a valid quantity.', 'error')
        return
    end

    local response = lib.callback.await('nbrp_jobcrafting:beginCraft', false, station.id, recipe.id, quantity)

    if not response or not response.success then
        notify(response and response.message or 'Unable to start crafting.', 'error')
        return
    end

    local progressData = {
        duration = response.duration,
        label = response.label,
        position = Config.Progress.position,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        }
    }

    if recipe.animation then
        if recipe.animation.scenario and recipe.animation.scenario ~= '' then
            progressData.anim = {
                scenario = recipe.animation.scenario
            }
        elseif recipe.animation.dict and recipe.animation.dict ~= '' and recipe.animation.clip and recipe.animation.clip ~= '' then
            progressData.anim = {
                dict = recipe.animation.dict,
                clip = recipe.animation.clip,
                flag = tonumber(recipe.animation.flag) or 49
            }
        end
    end

    local completed

    if Config.Progress.useCircle then
        completed = lib.progressCircle(progressData)
    else
        completed = lib.progressBar(progressData)
    end

    if completed then
        TriggerServerEvent('nbrp_jobcrafting:server:finishCraft', response.craftId)
    else
        TriggerServerEvent('nbrp_jobcrafting:server:cancelCraft', response.craftId)
    end
end

local function openCraftMenu(station)
    local options = {}

    for index = 1, #(station.recipes or {}) do
        local recipe = station.recipes[index]

        options[#options + 1] = {
            title = recipe.label,
            description = recipe.description ~= '' and recipe.description or summarizeEntries(recipe.ingredients),
            icon = recipe.icon,
            image = getRecipeImage(recipe),
            metadata = {
                { label = 'Ingredients', value = summarizeEntries(recipe.ingredients) },
                { label = 'Rewards', value = summarizeEntries(recipe.rewards) },
                { label = 'Duration', value = ('%sms each'):format(recipe.duration) },
            },
            onSelect = function()
                openCraftQuantityPrompt(station, recipe)
            end
        }
    end

    if #options == 0 then
        options[1] = {
            title = 'No recipes yet',
            description = 'This crafting station has no recipes configured.',
            readOnly = true
        }
    end

    lib.registerContext({
        id = ('nbrp_jobcrafting_station_%s'):format(station.id),
        title = station.label,
        options = options
    })

    lib.showContext(('nbrp_jobcrafting_station_%s'):format(station.id))
end

local function rebuildZones()
    removeZones()
    deleteSpawnedProps()

    for _, station in pairs(stations) do
        spawnStationProp(station)

        zoneHandles[station.id] = exports.ox_target:addSphereZone({
            coords = vec3(station.coords.x, station.coords.y, station.coords.z),
            radius = station.radius,
            debug = Config.DebugZones,
            options = {
                {
                    name = ('nbrp_jobcrafting_use_%s'):format(station.id),
                    icon = station.icon or Config.DefaultIcon,
                    label = station.label,
                    distance = Config.TargetDistance,
                    canInteract = function()
                        return canAccessStation(station)
                    end,
                    onSelect = function()
                        openCraftMenu(station)
                    end
                },
                {
                    name = ('nbrp_jobcrafting_edit_%s'):format(station.id),
                    icon = 'fas fa-sliders',
                    label = 'Edit Crafting Station',
                    distance = Config.TargetDistance,
                    canInteract = function()
                        return builderData.isAdmin
                    end,
                    onSelect = function()
                        openStationAdminMenu(station.id)
                    end
                }
            }
        })
    end
end

local function syncStations(newStations)
    stations = newStations or {}
    rebuildZones()
end

local function getJobOption(jobName)
    for index = 1, #builderData.jobs do
        local jobOption = builderData.jobs[index]

        if jobOption.value == jobName then
            return jobOption
        end
    end
end

local function ensureBuilderData()
    local response = lib.callback.await('nbrp_jobcrafting:getBuilderData', false)

    if not response then
        notify('You do not have permission to use the craft builder.', 'error')
        return false
    end

    builderData.isAdmin = true
    builderData.items = response.items or {}
    rebuildItemLookup()
    builderData.jobs = response.jobs or {}

    if response.stations then
        syncStations(response.stations)
    end

    return true
end

local function openEntryForm(existingEntry, title)
    local itemDefault = existingEntry and existingEntry.name or ''
    local countDefault = existingEntry and existingEntry.count or 1

    local selectedItem = chooseItemOption(itemDefault)

    if not selectedItem then
        return
    end

    local input = lib.inputDialog(title, {
        {
            type = 'number',
            label = 'Count',
            required = true,
            default = countDefault,
            min = 1
        }
    })

    if not input then
        return
    end

    return {
        name = selectedItem,
        count = math.floor(tonumber(input[1]) or 1)
    }
end

local function openRecipeForm(station, existingRecipe)
    local editing = existingRecipe ~= nil
    local rows = {}
    local animation = existingRecipe and existingRecipe.animation or {}

    if not editing then
        rows[#rows + 1] = {
            type = 'input',
            label = 'Recipe Id',
            description = 'Internal id, for example coffee.',
            required = true,
            default = ''
        }
    end

    rows[#rows + 1] = {
        type = 'input',
        label = 'Label',
        required = true,
        default = existingRecipe and existingRecipe.label or ''
    }
    rows[#rows + 1] = {
        type = 'textarea',
        label = 'Description',
        default = existingRecipe and existingRecipe.description or ''
    }
    rows[#rows + 1] = {
        type = 'input',
        label = 'Icon',
        description = 'FontAwesome icon name',
        default = existingRecipe and existingRecipe.icon or 'fas fa-box-open'
    }
    rows[#rows + 1] = {
        type = 'input',
        label = 'Image',
        description = 'Optional inventory image path or URL',
        default = existingRecipe and existingRecipe.image or ''
    }
    rows[#rows + 1] = {
        type = 'number',
        label = 'Duration (ms)',
        required = true,
        default = existingRecipe and existingRecipe.duration or Config.DefaultDuration,
        min = 1000
    }
    rows[#rows + 1] = {
        type = 'input',
        label = 'Progress Label',
        default = existingRecipe and existingRecipe.progressLabel or ''
    }
    rows[#rows + 1] = {
        type = 'input',
        label = 'Animation Scenario',
        description = 'Optional. Example: WORLD_HUMAN_HAMMERING. Leave dict/clip blank if you use this.',
        default = animation.scenario or ''
    }
    rows[#rows + 1] = {
        type = 'input',
        label = 'Animation Dict',
        description = 'Optional. Example: mini@repair',
        default = animation.dict or ''
    }
    rows[#rows + 1] = {
        type = 'input',
        label = 'Animation Clip',
        description = 'Optional. Example: fix_car_bumper',
        default = animation.clip or ''
    }
    rows[#rows + 1] = {
        type = 'number',
        label = 'Animation Flag',
        description = 'Optional. Default is 49.',
        default = animation.flag or 49,
        min = 0
    }

    local input = lib.inputDialog(editing and 'Edit Recipe' or 'Create Recipe', rows)

    if not input then
        return
    end

    local index = 1
    local recipeId = existingRecipe and existingRecipe.id or input[index]
    if not existingRecipe then
        index = index + 1
    end

    local recipe = existingRecipe or {
        id = normalizeId(recipeId),
        ingredients = {},
        rewards = {}
    }

    recipe.label = input[index]
    recipe.description = input[index + 1] or ''
    recipe.icon = input[index + 2] ~= '' and input[index + 2] or Config.DefaultIcon
    recipe.image = input[index + 3] or ''
    recipe.duration = math.floor(tonumber(input[index + 4]) or Config.DefaultDuration)
    recipe.progressLabel = input[index + 5] or recipe.label
    recipe.animation = {
        scenario = input[index + 6] or '',
        dict = input[index + 7] or '',
        clip = input[index + 8] or '',
        flag = math.floor(tonumber(input[index + 9]) or 49)
    }

    if not existingRecipe then
        station.recipes[#station.recipes + 1] = recipe
    end
end

local function saveStation(station)
    local response = lib.callback.await('nbrp_jobcrafting:saveStation', false, station)

    if not response or not response.success then
        notify(response and response.message or 'Failed to save station.', 'error')
        return false
    end

    stations[response.station.id] = response.station
    rebuildZones()
    notify('Crafting station saved.', 'success')
    return true
end

local function openStationSettingsForm(existingStation)
    local editing = existingStation ~= nil

    local defaultJob = existingStation and existingStation.job or ''
    local selectedJob = getJobOption(defaultJob)

    local rows = {}

    if not editing then
        rows[#rows + 1] = {
            type = 'input',
            label = 'Station Id',
            description = 'Internal id, for example burgershot_coffee',
            required = true
        }
    end

    rows[#rows + 1] = {
        type = 'input',
        label = 'Label',
        required = true,
        default = existingStation and existingStation.label or ''
    }
    rows[#rows + 1] = {
        type = 'select',
        label = 'Job Access',
        searchable = true,
        default = selectedJob and selectedJob.value or '',
        options = builderData.jobs
    }
    rows[#rows + 1] = {
        type = 'number',
        label = 'Minimum Grade',
        default = existingStation and existingStation.grade or 0,
        min = 0
    }
    rows[#rows + 1] = {
        type = 'number',
        label = 'Radius',
        default = existingStation and existingStation.radius or Config.DefaultRadius,
        min = 0.5
    }
    rows[#rows + 1] = {
        type = 'input',
        label = 'Icon',
        default = existingStation and existingStation.icon or Config.DefaultIcon
    }
    rows[#rows + 1] = {
        type = 'input',
        label = 'Prop Model',
        description = 'Leave blank for no prop',
        default = existingStation and existingStation.propModel or Config.DefaultPropModel
    }

    local input = lib.inputDialog(editing and 'Edit Station' or 'Create Station', rows)

    if not input then
        return
    end

    local index = 1
    local stationId = existingStation and existingStation.id or normalizeId(input[index])

    if not existingStation then
        index = index + 1
    end

    local station = existingStation and cloneTable(existingStation) or {
        id = stationId,
        recipes = {}
    }

    station.label = input[index]
    station.job = input[index + 1] or ''
    station.grade = math.floor(tonumber(input[index + 2]) or 0)
    station.radius = tonumber(input[index + 3]) or Config.DefaultRadius
    station.icon = input[index + 4] ~= '' and input[index + 4] or Config.DefaultIcon
    station.propModel = input[index + 5] or ''

    if not existingStation then
        local selectedCoords = pickPlacementCoords('Aim where the crafting station should go, then press E.')

        if not selectedCoords then
            return
        end

        station.coords = selectedCoords
    end

    saveStation(station)
end

local function deleteStation(stationId)
    local alert = lib.alertDialog({
        header = 'Delete Station',
        content = 'Delete this crafting station and all recipes?',
        centered = true,
        cancel = true
    })

    if alert ~= 'confirm' then
        return
    end

    local response = lib.callback.await('nbrp_jobcrafting:deleteStation', false, stationId)

    if not response or not response.success then
        notify(response and response.message or 'Failed to delete station.', 'error')
        return
    end

    stations[stationId] = nil
    rebuildZones()
    notify('Crafting station deleted.', 'success')
end

openEntriesMenu = function(stationId, recipeId, entryType)
    local station, recipe = getRecipeById(stationId, recipeId)

    if not station or not recipe then
        return
    end

    local entries = recipe[entryType]
    local options = {
        {
            title = entryType == 'ingredients' and 'Add Ingredient' or 'Add Reward',
            icon = 'fas fa-plus',
            onSelect = function()
                local currentStation, currentRecipe = getRecipeById(stationId, recipeId)
                if not currentStation or not currentRecipe then
                    notify('Recipe not found.', 'error')
                    return
                end

                local newEntry = openEntryForm(nil, entryType == 'ingredients' and 'Add Ingredient' or 'Add Reward')

                if newEntry then
                    currentRecipe[entryType][#currentRecipe[entryType] + 1] = newEntry
                    if saveStation(currentStation) then
                        openEntriesMenu(stationId, recipeId, entryType)
                    end
                end
            end
        }
    }

    for entryIndex = 1, #entries do
        local entry = entries[entryIndex]

        options[#options + 1] = {
            title = ('%sx %s'):format(entry.count, entry.name),
            icon = 'fas fa-box',
            menu = ('nbrp_jobcrafting_recipe_%s_%s'):format(stationId, recipeId),
            onSelect = function()
                lib.registerContext({
                    id = ('nbrp_jobcrafting_entry_%s_%s_%s_%s'):format(stationId, recipeId, entryType, entryIndex),
                    title = ('%sx %s'):format(entry.count, entry.name),
                    menu = ('nbrp_jobcrafting_entries_%s_%s_%s'):format(stationId, recipeId, entryType),
                    options = {
                        {
                            title = 'Edit',
                            icon = 'fas fa-pen',
                            onSelect = function()
                                local currentStation, currentRecipe = getRecipeById(stationId, recipeId)
                                if not currentStation or not currentRecipe or not currentRecipe[entryType][entryIndex] then
                                    notify('Entry not found.', 'error')
                                    return
                                end

                                local updated = openEntryForm(entry, 'Edit Entry')

                                if updated then
                                    currentRecipe[entryType][entryIndex] = updated
                                    if saveStation(currentStation) then
                                        openEntriesMenu(stationId, recipeId, entryType)
                                    end
                                end
                            end
                        },
                        {
                            title = 'Delete',
                            icon = 'fas fa-trash',
                            onSelect = function()
                                local currentStation, currentRecipe = getRecipeById(stationId, recipeId)
                                if not currentStation or not currentRecipe or not currentRecipe[entryType][entryIndex] then
                                    notify('Entry not found.', 'error')
                                    return
                                end

                                table.remove(currentRecipe[entryType], entryIndex)
                                if saveStation(currentStation) then
                                    openEntriesMenu(stationId, recipeId, entryType)
                                end
                            end
                        }
                    }
                })

                lib.showContext(('nbrp_jobcrafting_entry_%s_%s_%s_%s'):format(stationId, recipeId, entryType, entryIndex))
            end
        }
    end

    lib.registerContext({
        id = ('nbrp_jobcrafting_entries_%s_%s_%s'):format(stationId, recipeId, entryType),
        title = entryType == 'ingredients' and Config.Text.ingredientTitle or Config.Text.rewardTitle,
        menu = ('nbrp_jobcrafting_recipe_%s_%s'):format(stationId, recipeId),
        options = options
    })

    lib.showContext(('nbrp_jobcrafting_entries_%s_%s_%s'):format(stationId, recipeId, entryType))
end

openRecipeAdminMenu = function(stationId, recipeId)
    local station, recipe, recipeIndex = getRecipeById(stationId, recipeId)

    if not station or not recipe then
        return
    end

    lib.registerContext({
        id = ('nbrp_jobcrafting_recipe_%s_%s'):format(stationId, recipeId),
        title = recipe.label,
        menu = ('nbrp_jobcrafting_recipes_%s'):format(stationId),
        options = {
            {
                title = 'Edit Recipe',
                icon = 'fas fa-pen',
                onSelect = function()
                    local currentStation, currentRecipe = getRecipeById(stationId, recipeId)
                    if not currentStation or not currentRecipe then
                        notify('Recipe not found.', 'error')
                        return
                    end

                    openRecipeForm(currentStation, currentRecipe)
                    if saveStation(currentStation) then
                        openRecipeAdminMenu(stationId, recipeId)
                    end
                end
            },
            {
                title = 'Ingredients',
                icon = 'fas fa-list',
                onSelect = function()
                    openEntriesMenu(stationId, recipeId, 'ingredients')
                end
            },
            {
                title = 'Rewards',
                icon = 'fas fa-gift',
                onSelect = function()
                    openEntriesMenu(stationId, recipeId, 'rewards')
                end
            },
            {
                title = 'Delete Recipe',
                icon = 'fas fa-trash',
                onSelect = function()
                    local currentStation, _, currentRecipeIndex = getRecipeById(stationId, recipeId)
                    if not currentStation or not currentRecipeIndex then
                        notify('Recipe not found.', 'error')
                        return
                    end

                    table.remove(currentStation.recipes, currentRecipeIndex)
                    if saveStation(currentStation) then
                        openStationAdminMenu(stationId)
                    end
                end
            }
        }
    })

    lib.showContext(('nbrp_jobcrafting_recipe_%s_%s'):format(stationId, recipeId))
end

local function openRecipeListMenu(stationId)
    local station = getStationById(stationId)
    if not station then
        return
    end

    local options = {
        {
            title = 'Add Recipe',
            icon = 'fas fa-plus',
            onSelect = function()
                local currentStation = getStationById(stationId)
                if not currentStation then
                    notify('Station not found.', 'error')
                    return
                end

                openRecipeForm(currentStation)

                if saveStation(currentStation) then
                    openRecipeListMenu(stationId)
                end
            end
        }
    }

    for index = 1, #station.recipes do
        local recipe = station.recipes[index]

        options[#options + 1] = {
            title = recipe.label,
            description = summarizeEntries(recipe.ingredients),
            icon = recipe.icon,
            image = getRecipeImage(recipe),
            onSelect = function()
                openRecipeAdminMenu(stationId, recipe.id)
            end
        }
    end

    lib.registerContext({
        id = ('nbrp_jobcrafting_recipes_%s'):format(stationId),
        title = Config.Text.recipeTitle,
        menu = ('nbrp_jobcrafting_admin_station_%s'):format(stationId),
        options = options
    })

    lib.showContext(('nbrp_jobcrafting_recipes_%s'):format(stationId))
end

openStationAdminMenu = function(stationId)
    local station = getStationById(stationId)
    if not station then
        notify('Crafting station not found.', 'error')
        return
    end

    lib.registerContext({
        id = ('nbrp_jobcrafting_admin_station_%s'):format(stationId),
        title = station.label,
        menu = 'nbrp_jobcrafting_admin_root',
        options = {
            {
                title = 'Edit Details',
                icon = 'fas fa-sliders',
                onSelect = function()
                    local currentStation = getStationById(stationId)
                    if not currentStation then
                        notify('Crafting station not found.', 'error')
                        return
                    end

                    openStationSettingsForm(currentStation)
                end
            },
            {
                title = 'Move To Looked At Point',
                icon = 'fas fa-location-arrow',
                onSelect = function()
                    local currentStation = getStationById(stationId)
                    if not currentStation then
                        notify('Crafting station not found.', 'error')
                        return
                    end

                    local selectedCoords = pickPlacementCoords('Aim where this crafting station should move, then press E.')

                    if not selectedCoords then
                        return
                    end

                    currentStation.coords = selectedCoords

                    saveStation(currentStation)
                end
            },
            {
                title = 'Recipes',
                icon = 'fas fa-boxes-stacked',
                onSelect = function()
                    openRecipeListMenu(stationId)
                end
            },
            {
                title = 'Delete Station',
                icon = 'fas fa-trash',
                onSelect = function()
                    deleteStation(stationId)
                end
            }
        }
    })

    lib.showContext(('nbrp_jobcrafting_admin_station_%s'):format(stationId))
end

openAdminMenu = function()
    if not ensureBuilderData() then
        return
    end

    local nearestStation = getNearestStation(5.0)
    local options = {
        {
            title = 'Create Station At Looked At Point',
            description = 'Creates a new crafting station where you are aiming.',
            icon = 'fas fa-plus',
            onSelect = function()
                openStationSettingsForm(nil)
            end
        },
        {
            title = nearestStation and ('Edit Nearest Station: %s'):format(nearestStation.label) or 'No Nearby Station',
            description = nearestStation and 'Opens the nearest crafting station editor.' or 'Move closer to a station to edit it quickly.',
            icon = 'fas fa-pen',
            disabled = nearestStation == nil,
            onSelect = function()
                if nearestStation then
                    openStationAdminMenu(nearestStation.id)
                end
            end
        }
    }

    for stationId, station in pairs(stations) do
        options[#options + 1] = {
            title = station.label,
            description = station.job ~= '' and ('Job: %s | Grade: %s'):format(station.job, station.grade) or 'Public station',
            icon = station.icon or Config.DefaultIcon,
            onSelect = function()
                openStationAdminMenu(stationId)
            end
        }
    end

    lib.registerContext({
        id = 'nbrp_jobcrafting_admin_root',
        title = Config.Text.builderTitle,
        options = options
    })

    lib.showContext('nbrp_jobcrafting_admin_root')
end

RegisterCommand(Config.AdminCommand, function()
    openAdminMenu()
end, false)

RegisterNetEvent('nbrp_jobcrafting:client:syncStations', function(newStations)
    syncStations(newStations)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    updatePlayerJobData()
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    playerJob = job.name or ''
    playerGrade = tonumber(job.grade and job.grade.level) or 0
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource ~= GetCurrentResourceName() then
        return
    end

    removeZones()
    deleteSpawnedProps()
end)

CreateThread(function()
    updatePlayerJobData()

    local initialData = lib.callback.await('nbrp_jobcrafting:getInitialData', false)

    if initialData then
        builderData.isAdmin = initialData.isAdmin or false
        syncStations(initialData.stations or {})
    end
end)
