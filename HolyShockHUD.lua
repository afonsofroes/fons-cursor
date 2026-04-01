-- HolyShockHUD
-- /holyhud        -> toggle HUD
-- /holyhud config -> open settings panel

-- ── Defaults ─────────────────────────────────────────────────────────────
local DEFAULTS = {
    ringRadius  = 30,
    ringThick   = 5,
    numSegments = 48,
    gapDegrees  = 80,
    ringR = 0.09, ringG = 0.37, ringB = 0.65,
    dotR  = 0.09, dotG  = 0.37, dotB  = 0.65,
    offsetX  = 0,
    offsetY  = 0,
    dot1X = -38, dot1Y = -26,
    dot2X = -26, dot2Y = -38,
    fontSize = 20,
    fontPath = "Fonts\\FRIZQT__.TTF",
}

local function DeepCopy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

local cfg = DeepCopy(DEFAULTS)

-- ── LSM font helpers (defined early so BuildRing can call them) ───────────
local FALLBACK_FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF"  },
    { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF"    },
    { name = "Skurri",        path = "Fonts\\skurri.TTF"    },
    { name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF"  },
    { name = "Damage",        path = "Fonts\\DAMAGE.TTF"    },
}

local function GetFontList()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local list = {}
        for name, path in pairs(LSM:HashTable("font")) do
            list[#list + 1] = { name = name, path = path }
        end
        table.sort(list, function(a, b) return a.name < b.name end)
        return list, true
    end
    return FALLBACK_FONTS, false
end

local function ResolveFontPath(nameOrPath)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local path = LSM:Fetch("font", nameOrPath)
        if path then return path end
    end
    return nameOrPath
end

-- ── Profile helpers ───────────────────────────────────────────────────────
HolyShockHUD_Config = HolyShockHUD_Config or {}

local function LoadProfile(name)
    local data = (HolyShockHUD_Config.profiles or {})[name] or {}
    for k, v in pairs(DEFAULTS) do
        cfg[k] = (data[k] ~= nil) and data[k] or v
    end
    HolyShockHUD_Config.activeProfile = name
end

local function SaveProfile(name)
    HolyShockHUD_Config.profiles = HolyShockHUD_Config.profiles or {}
    HolyShockHUD_Config.profiles[name] = DeepCopy(cfg)
    HolyShockHUD_Config.activeProfile  = name
end

local function DeleteProfile(name)
    if name == "Default" then return false, "Cannot delete the Default profile." end
    HolyShockHUD_Config.profiles[name] = nil
    LoadProfile("Default")
    return true
end

local function GetProfileNames()
    local names = {}
    for k in pairs(HolyShockHUD_Config.profiles or {}) do names[#names + 1] = k end
    table.sort(names)
    return names
end

local function ActiveProfileName()
    return HolyShockHUD_Config.activeProfile or "Default"
end

-- ── Constants ─────────────────────────────────────────────────────────────
local HOLY_SHOCK_ID = 20473
local DT_ID         = 375576
local IOL_MAX_DUR   = 15
local PI            = math.pi
local TAU           = PI * 2
local function rad(d) return d * PI / 180 end

-- ── Root frame ────────────────────────────────────────────────────────────
local root = CreateFrame("Frame", "HolyShockHUD", UIParent)
root:SetSize(1, 1)
root:SetFrameStrata("TOOLTIP")
root:SetPoint("CENTER", UIParent, "CENTER")

local ringFrame = CreateFrame("Frame", nil, root)
ringFrame:SetPoint("CENTER", root, "CENTER", 0, 0)

-- We keep a single pool table of all child objects so BuildRing can destroy
-- them properly each time without leaking invisible textures/frames.
local ringPool = {}   -- { type="frame"|"texture", obj=... }

local chargeText = nil
local dots       = {}
local segments   = {}

-- ── Build / rebuild the ring ──────────────────────────────────────────────
local function BuildRing()
    -- Destroy previous objects
    for _, entry in ipairs(ringPool) do
        if entry.type == "frame" then
            entry.obj:Hide()
            entry.obj:SetParent(nil)
        else
            entry.obj:Hide()
        end
    end
    ringPool   = {}
    segments   = {}
    dots       = {}
    chargeText = nil

    local r   = cfg.ringRadius
    local tk  = cfg.ringThick
    local n   = cfg.numSegments
    local gap = cfg.gapDegrees

    local SIZE = (r + tk) * 2 + 4
    ringFrame:SetSize(SIZE, SIZE)

    local STEP     = TAU / n
    local SEG_W    = tk
    local SEG_H    = 2 * r * math.sin(STEP / 2) + 1
    local gapStart = rad(180 - gap / 2)
    local gapEnd   = rad(180 + gap / 2)

    local function inGap(angle)
        angle = angle % TAU
        local gs = gapStart % TAU
        local ge = gapEnd   % TAU
        if gs <= ge then return angle >= gs and angle <= ge
        else return angle >= gs or angle <= ge end
    end

    local cx, cy = SIZE / 2, SIZE / 2

    for i = 0, n - 1 do
        local angle = i * STEP
        local f = CreateFrame("Frame", nil, ringFrame)
        f:SetSize(SEG_W, SEG_H)
        f:SetPoint("CENTER", ringFrame, "BOTTOMLEFT",
            cx + r * math.cos(angle), cy + r * math.sin(angle))
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(f)
        tex:SetTexture("Interface\\Buttons\\WHITE8x8")
        tex:SetRotation(angle + PI / 2)
        segments[i] = { frame = f, tex = tex, angle = angle,
                         inGap = inGap(angle), gapEnd = gapEnd }
        ringPool[#ringPool + 1] = { type = "frame", obj = f }
    end

    -- Charge text
    chargeText = ringFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    chargeText:SetPoint("CENTER", ringFrame, "CENTER", -(r - 2), 0)
    chargeText:SetFont(ResolveFontPath(cfg.fontPath), cfg.fontSize, "OUTLINE")
    chargeText:SetTextColor(cfg.ringR, cfg.ringG, cfg.ringB, 1)
    ringPool[#ringPool + 1] = { type = "texture", obj = chargeText }

    -- Dots
    local dotSize = math.max(6, tk + 2)
    local dotOffsets = {
        { x = cfg.dot1X, y = cfg.dot1Y },
        { x = cfg.dot2X, y = cfg.dot2Y },
    }
    for i = 1, 2 do
        local df = CreateFrame("Frame", nil, ringFrame)
        df:SetSize(dotSize, dotSize)
        df:SetPoint("CENTER", ringFrame, "CENTER", dotOffsets[i].x, dotOffsets[i].y)
        local dtex = df:CreateTexture(nil, "ARTWORK")
        dtex:SetAllPoints(df)
        dtex:SetColorTexture(cfg.dotR, cfg.dotG, cfg.dotB, 0.35)
        dtex:SetMask("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        dots[i] = { frame = df, tex = dtex }
        ringPool[#ringPool + 1] = { type = "frame", obj = df }
    end
end

-- ── Ring progress ─────────────────────────────────────────────────────────
local function SetRingProgress(progress)
    local availableArc = TAU - rad(cfg.gapDegrees)
    local filledArc    = availableArc * progress
    for _, seg in pairs(segments) do
        if seg.inGap then
            seg.tex:SetVertexColor(0, 0, 0, 0)
        else
            local a = (seg.angle - seg.gapEnd) % TAU
            if a <= filledArc then
                seg.tex:SetVertexColor(cfg.ringR, cfg.ringG, cfg.ringB, 1)
            else
                seg.tex:SetVertexColor(0.5, 0.5, 0.5, 0.2)
            end
        end
    end
end

-- ── IoL tracking ─────────────────────────────────────────────────────────
local IOL_WINDOW      = 1
local lastHSCastTime  = 0
local iolEligible     = false
local HOLY_SHOCK_ID = 20473
local DIVINE_TOLL_ID = 375576

local VALID_TRIGGERS = {
    [HOLY_SHOCK_ID] = true,
    [DIVINE_TOLL_ID] = true,
}

-- 1. Create a frame to listen for the cast event
local eventHandler = CreateFrame("Frame")
eventHandler:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

eventHandler:SetScript("OnEvent", function(_, event, unit, castID, spellID)
    -- If the spell cast is in our trigger list, start the window
    if VALID_TRIGGERS[spellID] then
        lastHSCastTime = GetTime()
        iolEligible = true
    end
end)

local function GetIoLStacks()
    -- If we haven't cast Holy Shock recently, ignore ALL auras
    if not iolEligible then return 0 end

    local stacks = 0
    local auras = C_UnitAuras.GetUnitAuras("player", "PLAYER|HELPFUL")
    if auras then
        for _, aura in ipairs(auras) do
            local dur = aura.duration
            -- TIGHTEN THE FILTER:
            -- Divine Purpose is 12s. IoL is 15s.
            -- We only count it if the duration is exactly 15s.
            if dur and math.abs(dur - 15) < 0.1 then
                stacks = stacks + (aura.applications or 1)
            end
        end
    end
    return math.min(stacks, 2)
end

-- We keep this for the "Expiration" check
local function UpdateIoLEligibility()
    -- If we aren't even looking for a proc, do nothing
    if not iolEligible then return end

    local now = GetTime()
    local timeSinceCast = now - lastHSCastTime

    -- 1. If we are within the 1.5s window, stay eligible (waiting for the server to give us the buff)
    if timeSinceCast <= IOL_WINDOW then
        return
    end

    -- 2. If we are PAST the 1.5s window, check if the buff is active.
    -- If the buff is gone (consumed or expired), we stop being eligible.
    if GetIoLStacks() == 0 then
        iolEligible = false
    end
end

-- ── HUD update ────────────────────────────────────────────────────────────
local cdStart    = 0
local cdDuration = 0
local onCooldown = false

local function UpdateHUD()
    if not chargeText then return end

    local chargeInfo = C_Spell.GetSpellCharges(HOLY_SHOCK_ID)
    if chargeInfo then
        local charges        = chargeInfo.currentCharges
        local maxCharges     = chargeInfo.maxCharges
        local chargeStart    = chargeInfo.cooldownStartTime
        local chargeDuration = chargeInfo.cooldownDuration

        -- REMOVED: CheckHolyShockCast(charges) -> This is now handled by the event listener!

        chargeText:SetText(tostring(charges))

        if charges < maxCharges and chargeDuration and chargeDuration > 0 then
            cdStart = chargeStart; cdDuration = chargeDuration; onCooldown = true
            chargeText:SetTextColor(0.5, 0.5, 0.5, 1)
        else
            onCooldown = false
            chargeText:SetTextColor(cfg.ringR, cfg.ringG, cfg.ringB, 1)
            SetRingProgress(1)
        end
    else
        chargeText:SetText("-"); onCooldown = false; SetRingProgress(1)
    end

    -- ── Dots Logic (Updated for full transparency) ──
    local stacks = GetIoLStacks()
    for i = 1, 2 do
        if dots[i] then
            if i <= stacks then
                dots[i].tex:SetColorTexture(cfg.dotR, cfg.dotG, cfg.dotB, 1)
            else
                -- Full transparency as requested
                dots[i].tex:SetColorTexture(0, 0, 0, 0)
            end
        end
    end
end

root:SetScript("OnUpdate", function()
    -- Handle cursor positioning
    local x, y = GetCursorPosition()
    local s    = UIParent:GetEffectiveScale()
    root:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s + cfg.offsetX, y / s + cfg.offsetY)

    -- Check if the 1.5s window for IoL has expired
    UpdateIoLEligibility()

    -- Smooth Cooldown Ring animation
    if onCooldown then
        local progress = math.min((GetTime() - cdStart) / cdDuration, 1)
        SetRingProgress(progress)
        if progress >= 1 then onCooldown = false end
    end

    -- Update the text and dots
    UpdateHUD()
end)

-- ══════════════════════════════════════════════════════════════════════════
-- CONFIG PANEL
-- Layout (Y offsets from top of frame interior, step down as we add rows):
--   -30  Active profile label
--   -50  Profile dropdown
--   -90  New profile name / Save / Delete
--   -120 Divider
--   -135 Ring radius slider
--   -170 Ring thickness slider
--   -205 Gap size slider
--   -240 Segments slider
--   -280 Ring colour swatches
--   -305 Dot colour swatches
--   -330 Charge font label
--   -348 Font scrollbox  (120px tall → bottom at -468)
--   -478 Font size slider
--   -515 bottom buttons
-- ══════════════════════════════════════════════════════════════════════════

local cf = CreateFrame("Frame", "HolyShockHUDConfig", UIParent, "BasicFrameTemplateWithInset")
cf:SetSize(320, 700)
cf:SetPoint("CENTER")
cf:SetMovable(true)
cf:EnableMouse(true)
cf:RegisterForDrag("LeftButton")
cf:SetScript("OnDragStart", cf.StartMoving)
cf:SetScript("OnDragStop",  cf.StopMovingOrSizing)
cf:Hide()
cf:SetFrameStrata("DIALOG")
cf.TitleText:SetText("HolyShockHUD Settings")
local configFrame = cf

local function MakeLabel(parent, text, x, y)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    f:SetText(text)
    f:SetTextColor(0.7, 0.7, 0.7, 1)
    return f
end

-- ── Sliders ───────────────────────────────────────────────────────────────
local sliderRefs = {}

local function MakeSlider(parent, label, minVal, maxVal, step, cfgKey, x, y, w)
    MakeLabel(parent, label, x, y)
    local sl = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 16)
    sl:SetWidth(w or 210)
    sl:SetMinMaxValues(minVal, maxVal)
    sl:SetValueStep(step)
    sl:SetValue(cfg[cfgKey])
    sl.Low:SetText(tostring(minVal))
    sl.High:SetText(tostring(maxVal))
    sl.Text:SetText("")
    local vt = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    vt:SetPoint("LEFT", sl, "RIGHT", 6, 0)
    vt:SetText(tostring(cfg[cfgKey]))
    sl.valText = vt
    sl.cfgKey  = cfgKey
    sl:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val / step + 0.5) * step
        cfg[cfgKey] = val
        vt:SetText(tostring(val))
        SaveProfile(ActiveProfileName())
        BuildRing(); UpdateHUD()
    end)
    sliderRefs[cfgKey] = sl
    return sl
end

-- ── Swatches ──────────────────────────────────────────────────────────────
local COLOURS = {
    { r=0.09,g=0.37,b=0.65 }, { r=0.11,g=0.62,b=0.46 },
    { r=0.50,g=0.47,b=0.87 }, { r=0.85,g=0.35,b=0.19 },
    { r=0.83,g=0.33,b=0.49 }, { r=0.94,g=0.62,b=0.15 },
    { r=0.39,g=0.60,b=0.13 }, { r=0.89,g=0.29,b=0.29 },
    { r=0.90,g=0.90,b=0.90 },
}

local function MakeSwatches(parent, label, rKey, gKey, bKey, x, y)
    MakeLabel(parent, label, x, y)
    local sw = {}
    for i, col in ipairs(COLOURS) do
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(18, 18)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i-1)*22, y - 16)
        local tex = btn:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints(btn); tex:SetColorTexture(col.r, col.g, col.b, 1)
        local brd = btn:CreateTexture(nil, "OVERLAY")
        brd:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -1,  1)
        brd:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  1, -1)
        brd:SetColorTexture(1, 1, 1, 0)
        btn.border = brd; sw[i] = btn
        btn:SetScript("OnClick", function()
            cfg[rKey]=col.r; cfg[gKey]=col.g; cfg[bKey]=col.b
            SaveProfile(ActiveProfileName())
            for j,s in ipairs(sw) do s.border:SetColorTexture(1,1,1,j==i and 1 or 0) end
            BuildRing(); UpdateHUD()
        end)
    end
    return sw
