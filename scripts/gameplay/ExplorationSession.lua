local ExplorationSession = {}

function ExplorationSession.New()
    return {
        active = false,
        kind = nil,
        exploreState = nil,
        exploreOverlay = nil,
        exploreCombatPanel = nil,
        exploreNodes = {},
        exploreFarmPos = nil,
        exploreEntities3D = {},
        mineState = nil,
        mineNodes = {},
        mineEntities = {},
        mineFarmPos = nil,
        mineHUD = nil,
        mineAttackCooldown = 0,
        mineMaxFloorReached = 1,
    }
end

function ExplorationSession.Sync(session, exploreRef, mineRef)
    if mineRef and mineRef.mineState then
        session.active = mineRef.exploreActive == true
        session.kind = session.active and "mine" or nil
        session.exploreState = mineRef.exploreState
        session.mineState = mineRef.mineState
        session.mineNodes = mineRef.mineNodes or {}
        session.mineEntities = mineRef.mineEntities or {}
        session.mineFarmPos = mineRef.mineFarmPos
        session.mineHUD = mineRef.mineHUD
        session.mineAttackCooldown = mineRef.mineAttackCooldown or 0
        session.mineMaxFloorReached = mineRef.mineMaxFloorReached or 1
        return session
    end

    exploreRef = exploreRef or {}
    session.active = exploreRef.exploreActive == true
    session.kind = session.active and "explore" or nil
    session.exploreState = exploreRef.exploreState_
    session.exploreOverlay = exploreRef.exploreOverlay_
    session.exploreCombatPanel = exploreRef.exploreCombatPanel_
    session.exploreNodes = exploreRef.exploreNodes_ or {}
    session.exploreFarmPos = exploreRef.exploreFarmPos_
    session.exploreEntities3D = exploreRef.exploreEntities3D_ or {}
    session.mineState = nil
    session.mineNodes = {}
    session.mineEntities = {}
    session.mineFarmPos = nil
    session.mineHUD = nil
    session.mineAttackCooldown = 0
    return session
end

function ExplorationSession.IsMine(session)
    return session and session.kind == "mine"
end

return ExplorationSession
