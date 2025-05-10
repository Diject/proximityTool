local storage = require('openmw.storage')
local async = require('openmw.async')

local common = require("scripts.proximityTool.common")

local tableLib = require("scripts.proximityTool.utils.table")

local settingStorage = storage.globalSection(common.settingStorageId)
local localStorage = storage.playerSection(common.localSettingStorageId)


local this = {}

this.storage = settingStorage

settingStorage:subscribe(async:callback(function(section, key)
    if key then
        tableLib.setValueByPath(this.data, key, settingStorage:get(key))
    else
        local data = settingStorage:asTable() or {}
        for path, value in pairs(data) do
            tableLib.setValueByPath(this.data, path, value)
        end
    end
end))


this.localStorage = localStorage

localStorage:subscribe(async:callback(function(section, key)
    if key then
        tableLib.setValueByPath(this.localConfig, key, localStorage:get(key))
    else
        local data = localStorage:asTable() or {}
        for path, value in pairs(data) do
            tableLib.setValueByPath(this.localConfig, path, value)
        end
    end
end))


---@class proximityTool.config
local default = {
    enabled = true,
    updateInterval = 40, -- ms
    ui = {
        hideHUD = false,
        hideWindow = false,
        showHeader = false,
        align = "End",
        size = {
            x = 25, -- %
            y = 40, -- %
        },
        position = {
            x = 100,
            y = 30,
        },
        orderH = "Left to right", -- "Left to right", "Right to left"
    },
}

---@class proximityTool.localConfig
local localDefault = {
    ui = {
        positionAlt = {
            x = 25,
            y = 40,
        },
    },
}


local function loadData(stor, t)
    if not t then t = {} end
    local values = stor:asTable() or {}

    for key, value in pairs(values) do
        tableLib.setValueByPath(t, key, value)
    end

    return t
end


---@class proximityTool.config
this.data = loadData(settingStorage)

tableLib.addMissing(this.data, default)


---@class proximityTool.localConfig
this.localConfig = loadData(localStorage)

tableLib.addMissing(this.localConfig, localDefault)


function this.setLocal(path, value)
    tableLib.setValueByPath(this.localConfig, path, value)
    localStorage:set(path, value)
end


-- TODO
function this.save()

end


return this