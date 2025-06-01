---@diagnostic disable: undefined-doc-name
local I = require('openmw.interfaces')
local ui = require('openmw.ui')
local util = require('openmw.util')
local time = require('openmw_aux.time')
local player = require('openmw.self')
local async = require('openmw.async')
local storage = require('openmw.storage')

local common = require("scripts.proximityTool.common")

local log = require("scripts.proximityTool.log")
local uniqueId = require("scripts.proximityTool.uniqueId")
local activeObjects = require("scripts.proximityTool.activeObjects")

local getObject = require("scripts.proximityTool.utils.getObject")
local tableLib = require("scripts.proximityTool.utils.table")

local icons = require("scripts.proximityTool.icons")

local mainMenu = require("scripts.proximityTool.ui.mainMenu")
local activeMarkers = require("scripts.proximityTool.activeMarkers")
local safeUIContainers = require("scripts.proximityTool.ui.safeContainer")

local mapData = require("scripts.proximityTool.data.mapDataHandler")

local config = require("scripts.proximityTool.config")

local settingStorage = storage.globalSection(common.settingStorageId)


---@class proximityTool.cellData
---@field id string?
---@field gridX integer?
---@field gridY integer?
---@field isExterior boolean

---@class proximityTool.activeMarkerData
---@field type integer 1 - object id, 2 - game object, 3 - position, 4 - group of objects
---@field marker proximityTool.markerData
---@field id string?
---@field recordId string?
---@field record proximityTool.markerRecord
---@field objectId string?
---@field objectIds string[]?
---@field object any?
---@field name string?
---@field proximity number?
---@field position Vector3|{x: number, y: number, z: number}?
---@field cell proximityTool.cellData?
---@field priority number?
---@field noteId string?
---@field playerExteriorFlag boolean?
---@field events table<string, function>?
---@field isValid boolean?

---@class proximityTool.markerData
---@field record proximityTool.markerRecord|string
---@field id string?
---@field groupId string?
---@field groupName string?
---@field position Vector3|{x: number, y: number, z: number}?
---@field cell proximityTool.cellData?
---@field objectId string?
---@field object any?
---@field objects string[]?
---@field itemId string?
---@field temporary boolean? if true, this marker will not be saved to the save file
---@field shortTerm boolean? if true, this marker will be deleted after the cell has changed
---@field invalid boolean?

---@class proximityTool.markerRecord.options
---@field showGroupIcon boolean? *true* by default
---@field showNoteIcon boolean? *true* by default
---@field enableGroupEvent boolean? *true* by default

---@class proximityTool.markerRecord
---@field id string?
---@field name string?
---@field description string|string[]?
---@field note string?
---@field nameColor number[]?
---@field descriptionColor number[]|number[][]?
---@field noteColor number[]?
---@field icon string?
---@field iconColor number[]?
---@field iconRatio number? image height to width ratio
---@field hidden boolean?
---@field alpha number?
---@field proximity number?
---@field priority number?
---@field temporary boolean? if true, this record will not be saved to the save file
---@field events table<string, function>?
---@field options proximityTool.markerRecord.options?
---@field invalid boolean?

local this = {}


if config.data.enabled then
    mainMenu.create{showBorder = false}
end

local function updateTime()
    mainMenu.update()
end

local stopTimer = time.runRepeatedly(updateTime, config.data.updateInterval / 1000 * time.second, { type = time.SimulationTime })

settingStorage:subscribe(async:callback(function(section, key)
    local enabled = settingStorage:get("enabled")
    if enabled then
        mainMenu.create{showBorder = false}
        if stopTimer then
            stopTimer()
        end
        stopTimer = time.runRepeatedly(updateTime, config.data.updateInterval / 1000 * time.second, { type = time.SimulationTime })
    else
        if stopTimer then
            stopTimer()
            stopTimer = nil
        end
        mainMenu.destroy()
    end
end))



---@param params proximityTool.markerRecord
---@return string?
local function addRecord(params)
    ---@type proximityTool.markerRecord
    local record = tableLib.deepcopy(params)
    record.id = uniqueId.get()
    mapData.addRecord(record.id, params)
    return record.id
end


---@param markerData proximityTool.markerData
local function registerMarker(markerData)
    if markerData.invalid then return end
    if markerData.cell and markerData.position then
        if player.cell.isExterior ~= markerData.cell.isExterior or
                (not player.cell.isExterior and markerData.cell.id ~= player.cell.id) then
            return
        end
    elseif markerData.objectId and not activeObjects.isContainValidRecordId(markerData.objectId) then
        return
    elseif markerData.object and not activeObjects.isContainRefId(markerData.object.recordId, markerData.object.id) then
        return
    elseif markerData.objects and not activeObjects.isContainValidRecordIds(markerData.objects) then
        return
    end

    local marker = activeMarkers.register(markerData)
    if not marker then return end

    mainMenu.registerMarker(marker)
