local I = require('openmw.interfaces')
local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local core = require('openmw.core')
local playerObj = require('openmw.self')

local commonData = require("scripts.proximityTool.common")

local config = require("scripts.proximityTool.config")

local uniqueId = require("scripts.proximityTool.uniqueId")
local tableLib = require("scripts.proximityTool.utils.table")

local uiUtils = require("scripts.proximityTool.ui.utils")

local log = require("scripts.proximityTool.log")

local icons = require("scripts.proximityTool.icons")

local activeObjects = require("scripts.proximityTool.activeObjects")
local activeMarkers = require("scripts.proximityTool.activeMarkers")
local cellLib = require("scripts.proximityTool.cell")

local safeContainers = require("scripts.proximityTool.ui.safeContainer")

local tooltipFuncs = require("scripts.proximityTool.ui.mainMenuTooltip")

local addButton = require("scripts.proximityTool.ui.button")
local addInterval = require("scripts.proximityTool.ui.interval")


local this = {}

local defaultColor = commonData.defaultColor
local elementRelPos = util.vector2(config.localConfig.ui.positionAlt.x / 100, config.localConfig.ui.positionAlt.y / 100)

this.hiddenGroupElement = {
    userData = {
        groupName = commonData.hiddenGroupId,
    },
    content = ui.content{}
}

local eventNames = {
    "keyPress",
    "keyRelease",
    "mouseClick",
    "mouseDoubleClick",
    "mousePress",
    "mouseRelease",
    "textInput",
    "focusGain"
}

this.element = nil
---@type proximityTool.elementSafeContainer
this.tooltip = nil

local mainMenuSafeContainer = safeContainers.new("mainMenu")
local markerParentElement = nil


local function getNexUpdateTimestamp(val)
    return val + config.data.objectPosUpdateInterval * (1 + (math.random() - 0.5) * 0.5)
end


local function getMainFlex()
    if not this.element or not this.element.layout then return end

    if markerParentElement then
        return markerParentElement
    else
        markerParentElement = this.element.layout.content[1].content[2].content[1]
        return markerParentElement
    end
end


local function getMarkerParentElement(groupName)
    if not this.element or not this.element.layout then return end

    if markerParentElement and not groupName then
        return getMainFlex()
    elseif groupName == commonData.hiddenGroupId then
        return this.hiddenGroupElement
    elseif groupName then
        local parent = getMainFlex()
        if not parent then return end

        local index = parent.content:indexOf(groupName)
        if not index then return end

        return parent.content[index].content[2]
    else
        return getMainFlex()
    end
end


---@param groupName string
---@param params {priority : number?, protected : boolean?}?
local function createGroup(groupName, params)
    if not params then params = {} end

    if groupName == commonData.hiddenGroupId then
        this.hiddenGroupElement.content = ui.content{}
        return
    end

    local parent = getMarkerParentElement()
    if not parent or not parent.content then return end

    local parentContent = parent.content

    local parentIndex = parentContent:indexOf(groupName)
    if parentIndex then return end

    local groupNameText = groupName
    local groupNameFontSize = 24
    if groupNameText == commonData.hiddenGroupId or groupNameText == commonData.defaultGroupId then
        groupNameText = ""
        groupNameFontSize = 0
    end

    local uiData = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = false,
            autoSize = true,
            arrange = uiUtils.convertAlign(config.data.ui.align),
            alpha = 0,
            visible = true,
        },
        userData = {
            isGroupParent = true,
            isProtected = params.protected,
            priority = params.priority or 0,
            orderIndex = 0,
            orderCounter = 0,
            alpha = 1,
            groupName = groupName,
        },
        name = groupName,
        content = ui.content{
            {
                template = I.MWUI.templates.textNormal,
                type = ui.TYPE.Text,
                props = {
                    text = groupNameText,
                    textSize = groupNameFontSize,
                    multiline = false,
                    wordWrap = false,
                    textAlignH = uiUtils.convertAlign(config.data.ui.align),
                    textShadow = true,
                    textShadowColor = util.color.rgb(0, 0, 0),
                },
                userData = {

                },
            },
            {
                type = ui.TYPE.Flex,
                props = {
                    position = util.vector2(0, 0),
                    autoSize = true,
                    horizontal = false,
                    arrange = uiUtils.convertAlign(config.data.ui.align),
                },
                userData = {
                    groupName = groupName,
                },
                content = ui.content {

                },
            },
            addInterval(8, 8),
        },
    }

    parentContent:add(uiData)
