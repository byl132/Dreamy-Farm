local MineGenerator = {}

MineGenerator.CONFIG = {
    mapSize = 10,
    maxFloors = 5,   -- F1(C3裁定): 矿洞 5 层（原 40 层为早期残留，与 GDD §3 #8/§8.1 冲突）
    elevatorEvery = 5,
    cellSize = 3.0,
    ores = {
        { name = "铜矿", color = {180, 100, 40}, hp = 2, floors = {1, 2}, value = 5 },    -- F1: 5层重排（数值待确认）
        { name = "铁矿", color = {100, 100, 110}, hp = 3, floors = {2, 3}, value = 12 },
        { name = "金矿", color = {220, 180, 40}, hp = 4, floors = {3, 4}, value = 25 },
        { name = "虹晶矿", color = {160, 80, 200}, hp = 5, floors = {4, 5}, value = 50 },
    },
    monsters = {
        { name = "石蝙蝠", asset = "stone_bat", hp = 15, atk = 4, speed = 2.0, floors = {1, 5}, gold = 5, icon = "🦇" },   -- F1: 普通怪分散在 1-5 层（数值待确认）
        { name = "矿洞蜘蛛", asset = "mine_spider", hp = 22, atk = 6, speed = 1.5, floors = {1, 5}, gold = 8, icon = "🕷️" },
        { name = "暗影精灵", asset = "shadow_sprite", hp = 35, atk = 9, speed = 2.5, floors = {1, 5}, gold = 15, icon = "👻" },
        { name = "岩石蠕虫", asset = "rock_worm", hp = 45, atk = 8, speed = 1.0, floors = {1, 5}, gold = 20, icon = "🪱" },
        { name = "骷髅战士", asset = "skeleton_warrior", hp = 60, atk = 12, speed = 1.8, floors = {5, 5}, gold = 30, icon = "💀", isBoss = true },  -- F1: 第5层 boss 级
        { name = "矿石巨人", asset = "ore_giant", hp = 100, atk = 16, speed = 0.8, floors = {5, 5}, gold = 60, icon = "🪨", isBoss = true },  -- F1: 第5层 boss 级（春之种/守护怪由 c3_11/c4_03 任务驱动，不在生成表）
    },
}

