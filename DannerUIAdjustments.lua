--------------------------------------------------------------------------------
--  DannerUIBags
--
--  An EllesmereUI extension for WoW Forever: gives the bag bar buttons (backpack,
--  bag slots, reagent bag, keyring) AND the micro menu buttons the same look as
--  EllesmereUI's action bar buttons: flat dark slot background, square zoomed
--  icon, thin solid border and (bags) the action bar hover highlight. The micro
--  buttons keep Blizzard's own hover glyph and are resized to the action bar
--  button size. The look is read live
--  from the user's Action Bars profile, so it follows their slot colour, zoom,
--  border and highlight settings (/dbags refresh after changing them).
--
--  Taint-safe like EUI's own skins: alpha-only art removal, our own child
--  frames/textures, no Hide/SetParent on anything inside the BagsBar or
--  MicroMenu trees. The micro buttons are secure: every write to them is skipped
--  in combat and replayed when combat ends.
--
--  EUI's own "Bag Bar" / "Micro Menu" window skins paint the same buttons with
--  the micro menu pack look. While one is active (Blizzard Skins+ > Window Skins
--  is not Blizz Default / Off) this addon stands down for that bar so the two do
--  not stack.
--------------------------------------------------------------------------------
local ADDON_NAME = ...

local EllesmereUI = _G.EllesmereUI
local PREFIX = "|cff0cd29fDannerUIBags|r: "

local DEFAULTS = {
    enabled = true,          -- skin the bag bar
    microBar = true,         -- skin the micro menu
    microMatchSize = true,   -- resize micro buttons to the action bar button size
    microNoDim = true,       -- keep disabled/locked micro buttons at full opacity
    matchActionBars = true,  -- read the look from the EUI Action Bars profile
    qualityBorders = false,  -- colour a bag's border by item quality (uncommon+)
}
local DB = {}