end


---@param activeMarker proximityTool.activeMarker
function this.registerMarker(activeMarker)
    if not activeMarker or not this.element then return end

    local elementId = activeMarker.markerId or uniqueId.get()

    activeMarker.markerId = elementId

    ---@type proximityTool.activeMarkerData
    local topRecord = activeMarker.topMarker

    local unitedEvents = {
        mouseMove = async:callback(function(coord, layout)
            tooltipFuncs.tooltipMoveOrCreate(coord, layout)

            if not layout.userData or not layout.userData.data then return end
            local activeM = layout.userData.data
            activeM:triggerEvent("mouseMove", coord)
        end),

        focusLoss = async:callback(function(e, layout)
            tooltipFuncs.tooltipDestroy(layout)

            if not layout.userData or not layout.userData.data then return end
            local activeM = layout.userData.data
            activeM:triggerEvent("focusLoss", e)
        end),
    }

    for _, eventName in pairs(eventNames) do
        unitedEvents[eventName] = async:callback(function(e, layout)
            if not layout.userData or not layout.userData.data then return end
            ---@type proximityTool.activeMarker
            local activeM = layout.userData.data
            activeM:triggerEvent(eventName, e)
        end)
    end


    local eventsForRecord = {
        mouseMove = async:callback(function(coord, layout)
            tooltipFuncs.tooltipMoveOrCreate(coord, layout, true)

            if not layout.userData or not layout.userData.record then return end
            ---@type proximityTool.markerRecord
            local record = layout.userData.record
            if record.events and record.events["mouseMove"] then record.events["mouseMove"]() end
        end),

        focusLoss = async:callback(function(e, layout)
            tooltipFuncs.tooltipDestroy(layout)

            if not layout.userData or not layout.userData.record then return end
            ---@type proximityTool.markerRecord
            local record = layout.userData.record
            if record.events and record.events["focusLoss"] then record.events["focusLoss"]() end
        end),
    }

    for _, eventName in pairs(eventNames) do
        eventsForRecord[eventName] = async:callback(function(e, layout)
            if not layout.userData or not layout.userData.record then return end
            ---@type proximityTool.markerRecord
            local record = layout.userData.record
            if record.events and record.events[eventName] then record.events[eventName]() end
        end)
    end

    local nameColorData = topRecord.record.nameColor
    local nameColor = nameColorData and util.color.rgb(nameColorData[1] or 1, nameColorData[2] or 1, nameColorData[3] or 1) or defaultColor

    local mainLine = {
        {
            template = I.MWUI.templates.textNormal,
            type = ui.TYPE.Text,
            props = {
                text = "",
                textSize = 24,
                multiline = false,
                wordWrap = false,
                textAlignH = ui.ALIGNMENT.End,
                textAlignV = ui.ALIGNMENT.Start,
            },
            events = unitedEvents,
            userData = {
                data = activeMarker,
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = icons.arrowIcons[1],
                size = util.vector2(24, 24),
                color = defaultColor,
            },
            events = unitedEvents,
            userData = {
                data = activeMarker,
            },
        },
        {
            template = I.MWUI.templates.interval,
            userData = {
                data = activeMarker,
            },
            events = unitedEvents,
        },
        {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
            },
            userData = {
                data = activeMarker,
            },
            content = ui.content {}
        },
        {
            template = I.MWUI.templates.interval,
            userData = {
                data = activeMarker,
            },
            events = unitedEvents,
        },
        {
            type = ui.TYPE.Text,
            userData = {
                data = activeMarker,
            },
            props = {
                text = topRecord.name,
                textSize = 24,
                multiline = false,
                wordWrap = false,
                textAlignH = ui.ALIGNMENT.End,
                textColor = nameColor,
            },
            events = unitedEvents,
        },
    }

    local content = {
        {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                arrange = uiUtils.convertAlign(config.data.ui.align),
                alpha = 1,
            },
            userData = {
                distanceIndex = 1,
                directionIconIndex = 2,
            },
            content = nil
        },
        {
            type = ui.TYPE.Flex,
            props = {
                horizontal = false,
                arrange = uiUtils.convertAlign(config.data.ui.align),
                alpha = 1,
            },
            content = ui.content{},
        }
    }

    ---@type proximityTool.activeMarkerData[]
    local sortedRecords = tableLib.values(activeMarker.markers, function (a, b)
        return (a.record.priority or 0) > (b.record.priority or 0)
    end)

    for _, rDt in ipairs(sortedRecords) do
        local rec = rDt.record

        local noteContent

        if rec.note and rec.alpha ~= 0 then
            rDt.noteId = uniqueId.get()

            local noteColor = rec.noteColor and
                util.color.rgb(rec.noteColor[1] or 1, rec.noteColor[2] or 1, rec.noteColor[3] or 1) or defaultColor

            noteContent = ui.content {}

            noteContent:add {
                type = ui.TYPE.Text,
                name = rDt.noteId,
                props = {
                    text = tostring(rec.note):sub(1, 50),
                    textColor = noteColor,
                    textSize = 24,
                    multiline = false,
                    wordWrap = false,
                    visible = true,
                    textAlignH = ui.ALIGNMENT.End,
                },
                events = eventsForRecord,
                userData = {
                    recordId = rDt.recordId,
                    record = rDt.record,
                    data = activeMarker,
                },
            }

            content[2].content:add{
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                },
                userData = {
                    recordId = rDt.recordId,
                    record = rDt.record
                },
                events = eventsForRecord,
                content = noteContent,
            }
        end

        if rec.icon then
            local texture = ui.texture{path = rec.icon}
            local iconColor = rec.iconColor and util.color.rgb(rec.iconColor[1] or 1, rec.iconColor[2] or 1, rec.iconColor[3] or 1) or nil
            local name = rec.icon..tostring(iconColor)

            local size = {24, 24}
            local iconRatio = rec.iconRatio or 1
            if iconRatio > 1 then
                size[1] = size[1] / iconRatio
            else
                size[2] = size[2] * iconRatio
            end

            local iconSize = util.vector2(math.floor(size[1]), math.floor(size[2]))

            local iconContent = {
                type = ui.TYPE.Image,
                props = {
                    resource = texture,
                    size = iconSize,
                    color = iconColor,
                },
                name = name,
                events = eventsForRecord,
                userData = {
                    recordId = rDt.recordId,
                    record = rDt.record,
                    data = activeMarker,
                },
            }

            if noteContent and (not rec.options or rec.options.showNoteIcon ~= false) then
                noteContent:add(iconContent)
                noteContent:add{
                    template = I.MWUI.templates.interval,
                    events = eventsForRecord,
                }
            end

            if (not rec.options or rec.options.showGroupIcon ~= false) and #mainLine[4].content < 6 then
                local index = mainLine[4].content:indexOf(name)
                if index then
                    local elem = mainLine[4].content[index]
                    ---@type proximityTool.markerRecord
                    local record = elem.userData.record
                    if record and (record.priority or 0) < (rec.priority or 0) then
                        elem.userData.record = rec
                        elem.userData.recordId = rDt.recordId
                        elem.props.resource = texture
                    end
                else
                    mainLine[4].content:add(iconContent)
                end
            end
        end
    end

    if config.data.ui.orderH == "Right to left" then
        mainLine = tableLib.invertIndexes(mainLine)
        content[1].userData.distanceIndex = 6
        content[1].userData.directionIconIndex = 5
    end
    content[1].content = ui.content(mainLine)

    local uiData = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = false,
            arrange = uiUtils.convertAlign(config.data.ui.align),
            alpha = 0,
            visible = true,
        },
        userData = {
            data = activeMarker,
        },
        name = elementId,
        content = ui.content(content),
    }

    local function updateInGroupIfExists(grName)
        local grContent = (getMarkerParentElement(grName) or {}).content
        if not grContent then return end

        local grIndex = grContent:indexOf(elementId)
        if grIndex then
            grContent[grIndex] = uiData
            return grIndex
        end
    end

    local groupName = activeMarker.groupName

    if not updateInGroupIfExists(groupName) and not updateInGroupIfExists(commonData.hiddenGroupId) then
        createGroup(groupName)
        local parentContent = (getMarkerParentElement(groupName) or {}).content
        if not parentContent then return end

        parentContent:add(uiData)
    end