end

-- ── Profile UI ────────────────────────────────────────────────────────────
local activeNameLabel = cf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
activeNameLabel:SetPoint("TOPLEFT", cf, "TOPLEFT", 20, -30)
activeNameLabel:SetText("Active: Default")

MakeLabel(cf, "Profile", 20, -50)
local profileDropdown = CreateFrame("Frame", "HolyShockHUDDropdown", cf, "UIDropDownMenuTemplate")
profileDropdown:SetPoint("TOPLEFT", cf, "TOPLEFT", 10, -62)
UIDropDownMenu_SetWidth(profileDropdown, 140)

local function BuildProfileDropdown()
    UIDropDownMenu_Initialize(profileDropdown, function(self, level)
        for _, name in ipairs(GetProfileNames()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = name
            info.checked = (name == ActiveProfileName())
            info.func    = function()
                LoadProfile(name)
                UIDropDownMenu_SetText(profileDropdown, name)
                activeNameLabel:SetText("Active: " .. name)
                for key, sl in pairs(sliderRefs) do
                    sl:SetValue(cfg[key])
                    sl.valText:SetText(tostring(cfg[key]))
                end
                BuildRing(); UpdateHUD()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(profileDropdown, ActiveProfileName())
end

MakeLabel(cf, "New profile name", 20, -92)
local profileNameBox = CreateFrame("EditBox", "HolyShockHUDNameBox", cf, "InputBoxTemplate")
profileNameBox:SetSize(130, 20)
profileNameBox:SetPoint("TOPLEFT", cf, "TOPLEFT", 24, -105)
profileNameBox:SetAutoFocus(false)
profileNameBox:SetMaxLetters(32)

local saveNewBtn = CreateFrame("Button", nil, cf, "GameMenuButtonTemplate")
saveNewBtn:SetSize(80, 22)
saveNewBtn:SetPoint("LEFT", profileNameBox, "RIGHT", 6, 0)
saveNewBtn:SetText("Save new")
saveNewBtn:SetScript("OnClick", function()
    local name = profileNameBox:GetText():match("^%s*(.-)%s*$")
    if name == "" then print("|cff5599ffHolyShockHUD|r: Enter a name."); return end
    SaveProfile(name)
    profileNameBox:SetText("")
    BuildProfileDropdown()
    activeNameLabel:SetText("Active: " .. name)
    print("|cff5599ffHolyShockHUD|r: Saved profile \"" .. name .. "\".")
end)

local deleteBtn = CreateFrame("Button", nil, cf, "GameMenuButtonTemplate")
deleteBtn:SetSize(60, 22)
deleteBtn:SetPoint("LEFT", saveNewBtn, "RIGHT", 6, 0)
deleteBtn:SetText("Delete")
deleteBtn:SetScript("OnClick", function()
    local name = ActiveProfileName()
    local ok, err = DeleteProfile(name)
    if not ok then print("|cff5599ffHolyShockHUD|r: " .. err); return end
    BuildProfileDropdown()
    activeNameLabel:SetText("Active: Default")
    for key, sl in pairs(sliderRefs) do
        sl:SetValue(cfg[key]); sl.valText:SetText(tostring(cfg[key]))
    end
    BuildRing(); UpdateHUD()
    print("|cff5599ffHolyShockHUD|r: Deleted \"" .. name .. "\".")
end)

-- Divider
local div = cf:CreateTexture(nil, "ARTWORK")
div:SetHeight(1)
div:SetPoint("TOPLEFT",  cf, "TOPLEFT",  20, -132)
div:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -20, -132)
div:SetColorTexture(0.3, 0.3, 0.3, 1)

-- ── Sliders ───────────────────────────────────────────────────────────────
MakeSlider(cf, "Ring radius",    16, 60,  1, "ringRadius",  20, -145, 210)
MakeSlider(cf, "Ring thickness",  2, 12,  1, "ringThick",   20, -180, 210)
MakeSlider(cf, "Gap size (deg)", 40, 120, 2, "gapDegrees",  20, -215, 210)
MakeSlider(cf, "Segments",       24, 96,  4, "numSegments", 20, -250, 210)

-- ── Swatches ──────────────────────────────────────────────────────────────
MakeSwatches(cf, "Ring colour", "ringR", "ringG", "ringB", 20, -298)
MakeSwatches(cf, "Dot colour",  "dotR",  "dotG",  "dotB",  20, -336)

MakeSlider(cf, "Dot 1  X", -80, 80, 1, "dot1X", 20, -370, 210)
MakeSlider(cf, "Dot 1  Y", -80, 80, 1, "dot1Y", 20, -405, 210)
MakeSlider(cf, "Dot 2  X", -80, 80, 1, "dot2X", 20, -440, 210)
MakeSlider(cf, "Dot 2  Y", -80, 80, 1, "dot2Y", 20, -475, 210)

-- ── Font list ─────────────────────────────────────────────────────────────
local FONT_LIST_H = 110
local FONT_ROW_H  = 18
local fontButtons = {}
local fontSelLabel

MakeLabel(cf, "Charge font", 20, -490)

fontSelLabel = cf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fontSelLabel:SetPoint("TOPLEFT", cf, "TOPLEFT", 105, -490)
fontSelLabel:SetTextColor(1, 0.82, 0, 1)
fontSelLabel:SetText("")

-- Outer box (plain frame with a visible border via backdrop)
local fontOuter = CreateFrame("Frame", nil, cf, "BackdropTemplate")
fontOuter:SetSize(276, FONT_LIST_H)
fontOuter:SetPoint("TOPLEFT", cf, "TOPLEFT", 20, -506)
fontOuter:SetBackdrop({
    bgFile   = "Interface\Buttons\WHITE8x8",
    edgeFile = "Interface\Tooltips\UI-Tooltip-Border",
    edgeSize = 12,
    insets   = { left=3, right=3, top=3, bottom=3 },
})
fontOuter:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
fontOuter:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

-- Clip frame: sits inside the border and hides overflowing rows
local fontClip = CreateFrame("Frame", nil, fontOuter)
fontClip:SetPoint("TOPLEFT",     fontOuter, "TOPLEFT",      4, -4)
fontClip:SetPoint("BOTTOMRIGHT", fontOuter, "BOTTOMRIGHT", -18,  4)
fontClip:SetClipsChildren(true)

-- Scrollbar (plain Slider, no template so no SecureScrollTemplate interference)
local fontBar = CreateFrame("Slider", nil, fontOuter)
fontBar:SetPoint("TOPRIGHT",    fontOuter, "TOPRIGHT",    -3, -4)
fontBar:SetPoint("BOTTOMRIGHT", fontOuter, "BOTTOMRIGHT", -3,  4)
fontBar:SetWidth(12)
fontBar:SetOrientation("VERTICAL")
fontBar:SetMinMaxValues(0, 0)
fontBar:SetValueStep(FONT_ROW_H)

local barBg = fontBar:CreateTexture(nil, "BACKGROUND")
barBg:SetAllPoints(fontBar)
barBg:SetColorTexture(0.15, 0.15, 0.15, 1)

local barThumb = fontBar:CreateTexture(nil, "OVERLAY")
barThumb:SetSize(10, 30)
barThumb:SetColorTexture(0.5, 0.5, 0.5, 0.8)
fontBar:SetThumbTexture(barThumb)

-- Content frame created BEFORE the scrollbar callback so it is never nil
local fontContent = CreateFrame("Frame", nil, fontClip)
fontContent:SetPoint("TOPLEFT", fontClip, "TOPLEFT", 0, 0)
fontContent:SetWidth(fontClip:GetWidth() or 240)
fontContent:SetHeight(1)

local fontScrollOffset = 0

local function ApplyScroll(val)
    fontScrollOffset = val
    fontContent:ClearAllPoints()
    fontContent:SetPoint("TOPLEFT", fontClip, "TOPLEFT", 0, val)
end

fontBar:SetScript("OnValueChanged", function(self, val)
    ApplyScroll(val)
end)

-- Safe to set initial value now that fontContent and the callback both exist
fontBar:SetValue(0)

fontOuter:EnableMouseWheel(true)
fontOuter:SetScript("OnMouseWheel", function(self, delta)
    local mn, mx = fontBar:GetMinMaxValues()
    fontBar:SetValue(math.max(mn, math.min(mx, fontBar:GetValue() - delta * FONT_ROW_H * 3)))
end)

local function FontPick(name)
    cfg.fontPath = name
    SaveProfile(ActiveProfileName())
    fontSelLabel:SetText(name)
    for _, btn in ipairs(fontButtons) do
        if btn.fontName == name then btn:LockHighlight()
        else btn:UnlockHighlight() end
    end
    BuildRing(); UpdateHUD()
end

local function BuildFontList()
    local list = GetFontList()
    local totalH = #list * FONT_ROW_H
    fontContent:SetHeight(math.max(totalH, FONT_LIST_H))
    local maxS = math.max(0, totalH - FONT_LIST_H)
    fontBar:SetMinMaxValues(0, maxS)
    fontBar:SetValue(0)

    for i, font in ipairs(list) do
        local btn = fontButtons[i]
        if not btn then
            btn = CreateFrame("Button", nil, fontContent)
            btn:SetHeight(FONT_ROW_H)
            btn:SetPoint("LEFT",  fontContent, "LEFT",  2, 0)
            btn:SetPoint("RIGHT", fontContent, "RIGHT", -2, 0)
            btn:SetPoint("TOP",   fontContent, "TOP",   0, -(i-1)*FONT_ROW_H)
            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(btn); hl:SetColorTexture(1,1,1,0.1)
            btn:SetHighlightTexture(hl)
            local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lbl:SetPoint("LEFT",  btn, "LEFT",  4, 0)
            lbl:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            lbl:SetJustifyH("LEFT")
            btn.label = lbl
            fontButtons[i] = btn
        end
        btn:Show()
        btn.fontName = font.name
        btn.label:SetText(font.name)
        local active = (cfg.fontPath == font.name or cfg.fontPath == font.path)
        if active then btn:LockHighlight() else btn:UnlockHighlight() end
        btn:SetScript("OnClick", function() FontPick(font.name) end)
    end
    for i = #list + 1, #fontButtons do fontButtons[i]:Hide() end

    -- Update label
    fontSelLabel:SetText(cfg.fontPath)

    -- Scroll to selection
    for i, font in ipairs(list) do
        if cfg.fontPath == font.name or cfg.fontPath == font.path then
            local target = math.max(0, (i-1)*FONT_ROW_H - FONT_LIST_H/2)
            fontBar:SetValue(math.min(target, maxS))
            break
        end
    end
end

MakeSlider(cf, "Font size", 10, 36, 1, "fontSize", 20, -633, 210)

-- ── Bottom buttons ────────────────────────────────────────────────────────
local closeBtn = CreateFrame("Button", nil, cf, "GameMenuButtonTemplate")
closeBtn:SetSize(100, 26)
closeBtn:SetPoint("BOTTOM", cf, "BOTTOM", 0, 16)
closeBtn:SetText("Close")
closeBtn:SetScript("OnClick", function() cf:Hide() end)

-- ── Slash commands ────────────────────────────────────────────────────────
SLASH_HOLYHUD1 = "/holyhud"
SlashCmdList["HOLYHUD"] = function(msg)
    msg = msg and msg:lower():match("^%s*(.-)%s*$") or ""
    if msg == "config" then
        if cf:IsShown() then cf:Hide() else cf:Show() end
    else
        if root:IsShown() then
            root:Hide(); print("|cff5599ffHolyShockHUD|r hidden.")
        else
            root:Show(); print("|cff5599ffHolyShockHUD|r shown.")
        end
    end
end

-- ── Init ──────────────────────────────────────────────────────────────────
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    HolyShockHUD_Config = HolyShockHUD_Config or {}
    HolyShockHUD_Config.profiles = HolyShockHUD_Config.profiles or {}
    if not HolyShockHUD_Config.profiles["Default"] then
        local migrated = {}
        for k in pairs(DEFAULTS) do migrated[k] = HolyShockHUD_Config[k] end
        HolyShockHUD_Config.profiles["Default"] = migrated
    end
    HolyShockHUD_Config.activeProfile = HolyShockHUD_Config.activeProfile or "Default"
    LoadProfile(HolyShockHUD_Config.activeProfile)
    activeNameLabel:SetText("Active: " .. ActiveProfileName())
    BuildProfileDropdown()
    BuildFontList()
    BuildRing()
    UpdateHUD()
end)
