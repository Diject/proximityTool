local util = require('openmw.util')

local this = {}

this.worldCellLabel = "__world_cell__"

this.playerStorageId = "QuestGuider:LocalStorage"

this.uniqueIdKey = "UniqueId"

this.mapMarkersKey = "MapMarkers"

this.mapRecordsKey = "MapRecords"

this.mapDataVersion = "MapVersion"


this.defaultColorData = {202/255, 165/255, 96/255}
this.defaultColor = util.color.rgb(this.defaultColorData[1], this.defaultColorData[2], this.defaultColorData[3])

return this