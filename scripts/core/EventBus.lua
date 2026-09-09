local EventBus = {}

local eventHandlers = {}

function EventBus.Subscribe(eventName, callback)
    if not eventHandlers[eventName] then
        eventHandlers[eventName] = {}
    end
    table.insert(eventHandlers[eventName], callback)
    print("[EventBus] Subscribed to event: " .. eventName)
end

function EventBus.Unsubscribe(eventName, callback)
    if not eventHandlers[eventName] then return end
    for i, handler in ipairs(eventHandlers[eventName]) do
        if handler == callback then
            table.remove(eventHandlers[eventName], i)
            print("[EventBus] Unsubscribed from event: " .. eventName)
            return
        end
    end
end

function EventBus.Emit(eventName, ...)
    if not eventHandlers[eventName] then return end
    for _, handler in ipairs(eventHandlers[eventName]) do
        local success, err = pcall(handler, ...)
        if not success then
            print("[EventBus] ERROR: Event handler failed for '" .. eventName .. "': " .. err)
        end
    end
    print("[EventBus] Emitted event: " .. eventName)
end

function EventBus.Clear(eventName)
    if eventName then
        eventHandlers[eventName] = nil
    else
        eventHandlers = {}
    end
end

function EventBus.GetSubscriberCount(eventName)
    return eventHandlers[eventName] and #eventHandlers[eventName] or 0
end

return EventBus