local BAG_BUTTONS = {
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "CharacterReagentBag0Slot", "KeyRingButton",
}
-- Named micro buttons (the ones EUI's own micro menu pack knows, including WoW
-- Forever's split-out ones); any other Button child of MicroMenu is picked up too.
local MICRO_BUTTONS = {
    "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
    "SpellbookMicroButton", "TalentMicroButton", "AchievementMicroButton",
    "QuestLogMicroButton", "GuildMicroButton", "SocialsMicroButton",
    "LFDMicroButton", "PVPMicroButton", "CollectionsMicroButton", "EJMicroButton",
    "StoreMicroButton", "MainMenuMicroButton", "HelpMicroButton",
    "HousingMicroButton", "LegacyMicroButton",
}
-- Regions on a micro button that are plate/bevel art (the glyph is the
-- Normal/Pushed/Disabled texture and stays).
local MICRO_DECO = { "Background", "PushedBackground", "FlashBorder", "Shadow", "PushedShadow", "Border", "Backdrop" }
local MICRO_TRIM = 0.08   -- crops the glyph's baked bevel ring
local MICRO_GAP = 1       -- logical px above/below our box
local MICRO_WIDTH_EXTRA = 4 -- logical px added to each micro button's stock width

-- BagsBar container backdrop atlases (the stock strip behind the slots).
local FRAME_ATLASES = { "actionbar-frame", "iconframe-background" }

local EAB_MEDIA = "Interface\\AddOns\\EllesmereUIActionBars\\Media\\"
local HIGHLIGHT_FILES = { "highlight-2.png", "highlight-3.png", "highlight-4.png" }

local function Print(msg) print(PREFIX .. msg) end

-- Per-button state lives outside Blizzard's frame tables (taint).
local FD = setmetatable({}, { __mode = "k" })
local function GetFD(frame)
    local d = FD[frame]
    if not d then d = {}; FD[frame] = d end
    return d
end
local OURS = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
--  Look: what an action bar button looks like in the user's EUI profile
--------------------------------------------------------------------------------
local function GetABProfile()
    if not (EllesmereUI and EllesmereUI.GetActiveProfileData) then return end
    local data = EllesmereUI.GetActiveProfileData()
    return data and data.addons and data.addons.EllesmereUIActionBars
end

local function EABLoaded()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUIActionBars")
end

-- Defaults mirror EllesmereUIActionBars' own defaults, so the look is right even
-- without EllesmereUI's profile (or with matchActionBars off).
local function GetLook()
    local look = {
        zoom = 0.055,
        bgR = 0.15, bgG = 0.15, bgB = 0.15, bgA = 0.5,
        brdOn = true, brdR = 0, brdG = 0, brdB = 0, brdA = 1, brdSize = 1,
        hlR = 0.973, hlG = 0.839, hlB = 0.604, hlTex = nil, hlWash = 0.35,
        pushTex = nil,
    }
    local hasMedia = EABLoaded()
    if hasMedia then look.hlTex = EAB_MEDIA .. HIGHLIGHT_FILES[2] end
    if hasMedia then look.pushTex = EAB_MEDIA .. HIGHLIGHT_FILES[2] end

    local p = DB.matchActionBars and GetABProfile()
    -- Blizzard/Classic action bar styles are not the flat look; keep the defaults.
    if not p or p.useBlizzardStyle or p.useClassicStyle then return look end

    look.zoom = (p.iconZoom or 5.5) / 100
    local sc = p.slotBgColor
    if sc then look.bgR, look.bgG, look.bgB = sc.r or 0.15, sc.g or 0.15, sc.b or 0.15 end
    if p.slotBgOpacity ~= nil then look.bgA = p.slotBgOpacity / 100 end

    local bar = p.bars and p.bars.MainBar
    if bar then
        look.brdOn = bar.borderEnabled ~= false
        local bc = bar.borderColor
        if bc then look.brdR, look.brdG, look.brdB, look.brdA = bc.r or 0, bc.g or 0, bc.b or 0, bc.a or 1 end
        if bar.borderClassColor then
            local _, class = UnitClass("player")
            local cc = class and RAID_CLASS_COLORS[class]
            if cc then look.brdR, look.brdG, look.brdB = cc.r, cc.g, cc.b end
        end
        look.brdSize = bar.borderSize or 1
    end

    local hc = p.highlightCustomColor
    if hc then look.hlR, look.hlG, look.hlB = hc.r or look.hlR, hc.g or look.hlG, hc.b or look.hlB end
    if p.highlightUseClassColor then
        local _, class = UnitClass("player")
        local cc = class and RAID_CLASS_COLORS[class]
        if cc then look.hlR, look.hlG, look.hlB = cc.r, cc.g, cc.b end
    end
    local hType = p.highlightTextureType or 2
    if hType == 6 then
        look.hlTex, look.hlWash = nil, 0                 -- hover highlight off
    elseif hType == 4 or not hasMedia then
        look.hlTex = nil                                 -- flat colour wash
    else
        look.hlTex = EAB_MEDIA .. (HIGHLIGHT_FILES[hType] or HIGHLIGHT_FILES[1])
    end
    return look
end

--------------------------------------------------------------------------------
--  Borders: EUI's pixel-perfect border when present, else four 1px strips.
--  `host` is the frame the border is drawn around (the button, or our micro box).
--------------------------------------------------------------------------------
local function SetStripBorder(d, host, look, r, g, b, a)
    if not d.strips then
        local box = CreateFrame("Frame", nil, host)
        box:SetAllPoints(host)
        box:EnableMouse(false)
        box:SetFrameLevel(host:GetFrameLevel() + 2)
        OURS[box] = true
        local s = {}
        for i = 1, 4 do
            s[i] = box:CreateTexture(nil, "OVERLAY", nil, 2)
            s[i]:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        d.strips = s
    end
    local s = d.strips
    local scale = host:GetEffectiveScale()
    local _, physH = GetPhysicalScreenSize()
    local px = (768 / (physH or 768)) / (scale > 0 and scale or 1) * look.brdSize
    s[1]:ClearAllPoints(); s[1]:SetPoint("TOPLEFT");     s[1]:SetPoint("TOPRIGHT");    s[1]:SetHeight(px)
    s[2]:ClearAllPoints(); s[2]:SetPoint("BOTTOMLEFT");  s[2]:SetPoint("BOTTOMRIGHT"); s[2]:SetHeight(px)
    s[3]:ClearAllPoints(); s[3]:SetPoint("TOPLEFT");     s[3]:SetPoint("BOTTOMLEFT");  s[3]:SetWidth(px)
    s[4]:ClearAllPoints(); s[4]:SetPoint("TOPRIGHT");    s[4]:SetPoint("BOTTOMRIGHT"); s[4]:SetWidth(px)
    for i = 1, 4 do s[i]:SetVertexColor(r, g, b, a); s[i]:SetShown(look.brdOn) end
end

local function ApplyBorder(host, d, look, r, g, b, a)
    local PP = EllesmereUI and EllesmereUI.PP
    if PP and PP.CreateBorder and PP.SetBorderColor then
        if not d.ppBorder then
            d.ppBorder = PP.CreateBorder(host, r, g, b, a, look.brdSize, "OVERLAY", 2)
        end
        if PP.SetBorderSize then PP.SetBorderSize(host, look.brdSize) end
        PP.SetBorderColor(host, r, g, b, a)
        if d.ppBorder then d.ppBorder:SetShown(look.brdOn) end
    else
        SetStripBorder(d, host, look, r, g, b, a)
    end
end

--------------------------------------------------------------------------------
--  Shared painting
--------------------------------------------------------------------------------
-- Hover (and, for plain buttons, pressed) highlight in the action bar look.
-- `anchor` is the frame the highlight covers. Not used on micro buttons: their
-- Highlight/Pushed textures are glyphs, not overlays.
local function StyleHighlights(btn, look, anchor, keepPushed)
    anchor = anchor or btn
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl then
        if hl.SetAtlas then hl:SetAtlas(nil) end
        if look.hlTex then
            hl:SetTexture(look.hlTex)
            hl:SetTexCoord(0, 1, 0, 1)
            hl:SetVertexColor(look.hlR, look.hlG, look.hlB, 1)
        else
            hl:SetColorTexture(look.hlR, look.hlG, look.hlB, look.hlWash)
        end
        hl:ClearAllPoints()
        hl:SetAllPoints(anchor)
        hl:SetAlpha((look.hlTex or look.hlWash > 0) and 1 or 0)
    end
    if keepPushed then return end
    local pt = btn.GetPushedTexture and btn:GetPushedTexture()
    if pt then
        if pt.SetAtlas then pt:SetAtlas(nil) end
        if look.pushTex then
            pt:SetTexture(look.pushTex)
            pt:SetTexCoord(0, 1, 0, 1)
            pt:SetVertexColor(look.hlR, look.hlG, look.hlB, 1)
        else
            pt:SetColorTexture(look.hlR, look.hlG, look.hlB, 0.3)
        end
        pt:ClearAllPoints()
        pt:SetAllPoints(anchor)
    end
end

local function FadeRegionsByAtlas(frame, wanted)
    if not frame then return end
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        local atlas = r and r.GetAtlas and r:GetAtlas()
        if atlas then
            local la = atlas:lower()
            for _, want in ipairs(wanted) do
                if la:find(want, 1, true) then r:SetAlpha(0); break end
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Coexistence with EUI's own bag bar / micro menu skins
--------------------------------------------------------------------------------
-- true while EllesmereUI's window skin `key` is painting those buttons itself.
local function EUISkinActive(key)
    if not (EllesmereUI and EllesmereUI.IS_FOREVER and EllesmereUI.GetBlizzWindowStyle) then return false end
    local ok, style = pcall(EllesmereUI.GetBlizzWindowStyle, key)
    return ok and (style == "eui" or style == "modern")
end

local standDownWarned = {}
local function WarnStandDown(key, label)
    if standDownWarned[key] then return end
    standDownWarned[key] = true
    Print("EllesmereUI's own " .. label .. " skin is active, so DannerUIBags stands down for it. " ..
          "Set Blizzard Skins+ > Window Skins > " .. label .. " to Blizz Default (or Off), then /reload.")
end

--------------------------------------------------------------------------------
--  Bag bar
--------------------------------------------------------------------------------
-- The keyring's frame art sits in child frames (a NineSlice border built after
-- the first pass): fade their textures, walking Blizzard's own frames only.
local function FadeKeyRingArt(f, depth)
    if not f or depth > 4 or (f.IsForbidden and f:IsForbidden()) then return end
    local children = { f:GetChildren() }
    for i = 1, #children do
        local c = children[i]
        if c and not OURS[c] then
            local regions = { c:GetRegions() }
            for j = 1, #regions do
                local r = regions[j]
                if r and r.GetObjectType and r:GetObjectType() == "Texture" then r:SetAlpha(0) end
            end
            FadeKeyRingArt(c, depth + 1)
        end
    end
