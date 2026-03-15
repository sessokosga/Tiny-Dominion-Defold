local data_proxy = require "logic.data_proxy"

local M = {}

local state = {
    gems = 0,
    boosters = {} -- Map of boosterId -> count
}

local subscribers = {}
local save_file_path = ""

--- Initialize the Player Manager
function M.init()
    save_file_path = sys.get_save_file("TinyDominion", "player")
    state = { gems = 0, boosters = {} }
    subscribers = {}
    M.load()
end

--- Register a listener (a script URL) to receive "sync_ui" messages
function M.subscribe(url)
    for _, sub in ipairs(subscribers) do
        if sub == url then return end
    end
    table.insert(subscribers, url)
end

--- Unregister a listener
function M.unsubscribe(url)
    for i, sub in ipairs(subscribers) do
        if sub == url then
            table.remove(subscribers, i)
            break
        end
    end
end

--- Notify all subscribers of a change
-- @param update_type (string) e.g., "gems" or "boosters"
local function notify_ui(update_type)
    local message = { type = "player", subtype = update_type }
    for _, url in ipairs(subscribers) do
        msg.post(url, "sync_ui", message)
    end
end

--- Get current gems
function M.get_gems()
    return state.gems
end

--- Add gems
function M.add_gems(amount)
    state.gems = state.gems + amount
    notify_ui("gems")
    M.save()
end

--- Check if player has enough gems
function M.has_enough_gems(amount)
    return state.gems >= amount
end

--- Spend gems
-- @return (boolean) True if successful
function M.spend_gems(amount)
    if state.gems >= amount then
        state.gems = state.gems - amount
        notify_ui("gems")
        M.save()
        return true
    end
    return false
end

--- Get the count of a specific booster
function M.get_booster_count(booster_id)
    return state.boosters[booster_id] or 0
end

--- Add a booster to the inventory
-- @return (boolean) True if successfully added, false if full or invalid
function M.add_booster(booster_id, amount)
    amount = amount or 1
    local booster_data = data_proxy.get_entry("boosters", booster_id)
    if not booster_data then return false end

    local current = M.get_booster_count(booster_id)
    local max = booster_data.stack_max or 99

    if current >= max then return false end

    local new_amount = math.min(current + amount, max)
    state.boosters[booster_id] = new_amount
    
    notify_ui("boosters")
    M.save()
    return true
end

--- Consume a booster from the inventory
-- @return (boolean) True if successfully consumed
function M.consume_booster(booster_id)
    local current = M.get_booster_count(booster_id)
    if current > 0 then
        state.boosters[booster_id] = current - 1
        notify_ui("boosters")
        M.save()
        return true
    end
    return false
end

--- Get a list of all owned boosters
-- @return (table) Array of {id = string, count = number}
function M.get_owned_boosters()
    local result = {}
    for id, count in pairs(state.boosters) do
        if count > 0 then
            table.insert(result, { id = id, count = count })
        end
    end
    return result
end

--- Save player state to disk
function M.save()
    sys.save(save_file_path, state)
end

--- Load player state from disk
function M.load()
    local loaded_data = sys.load(save_file_path)
    if next(loaded_data) ~= nil then
        state = loaded_data
        -- Ensure sub-tables exist if they were empty on save
        state.boosters = state.boosters or {}
    else
        state = { gems = 0, boosters = {} }
    end
end

return M
