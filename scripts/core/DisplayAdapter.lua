local DisplayAdapter = {}

function DisplayAdapter.Refresh(graphicsRef, isMobile)
    local dpr = graphicsRef:GetDPR() or 1.0
    if dpr <= 0 then dpr = 1.0 end

    local physicalW = graphicsRef:GetWidth()
    local physicalH = graphicsRef:GetHeight()
    local logicalW = math.floor(physicalW / dpr + 0.5)
    local logicalH = math.floor(physicalH / dpr + 0.5)
    local adaptiveScale = math.max(0.75, math.min(1.25, math.min(logicalW / 800, logicalH / 600)))
    local targetFrameRate = (isMobile or dpr >= 2.0) and 60 or 90

    return {
        dpr = dpr,
        physicalW = physicalW,
        physicalH = physicalH,
        logicalW = logicalW,
        logicalH = logicalH,
        adaptiveScale = adaptiveScale,
        targetFrameRate = targetFrameRate,
        renderStepDt = 1.0 / targetFrameRate,
        maxFrameDt = 1.0 / 30.0,
    }
end

function DisplayAdapter.GetFrameDt(dt, state)
    if dt <= 0 then return state.renderStepDt end
    return math.min(dt, state.maxFrameDt)
end

function DisplayAdapter.UpdateMeasuredFps(state, rawDt)
    if rawDt <= 0 then return state.measuredFps or state.targetFrameRate end
    local instant = 1.0 / rawDt
    local current = state.measuredFps or instant
    state.measuredFps = current * 0.92 + instant * 0.08
    return state.measuredFps
end

function DisplayAdapter.GetAdaptiveIntervals(state)
    local fps = state.measuredFps or state.targetFrameRate or 60
    local intervals = state.intervals or {}
    if state.isMobile then
        if fps < 35 then
            intervals.minimap = 0.35
            intervals.weather = 0.55
            intervals.slowWorld = 0.40
            intervals.crops = 0.50
            intervals.proximity = 0.16
        elseif fps < 50 then
            intervals.minimap = 0.25
            intervals.weather = 0.42
            intervals.slowWorld = 0.32
            intervals.crops = 0.40
            intervals.proximity = 0.13
        else
            intervals.minimap = 0.18
            intervals.weather = 0.32
            intervals.slowWorld = 0.24
            intervals.crops = 0.32
            intervals.proximity = 0.10
        end
        return intervals
    end

    if fps < 35 then
        intervals.minimap = 0.20
        intervals.weather = 0.35
        intervals.slowWorld = 0.25
            intervals.crops = 0.30
            intervals.proximity = 0.14
    elseif fps < 50 then
        intervals.minimap = 0.14
        intervals.weather = 0.25
        intervals.slowWorld = 0.20
            intervals.crops = 0.22
            intervals.proximity = 0.12
    elseif fps > 75 then
        intervals.minimap = 0.08
        intervals.weather = 0.16
        intervals.slowWorld = 0.12
            intervals.crops = 0.16
            intervals.proximity = 0.08
    else
        intervals.minimap = 0.10
        intervals.weather = 0.20
        intervals.slowWorld = 0.15
            intervals.crops = 0.18
            intervals.proximity = 0.10
    end
    return intervals
end

return DisplayAdapter