end

local function PaintBag(btn, look)
    local d = GetFD(btn)
    local isKeyRing = (btn == _G.KeyRingButton)

    -- Slot background behind the icon (action bars: slotBgColor at slotBgOpacity).
    if not d.bg then
        d.bg = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
        d.bg:SetAllPoints(btn)
    end
    d.bg:SetColorTexture(look.bgR, look.bgG, look.bgB, look.bgA)

    local icon = btn.icon or (btn.GetName and _G[btn:GetName() .. "IconTexture"])
    local nt = (btn.GetNormalTexture and btn:GetNormalTexture()) or btn.NormalTexture
    if isKeyRing then
        -- Its glyph can live on the NormalTexture, under its own SquareMask.
        local sm = btn.SquareMask
        if sm then
            for _, t in ipairs({ _G.KeyRingButtonIconTexture, nt }) do
                if t and t.RemoveMaskTexture then pcall(t.RemoveMaskTexture, t, sm) end
            end
        end
        FadeKeyRingArt(btn, 1)
        if not (icon and icon.GetTexture and icon:GetTexture()) then icon = nt end
    end
    if icon and icon.SetTexCoord then
        icon:SetTexCoord(look.zoom, 1 - look.zoom, look.zoom, 1 - look.zoom)
    end
    -- The bevel NormalTexture fades, except while it is the keyring glyph.
    if nt and nt ~= icon then nt:SetAlpha(0) end
    if btn.IconBorder then btn.IconBorder:SetAlpha(0) end

    local regions = { btn:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        local kind = r and r.GetObjectType and r:GetObjectType()
        if kind == "MaskTexture" then
            -- pcall: a texture the mask is not on may reject the removal.
            if icon and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, r) end
            if nt and nt ~= icon and nt.RemoveMaskTexture then pcall(nt.RemoveMaskTexture, nt, r) end
        elseif kind == "Texture" and r ~= d.bg then
            local atlas = r.GetAtlas and r:GetAtlas()
            if atlas and atlas:lower():find("iconframe", 1, true) then r:SetAlpha(0) end
        end
    end

    -- Empty bag slot: Blizzard shows a placeholder "wings" icon there. Hide it
    -- (alpha only) while no bag is equipped; the slot background and border stay.
    if not isKeyRing and btn ~= _G.MainMenuBarBackpackButton then
        local id = btn.GetID and btn:GetID()
        local empty
        if id and id > 0 then empty = not GetInventoryItemID("player", id) end
        local function IsPlaceholder(tex)
            local path = tex.GetTexture and tex:GetTexture()
            local atlas = tex.GetAtlas and tex:GetAtlas()
            path = type(path) == "string" and path:lower() or ""
            atlas = type(atlas) == "string" and atlas:lower() or ""
            return path:find("paperdoll", 1, true) or path:find("slot%-bag")
                or atlas:find("bag%-empty") or atlas:find("slot%-bag")
        end
        if empty == nil and icon then empty = IsPlaceholder(icon) and true or false end
        local a = empty and 0 or 1
        if icon and icon.SetAlpha then icon:SetAlpha(a) end
        -- The placeholder can also live on another region of the button.
        for i = 1, #regions do
            local r = regions[i]
            if r ~= icon and r ~= d.bg and r.GetObjectType and r:GetObjectType() == "Texture"
               and IsPlaceholder(r) then
                r:SetAlpha(a)
            end
        end
    end

    StyleHighlights(btn, look)

    -- Border: the action bar border colour; optionally the bag's quality colour.
    local r, g, b, a = look.brdR, look.brdG, look.brdB, look.brdA
    if DB.qualityBorders then
        local id = btn.GetID and btn:GetID()
        local itemID = id and id > 0 and GetInventoryItemID("player", id)
        local q = itemID and C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
        if q and q >= 2 then r, g, b = C_Item.GetItemQualityColor(q); a = 1 end
    end
    ApplyBorder(btn, d, look, r, g, b, a)
