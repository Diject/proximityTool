local I = require('openmw.interfaces')
local ui = require('openmw.ui')
local util = require('openmw.util')

local commonData = require("scripts.proximityTool.common")

local tableLib = require("scripts.proximityTool.utils.table")
local safeContainers = require("scripts.proximityTool.ui.safeContainer")

local this = {}


local function calcTooltipPosAnchor(cursorPos)
    local screenSize = ui.screenSize()

    local halfWidth = screenSize.x / 2
    local halfHeight = screenSize.y / 2

    local anchorX = cursorPos.x > halfWidth and 1 or 0
    local anchorY = cursorPos.y > halfHeight and 1 or 0
    local anchor = util.vector2 (anchorX, anchorY)

    local posX = cursorPos.x
    if anchorX <= 0 and anchorY <= 0 then
        posX = posX + 30
    end
    local tooltipPos = util.vector2(posX, cursorPos.y)

    return tooltipPos, anchor
end


---@param forRecord boolean?
function this.tooltipMoveOrCreate(coord, layout, forRecord)
    if not layout.userData or not layout.userData.data then return end

    local position, anchor = calcTooltipPosAnchor(coord.position)

    if not layout.userData.tooltip or not layout.userData.tooltip.valid then
        local tooltipHandler = safeContainers.new("mainMenuElementTooltip")

        layout.userData["tooltip"] = tooltipHandler

        local tooltipLayout = {
            template = I.MWUI.templates.boxSolid,
            layer = "Notification",
            props = {
                position = position,
                anchor = anchor,
            },
            content = ui.content {
                {
                    type = ui.TYPE.Flex,
                    props = {
                        horizontal = false,
                    },
                    content = ui.content {}
                }
            }
        }

        local foundDescription = false

        local function drawDescription(record)
            if not record.description then return end

            local dCol = record.descriptionColor

            local line = {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = false,
                },
                content = ui.content {}
            }

            local added = false
            local function addDescrLine(str, color)
                if str and str ~= "" then
                    added = true
                    line.content:add{
                        type = ui.TYPE.Text,
                        props = {
                            text = str,
                            textSize = 24,
                            multiline = true,
                            wordWrap = true,
                            autoSize = true,
                            textAlignH = ui.ALIGNMENT.Start,
                            textAlignV = ui.ALIGNMENT.End,
                            textColor = color,
                        },
                    }
                end
            end

            if type(record.description) == "string" then
                local color = dCol and util.color.rgb(dCol[1], dCol[2], dCol[3])
                if dCol then
                    if type(dCol[1]) == "number" then
                        color = util.color.rgb(dCol[1], dCol[2], dCol[3])
                    else
                        color = util.color.rgb(dCol[1][1], dCol[1][2], dCol[1][3])
                    end
                else
                    color = commonData.defaultColor
                end
                addDescrLine(record.description, color)
            else
                for i, str in ipairs(record.description) do ---@diagnostic disable-line: param-type-mismatch
                    local color
                    if dCol then
                        if type(dCol[1]) == "number" then
                            color = util.color.rgb(dCol[1], dCol[2], dCol[3])
                        else
                            local colDt = dCol[i] or commonData.defaultColorData
                            color = util.color.rgb(colDt[1], colDt[2], colDt[3])
                        end
                    else
                        color = commonData.defaultColor
                    end
                    addDescrLine(str, color)
                end
            end

            if not added then return end

            if foundDescription then
                tooltipLayout.content[1].content:add{
                    template = I.MWUI.templates.interval,
                }
            end

            foundDescription = true

            tooltipLayout.content[1].content:add(line)
        end


        if forRecord then
            ---@type proximityTool.markerRecord
            local record = layout.userData.record
            if not record or record.invalid then return end

            drawDescription(record)
        else
            ---@type proximityTool.activeMarker
            local markerHandler = layout.userData.data
            if not markerHandler then return end

            ---@type proximityTool.activeMarkerData[]
            local records = tableLib.values(markerHandler.markers, function (a, b)
                return (a.record.priority or 0) > (b.record.priority or 0)
            end)

            for _, recDt in ipairs(records) do
                local record = recDt.record
                if record and not record.invalid then
                    drawDescription(record)
                end
            end
        end

        if foundDescription then
            tooltipHandler:create(tooltipLayout)
        end

        return
    end


    if not layout.userData or not layout.userData.tooltip then return end
    local tooltipHandler = layout.userData.tooltip
    if not tooltipHandler.element then return end

    local props = tooltipHandler.element.layout.props

    props.position, props.anchor = position, anchor

    tooltipHandler:update()
end


function this.tooltipDestroy(layout)
    if not layout.userData or not layout.userData.tooltip then return end
    local tooltipHandler = layout.userData.tooltip
    layout.userData.tooltip = nil
    if not tooltipHandler.valid then return end
    tooltipHandler:destroy()
end

return this