local storage = require('openmw.storage')
local async = require('openmw.async')

local common = require("scripts.proximityTool.common")

local tableLib = require("scripts.proximityTool.utils.table")

local settingStorage = storage.globalSection(common.settingStorageId)


local this = {}


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


---@class proximityTool.config
local default = {
    enabled = true,
    updateInterval = 40, -- ms
    ui = {
        showHeader = false,
        align = "End",
        size = {
            x = 25, -- %
            y = 40, -- %
        },
        orderH = "Left to right", -- "Left to right", "Right to left"
    },
}

---@class proximityTool.config
this.data = settingStorage:asTable() or {}

tableLib.addMissing(this.data, default)


return this