end

local function PaintBags()
    if not DB.enabled then return end
    if EUISkinActive("bagbar") then WarnStandDown("bagbar", "Bag Bar"); return end
    local look = GetLook()
    FadeRegionsByAtlas(_G.BagsBar, FRAME_ATLASES)
    for _, name in ipairs(BAG_BUTTONS) do
        local btn = _G[name]
        if btn and not (btn.IsForbidden and btn:IsForbidden()) then
            local ok, err = pcall(PaintBag, btn, look)
            if not ok and not GetFD(btn).errored then
                GetFD(btn).errored = true
                Print(name .. ": " .. tostring(err))
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Micro menu
--------------------------------------------------------------------------------
-- Screen-space size of an action bar button: the size the micro buttons match.
local function TargetScreenSize()
    for _, ref in ipairs({ _G.ActionButton1, _G.MainMenuBarBackpackButton }) do
        local h = ref and ref.GetHeight and ref:GetHeight()
        local es = ref and ref.GetEffectiveScale and ref:GetEffectiveScale()
        if h and es and h > 8 and es > 0 then return h * es end
    end
end

local function CollectMicroButtons()
    local list, seen = {}, {}
    local function add(btn)
        if btn and not seen[btn] and not OURS[btn] and btn.GetObjectType
           and not (btn.IsForbidden and btn:IsForbidden()) then
            seen[btn] = true
            list[#list + 1] = btn
        end
    end
    for _, name in ipairs(MICRO_BUTTONS) do add(_G[name]) end
    local mm = _G.MicroMenu
    if mm and mm.GetChildren then
        local children = { mm:GetChildren() }
        for i = 1, #children do
            local c = children[i]
            if c.GetObjectType and c:GetObjectType() == "Button" and c.GetNormalTexture then add(c) end
        end
    end
    return list
end

-- Crop the glyph's baked bevel ring and fill the box with it: stock width, the
-- increased height of the action bar buttons. The hover glyph keeps its
-- HIGHLIGHT layer, so the engine still shows it only while hovered.
local function TrimGlyph(tex, box)
    if not tex or not tex.SetTexCoord then return end
    if tex.SetDrawLayer and not (tex.GetDrawLayer and tex:GetDrawLayer() == "HIGHLIGHT") then
        tex:SetDrawLayer("ARTWORK")
    end
    tex:SetTexCoord(MICRO_TRIM, 1 - MICRO_TRIM, MICRO_TRIM, 1 - MICRO_TRIM)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
end

-- Every state of the glyph: Normal/Pushed/Disabled, the stock hover glyph (the
-- Highlight texture is Blizzard's brighter copy of the icon, left as it is) and
-- the character portrait.
local function MicroGlyphs(btn)
    return {
        btn.GetNormalTexture and btn:GetNormalTexture(),
        btn.GetPushedTexture and btn:GetPushedTexture(),
        btn.GetDisabledTexture and btn:GetDisabledTexture(),
        btn.GetHighlightTexture and btn:GetHighlightTexture(),
        btn.Portrait,
    }
end

-- Puts one button's art back in our box: plate art faded, glyphs cropped and
-- anchored. Blizzard re-anchors the glyphs and re-shows plate art when a button
-- is pressed or released, so this runs right then, for that button only (no
-- resize, no relayout, so the rest of the row is left alone).
local microDirty = false
local function RefitMicro(btn)
    local d = FD[btn]
    if not (DB.microBar and d and d.box) then return end
    if InCombatLockdown() then microDirty = true; return end
    for _, k in ipairs(MICRO_DECO) do
        local r = btn[k]
        if r and r.SetAlpha then r:SetAlpha(0) end
    end
    for _, tex in pairs(MicroGlyphs(btn)) do TrimGlyph(tex, d.box) end
end

local function HookMicroPress(btn, d)
    if d.pressHooked then return end
    d.pressHooked = true
    local function refit() pcall(RefitMicro, btn) end
    btn:HookScript("OnMouseDown", refit)
    btn:HookScript("OnMouseUp", refit)
    -- Blizzard's own pressed/normal state switch (also run for the button whose
    -- window opens or closes).
    for _, method in ipairs({ "SetPushed", "SetNormal" }) do
        if type(btn[method]) == "function" then hooksecurefunc(btn, method, refit) end
    end
end

local function PaintMicro(btn, look, target)
    local d = GetFD(btn)
    -- The stock width, recorded before the first resize.
    if not d.origW then d.origW = btn:GetWidth() end
    for _, k in ipairs(MICRO_DECO) do
        local r = btn[k]
        if r and r.SetAlpha then r:SetAlpha(0) end
    end

    -- Same height as the action bar buttons (`target` screen pixels, plus
    -- MICRO_GAP above and below), and the stock width plus MICRO_WIDTH_EXTRA.
    local resized = false
    if target and DB.microMatchSize and d.origW and d.origW > 1 then
        local es = btn:GetEffectiveScale()
        if es and es > 0 then
            local height = target / es + 2 * MICRO_GAP
            local width = d.origW + MICRO_WIDTH_EXTRA
            if math.abs((btn:GetWidth() or 0) - width) > 0.3 or math.abs((btn:GetHeight() or 0) - height) > 0.3 then
                btn:SetSize(width, height)
                resized = true
            end
        end
    end

    if not d.box then
        local box = CreateFrame("Frame", nil, btn)
        box:EnableMouse(false)
        OURS[box] = true
        d.box = box
        d.bg = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
        d.bg:SetAllPoints(box)
    end
    d.box:ClearAllPoints()
    d.box:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -MICRO_GAP)
    d.box:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, MICRO_GAP)
    d.bg:SetColorTexture(look.bgR, look.bgG, look.bgB, look.bgA)

    for _, tex in pairs(MicroGlyphs(btn)) do TrimGlyph(tex, d.box) end
    HookMicroPress(btn, d)

    -- Own strips rather than EUI's PP border: the box is anchored (no size of its
    -- own), and the strips follow it however Blizzard's layout moves the button.
    SetStripBorder(d, d.box, look, look.brdR, look.brdG, look.brdB, look.brdA)
    return resized
