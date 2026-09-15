--
-- ProjectC_CharunJuice.lua
--
-- 차룬주스 (featureId: charun_juice) -- Project C 서버 전용 퐁듀 후원 기능.
--
-- 후원 1건마다 Lifestyle 모드의 화장실 욕구 수치(modData.bathroomNeed, 0~100)를
-- 샌드박스 PongDu.CharunJuice_Amount 만큼 올린다. 이후 무들 단계/통증/사고
-- (100 도달 시 분당 10% 확률로 실수)는 전부 Lifestyle 이 원래대로 처리한다.
--
-- 퐁듀 본체는 건드리지 않고 PongDuAddon.register() 로만 붙는다.
--   * 금액/대기시간: PongDu.Tier_charun_juice / PongDu.Delay_charun_juice
--     (media/sandbox-options.txt, 페이지 "퐁듀 - Project C")
--   * 큐박스/런처/테스트메뉴 표시명: IGUI_donation_charun_juice
--   * 큐박스 아이콘: media/textures/donation/charun_juice.png (퐁듀 PongDuAddon icon 지원 버전 필요)
--
-- Lifestyle 참고 (client/Hygiene/ToiletBladderNeed.lua, AdjustBladderNeed):
--   * 실제 수치는 modData.bathroomNeed. 무들 표시값 LSMoodles.BladderNeed.Value 는
--     매 게임 1분(EveryOneMinute)마다 bathroomNeed 로부터 다시 계산된다.
--   * 그 1분 사이 무들 반영이 늦는 걸 없애려고 Value 도 같은 구간표로 바로 넣는다.
--     (다음 틱 계산 결과와 동일한 값이라 충돌 없음)
--   * 갓모드면 Lifestyle 이 매 분 bathroomNeed 를 0으로 되돌린다 -> 테스트 시 주의.
--   * 샌드박스 Text.DividerHygiene 가 꺼져 있으면 Lifestyle 이 욕구 계산을 아예 안 한다.
--
-- 이 파일에는 한글 문자열 리터럴을 넣지 않는다 (표시 문구는 전부 번역 파일).
--

local LOG = "[ProjectC] "
local FEATURE_ID = "charun_juice"
local LIFESTYLE_MOD_ID = "Lifestyle"

-- bathroomNeed -> BladderNeed 무들 Value. Lifestyle AdjustBladderNeed 의 구간표와 동일.
local function bladderMoodleValue(need)
    if need >= 90 then return 0.8 end
    if need >= 80 then return 0.6 end
    if need >= 60 then return 0.4 end
    if need >= 30 then return 0.2 end
    return 0
end

local function applyCharunJuice(sender)
    local player = getPlayer()
    if not player then
        print(LOG .. "charun_juice skipped: local player is nil (sender=" .. tostring(sender) .. ")")
        return
    end
    if not getActivatedMods():contains(LIFESTYLE_MOD_ID) then
        print(LOG .. "charun_juice skipped: mod '" .. LIFESTYLE_MOD_ID .. "' is not active")
        return
    end
    if not SandboxVars.Text.DividerHygiene then
        print(LOG .. "charun_juice skipped: Lifestyle hygiene module is disabled (SandboxVars.Text.DividerHygiene=false)")
        return
    end
    if player:isGodMod() then
        print(LOG .. "charun_juice WARNING: player is in god mode - Lifestyle resets bathroomNeed to 0 every minute")
    end

    local data = player:getModData()
    -- Lifestyle 은 bathroomNeed 를 첫 분 틱에서야 만든다. 접속 직후 후원이면 아직 nil.
    local before = data.bathroomNeed
    if type(before) ~= "number" then
        print(LOG .. "charun_juice: bathroomNeed not initialised yet (" .. tostring(before) .. "), starting from 0")
        before = 0
    end

    local amount = SandboxVars.PongDu.CharunJuice_Amount
    local after = before + amount
    if after > 100 then after = 100 end
    data.bathroomNeed = after

    local moodles = data.LSMoodles
    local bladder = moodles and moodles["BladderNeed"]
    if bladder then
        bladder.Value = bladderMoodleValue(after)
    else
        print(LOG .. "charun_juice: LSMoodles.BladderNeed not initialised yet - moodle updates on the next Lifestyle minute tick")
    end

    HaloTextHelper.addTextWithArrow(player, getText("IGUI_donation_charun_juice_halo", tostring(amount)), true, 255, 200, 60)

    print(LOG .. "charun_juice applied: sender=" .. tostring(sender)
        .. " amount=" .. tostring(amount)
        .. " bathroomNeed " .. tostring(before) .. " -> " .. tostring(after)
        .. " moodleValue=" .. tostring(bladder and bladder.Value))
end

-- ── 퐁듀 등록 ────────────────────────────────────────────────────────────────
-- require 는 파일이 없으면 nil 을 돌려준다 (퐁듀 비활성 / PongDuAddon 이 없는 구버전).
local PongDuAddon = require("PongDuAddon")
if not PongDuAddon then
    print(LOG .. "charun_juice NOT registered: PongDuAddon not found (PongDu mod 't3chzzkDonation' inactive or outdated)")
else
    PongDuAddon.register(FEATURE_ID, {
        labelKey  = "IGUI_donation_charun_juice",
        immediate = true,               -- 본인 몸에만 적용 -> 안전지대에서도 즉시 발동
        color     = {0.80, 0.80, 0.10},
        category  = "personal",
        icon      = "media/textures/donation/charun_juice.png",  -- 큐박스 아이콘 (구버전 퐁듀는 무시)
        fn        = applyCharunJuice,
    })
end
