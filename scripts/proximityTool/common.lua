local util = require('openmw.util')
local types = require('openmw.types')

local this = {}

this.worldCellLabel = "__world_cell__"

this.objectsLabel = "__objects__"
this.positionsLabel = "__positions__"

this.defaultGroupId = "__default__"
this.hiddenGroupId = "__hidden__"

this.playerStorageId = "proximityTool:LocalStorage"

this.settingStorageId = "proximityTool:Settings"

this.localSettingStorageId = "proximityTool:LocalSettings"

this.uniqueIdKey = "UniqueId"

this.mapMarkersKey = "MapMarkers"

this.mapRecordsKey = "MapRecords"

this.hudmMarkersKey = "HUDMRecords"

this.mapDataVersionKey = "MapVersion"


this.defaultColorData = {202/255, 165/255, 96/255}
this.defaultColor = util.color.rgb(this.defaultColorData[1], this.defaultColorData[2], this.defaultColorData[3])


this.supportedObjectTypes = {
    [types.NPC] = true,
    [types.Creature] = true,
    [types.Apparatus] = true,
    [types.Armor] = true,
    [types.Book] = true,
    [types.Clothing] = true,
    [types.Container] = true,
    [types.Door] = true,
    [types.Ingredient] = true,
    [types.Light] = true,
    [types.Lockpick] = true,
    [types.Miscellaneous] = true,
    [types.Potion] = true,
    [types.Probe] = true,
    [types.Repair] = true,
    [types.Weapon] = true,
}

return this