end

-- Blizzard's micro button OnDisable sets alpha 0.5: locked buttons always, and
-- every other button while a full-screen panel is open. Alpha is not a protected
-- write, so this also runs in combat. Independent of the skin (and of EUI's).
local noDimHooked = setmetatable({}, { __mode = "k" })
local function UndimMicro(btn)
    if DB.microNoDim and not btn:IsEnabled() then btn:SetAlpha(1) end
end
local function HookMicroNoDim()
    for _, btn in ipairs(CollectMicroButtons()) do
        if not noDimHooked[btn] and btn.HookScript and btn.IsEnabled then
            noDimHooked[btn] = true
            btn:HookScript("OnDisable", UndimMicro)
        end
        if btn.IsEnabled then pcall(UndimMicro, btn) end
    end
end

local function PaintMicroMenu()
    HookMicroNoDim()
    if not DB.microBar then return end
    if EUISkinActive("micromenu") then WarnStandDown("micromenu", "Micro Menu"); return end
    -- Micro buttons are secure: nothing is written in combat, it is replayed after.
    if InCombatLockdown() then microDirty = true; return end
    microDirty = false

    local look = GetLook()
    local target = TargetScreenSize()
    local anyResized = false
    for _, btn in ipairs(CollectMicroButtons()) do
        local ok, res = pcall(PaintMicro, btn, look, target)
        if ok then
            anyResized = anyResized or res
        elseif not GetFD(btn).errored then
            GetFD(btn).errored = true
            Print((btn.GetName and btn:GetName() or "micro button") .. ": " .. tostring(res))
        end
    end

    -- The ornate container strip behind the buttons: alpha only, the container
    -- is Edit Mode's.
    local mm = _G.MicroMenu
    if mm then
        if mm.BackgroundArt and mm.BackgroundArt.SetAlpha then mm.BackgroundArt:SetAlpha(0) end
        if mm.BorderArt and mm.BorderArt.SetAlpha then mm.BorderArt:SetAlpha(0) end
        local regions = { mm:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r and r.GetObjectType and r:GetObjectType() == "Texture" then r:SetAlpha(0) end
        end
        -- New button sizes: let Blizzard's layout frame re-flow the row.
        if anyResized and mm.Layout then pcall(mm.Layout, mm) end
    end
end

--------------------------------------------------------------------------------
--  Apply
--------------------------------------------------------------------------------
local pending
local function SchedulePaint()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = nil
        PaintBags()
        PaintMicroMenu()
    end)
end

local hooked = false
local function Install()
    if hooked then return end
    hooked = true
    local f = CreateFrame("Frame")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("UI_SCALE_CHANGED")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and not microDirty then return end
        SchedulePaint()
    end)
    -- The keyring rebuilds its art in its own texture update: repaint right after.
    local kr = _G.KeyRingButton
    if kr and kr.UpdateTextures then
        hooksecurefunc(kr, "UpdateTextures", SchedulePaint)
    end
    -- Blizzard re-anchors the micro glyphs here (several times per frame on
    -- routine events): the debounce collapses each burst into one repaint.
    if _G.UpdateMicroButtons then
        hooksecurefunc("UpdateMicroButtons", SchedulePaint)
    end
