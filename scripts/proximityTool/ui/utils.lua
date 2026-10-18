local ui = require('openmw.ui')
local util = require('openmw.util')

local this = {}


function this.convertAlign(str, default)
    return ui.ALIGNMENT[str] or (default or ui.ALIGNMENT.End)
end


function this.removeFromContent(content, index)
    local ss, res = pcall(function ()
        local elem = content[index]
        if elem then
            content[elem.name or index] = nil
        end
    end)
    return ss and index or nil
end


function this.clearContent(content)
    for i = #content, 1, -1 do
        this.removeFromContent(content, i)
    end
end


function this.isExistsInContent(content, index)
    return this.getFromContent(content, index) ~= nil
end


function this.getTextHeight(text, fontSize, width, mul)
    if not mul then mul = 0.7 end
    if #text == 0 then return 0 end
    local words = {}
    local charWidth = fontSize * mul
    local rowMaxSize = math.floor(width / charWidth)
    local rowCount = 1
    for line in text:gmatch("[^\n]+") do
        local currentRowSize = 0
        for word in line:gmatch("%S+") do
            local wordSize = utf8.len(word) or string.len(word)
            if currentRowSize + wordSize <= rowMaxSize then
                currentRowSize = currentRowSize + wordSize + 1
            else
                rowCount = rowCount + 1
                currentRowSize = wordSize ---@diagnostic disable-line: cast-local-type
            end
            table.insert(words, word)
        end
        rowCount = rowCount + 1
    end
    rowCount = rowCount - 1
    return rowCount * fontSize, rowCount
end


function this.getUIScale()
	local width = ui.layers[1].size.x
	local screenSize = ui.screenSize()
	return screenSize.x / width
end


function this.getScaledScreenSize()
    return ui.layers[1].size
end


function this.getElementHeight(elem)
    if elem.userData and elem.userData.height then
        return math.floor(elem.userData.height)
    elseif elem.props and elem.props.size and elem.props.autoSize ~= true then
        return math.floor(elem.props.size.y)
    elseif elem.props and elem.props.textSize and elem.props.autoSize ~= false then
        return math.floor(elem.props.textSize + (elem.props.textShadow and 2 or 0))
    elseif elem.content then
        return this.getContentHeight(elem.content, elem.props and elem.props.horizontal or false)
    end

    return 0
end


---@return number
function this.getContentHeight(content, isHorizontal)
    local res = 0

    local function add(val)
        val = math.floor(val)
        if isHorizontal then
            res = math.max(res, val)
        else
            res = res + val
        end
    end

    for _, elem in ipairs(content) do
        add(this.getElementHeight(elem))
    end

    return res
end


return this