local function pickCandidate(defs, floor)
    local candidates = {}
    for i, def in ipairs(defs) do
        if floor >= def.floors[1] and floor <= def.floors[2] then
            candidates[#candidates + 1] = i
        end
    end
    if #candidates == 0 then return 1 end
    return candidates[math.random(1, #candidates)]
end

function MineGenerator.Generate(floor, config)
    config = config or MineGenerator.CONFIG
    local size = config.mapSize
    local grid = {}
    for x = 1, size do
        grid[x] = {}
        for y = 1, size do
            grid[x][y] = "wall"
        end
    end

    local rooms = {}
    local numRooms = math.min(3 + math.floor(floor / 8), 6)
    for _ = 1, numRooms do
        local rw = math.random(3, 5)
        local rh = math.random(3, 5)
        local rx = math.random(2, size - rw)
        local ry = math.random(2, size - rh)
        for x = rx, rx + rw - 1 do
            for y = ry, ry + rh - 1 do
                if x >= 1 and x <= size and y >= 1 and y <= size then
                    grid[x][y] = "floor"
                end
            end
        end
        rooms[#rooms + 1] = {cx = rx + math.floor(rw / 2), cy = ry + math.floor(rh / 2)}
    end

    for i = 1, #rooms - 1 do
        local a = rooms[i]
        local b = rooms[i + 1]
        local cx, cy = a.cx, a.cy
        while cx ~= b.cx do
            if cx >= 1 and cx <= size and cy >= 1 and cy <= size then
                grid[cx][cy] = "floor"
                if cy > 1 then grid[cx][cy - 1] = "floor" end
            end
            cx = cx + (b.cx > cx and 1 or -1)
        end
        while cy ~= b.cy do
            if cx >= 1 and cx <= size and cy >= 1 and cy <= size then
                grid[cx][cy] = "floor"
                if cx > 1 then grid[cx - 1][cy] = "floor" end
            end
            cy = cy + (b.cy > cy and 1 or -1)
        end
    end

    grid[1][1] = "floor"
    grid[2][1] = "floor"
    grid[1][2] = "floor"
    grid[2][2] = "floor"
    grid[3][1] = "floor"
    grid[1][3] = "floor"

    if #rooms > 0 then
        local target = rooms[1]
        local cx, cy = 1, 1
        while cx ~= target.cx do
            if cx >= 1 and cx <= size and cy >= 1 and cy <= size then
                grid[cx][cy] = "floor"
                if cy < size then grid[cx][cy + 1] = "floor" end
            end
            cx = cx + (target.cx > cx and 1 or -1)
        end
        while cy ~= target.cy do
            if cx >= 1 and cx <= size and cy >= 1 and cy <= size then
                grid[cx][cy] = "floor"
                if cx > 1 then grid[cx - 1][cy] = "floor" end
            end
            cy = cy + (target.cy > cy and 1 or -1)
        end
    end

    local rocks = {}
    local rockCount = math.min(4 + math.floor(floor / 3), 12)
    for _ = 1, rockCount * 3 do
        if #rocks >= rockCount then break end
        local rx, ry = math.random(1, size), math.random(1, size)
        if grid[rx][ry] == "wall" then
            local adjFloor = false
            if rx > 1 and grid[rx - 1][ry] == "floor" then adjFloor = true end
            if rx < size and grid[rx + 1][ry] == "floor" then adjFloor = true end
            if ry > 1 and grid[rx][ry - 1] == "floor" then adjFloor = true end
            if ry < size and grid[rx][ry + 1] == "floor" then adjFloor = true end
            if adjFloor then
                grid[rx][ry] = "rock"
                local oreType = pickCandidate(config.ores, floor)
                rocks[#rocks + 1] = {x = rx, y = ry, oreType = oreType, hp = config.ores[oreType].hp}
            end
        end
    end

    local monsters = {}
    local monsterCount = math.min(2 + math.floor(floor / 5), 6)
    local floorCells = {}
    for x = 1, size do
        for y = 1, size do
            if grid[x][y] == "floor" and not (x <= 2 and y <= 2) then
                floorCells[#floorCells + 1] = {x = x, y = y}
            end
        end
    end
    for i = #floorCells, 2, -1 do
        local j = math.random(1, i)
        floorCells[i], floorCells[j] = floorCells[j], floorCells[i]
    end
    for i = 1, math.min(monsterCount, #floorCells) do
        local cell = floorCells[i]
        local mType = pickCandidate(config.monsters, floor)
        local mDef = config.monsters[mType]
        local hpScale = 1 + (floor - mDef.floors[1]) * 0.05
        monsters[#monsters + 1] = {
            x = cell.x, y = cell.y,
            name = mDef.name, asset = mDef.asset, icon = mDef.icon,
            hp = math.floor(mDef.hp * hpScale),
            maxHP = math.floor(mDef.hp * hpScale),
            atk = mDef.atk + math.floor(floor * 0.3),
            speed = mDef.speed,
            gold = mDef.gold + math.floor(floor * 0.5),
            alive = true,
            isBoss = mDef.isBoss,
        }
    end

    local ladderPos = nil
    for i = #floorCells, math.max(1, #floorCells - 5), -1 do
        local c = floorCells[i]
        if c and (c.x + c.y) > 6 then
            ladderPos = {x = c.x, y = c.y}
            break
        end
    end
    if not ladderPos then
        ladderPos = {x = size, y = size}
        grid[size][size] = "floor"
    end

    local walls = {}
    for x = 1, size do
        for y = 1, size do
            if grid[x][y] == "wall" then
                walls[#walls + 1] = {x, y}
            end
        end
    end

    return {
        size = size,
        grid = grid,
        walls = walls,
        rocks = rocks,
        monsters = monsters,
        ladderPos = ladderPos,
        ladderRevealed = false,
        floor = floor,
    }
end

return MineGenerator