end

function DannerUIBags_Refresh()
    Install()
    SchedulePaint()
end

--------------------------------------------------------------------------------
--  Options page inside the EllesmereUI panel
--------------------------------------------------------------------------------
local function RegisterOptions()
    if not (EllesmereUI and EllesmereUI.RegisterPlugin) then return end
    EllesmereUI.RegisterPlugin("DannerUIBags", {
        label = "DannerUIBags",
        modules = {
            {
                key = "Bars",
                title = "Bag & Micro Bar Skin",
                description = "Gives the bag bar and micro menu the same look as your action bar buttons.",
                pages = { "General" },
                buildPage = function(_, parent, yOffset)
                    local W = EllesmereUI.Widgets
                    local y = yOffset
                    local _, h
                    _, h = W:SectionHeader(parent, "BAG BAR", y); y = y - h
                    _, h = W:Toggle(parent, "Skin the bag bar", y,
                        function() return DB.enabled end,
                        function(v)
                            DB.enabled = v and true or false
                            if DB.enabled then DannerUIBags_Refresh()
                            else Print("Bag bar skin disabled. /reload to restore the stock art.") end
                        end); y = y - h
                    _, h = W:Toggle(parent, "Quality-coloured bag borders", y,
                        function() return DB.qualityBorders end,
                        function(v) DB.qualityBorders = v and true or false; DannerUIBags_Refresh() end); y = y - h
                    _, h = W:SectionHeader(parent, "MICRO MENU", y); y = y - h
                    _, h = W:Toggle(parent, "Skin the micro menu", y,
                        function() return DB.microBar end,
                        function(v)
                            DB.microBar = v and true or false
                            if DB.microBar then DannerUIBags_Refresh()
                            else Print("Micro menu skin disabled. /reload to restore the stock art.") end
                        end); y = y - h
                    _, h = W:Toggle(parent, "Match action bar button size", y,
                        function() return DB.microMatchSize end,
                        function(v)
                            DB.microMatchSize = v and true or false
                            if DB.microMatchSize then DannerUIBags_Refresh()
                            else Print("Micro button size will return to stock after /reload.") end
                        end); y = y - h
                    _, h = W:Toggle(parent, "Don't dim disabled / locked buttons", y,
                        function() return DB.microNoDim end,
                        function(v)
                            DB.microNoDim = v and true or false
                            if DB.microNoDim then DannerUIBags_Refresh()
                            else Print("Micro button dimming returns after /reload.") end
                        end); y = y - h
                    _, h = W:SectionHeader(parent, "LOOK", y); y = y - h
                    _, h = W:Toggle(parent, "Match Action Bars look", y,
                        function() return DB.matchActionBars end,
                        function(v) DB.matchActionBars = v and true or false; DannerUIBags_Refresh() end); y = y - h
                    return math.abs(y)
                end,
            },
        },
    })