end


local function mainWindowBox(content, showBorder)
    return {
        template = showBorder and I.MWUI.templates.boxSolid or nil,
        type = not showBorder and ui.TYPE.Flex or nil,
        props = {
            autoSize = true,
        },
        content = ui.content(content),
    }
end


function this.create(params)
    if not params then params = {} end
    if this.element then
        markerParentElement = nil
        this.element:destroy()
        mainMenuSafeContainer.element = nil
    end

    if config.data.ui.hideHUD and not params.showBorder then return end
    if config.data.ui.hideWindow and params.showBorder then return end

    local screenSize = ui.screenSize()

    local mainContent = {
        type = ui.TYPE.Container,
        content = ui.content {
            {
                type = ui.TYPE.Flex,
                props = {
                    position = util.vector2(0, 0),
                    size = util.vector2(screenSize.x * config.data.ui.size.x / 100, screenSize.y * config.data.ui.size.y / 100),
                    autoSize = false,
                    horizontal = false,
                    arrange = uiUtils.convertAlign(config.data.ui.align),
                },
                content = ui.content {

                },
            }
        },
    }

    local header = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            visible = config.data.ui.showHeader or params.showBorder,
        },
        content = ui.content {
            addButton{menu = this, textSize = 24, text = "P",
                event = function (layout)
                    local position = this.element.layout.props.relativePosition
                    config.data.ui.position.x = position.x * 100
                    config.data.ui.position.y = position.y * 100
                    config.save()
                end,
                tooltipContent = ui.content {
                    {
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = "[PH] Set position",
                            textSize = 24,
                        },
                    }
                }
            },
            addInterval(8, 8),
            addButton{menu = this, textSize = 24, text = "|<",
                event = function (layout)
                    local pos = mainContent.content[1].props.position
                    if not pos then return end

                    mainContent.content[1].props.position = util.vector2(0, 0)
                    this.element:update()
                end,
                tooltipContent = ui.content {
                    {
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = "[PH] Scroll to start",
                            textSize = 24,
                        },
                    }
                }
            },
            addInterval(4, 4),
            addButton{menu = this, textSize = 24, text = "<<",
                event = function (layout)
                    local pos = mainContent.content[1].props.position
                    if not pos then return end

                    mainContent.content[1].props.position = util.vector2(0, math.min(0, pos.y + 24))
                    this.element:update()
                end,
                tooltipContent = ui.content {
                    {
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = "[PH] Scroll up",
                            textSize = 24,
                        },
                    }
                }
            },
            addInterval(4, 4),
            addButton{menu = this, textSize = 24, text = ">>",
                event = function (layout)
                    local pos = mainContent.content[1].props.position
                    if not pos then return end

                    mainContent.content[1].props.position = util.vector2(0, pos.y - 24)
                    this.element:update()
                end,
                tooltipContent = ui.content {
                    {
                        template = I.MWUI.templates.textNormal,
                        props = {
                            text = "[PH] Scroll down",
                            textSize = 24,
                        },
                    }
                }
            },
            addInterval(8, 8),
            mainWindowBox({
                {
                    template = I.MWUI.templates.textHeader,
                    type = ui.TYPE.Text,
                    props = {
                        text = "Tracking:  ",
                        textSize = 28,
                        multiline = false,
                        wordWrap = false,
                        textAlignH = uiUtils.convertAlign(config.data.ui.align),
                        textShadow = true,
                        textShadowColor = util.color.rgb(0, 0, 0),
                    },
                    userData = {
                        lastMousePos = nil,
                    },
                    events = {
                        mousePress = async:callback(function(coord, layout)
                            layout.userData.doDrag = true
                            local screenSize = ui.screenSize()
                            layout.userData.lastMousePos = util.vector2(coord.position.x / screenSize.x, coord.position.y / screenSize.y)
                        end),

                        mouseRelease = async:callback(function(_, layout)
                            layout.userData.lastMousePos = nil
                        end),

                        mouseMove = async:callback(function(coord, layout)
                            if not layout.userData.lastMousePos then return end

                            local screenSize = ui.screenSize()
                            local props = this.element.layout.props
                            local relativePos = util.vector2(coord.position.x / screenSize.x, coord.position.y / screenSize.y)

                            props.relativePosition = props.relativePosition - (layout.userData.lastMousePos - relativePos)
                            elementRelPos = props.relativePosition
                            config.setLocal("ui.positionAlt.x", elementRelPos.x * 100)
                            config.setLocal("ui.positionAlt.y", elementRelPos.y * 100)
                            this.element:update()

                            layout.userData.lastMousePos = relativePos
                        end),
                    },
                }
            }, params.showBorder),
        }
    }


    local parentContent = {
        {
            type = ui.TYPE.Flex,
            props = {
                autoSize = false,
                size = util.vector2(screenSize.x * config.data.ui.size.x / 100, screenSize.y * config.data.ui.size.y / 100),
                horizontal = false,
                arrange = uiUtils.convertAlign(config.data.ui.align),
            },
            content = ui.content {
                header,
                mainContent,
            },
        },
    }

    local position
    if params.showBorder and elementRelPos then
        position = elementRelPos
    else
        position = util.vector2(config.data.ui.position.x / 100, config.data.ui.position.y / 100)
    end

    local base = mainWindowBox(parentContent, params.showBorder)
    base.props = {
        autoSize = true,
        horizontal = false,
        arrange = uiUtils.convertAlign(config.data.ui.align),
        relativePosition = position,
        anchor = util.vector2(1, 0),
    }
    base.layer = params.showBorder and "Windows" or "HUD"

    this.element = ui.create(base)

    mainMenuSafeContainer.element = this.element

    createGroup(commonData.defaultGroupId)
    createGroup(commonData.hiddenGroupId, {priority = -math.huge, protected = true})

    for _, activeMarker in pairs(activeMarkers.data) do
        this.registerMarker(activeMarker)
    end
