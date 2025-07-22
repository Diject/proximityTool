local storage = require('openmw.storage')
local async = require('openmw.async')

local common = require("scripts.proximityTool.common")

local tableLib = require("scripts.proximityTool.utils.table")

local settingStorage = storage.globalSection(common.settingStorageId)
local localStorage = storage.playerSection(common.localSettingStorageId)


local this = {}

this.storageSections = {
    storage.playerSection(common.settingStorageId),
    storage.playerSection(common.localSettingStorageId),
}


---@class proximityTool.config
local default = {
    enabled = true,
    updateInterval = 40, -- ms
    objectPosUpdateInterval = 3, -- s,
    ui = {
        hideHUD = false,
        hideWindow = false,
        showHeader = false,
        fontSize = 24,
        defaultColor = common.defaultColor,
        align = "End",
        size = {
            x = 25, -- %
            y = 40, -- %
        },
        position = {
            x = 100,
            y = 30,
        },
        positionInMenu = {
            x = 100,
            y = 30,
        },
        orderH = "Left to right", -- "Left to right", "Right to left"
    },
}


---@class proximityTool.config
this.data = {}


function this.loadFromStorage(section)
    local data = section:asTable() or {}
    for path, value in pairs(data) do
        tableLib.setValueByPath(this.data, path, value)
    end
end


for _, section in pairs(this.storageSections) do
    section:subscribe(async:callback(function(s, key)
        if key then
            tableLib.setValueByPath(this.data, key, section:get(key))
        else
            this.loadFromStorage(section)
        end
    end))

    this.loadFromStorage(section)
end
tableLib.addMissing(this.data, default)



function this.setValue(str, val)
    for _, section in pairs(this.storageSections) do
        if section:get(str) ~= nil then
            section:set(str, val)
        end
    end
    return tableLib.setValueByPath(this.data, str, val)
end


function this.setLocal(path, value)
    tableLib.setValueByPath(this.data, path, value)
    localStorage:set(path, value)
end


return this