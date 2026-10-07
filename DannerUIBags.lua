--------------------------------------------------------------------------------
--  DannerUIBags
--
--  An EllesmereUI extension for WoW Forever: gives the bag bar buttons (backpack,
--  bag slots, reagent bag, keyring) the same look as EllesmereUI's action bar
--  buttons: flat dark slot background, square zoomed icon, thin solid border and
--  the action bar hover/pressed highlight. The look is read live from the user's
--  Action Bars profile, so it follows their slot colour, zoom, border and
--  highlight settings (/dbags refresh after changing them).
--
--  Taint-safe like EUI's own skins: alpha-only art removal, our own child
--  frames/textures, no Hide/SetParent on anything inside the BagsBar tree.
--
--  EUI's own "Bag Bar" window skin paints the same buttons with the micro menu
--  look. While it is active (Blizzard Skins+ > Window Skins > Bag Bar is not
--  Blizz Default / Off) this addon stands down so the two do not stack.
--------------------------------------------------------------------------------
local ADDON_NAME = ...

local EllesmereUI = _G.EllesmereUI
local PREFIX = "|cff0cd29fDannerUIBags|r: "

local DEFAULTS = {
    enabled = true,          -- skin the bag bar at all
    matchActionBars = true,  -- read the look from the EUI Action Bars profile
    qualityBorders = false,  -- colour a bag's border by item quality (uncommon+)
}
local DB = {}

local BAG_BUTTONS = {
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "CharacterReagentBag0Slot", "KeyRingButton",
}
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
--  Borders: EUI's pixel-perfect border when present, else four 1px strips
--------------------------------------------------------------------------------
local function SetStripBorder(d, btn, look)
    if not d.strips then
        local box = CreateFrame("Frame", nil, btn)
        box:SetAllPoints(btn)
        box:EnableMouse(false)
        box:SetFrameLevel(btn:GetFrameLevel() + 2)
        OURS[box] = true
        local s = {}
        for i = 1, 4 do
            s[i] = box:CreateTexture(nil, "OVERLAY", nil, 2)
            s[i]:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        d.strips, d.stripBox = s, box
    end
    local s = d.strips
    local scale = btn:GetEffectiveScale()
    local _, physH = GetPhysicalScreenSize()
    local px = (768 / (physH or 768)) / (scale > 0 and scale or 1) * look.brdSize
    s[1]:ClearAllPoints(); s[1]:SetPoint("TOPLEFT");     s[1]:SetPoint("TOPRIGHT");    s[1]:SetHeight(px)
    s[2]:ClearAllPoints(); s[2]:SetPoint("BOTTOMLEFT");  s[2]:SetPoint("BOTTOMRIGHT"); s[2]:SetHeight(px)
    s[3]:ClearAllPoints(); s[3]:SetPoint("TOPLEFT");     s[3]:SetPoint("BOTTOMLEFT");  s[3]:SetWidth(px)
    s[4]:ClearAllPoints(); s[4]:SetPoint("TOPRIGHT");    s[4]:SetPoint("BOTTOMRIGHT"); s[4]:SetWidth(px)
    for i = 1, 4 do s[i]:SetVertexColor(look.brdR, look.brdG, look.brdB, look.brdA); s[i]:SetShown(look.brdOn) end
end

local function ApplyBorder(btn, d, look, r, g, b, a)
    local PP = EllesmereUI and EllesmereUI.PP
    if PP and PP.CreateBorder and PP.SetBorderColor then
        if not d.ppBorder then
            d.ppBorder = PP.CreateBorder(btn, r, g, b, a, look.brdSize, "OVERLAY", 2)
        end
        if PP.SetBorderSize then PP.SetBorderSize(btn, look.brdSize) end
        PP.SetBorderColor(btn, r, g, b, a)
        if d.ppBorder then d.ppBorder:SetShown(look.brdOn) end
    else
        local saveR, saveG, saveB, saveA = look.brdR, look.brdG, look.brdB, look.brdA
        look.brdR, look.brdG, look.brdB, look.brdA = r, g, b, a
        SetStripBorder(d, btn, look)
        look.brdR, look.brdG, look.brdB, look.brdA = saveR, saveG, saveB, saveA
    end
end

--------------------------------------------------------------------------------
--  Painting
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

local function StyleHighlights(btn, look)
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
        hl:SetAllPoints(btn)
        hl:SetAlpha((look.hlTex or look.hlWash > 0) and 1 or 0)
    end
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
        pt:SetAllPoints(btn)
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

