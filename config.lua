Config = {}

Config.AdminCommand = 'craftbuilder'
Config.DataFile = 'data/stations.json'
Config.Persistence = 'auto'
Config.SqlTable = 'nbrp_jobcrafting_data'

Config.AdminGroups = {
    god = true,
    admin = true,
}

Config.DefaultRadius = 1.5
Config.DefaultIcon = 'fas fa-hammer'
Config.DefaultDuration = 5000
Config.TargetDistance = 2.0
Config.MaxCraftQuantity = 250
Config.ScaleDurationByQuantity = true
Config.DebugZones = false

Config.Progress = {
    useCircle = true,
    position = 'bottom',
}

Config.DefaultPropModel = 'prop_tool_bench02'

Config.Text = {
    builderTitle = 'Craft Builder',
    builderDescription = 'Create and manage job crafting stations',
    stationTitle = 'Crafting Station',
    recipeTitle = 'Crafting Recipes',
    ingredientTitle = 'Ingredients',
    rewardTitle = 'Rewards',
    quantityTitle = 'Craft Quantity',
    progressFallback = 'Crafting...',
}
