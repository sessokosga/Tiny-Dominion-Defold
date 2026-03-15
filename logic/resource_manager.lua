local data_proxy = require "logic.data_proxy"

local M = {}

local resources = {}
local subscribers = {} -- Array of message URLs to notify on changes
local save_file_path = ""

--- Initialize the Resource Manager
function M.init()
    save_file_path = sys.get_save_file("TinyDominion", "resources")
    resources = {}
    subscribers = {}
    M.load()
end

--- Register a listener (a script URL) to receive "sync_ui" messages
-- @param url (string|url) The URL of the script listening to UI updates
function M.subscribe(url)
    for _, sub in ipairs(subscribers) do
        if sub == url then return end -- Already subscribed
    end
    table.insert(subscribers, url)
end

--- Unregister a listener
-- @param url (string|url) The URL to remove
function M.unsubscribe(url)
    for i, sub in ipairs(subscribers) do
        if sub == url then
            table.remove(subscribers, i)
            break
        end
    end
end

--- Notify all subscribers of a change
-- @param res_id (string) The resource ID that changed
-- @param value (number) The new value
local function notify_ui(res_id, value)
    local message = { type = "resource", id = res_id, amount = value }
    for _, url in ipairs(subscribers) do
        msg.post(url, "sync_ui", message)
    end
end

--- Get the current amount of a resource
-- @param res_id (string) e.g., "wood", "stone", "gold"
-- @return (number)
function M.get(res_id)
    return resources[res_id] or 0
end

--- Check if the player has enough of a specific resource
-- @param res_id (string)
-- @param amount (number)
-- @return (boolean)
function M.has(res_id, amount)
    return M.get(res_id) >= amount
end

--- Check if the player has enough resources given a list of costs
-- @param costs (table) Array of { resourceId = string, amount = { value = number } } (from data_proxy)
-- @return (boolean)
function M.has_enough(costs)
    for _, cost in ipairs(costs) do
        local required_amount = cost.amount.value or cost.amount.min or 0
        if not M.has(cost.resourceId, required_amount) then
            return false
        end
    end
    return true
end

--- Add an amount of a resource
-- @param res_id (string)
-- @param amount (number)
function M.add(res_id, amount)
    local current = resources[res_id] or 0
    local new_value = current + amount
    
    -- Check max stack from data
    local res_data = data_proxy.get_entry("resources", res_id)
    local max_stack = (res_data and res_data.stack_max) or 999999
    
    if new_value > max_stack then
        new_value = max_stack
    end

    resources[res_id] = new_value
    notify_ui(res_id, new_value)
    M.save()
end

--- Remove an amount of a resource
-- @param res_id (string)
-- @param amount (number)
-- @return (boolean) True if successful, false if not enough
function M.remove(res_id, amount)
    if not M.has(res_id, amount) then
        return false
    end

    local current = resources[res_id] or 0
    local new_value = current - amount
    resources[res_id] = new_value
    notify_ui(res_id, new_value)
    M.save()
    return true
end

--- Consume a list of costs (e.g. for a building)
-- @param costs (table)
-- @return (boolean) True if successfully consumed all, false otherwise
function M.consume_costs(costs)
    if not M.has_enough(costs) then return false end
    
    for _, cost in ipairs(costs) do
        local amount = cost.amount.value or cost.amount.min or 0
        M.remove(cost.resourceId, amount)
    end
    return true
end

--- Open a resource pack booster
-- @param booster_id (string)
function M.open_resource_pack(booster_id)
    local booster = data_proxy.get_entry("boosters", booster_id)
    if booster and booster.effect and booster.effect.kind == "resourcePack" then
        for _, item in ipairs(booster.effect.contents or {}) do
            local amount = item.amount.value or item.amount.min or 0
            M.add(item.resourceId, amount)
        end
    end
end

--- Save the current resources to disk
function M.save()
    sys.save(save_file_path, resources)
end

--- Load the resources from disk
function M.load()
    local loaded_data = sys.load(save_file_path)
    if next(loaded_data) ~= nil then
        resources = loaded_data
    else
        resources = {}
    end
end

return M
