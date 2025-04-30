local this = {}

function this.count(table)
    local count = 0
    for _, _ in pairs(table) do
        count = count + 1
    end
    return count
end


--- @param t table
--- @param sort boolean|(fun(a: any, b: any):boolean)|nil
--- @return table values
function this.values(t, sort)
    local ret = {}
    for _, v in pairs(t) do
        table.insert(ret, v)
    end

    if sort then
        if sort == true then
            sort = nil
        end
        table.sort(ret, sort)
    end

    return ret
end


---@param t table
---@return table
function this.deepcopy(t)
	local copy = nil
	if type(t) == "table" then
		copy = {}
		for k, v in next, t, nil do
			copy[this.deepcopy(k)] = this.deepcopy(v)
		end
		setmetatable(copy, this.deepcopy(getmetatable(t)))
	else
		copy = t
	end
	return copy
end


---@param t table
function this.clear(t)
    for id, _ in pairs(t) do
        t[id] = nil
    end
end


---@param from table
---@param to table?
---@return table
function this.copy(from, to)
	if not to then to = {} end

	for n, v in pairs(from) do
		to[n] = v
	end

	return to
end


return this