end

---@class objectTrackingBD.mainMenu.update.params
---@field force boolean?

---@param params objectTrackingBD.mainMenu.update.params?
function this.update(params)
    if not this.element then return end
    if not params then params = {} end

    local parentElement = getMarkerParentElement()
    local hiddenGroupElement = getMarkerParentElement(commonData.hiddenGroupId)
    if not parentElement or not hiddenGroupElement then return end

    local player = playerObj.object
    local playerPos = player.position
    local pitch, yaw  = player.rotation:getAnglesXZ()

    local doUpdate = params.force or false

    local function orderAndOpacity(parent)
        local sortedData = {}
        for i, element in ipairs(parent.content) do
            local priority = element.userData.priority or 0
            table.insert(sortedData, {element = element, priority = priority})
        end
        table.sort(sortedData, function (a, b)
            return a.priority > b.priority
        end)

        for i = #parent.content, 1, -1 do
            local element = parent.content[i]
            if not element or not element.userData or not element.userData then goto continue end

            local disabled = element.userData.disabled

            if disabled then
                if element.props.visible then
                    element.props.alpha = params.force and 0 or element.props.alpha - 0.03
                    if element.props.alpha <= 0 then
                        element.userData.locked = true
                        element.props.alpha = 0
                        element.props.visible = false

                        uiUtils.removeFromContent(parent.content, i)
                        hiddenGroupElement.content:add(element)
                        doUpdate = true
                        goto continue
                    end
                end
            else
                local orderElemData = sortedData[i]

                if orderElemData then
                    local elem2 = orderElemData.element
                    local index = parent.content:indexOf(elem2)
                    if not index or index <= i or math.floor(element.userData.priority or 0) == math.floor(elem2.userData.priority or 0) or
                        element.userData.disabled or elem2.userData.disabled then
                            goto nextAction
                    end

                    local alpha1 = element.props.alpha
                    if alpha1 > 0.5 then
                        alpha1 = params.force and 0.5 or math.max(0, alpha1 - 0.05)
                        element.props.alpha = alpha1
                        doUpdate = true
                    end

                    local alpha2 = elem2.props.alpha
                    if alpha2 > 0.5 then
                        alpha2 = params.force and 0.5 or math.max(0, alpha2 - 0.05)
                        elem2.props.alpha = alpha2
                        doUpdate = true
                    end

                    if alpha1 < 0.51 and alpha2 < 0.51 then
                        parent.content.__nameIndex[element.name], parent.content.__nameIndex[elem2.name] =
                            parent.content.__nameIndex[elem2.name], parent.content.__nameIndex[element.name]
                        parent.content[index], parent.content[i] = element, elem2
                        doUpdate = true
                    end

                    goto continue
                end

                ::nextAction::

                if element.userData.alpha then
                    if element.props.alpha < element.userData.alpha then
                        element.props.alpha = params.force and 1 or math.min(element.props.alpha + 0.03, element.userData.alpha)
                        doUpdate = true
                    elseif element.props.alpha > element.userData.alpha then
                        element.props.alpha = params.force and 0 or math.max(element.props.alpha - 0.03, element.userData.alpha)
                        doUpdate = true
                    end
                end
                element.props.visible = true

                if parent.userData and parent.userData.groupName and parent.userData.groupName == commonData.hiddenGroupId then
                    local groupElement = getMarkerParentElement(element.userData.data.groupName)
                    if not groupElement then
                        createGroup(element.userData.data.groupName)
                        groupElement = getMarkerParentElement(element.userData.data.groupName)
                    end

                    if groupElement then
                        uiUtils.removeFromContent(parent.content, i)
                        groupElement.content:add(element)
                        doUpdate = true
                        goto continue
                    end
                end
            end

            ::continue::
        end
    end


    local function processGroup(contentOwner, parent)
        if not contentOwner then return end

        local timestamp = core.getRealTime()

        for i = #contentOwner.content, 1, -1 do
            local elem = contentOwner.content[i]
            if not elem or not elem.props or not elem.userData or not elem.userData.data then goto continue end

            elem.userData.locked = false

            ---@type proximityTool.activeMarker
            local trackingData = elem.userData.data

            if not trackingData.isValid then
                uiUtils.removeFromContent(contentOwner.content, i)
                doUpdate = true
                goto continue
            end

            ---@type proximityTool.activeMarkerData?
            local topMarkerRecord = trackingData.topMarker
            if not topMarkerRecord then
                uiUtils.removeFromContent(contentOwner.content, i)
                doUpdate = true
                goto continue
            end

            local trackingPos

            if topMarkerRecord.type == 1 and topMarkerRecord.objectId then
                if trackingData.nextUpdate < timestamp or not trackingData.lastTrackedObject then
                    local trackerObjPositions = activeObjects.getObjectPositions(topMarkerRecord.objectId, player, topMarkerRecord.marker.itemId)
                    if not trackerObjPositions then
                        uiUtils.removeFromContent(contentOwner.content, i)
                        doUpdate = true
                        goto continue
                    end

                    table.sort(trackerObjPositions, function (a, b)
                        return (a.dif or math.huge) < (b.dif or math.huge)
                    end)

                    if #trackerObjPositions > 0 then
                        local posData = trackerObjPositions[1]
                        trackingPos = util.vector3(posData.x, posData.y, posData.z)
                        trackingData.lastTrackedObject = posData.object
                    end

                    trackingData.nextUpdate = getNexUpdateTimestamp(timestamp)
                else
                    local posData = activeObjects.getObjectPositionData(trackingData.lastTrackedObject, nil, topMarkerRecord.marker.itemId)
                    if posData then
                        trackingPos = util.vector3(posData.x, posData.y, posData.z)
                    else
                        trackingData.nextUpdate = 0
                    end
                end

            elseif topMarkerRecord.type == 2 and topMarkerRecord.object then
                local objectRef = topMarkerRecord.object
                local posData = activeObjects.getObjectPositionData(objectRef, nil, topMarkerRecord.marker.itemId)
                if posData then
                    trackingPos = util.vector3(posData.x, posData.y, posData.z)
                else
                    uiUtils.removeFromContent(contentOwner.content, i)
                    doUpdate = true
                    goto continue
                end

            elseif topMarkerRecord.type == 3 and topMarkerRecord.positions then
                if trackingData.nextUpdate < timestamp or not trackingData.lastTrackedObject then
                    trackingPos = cellLib.getClosestPosition(topMarkerRecord.positions)
                    trackingData.lastTrackedObject = trackingPos
                    trackingData.nextUpdate = getNexUpdateTimestamp(timestamp)
                else
                    trackingPos = trackingData.lastTrackedObject
                end

            elseif topMarkerRecord.type == 4 and topMarkerRecord.objectIds then
                if trackingData.nextUpdate < timestamp or not trackingData.lastTrackedObject then
                    local trackerObjPositions = activeObjects.getObjectPositionsByGroupName(topMarkerRecord.id, player, topMarkerRecord.marker.itemId)
                    if not trackerObjPositions then
                        uiUtils.removeFromContent(contentOwner.content, i)
                        doUpdate = true
                        goto continue
                    end

                    table.sort(trackerObjPositions, function (a, b)
                        return (a.dif or math.huge) < (b.dif or math.huge)
                    end)

                    if #trackerObjPositions > 0 then
                        local posData = trackerObjPositions[1]
                        trackingPos = util.vector3(posData.x, posData.y, posData.z)
                        trackingData.lastTrackedObject = posData.object
                    end

                    trackingData.nextUpdate = getNexUpdateTimestamp(timestamp)
                else
                    local posData = activeObjects.getObjectPositionData(trackingData.lastTrackedObject, nil, topMarkerRecord.marker.itemId)
                    if posData then
                        trackingPos = util.vector3(posData.x, posData.y, posData.z)
                    else
                        trackingData.nextUpdate = 0
                    end
                end

            else
                uiUtils.removeFromContent(contentOwner.content, i)
                doUpdate = true
                goto continue
            end


            if not trackingPos then
                uiUtils.removeFromContent(contentOwner.content, i)
                doUpdate = true
                goto continue
            end

            local distance = (playerPos - trackingPos):length()
            local distance2D = math.sqrt((playerPos.x - trackingPos.x)^2 + (playerPos.y - trackingPos.y)^2)
            local heightDiff = playerPos.z - trackingPos.z

            elem.userData.distance = distance
            elem.userData.distance2D = distance2D
            elem.userData.heightDiff = heightDiff
            elem.userData.alpha = trackingData.alpha

            -- for ordering
            local priorityByDistance = 0
            if distance < 150 then
                priorityByDistance = 200
            elseif distance < 600 then
                priorityByDistance = math.floor((500 - distance) / 50) * 10
            elseif distance > 10000 then
                priorityByDistance = -math.floor(distance / 10000) * 10
            end

            elem.userData.priority = trackingData.priority + priorityByDistance
            if parent and not parent.userData.isProtected then
                parent.userData.priority = math.max(elem.userData.priority, parent.userData.priority)
            end

            local hide = (distance > trackingData.proximity) or (trackingData.alpha <= 0) or trackingData.hidden
            if elem.userData.disabled ~= hide then
                doUpdate = true
            end
            elem.userData.disabled = hide

            local arrowImageIndex
            local iconImage

            if  distance2D < 200 then
                if heightDiff > 200 then
                    iconImage = icons.arrowIcons_P[3]
                elseif heightDiff < -200 then
                    iconImage = icons.arrowIcons_P[2]
                else
                    iconImage = icons.arrowIcons_P[1]
                end
            else
                local imageArr
                if heightDiff > 200 then
                    imageArr = icons.arrowIcons_B
                elseif heightDiff < -200 then
                    imageArr = icons.arrowIcons_A
                else
                    imageArr = icons.arrowIcons
                end

                local angle = util.normalizeAngle(yaw - math.atan2(playerPos.x - trackingPos.x, playerPos.y - trackingPos.y) + math.pi * 1/16) ---@diagnostic disable-line: deprecated
                arrowImageIndex = 1 + util.round((math.pi + angle) / (2 * math.pi) * 7)
                iconImage = imageArr[arrowImageIndex]
            end

            local distanceIndex = elem.content[1].userData.distanceIndex
            local directionIndex = elem.content[1].userData.directionIconIndex
            local newText = string.format("%.0fm", distance / 64 * 0.9144)
            if elem.content[1].content[distanceIndex or 1].props.text ~= newText then
                elem.content[1].content[distanceIndex or 1].props.text = newText
                doUpdate = true
            end
            if elem.content[1].content[directionIndex or 2].props.resource ~= iconImage then
                elem.content[1].content[directionIndex or 2].props.resource = iconImage
                doUpdate = true
            end

            ::continue::
        end

        orderAndOpacity(contentOwner)
    end


    for i = #parentElement.content, 1, -1 do
        local elem = parentElement.content[i]
        if not elem or not elem.userData or not elem.userData.groupName then goto continue end

        if not elem.userData.isProtected then
            elem.userData.priority = 0
        end

        local contentElement = getMarkerParentElement(elem.userData.groupName)
        if not contentElement then goto continue end

        if not elem.userData.isProtected and #contentElement.content == 0 then
            uiUtils.removeFromContent(parentElement.content, i)
            goto continue
        end

        processGroup(contentElement, elem)

        ::continue::
    end

    processGroup(hiddenGroupElement)

    orderAndOpacity(parentElement)

    if doUpdate then
        this.element:update()
    end
end


function this.destroy()
    if this.element then
        markerParentElement = nil
        this.element:destroy()
        this.element = nil
        mainMenuSafeContainer.element = nil
    end
end


return this