local function FadeFrameArt(frame)
    if not frame then return end
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        local atlas = r and r.GetAtlas and r:GetAtlas()
        if atlas then
            local la = atlas:lower()
            for _, want in ipairs(FRAME_ATLASES) do
                if la:find(want, 1, true) then r:SetAlpha(0); break end
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Coexistence with EUI's own bag bar skin
--------------------------------------------------------------------------------
-- true while EllesmereUI's Bag Bar window skin is painting the buttons itself.
local function EUISkinActive()
    if not (EllesmereUI and EllesmereUI.IS_FOREVER and EllesmereUI.GetBlizzWindowStyle) then return false end
    local ok, style = pcall(EllesmereUI.GetBlizzWindowStyle, "bagbar")
    return ok and (style == "eui" or style == "modern")
end

--------------------------------------------------------------------------------
--  Apply
--------------------------------------------------------------------------------
local applied = false

local function PaintAll()
    if not DB.enabled or EUISkinActive() then return end
    local look = GetLook()
    FadeFrameArt(_G.BagsBar)
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
    applied = true
end

local pending
local function SchedulePaint()
    if pending then return end
    pending = true
    C_Timer.After(0, function() pending = nil; PaintAll() end)
end

local hooked = false
local function Install()
    if hooked then return end
    hooked = true
    local f = CreateFrame("Frame")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:SetScript("OnEvent", SchedulePaint)
    -- The keyring rebuilds its art in its own texture update: repaint right after.
    local kr = _G.KeyRingButton
    if kr and kr.UpdateTextures then
        hooksecurefunc(kr, "UpdateTextures", SchedulePaint)
    end
end

function DannerUIBags_Refresh()
    if EUISkinActive() then
        Print("EllesmereUI's own Bag Bar skin is active, so DannerUIBags stands down. " ..
              "Set Blizzard Skins+ > Window Skins > Bag Bar to Blizz Default (or Off), then /reload.")
        return
    end
    PaintAll()
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
                key = "BagBar",
                title = "Bag Bar Skin",
                description = "Gives the bag bar the same look as your action bar buttons.",
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
                            else Print("Disabled. /reload to restore the stock bag bar art.") end
                        end); y = y - h
                    _, h = W:Toggle(parent, "Match Action Bars look", y,
                        function() return DB.matchActionBars end,
                        function(v) DB.matchActionBars = v and true or false; DannerUIBags_Refresh() end); y = y - h
                    _, h = W:Toggle(parent, "Quality-coloured bag borders", y,
                        function() return DB.qualityBorders end,
                        function(v) DB.qualityBorders = v and true or false; DannerUIBags_Refresh() end); y = y - h
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
        if not DB.enabled then return end
        if EUISkinActive() then
            C_Timer.After(3, function()
                Print("EllesmereUI's own Bag Bar skin is active, so DannerUIBags stands down. " ..
                      "Set Blizzard Skins+ > Window Skins > Bag Bar to Blizz Default (or Off), then /reload.")
            end)
            return
        end
        Install()
        PaintAll()
        -- Blizzard builds some bag art a beat after login; one late pass catches it.
        C_Timer.After(1, PaintAll)
    end
end)

SLASH_DANNERUIBAGS1 = "/dbags"
SLASH_DANNERUIBAGS2 = "/danneruibags"
SlashCmdList.DANNERUIBAGS = function(msg)
    msg = (msg or ""):lower():match("^%s*(%S*)") or ""
    if msg == "on" then
        DB.enabled = true; Install(); DannerUIBags_Refresh(); Print("Enabled.")
    elseif msg == "off" then
        DB.enabled = false; Print("Disabled. /reload to restore the stock bag bar art.")
    elseif msg == "refresh" or msg == "" then
        DannerUIBags_Refresh()
        if msg == "" then
            Print("/dbags on | off | refresh | quality | match | config")
        end
    elseif msg == "quality" then
        DB.qualityBorders = not DB.qualityBorders; DannerUIBags_Refresh()
        Print("Quality borders " .. (DB.qualityBorders and "on" or "off") .. ".")
    elseif msg == "match" then
        DB.matchActionBars = not DB.matchActionBars; DannerUIBags_Refresh()
        Print("Match Action Bars look " .. (DB.matchActionBars and "on" or "off") .. ".")
    elseif msg == "config" then
        if EllesmereUI and EllesmereUI.OpenPlugin then EllesmereUI.OpenPlugin("DannerUIBags")
        else Print("EllesmereUI is not loaded.") end
    else
        Print("/dbags on | off | refresh | quality | match | config")
    end
end