end


local function registerMarkersForCell()
    local cellId = player.cell.isExterior and common.worldCellLabel or player.cell.id
    for id, data in mapData.iterMarkerGroup(cellId) do
        registerMarker(data)
    end

    async:newUnsavableSimulationTimer(1, function ()
        activeMarkers.update()
    end)
end


---@param data proximityTool.markerData
---@return string? id
---@return string? groupId
local function addMarker(data)
    if not data then return end
    if not data.record or (not (data.position and data.cell) and not data.objectId and not data.object and not data.objects) then return end

    ---@type proximityTool.markerData
    local markerData = tableLib.deepcopy(data)

    if not markerData.objects then
        local groupId = common.worldCellLabel

        if markerData.cell then
            local c = markerData.cell
            if not c.isExterior then ---@diagnostic disable-line: need-check-nil
                groupId = c.id ---@diagnostic disable-line: need-check-nil
            end
            markerData.cell = {gridX = c.gridX, gridY = c.gridY, id = c.id, isExterior = c.isExterior} ---@diagnostic disable-line: need-check-nil
        end

        if markerData.objectId then
            groupId = markerData.objectId
        elseif markerData.position then
            local p = markerData.position
            markerData.position = {x = p.x, y = p.y, z = p.z} ---@diagnostic disable-line: need-check-nil
        elseif markerData.object then
            groupId = markerData.object.id
        end

        markerData.id = uniqueId.get()
        markerData.groupId = groupId

        mapData.addMarker(markerData.id, markerData.groupId, markerData)

    else
        markerData.id = uniqueId.get()
        for _, objId in pairs(markerData.objects) do
            local dt = tableLib.deepcopy(markerData)
            dt.groupId = objId
            mapData.addMarker(markerData.id, dt.groupId, dt)
        end
    end

    registerMarker(markerData)

    return markerData.id, markerData.groupId
end


---@param id string
---@param data proximityTool.markerRecord
---@return boolean?
local function updateRecord(id, data)
    if not id then return end
    if not data then data = {} end

    local recordData = mapData.getRecord(id)
    if not recordData then return end

    local dt = tableLib.deepcopy(data)
    dt.id = nil

    tableLib.applyChanges(recordData, dt)

    return true
end


---@param id string
---@param groupId string?
---@param val boolean
---@return boolean?
local function setVisibility(id, groupId, val)
    local record
    if groupId then
        local markerData = mapData.getMarker(id, groupId)
        if not markerData then return end
        if type(markerData.record) == "string" then return end

        record = markerData.record
    else
        record = mapData.getRecord(id)
    end

    if not record then return end

    record.hidden = not val
    return true
end


local function updateMarkers()
    activeMarkers.update()
end



return {
    interfaceName = "proximityTool",
    interface = {
        version = 1,
        addMarker = addMarker,
        addRecord = addRecord,
        update = updateMarkers,
        updateRecord = updateRecord,
        setVisibility = setVisibility,
        --TODO chage event sys
        registerEvent = function (eventId, id, groupId, data)
            local record = mapData.getRecord(id)
            if not record then return end
            if not record.events then record.events = {} end

            record.events[eventId] = data
            return true
        end,
        removeRecord = function (recordId)
            return mapData.removeRecord(recordId)
        end,
        removeMarker = function (id, groupId)
            return mapData.removeMarker(id, groupId)
        end,
    },
    eventHandlers = {
        UiModeChanged = function(data)
            if not config.data.enabled then return end

            if data.newMode == nil then
                mainMenu.create{showBorder = false}
            elseif data.newMode == "Interface" then
                mainMenu.create{showBorder = true}
                for i = 1, 200 do -- just works
                    mainMenu.update()
                end
            end
        end,
        ["proximityTool:addActiveObject"] = function(object)
            activeObjects.add(object)
            local registered = false
            for id, data in mapData.iterMarkerGroup(object.id) do
                registerMarker(data)
                registered = true
            end
            for id, data in mapData.iterMarkerGroup(object.recordId) do
                registerMarker(data)
                registered = true
            end
        end,
        ["proximityTool:removeActiveObject"] = function(object)
            activeObjects.remove(object)
            activeMarkers.update(object.recordId)
        end,
    },
    engineHandlers = {
        onFrame = function(dt)
            safeUIContainers.update()
        end,
        onSave = function()
            local data = {}

            uniqueId.save()
            mapData.save(data)

            return data
        end,
        onLoad = function (data)
            mapData.load(data)
        end,
        onTeleported = function ()
            async:newUnsavableSimulationTimer(0.0001, function () -- delay for the player cell data to be updated
                registerMarkersForCell()
            end)
        end,
        onActive = function ()
            registerMarkersForCell()
        end
    },
}