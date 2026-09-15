--
-- ExplosionPvpGate.lua  (v2)
--
-- 폭발 / 화염 계열 무기가 플레이어에게 주는 피해를 안전장치(G키) 상태로 통제한다.
--   안전장치 ON  (= PVP 모드 off) -> 폭발 데미지, 화염 데미지, 화상 전부 무효
--   안전장치 OFF (= PVP 모드 on)  -> 바닐라대로 전부 들어감
-- 좀비 피해 / 지형 파괴 / 불 확산 자체는 그대로 유지된다.
--
-- 커버하는 데미지 경로 (B41 41.78.20 기준):
--   1) 폭발 직격  : IsoGridSquare.explosion() -> Hit()      -> setAvoidDamage 로 무효화
--   2) 화염 지속  : FireCheck() / ReduceHealthWhenBurning()  -> OnPlayerGetDamage "FIRE" 환급
--   3) 착화 상태  : SetOnFire()                              -> StopBurning() 으로 즉시 소화
--   4) 화상 누적  : BodyPart.setBurned()                     -> burnTime 이전값 복원
--
-- 커버하지 못하는 것:
--   모드가 자체 Lua 로 character:Hit(...) 을 직접 호출하는 경우 (모드별 대응 필요)
--

local PROTECT_FROM_FIRE = true   -- false 로 두면 폭발 직격만 막고 화염/화상은 바닐라대로 둔다
local SHIELD_IN_SP      = true   -- 싱글플레이(안전장치 시스템 없음)에서도 보호할지
local BP_COUNT          = 15     -- 엔진이 BodyPartType.FromIndex(Rand.Next(15)) 로 태움

local PENDING   = {}   -- 폭발 1틱 방어 큐
local BURN_PREV = {}   -- [playerNum] = 직전 틱 burnTime 스냅샷

-- =========================================================================
-- 공통
-- =========================================================================

local function isProtected(pl)
    if pl == nil or pl:isDead() then return false end
    if not isClient() then return SHIELD_IN_SP end
    local safety = pl:getSafety()
    if safety == nil then return true end
    return safety:isEnabled()   -- enabled == true 는 "안전장치 켜짐" = PVP off
end

local function snapshotBurn(pl, out)
    local bd = pl:getBodyDamage()
    for b = 0, BP_COUNT - 1 do
        out[b] = bd:getBodyPart(BodyPartType.FromIndex(b)):getBurnTime()
    end
end

-- 증가분만 되돌린다. 자연 회복으로 줄어든 값은 그대로 둔다.
local function revertBurnIncrease(pl, prev)
    local bd = pl:getBodyDamage()
    for b = 0, BP_COUNT - 1 do
        local part = bd:getBodyPart(BodyPartType.FromIndex(b))
        local old  = prev[b]
        if old ~= nil and part:getBurnTime() > old then
            part:setBurnTime(old)
            if old <= 0 then
                part:setNeedBurnWash(false)
            end
        end
    end
end

-- =========================================================================
-- 1) 폭발 직격 방어
--    IsoTrap.triggerExplosion() 이 drawCircleExplosion() 호출 직전에 이 이벤트를 쏜다.
--    setAvoidDamage(true) 는 Hit() 안의 1회성 무효화 분기에 걸려 0 데미지로 리턴된다.
-- =========================================================================

local function alreadyQueued(pl)
    for i = 1, #PENDING do
        if PENDING[i].player == pl then return true end
    end
    return false
end

local function shield(pl)
    if alreadyQueued(pl) then return end
    pl:setAvoidDamage(true)
    local burns = {}
    snapshotBurn(pl, burns)
    table.insert(PENDING, { player = pl, burns = burns })
end

local function inBlast(pl, square, r)
    if pl:getZ() ~= square:getZ() then return false end
    local dx = pl:getX() - (square:getX() + 0.5)
    local dy = pl:getY() - (square:getY() + 0.5)
    return (dx * dx + dy * dy) <= (r + 1) * (r + 1)
end

local function tryShield(pl, square, r)
    if pl == nil or pl:isDead() then return end
    if not inBlast(pl, square, r) then return end
    if not isProtected(pl) then
        print("[ExpPvpGate] pvp mode on, blast damage allowed: " .. tostring(pl:getUsername()))
        return
    end
    shield(pl)
    print("[ExpPvpGate] shielded from blast: " .. tostring(pl:getUsername()) .. " range=" .. tostring(r))
end

local function OnThrowableExplode(trap, square)
    if trap == nil or square == nil then return end
    local r = trap:getExplosionRange()
    if r == nil or r <= 0 then return end
    if r > 15 then r = 15 end

    for i = 0, getNumActivePlayers() - 1 do
        tryShield(getSpecificPlayer(i), square, r)
    end

    if isClient() then
        local online = getOnlinePlayers()
        if online ~= nil then
            for i = 0, online:size() - 1 do
                tryShield(online:get(i), square, r)
            end
        end
    end
end

local function OnTick()
    if #PENDING == 0 then return end
    for i = 1, #PENDING do
        local e = PENDING[i]
        if e.player ~= nil then
            revertBurnIncrease(e.player, e.burns)
            e.player:setAvoidDamage(false)
        end
    end
    PENDING = {}
end

-- =========================================================================
-- 2~4) 화염 / 착화 / 화상 방어
-- =========================================================================

-- FIRE 데미지는 BodyDamage.ReduceGeneralHealth(amount) 직후에 이벤트가 발화한다.
-- ReduceGeneralHealth 는 amount/15 를 부위별 계수로 나눠 깎으므로 같은 식으로 되돌린다.
local function OnPlayerGetDamage(pl, dmgType, amount)
    if not PROTECT_FROM_FIRE then return end
    if dmgType ~= "FIRE" then return end
    if amount == nil or amount <= 0 then return end
    if not isProtected(pl) then return end

    local bd  = pl:getBodyDamage()
    local per = amount / BP_COUNT
    for b = 0, BP_COUNT - 1 do
        bd:getBodyPart(BodyPartType.FromIndex(b)):AddHealth(per / BodyPartType.getDamageModifyer(b))
    end
end

local function OnPlayerUpdate(pl)
    if not PROTECT_FROM_FIRE then return end
    if pl == nil then return end

    local n = pl:getPlayerNum()
    if not isProtected(pl) then
        BURN_PREV[n] = nil
        return
    end

    if pl:isOnFire() then
        pl:StopBurning()
        pl:getBodyDamage():OnFire(false)
        print("[ExpPvpGate] extinguished player " .. tostring(pl:getUsername()))
    end

    local prev = BURN_PREV[n]
    if prev ~= nil then
        revertBurnIncrease(pl, prev)
    else
        prev = {}
        BURN_PREV[n] = prev
    end
    snapshotBurn(pl, prev)
end

-- =========================================================================

Events.OnThrowableExplode.Add(OnThrowableExplode)
Events.OnTick.Add(OnTick)
Events.OnPlayerGetDamage.Add(OnPlayerGetDamage)
Events.OnPlayerUpdate.Add(OnPlayerUpdate)