end

--------------------------------------------------------------------------------
--  Boot
--------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        DannerUIBagsDB = DannerUIBagsDB or {}
        for k, v in pairs(DEFAULTS) do
            if DannerUIBagsDB[k] == nil then DannerUIBagsDB[k] = v end
        end
        DB = DannerUIBagsDB
        RegisterOptions()
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        Install()
        SchedulePaint()
        -- Blizzard builds some bar art a beat after login; one late pass catches it.
        C_Timer.After(1, SchedulePaint)
    end
end)

local HELP = "/dbags on | off | micro | microsize | nodim | quality | match | refresh | config | debug"
SLASH_DANNERUIBAGS1 = "/dbags"
SLASH_DANNERUIBAGS2 = "/danneruibags"
SlashCmdList.DANNERUIBAGS = function(msg)
    msg = (msg or ""):lower():match("^%s*(%S*)") or ""
    local function toggle(key, label)
        DB[key] = not DB[key]; DannerUIBags_Refresh()
        Print(label .. (DB[key] and " on." or " off (/reload to restore the stock look)."))
    end
    if msg == "on" then
        DB.enabled, DB.microBar = true, true; DannerUIBags_Refresh(); Print("Enabled.")
    elseif msg == "off" then
        DB.enabled, DB.microBar = false, false; Print("Disabled. /reload to restore the stock art.")
    elseif msg == "refresh" then
        DannerUIBags_Refresh()
    elseif msg == "micro" then toggle("microBar", "Micro menu skin")
    elseif msg == "microsize" then toggle("microMatchSize", "Micro button size match")
    elseif msg == "nodim" then toggle("microNoDim", "Keep disabled micro buttons opaque")
    elseif msg == "quality" then toggle("qualityBorders", "Quality borders")
    elseif msg == "match" then toggle("matchActionBars", "Match Action Bars look")
    elseif msg == "config" then
        if EllesmereUI and EllesmereUI.OpenPlugin then EllesmereUI.OpenPlugin("DannerUIBags")
        else Print("EllesmereUI is not loaded.") end
    elseif msg == "debug" then
        -- Dumps what the micro menu looks like on this client, for troubleshooting.
        local mm = _G.MicroMenu
        Print(("MicroMenu: %s, Layout: %s, target size: %s"):format(
            mm and (mm:GetObjectType() .. " " .. math.floor((mm:GetWidth() or 0) + 0.5) .. "x" .. math.floor((mm:GetHeight() or 0) + 0.5)) or "missing",
            tostring(mm and mm.Layout ~= nil), tostring(TargetScreenSize())))
        for _, btn in ipairs(CollectMicroButtons()) do
            Print(("  %s %.0fx%.0f"):format(btn.GetName and btn:GetName() or "?", btn:GetWidth() or 0, btn:GetHeight() or 0))
        end
    else
        Print(HELP)
    end
end
