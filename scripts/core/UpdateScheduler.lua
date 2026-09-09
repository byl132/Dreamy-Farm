local UpdateScheduler = {}
UpdateScheduler.__index = UpdateScheduler

function UpdateScheduler.Create()
    return setmetatable({ timers = {} }, UpdateScheduler)
end

function UpdateScheduler:Every(key, interval, dt)
    local elapsed = (self.timers[key] or 0) + dt
    if elapsed >= interval then
        self.timers[key] = elapsed - interval
        return true, elapsed
    end
    self.timers[key] = elapsed
    return false, elapsed
end

function UpdateScheduler:Reset(key)
    self.timers[key] = 0
end

return UpdateScheduler
