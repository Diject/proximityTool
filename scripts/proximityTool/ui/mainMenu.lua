local I = require('openmw.interfaces')
local ui = require('openmw.ui')
local util = require('openmw.util')
local async = require('openmw.async')
local core = require('openmw.core')
local playerObj = require('openmw.self')
local camera = require('openmw.camera')

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

local tooltip = require("scripts.proximityTool.ui.tooltip")
local tooltipFuncs = require("scripts.proximityTool.ui.mainMenuTooltip")

local addButton = require("scripts.proximityTool.ui.button")
local addInterval = require("scripts.proximityTool.ui.interval")

local l10n = core.l10n(commonData.l10nKey)


local this = {}

local elementRelPos = util.vector2(config.data.ui.positionInMenu.x / 100, config.data.ui.positionInMenu.y / 100)

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
---@type {content : any}
this.markerElementsData = nil
this.maxLines = math.huge

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
        return this.markerElementsData
    elseif groupName == commonData.hiddenGroupId then
        return this.hiddenGroupElement
    elseif groupName then
        local parent = this.markerElementsData
        if not parent then return end

        local index = parent.content:indexOf(groupName)
        if not index then return end

        return parent.content[index].content[2]
    else
        return this.markerElementsData
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
    local groupNameFontSize = config.data.ui.fontSize
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
                    textColor = config.data.ui.defaultColor,
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
    local nameColor = nameColorData and util.color.rgb(nameColorData[1] or 1, nameColorData[2] or 1, nameColorData[3] or 1) or config.data.ui.defaultColor

    local mainLine = {
        {
            template = I.MWUI.templates.textNormal,
            type = ui.TYPE.Text,
            props = {
                text = "",
                textSize = config.data.ui.fontSize,
                textColor = config.data.ui.defaultColor,
                multiline = false,
                wordWrap = false,
                textAlignH = ui.ALIGNMENT.End,
                textAlignV = ui.ALIGNMENT.Start,
                visible = activeMarker.type ~= 16,
                textShadow = true,
                textShadowColor = util.color.rgb(0, 0, 0),
            },
            userData = {
                data = activeMarker,
            },
        },
        {
            type = ui.TYPE.Image,
            props = {
                resource = icons.arrowIcons[1],
                size = util.vector2(config.data.ui.fontSize, config.data.ui.fontSize),
                color = config.data.ui.defaultColor,
                visible = activeMarker.type ~= 16,
            },
            userData = {
                data = activeMarker,
            },
        },
        {
            template = I.MWUI.templates.interval,
            userData = {
                data = activeMarker,
                visible = activeMarker.type ~= 16,
            },
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
        },
        {
            type = ui.TYPE.Text,
            userData = {
                data = activeMarker,
            },
            props = {
                text = topRecord.name,
                textSize = config.data.ui.fontSize,
                multiline = false,
                wordWrap = false,
                textAlignH = ui.ALIGNMENT.End,
                textColor = nameColor,
                textShadow = true,
                textShadowColor = util.color.rgb(0, 0, 0),
            },
        },
    }

    local content = {
        {
            type = ui.TYPE.Flex,
            props = {
                horizontal = true,
                arrange = uiUtils.convertAlign(config.data.ui.align),
                alpha = 1,
                propagateEvents = false,
            },
            userData = {
                data = activeMarker,
                distanceIndex = 1,
                directionIconIndex = 2,
                textIndex = 6,
            },
            events = unitedEvents,
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
                util.color.rgb(rec.noteColor[1] or 1, rec.noteColor[2] or 1, rec.noteColor[3] or 1) or config.data.ui.defaultColor

            noteContent = ui.content {}

            noteContent:add {
                type = ui.TYPE.Text,
                name = rDt.noteId,
                props = {
                    text = tostring(rec.note):sub(1, 50),
                    textColor = noteColor,
                    textSize = config.data.ui.fontSize,
                    multiline = false,
                    wordWrap = false,
                    visible = true,
                    textAlignH = ui.ALIGNMENT.End,
                    propagateEvents = false,
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
                    propagateEvents = false,
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

            local size = {config.data.ui.fontSize, config.data.ui.fontSize}
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
                    propagateEvents = false,
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
                    props = {
                        propagateEvents = false,
                    },
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


local function mainWindowBox(content, showBorder, userData)
    return {
        template = showBorder and I.MWUI.templates.boxSolid or nil,
        type = not showBorder and ui.TYPE.Flex or nil,
        props = {
            autoSize = true,
            inheritAlpha = false,
        },
        userData = userData,
        content = ui.content(content),
    }
end


local function setMainBoxVisibility(state)
    if not this.element then return end

    this.element.layout.props.alpha = state and 1 or 0
end


function this.create(params)
    if not params then params = {} end
    if this.element then
        markerParentElement = nil
        this.element:destroy()
        mainMenuSafeContainer.element = nil
        this.markerElementsData = nil
    end

    if config.data.ui.hideHUD and not params.showBorder then return end
    if config.data.ui.hideWindow and params.showBorder then return end

    local screenSize = uiUtils.getScaledScreenSize()

    local mainContent

    local function scrollUp(val)
        local pos = mainContent.content[1].props.position
        if not pos then return end

        mainContent.content[1].props.position = util.vector2(0, math.min(0, pos.y + val))
        this.element:update()
    end

    local function scrollDown(val)
        local pos = mainContent.content[1].props.position
        if not pos then return end

        mainContent.content[1].props.position = util.vector2(0, pos.y - val)
        this.element:update()
    end

    local function getScrollEvents()
        return {
            mousePress = async:callback(function(coord, layout)
                layout.userData.lastMousePos = util.vector2(coord.position.x, coord.position.y)
            end),

            mouseRelease = async:callback(function(_, layout)
                layout.userData.lastMousePos = nil
            end),

            focusLoss = async:callback(function(_, layout)
                layout.userData.lastMousePos = nil
            end),

            mouseMove = async:callback(function(coord, layout)
                if not layout.userData.lastMousePos then return end

                local posDIff = coord.position - layout.userData.lastMousePos

                if posDIff.y > 0 then
                    scrollUp(posDIff.y)
                elseif posDIff.y < 0 then
                    scrollDown(-posDIff.y)
                end

                layout.userData.lastMousePos = coord.position
            end),
        }
    end


    mainContent = {
        type = ui.TYPE.Container,
        content = ui.content {
            {
                type = ui.TYPE.Flex,
                props = {
                    position = util.vector2(0, 0),
                    autoSize = true,
                    horizontal = false,
                    arrange = uiUtils.convertAlign(config.data.ui.align),
                },
                userData = {},
                events = getScrollEvents(),
                content = ui.content {

                },
            }
        },
    }

    local isMainHidden = params.showBorder and config.data.ui.minimizeToAnchor or false

    local parentContent

    local headerHeight = config.data.ui.fontSize * 1.2 + 6

    local trackingLabelText = l10n("trackingAnchor")
    trackingLabelText = config.data.ui.orderH == "Right to left" and " "..trackingLabelText or trackingLabelText.." "

    local headerContentArr

    local function setHeaderContentVisibility(isVisible)
        for _, elem in pairs(headerContentArr or {}) do
            if elem.props and (not elem.userData or not elem.userData.isHeader) then
                elem.props.visible = isVisible
            end
        end
    end

    headerContentArr = {
        addButton{menu = this, textSize = config.data.ui.fontSize, text = "P", textColor = config.data.ui.defaultColor,
            event = function (layout)
                local position = this.element.layout.props.relativePosition
                config.setValue("ui.position.x", position.x * 100)
                config.setValue("ui.position.y", position.y * 100)
            end,
            tooltipContent = config.data.ui.helpTooltips and ui.content {
                {
                    template = I.MWUI.templates.textNormal,
                    props = {
                        text = l10n("setPosition"),
                        textSize = config.data.ui.fontSize,
                        textColor = config.data.ui.defaultColor,
                    },
                }
            }
        },
        addInterval(config.data.ui.fontSize / 2, config.data.ui.fontSize / 2),
        {
            type = ui.TYPE.Flex,
            props = {
                autoSize = true,
                horizontal = true,
            },
            content = ui.content{
                -- addButton{menu = this, textSize = config.data.ui.fontSize, text = "|<", textColor = config.data.ui.defaultColor,
                --     event = function (layout)
                --         local pos = mainContent.content[1].props.position
                --         if not pos then return end

                --         mainContent.content[1].props.position = util.vector2(0, 0)
                --         this.element:update()
                --     end,
                --     tooltipContent = config.data.ui.helpTooltips and ui.content {
                --         {
                --             template = I.MWUI.templates.textNormal,
                --             props = {
                --                 text = l10n("scrollToStart"),
                --                 textSize = config.data.ui.fontSize,
                --                 textColor = config.data.ui.defaultColor,
                --             },
                --         }
                --     }
                -- },
                -- addInterval(config.data.ui.fontSize / 2, config.data.ui.fontSize / 2),
                addButton{menu = this, textSize = config.data.ui.fontSize, text = "<<", textColor = config.data.ui.defaultColor,
                    event = function (layout)
                        scrollUp(config.data.ui.fontSize * 2)
                    end,
                    intervalEvent = function (layout)
                        scrollUp(config.data.ui.fontSize)
                    end,
                    tooltipContent = config.data.ui.helpTooltips and ui.content {
                        {
                            template = I.MWUI.templates.textNormal,
                            props = {
                                text = l10n("scrollUp"),
                                textSize = config.data.ui.fontSize,
                                textColor = config.data.ui.defaultColor,
                            },
                        }
                    }
                },
                addInterval(config.data.ui.fontSize / 2, config.data.ui.fontSize / 2),
                addButton{menu = this, textSize = config.data.ui.fontSize, text = ">>", textColor = config.data.ui.defaultColor,
                    event = function (layout)
                        scrollDown(config.data.ui.fontSize * 2)
                    end,
                    intervalEvent = function (layout)
                        scrollDown(config.data.ui.fontSize)
                    end,
                    tooltipContent = config.data.ui.helpTooltips and ui.content {
                        {
                            template = I.MWUI.templates.textNormal,
                            props = {
                                text = l10n("scrollDown"),
                                textSize = config.data.ui.fontSize,
                                textColor = config.data.ui.defaultColor,
                            },
                        }
                    }
                },
            },
        },
        addInterval(config.data.ui.fontSize, config.data.ui.fontSize),
        mainWindowBox({
            {
                template = I.MWUI.templates.textHeader,
                type = ui.TYPE.Text,
                props = {
                    text = trackingLabelText,
                    textSize = config.data.ui.fontSize * 1.2,
                    textColor = config.data.ui.defaultColor,
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
                        layout.userData.doDrag = false
                        local screenSize = uiUtils.getScaledScreenSize()
                        layout.userData.lastMousePos = util.vector2(coord.position.x / screenSize.x, coord.position.y / screenSize.y)
                    end),

                    mouseRelease = async:callback(function(_, layout)
                        layout.userData.lastMousePos = nil

                        if not layout.userData.doDrag then
                            if isMainHidden then
                                parentContent[1].props.size = util.vector2(screenSize.x * config.data.ui.size.x / 100, screenSize.y * config.data.ui.size.y / 100)
                            else
                                parentContent[1].props.size = util.vector2(screenSize.x * config.data.ui.size.x / 100, headerHeight)
                            end

                            setMainBoxVisibility(isMainHidden)
                            setHeaderContentVisibility(isMainHidden)
                            isMainHidden = not isMainHidden
                            this.element:update()
                        end
                        layout.userData.doDrag = false
                    end),

                    mouseMove = async:callback(function(coord, layout)
                        if config.data.ui.helpTooltips then
                            tooltip.createOrMove(coord, layout, ui.content {
                                {
                                    template = I.MWUI.templates.textNormal,
                                    props = {
                                        text = l10n("trackingAnchorTooltip"),
                                        textSize = config.data.ui.fontSize,
                                        textColor = config.data.ui.defaultColor,
                                    },
                                }
                            })
                        end

                        if not layout.userData.lastMousePos then return end

                        layout.userData.doDrag = true

                        local screenSize = uiUtils.getScaledScreenSize()
                        local props = this.element.layout.props
                        local relativePos = util.vector2(coord.position.x / screenSize.x, coord.position.y / screenSize.y)

                        props.relativePosition = props.relativePosition - (layout.userData.lastMousePos - relativePos)
                        elementRelPos = props.relativePosition
                        config.setLocal("ui.positionInMenu.x", elementRelPos.x * 100)
                        config.setLocal("ui.positionInMenu.y", elementRelPos.y * 100)

                        this.element:update()

                        layout.userData.lastMousePos = relativePos
                    end),

                    focusLoss = async:callback(function(e, layout)
                        tooltip.destroy(layout)
                    end),
                },
            }
        }, params.showBorder, {isHeader = true}),
    }

    setHeaderContentVisibility(not isMainHidden)

    if config.data.ui.orderH == "Right to left" then
        headerContentArr = tableLib.invertIndexes(headerContentArr)
    end

    local header = {
        type = ui.TYPE.Flex,
        props = {
            horizontal = true,
            visible = config.data.ui.showHeader or params.showBorder,
            propagateEvents = false,
        },
        content = ui.content(headerContentArr)
    }

    local parantContentHeight
    if isMainHidden then
        parantContentHeight = util.vector2(screenSize.x * config.data.ui.size.x / 100, headerHeight)
    else
        parantContentHeight = util.vector2(screenSize.x * config.data.ui.size.x / 100, screenSize.y * config.data.ui.size.y / 100)
    end
    parentContent = {
        {
            type = ui.TYPE.Flex,
            props = {
                autoSize = false,
                size = parantContentHeight,
                horizontal = false,
                arrange = uiUtils.convertAlign(config.data.ui.align),
            },
            userData = {},
            events = getScrollEvents(),
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
        alpha = isMainHidden and 0 or 1,
    }
    base.layer = params.showBorder and "Windows" or "HUD"

    this.maxLines = not params.showBorder and math.ceil(screenSize.y * config.data.ui.size.y / 100 / config.data.ui.fontSize) or 999

    this.element = ui.create(base)
    this.markerElementsData = {content = ui.content {}}

    mainMenuSafeContainer.element = this.element

    createGroup(commonData.defaultGroupId)
    createGroup(commonData.hiddenGroupId, {priority = -math.huge, protected = true})

    for _, activeMarker in pairs(activeMarkers.data) do
        this.registerMarker(activeMarker)
    end
end




local function getAdditionalPriorityByDistance(distance)
    local res = 0
    if distance < 150 then
        res = 200
    elseif distance < 600 then
        res = math.floor((1000 - distance) / 200) * 20
    elseif distance > 10000 then
        res = -math.floor(distance / 10000) * 10
    end

    return res
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
    local cameraPos = camera.getPosition()
    local cameraYaw = camera.getYaw() + camera.getExtraYaw()

    local doUpdate = params.force or false

    local alphaAdditiveVal = config.data.updateInterval / 1500
    local alphaAdditiveValAlt = alphaAdditiveVal * 1.5

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
                    element.props.alpha = params.force and 0 or element.props.alpha - alphaAdditiveVal
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
                        alpha1 = params.force and 0.5 or math.max(0, alpha1 - alphaAdditiveValAlt)
                        element.props.alpha = alpha1
                        doUpdate = true
                    end

                    local alpha2 = elem2.props.alpha
                    if alpha2 > 0.5 then
                        alpha2 = params.force and 0.5 or math.max(0, alpha2 - alphaAdditiveValAlt)
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
                        element.props.alpha = params.force and 1 or math.min(element.props.alpha + alphaAdditiveVal, element.userData.alpha)
                        doUpdate = true
                    elseif element.props.alpha > element.userData.alpha then
                        element.props.alpha = params.force and 0 or math.max(element.props.alpha - alphaAdditiveVal, element.userData.alpha)
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


            ---@type { object: any, x: number, y: number, z: number, dif: number? }[]
            local trackingPositions = {}

            if util.bitAnd(topMarkerRecord.type, 1) > 0 and topMarkerRecord.objectId then
                local trackedObjPosition = activeObjects.getClosestObjectPosition(topMarkerRecord.objectId, player, topMarkerRecord.marker.itemId)
                if trackedObjPosition then
                    table.insert(trackingPositions, trackedObjPosition)
                end
            end

            if util.bitAnd(topMarkerRecord.type, 2) > 0 and topMarkerRecord.object then
                local objectRef = topMarkerRecord.object
                local posData = activeObjects.getObjectPositionData(objectRef, nil, topMarkerRecord.marker.itemId)
                if posData then
                    table.insert(trackingPositions, posData)
                end
            end

            if util.bitAnd(topMarkerRecord.type, 4) > 0 and topMarkerRecord.positions then
                if trackingData.nextUpdate < timestamp or not trackingData.lastTrackedObject then
                    local pos, distance = cellLib.getClosestPosition(topMarkerRecord.positions)
                    trackingData.lastTrackedObject = {pos, distance}
                    trackingData.nextUpdate = getNexUpdateTimestamp(timestamp)
                end
                local pos = trackingData.lastTrackedObject[1]
                local distance = trackingData.lastTrackedObject[2]
                table.insert(trackingPositions, {dif = distance, x = pos.x, y = pos.y, z = pos.z})
            end

            if util.bitAnd(topMarkerRecord.type, 8) > 0 and topMarkerRecord.objectIds then
                if trackingData.nextUpdate < timestamp or not trackingData.lastTrackedObject then
                    local trackedObjPositions = activeObjects.getClosestObjectPositionsByGroupName(topMarkerRecord.id, player, topMarkerRecord.marker.itemId)
                    if trackedObjPositions and next(trackingPositions) then
                        table.sort(trackedObjPositions, function (a, b)
                            return (a.dif or math.huge) < (b.dif or math.huge)
                        end)
                    end
                    trackingData.lastTrackedObject = trackedObjPositions and trackedObjPositions[1]
                    trackingData.nextUpdate = getNexUpdateTimestamp(timestamp)
                end

                if trackingData.lastTrackedObject then
                    table.insert(trackingPositions, trackingData.lastTrackedObject)
                end
            end

            if topMarkerRecord.type == 16 then
                elem.userData.priority = trackingData.priority
                local textIndex = elem.content[1].userData.textIndex
                if elem.content[1].content[textIndex or 6].props.text ~= topMarkerRecord.record.name then
                    elem.content[1].content[textIndex or 6].props.text = topMarkerRecord.record.name
                    doUpdate = true
                end
                elem.userData.distance = 0
                elem.userData.distance2D = 0
                elem.userData.heightDiff = 0
                elem.userData.alpha = trackingData.alpha
                goto continue

            elseif not next(trackingPositions) then
                uiUtils.removeFromContent(contentOwner.content, i)
                doUpdate = true
                goto continue
            end


            table.sort(trackingPositions, function (a, b)
                return (a.dif or math.huge) < (b.dif or math.huge)
            end)
            local closest = trackingPositions[1]
            local trackingPos = util.vector3(closest.x, closest.y, closest.z)


            local distance = (playerPos - trackingPos):length()
            local distance2D = math.sqrt((playerPos.x - trackingPos.x)^2 + (playerPos.y - trackingPos.y)^2)
            local heightDiff = playerPos.z - trackingPos.z

            elem.userData.distance = distance
            elem.userData.distance2D = distance2D
            elem.userData.heightDiff = heightDiff
            elem.userData.alpha = trackingData.alpha

            -- for ordering
            local priorityByDistance = getAdditionalPriorityByDistance(distance)

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

                local angle = util.normalizeAngle(cameraYaw - math.atan2(cameraPos.x - trackingPos.x, cameraPos.y - trackingPos.y) + math.pi * 1/16) ---@diagnostic disable-line: deprecated
                arrowImageIndex = 1 + util.round((math.pi + angle) / (2 * math.pi) * 7)
                iconImage = imageArr[arrowImageIndex]
            end

            local distanceIndex = elem.content[1].userData.distanceIndex
            local directionIndex = elem.content[1].userData.directionIconIndex
            local newText = config.data.ui.imperialUnits and string.format("%.0fft", distance / 21.33)
                    or string.format("%.0fm", distance / 69.99)
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
        local mainFlex = getMainFlex()
        if mainFlex then
            mainFlex.content = ui.content{}
            local maxLines = this.maxLines or 999
            for i, groupData in ipairs(this.markerElementsData.content) do
                local group = tableLib.copy(groupData)
                group.content = ui.content{}
                for _, elem in ipairs(groupData.content) do
                    group.content:add(tableLib.copy(elem))
                end

                local content = ui.content{}
                group.content[2].content = content

                mainFlex.content:add(group)

                maxLines = maxLines - 1
                for i, elem in ipairs(groupData.content[2].content) do
                    if maxLines > 0 then
                        maxLines = maxLines - 1
                        content:add(elem)
                    else
                        goto endLabel
                    end
                end
                if maxLines <= 0 then goto endLabel end
            end

            ::endLabel::
        end
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