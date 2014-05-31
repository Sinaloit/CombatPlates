-----------------------------------------------------------------------------------------------
-- Client Lua Script for CombatPlates
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"

local CombatPlates = {}

CombatPlates.CodeEnumUnitState = {
	Ok = 1,
	Low = 2,
	Critical = 3,
	Vulnerable = 4,
	Dead = 5
}

-- a simplified version of showing / hiding certain parts of the nameplates - just three "versions" available
-- Standard is what you see on enemies, Info is what you see on friendly NPCs that may be useful,
-- Hidden is for "trash" friendly NPCs and will show up only on non full health and when targeted
CombatPlates.CodeEnumMode = {
	Standard = 1,
	Info = 2,
	Hidden = 3
}

local nAddonVersion = 10
local knNameplatePoolLimit	= 500 -- the window pool max size

local tDefaultSettings = {
	bDebug = false,
	nAddonVersion = nAddonVersion,
	nDrawDistance = 85,
	nHealthLowFraction = 0.55,
	nHealthCriticalFraction = 0.25,
	tColors = {
		tDisposition = {
			[Unit.CodeEnumDisposition.Friendly] = "ff21c36f",
			[Unit.CodeEnumDisposition.Neutral] = "ffffff14",
			[Unit.CodeEnumDisposition.Hostile] = "ffe50000",
			[Unit.CodeEnumDisposition.Unknown] = "ff0165fc",
		},
		tDispositionPlayerAlternate = {
			["t" .. Unit.CodeEnumDisposition.Friendly] = "ff40fd14",
			["f" .. Unit.CodeEnumDisposition.Hostile] = "fff97306"
		},
		tUnitState = {
			[CombatPlates.CodeEnumUnitState.Ok] = "ff15b01a",
			[CombatPlates.CodeEnumUnitState.Low] = "ffc1f80a",
			[CombatPlates.CodeEnumUnitState.Critical] = "ffe50000",
			[CombatPlates.CodeEnumUnitState.Vulnerable] = "ff720058",
			[CombatPlates.CodeEnumUnitState.Dead] = "ff000000"
		},
		tUnitCastingInfo = {
			[true] = "ff720058",
			[false] = "222a6c83"
		}
	},
	tClassNames = {
		[GameLib.CodeEnumClass.Engineer] = "Eng",
		[GameLib.CodeEnumClass.Esper] = "Esp",
		[GameLib.CodeEnumClass.Medic] = "Md",
		[GameLib.CodeEnumClass.Spellslinger] = "SS",
		[GameLib.CodeEnumClass.Stalker] = "Stk",
		[GameLib.CodeEnumClass.Warrior] = "War"
	},
	tIconsLimit = 4,
	tIconSize = 14,
	tIconWindowTop = 11
}
 
function CombatPlates:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 
	
    o.tUnitsBacklog = {}
    o.tResourcePool = {}
    o.tWindowLookup = {}

    return o
end

function CombatPlates:Init()
    Apollo.RegisterAddon(self)
end
 
--- load ---

function CombatPlates:OnLoad()
	self.tSettings = tDefaultSettings
	self:ConvertColorsToObjects()
	
	self.tNameplates = {}
	self.uPlayerUnit = nil
	self.uPlayerWindow = nil
	self.nTargetId = nil
	
	self.uXml = XmlDoc.CreateFromFile("CombatPlates.xml")
	Apollo.LoadSprites("CombatSprites.xml")
	
	-- basic events
	Apollo.RegisterEventHandler("UnitCreated", "OnUnitCreated", self)
	Apollo.RegisterEventHandler("UnitDestroyed", "OnUnitDestroyed", self)
	Apollo.RegisterEventHandler("ChangeWorld", "OnChangeWorld", self)
	Apollo.RegisterEventHandler("TargetUnitChanged", "OnTargetUnitChanged", self)

	-- this is a timer ~= 0.1 sec (at least on my computer)
	Apollo.RegisterEventHandler("VarChange_FrameCount", "UpdateAllNameplates", self)


	local tRewardUpdateEvents = {
		"QuestObjectiveUpdated", "QuestStateChanged", "ChallengeAbandon", "ChallengeLeftArea",
		"ChallengeFailTime", "ChallengeFailArea", "ChallengeActivate", "ChallengeCompleted",
		"ChallengeFailGeneric", "PublicEventObjectiveUpdate", "PublicEventUnitUpdate",
		"PlayerPathMissionUpdate", "FriendshipAdd", "FriendshipRemoved", "FriendshipUpdate" 
	}

	for nIndex, strEventName in pairs(tRewardUpdateEvents) do
		Apollo.RegisterEventHandler(strEventName, "UpdateAllNameplates", self)
	end
	
	-- icon update events
	Apollo.RegisterEventHandler("UnitActivationTypeChanged", "OnUnitActivationTypeChanged", self)

--[[ In Theory covered by above RewardUpdateEvents, need to verify
	Apollo.RegisterEventHandler("QuestInit", "UpdateAllNameplates", self)
	Apollo.RegisterEventHandler("PublicEventStart", "UpdateAllNameplates", self)
	Apollo.RegisterEventHandler("PublicEventEnd", "UpdateAllNameplates", self)
	Apollo.RegisterEventHandler("ChallengeUnlocked", "UpdateAllNameplates", self)
	Apollo.RegisterEventHandler("PlayerPathMissionUnlocked", "UpdateAllNameplates", self)
	Apollo.RegisterEventHandler("PlayerPathMissionUpdate", "UpdateAllNameplates", self)
	Apollo.RegisterEventHandler("PlayerPathMissionComplete", "UpdateAllNameplates", self)
	Apollo.RegisterEventHandler("PlayerPathMissionDeactivate", "UpdateAllNameplates", self)
	Apollo.RegisterEventHandler("PlayerPathMissionActivate", "UpdateAllNameplates", self)
--]]
end

--- main nameplate manipulation ---

function CombatPlates:AddNameplate(uUnit)
	local nUnitId = uUnit:GetId()
	
	if self.tNameplates[nUnitId] ~= nil then
		self:debug(nUnitId .. " - nameplate already added")
		return
	end
	
	local uNameplate = nil
	local wndReferences = nil
	if next(self.tResourcePool) ~= nil then
		local poolEntry = table.remove(self.tResourcePool)
		uNameplate = poolEntry[1]
		wndReferences = poolEntry[2]
	end
	
	if uNameplate == nil or not uNameplate:IsValid() then
		uNameplate = Apollo.LoadForm(self.uXml, "Nameplate", "InWorldHudStratum", self)
		wndReferences  = nil
	end
	
	uNameplate:Show(false, true)
	uNameplate:SetUnit(uUnit, 1)

	wndReferences = wndReferences or {
		BuffsLine	= uNameplate:FindChild("BuffsLine"),
		BuffsMinus	= uNameplate:FindChild("BuffsMinus"),
		LifeLine	= uNameplate:FindChild("LifeLine"),
		LifeBars 	= uNameplate:FindChild("LifeBars"),
		Sprint 		= uNameplate:FindChild("Sprint"),
		Health 		= uNameplate:FindChild("Health"),
		LifeText 	= uNameplate:FindChild("LifeText"),
		Shield 		= uNameplate:FindChild("Shield"),
		Absorption 	= uNameplate:FindChild("Absorption"),
		Name 		= uNameplate:FindChild("Name"),
		State 		= uNameplate:FindChild("State"),
		Guild 		= uNameplate:FindChild("Guild"),
		IconsLine 	= uNameplate:FindChild("IconsLine"),
		FlickerProtector = uNameplate:FindChild("FlickerProtector"),
		CastBar     = uNameplate:FindChild("CastBar")
	}

	wndReferences.Health:Show(true, true)

	wndReferences.BuffsMinus:SetUnit(uUnit)
	
	local uLifeBars = wndReferences.LifeBars
	self:MovePixieLineToFractionHorizontal(uLifeBars, 1, self.tSettings.nHealthCriticalFraction)
	self:MovePixieLineToFractionHorizontal(uLifeBars, 2, self.tSettings.nHealthLowFraction)
	
	local bIsMe = (nUnitId == self.uPlayerUnit:GetId())
	if bIsMe then
		wndReferences.Sprint:Show(true)
		local nLeft, nTop, nRight, nBottom = wndReferences.BuffsLine:GetAnchorOffsets()
		wndReferences.BuffsLine:SetAnchorOffsets(nLeft, nTop + 1, nRight, nBottom + 1)
	else
		wndReferences.Sprint:Show(false) -- Can we destroy? Possible could be recycled for us later.
	end
		
	self.tNameplates[nUnitId] = {
		window = uNameplate,
		unit = uUnit,
		isVisible = nil,
		lifeWidth = uLifeBars:GetWidth(),
		lifeHash = "",
		disposition = "",
		isMyTarget = false,
		isMe = bIsMe,
		unitState = nil,
		ccArmor = "",
		sprint = nil,
		icons = "",
		isImportant = nil,
		isWounded = nil,
		unitTypeString = "",
		bIsOver = true,
		measurement = nil,
		plateMode = self.CodeEnumMode.Standard,
		refs = wndReferences,
	}
	self:SetVisible(self.tNameplates[nUnitId], false)

	self.tWindowLookup[uNameplate:GetId()] = self.tNameplates[nUnitId]

	self:UpdateWholeNameplate(nUnitId)
end

-- because I have to use a timer anyway (not enough events), updating some information on existing events makes no sense,
-- it's actually more efficient to do that on a timer tick
function CombatPlates:UpdateAllNameplates()
	if self.uPlayerUnit == nil then
		self.uPlayerUnit = GameLib.GetPlayerUnit()
		
		if self.uPlayerUnit ~= nil then
			self:AddUnitsFromBacklog()
			self.uPlayerWindow = self.tNameplates[self.uPlayerUnit:GetId()].window
			self:OnTargetUnitChanged(GameLib.GetTargetUnit())
		end
		
		return
	end
	
	for nUnitId, tData in pairs(self.tNameplates) do
		self:UpdateNameplateEssentials(nUnitId)
	end
end

function CombatPlates:UpdateAllNameplateIcons()
	for nUnitId, tData in pairs(self.tNameplates) do
		self:UpdateIcons(nUnitId)
	end
end

function CombatPlates:RemoveNameplate(nUnitId)
	if self.tNameplates[nUnitId] == nil then
		self:debug(nUnitId .. " - nameplate already removed")
		return
	end

	local tNameplate = self.tNameplates[nUnitId]
	local wndNameplate = tNameplate.window
	
	self.tWindowLookup[wndNameplate:GetId()] = nil
	if #self.tResourcePool < knNameplatePoolLimit then
		wndNameplate:Show(false, true)
		wndNameplate:SetUnit(nil)
		tNameplate.refs.IconsLine:DestroyChildren()
		table.insert(self.tResourcePool, {wndNameplate, tNameplate.refs})
	else
		wndNameplate:Destroy()
	end

	self.tNameplates[nUnitId] = nil
end

--- main update methods ---

function CombatPlates:UpdateNameplateEssentials(nUnitId)
	local tData = self.tNameplates[nUnitId]
	
	local bShouldBeVisible = self:ShouldNameplateBeVisible(nUnitId)
	
	if tData.isVisible ~= bShouldBeVisible then
		self:SetVisible(tData, bShouldBeVisible)
	end
	
	if not tData.isVisible then
		return
	end
	
	local x, y = tData.window:GetPos()
	
	if y < 0 and tData.bIsOver then
		tData.measurement = Apollo.LoadForm(self.uXml, "Measurement", "InWorldHudStratum", self)
		tData.measurement:SetUnit(tData.unit, 1)
		tData.window:SetUnit(tData.unit, 0)
		tData.bIsOver = false
	elseif tData.measurement then
		local x, y = tData.measurement:GetPos()
		if y - 10 > 0 then
			tData.measurement:Destroy()
			tData.measurement = nil
			tData.window:SetUnit(tData.unit, 1)
			tData.bIsOver = true
		end
	end

	self:UpdateLife(nUnitId)
	self:UpdateUnitState(nUnitId)
	self:UpdateCCArmor(nUnitId)
	self:UpdateDisposition(nUnitId)
	self:UpdatePlateMode(nUnitId)
	if tData.isMe then
		self:UpdateSprint(nUnitId)
	end
end

function CombatPlates:UpdateTargetStatus(nUnitId, bIsTarget)
	local tData = self.tNameplates[nUnitId]
	
	if tData == nil then
		return
	end
	
	tData.isMyTarget = bIsTarget
	self:UpdateUnitTypeString(nUnitId)
	self:UpdateName(nUnitId)
end

-- can be used in emergency situations
function CombatPlates:UpdateWholeNameplate(nUnitId)
	self:UpdateUnitTypeString(nUnitId)
	self:UpdateNameplateEssentials(nUnitId)
	self:UpdateName(nUnitId)
	self:UpdateIcons(nUnitId)
end

--- nameplate partial updates - life ---

function CombatPlates:UpdateLife(nUnitId)
	local tData = self.tNameplates[nUnitId]
	local tLife = {
		tData.unit:GetHealth(), -- 1
		tData.unit:GetMaxHealth(), -- 2
		tData.unit:GetShieldCapacity(), -- 3
		tData.unit:GetShieldCapacityMax(), -- 4
		tData.unit:GetAbsorptionValue(), -- 5
--		tData.unit:GetAbsorptionMax() -- 6, Does anyone care about how much you used to have?
	}
	local sLifeHash = "n/a"
	if tLife[2] ~= nil and tLife[2] > 0 then
		sLifeHash = table.concat(tLife, "-")
	end
	
	if tData.lifeHash == sLifeHash then
		return
	end
	
	if sLifeHash == "n/a" then
		tData.refs.Health:Show(false)
		tData.refs.LifeText:SetText("")
		tData.isWounded = false
	else
		local nMaxLife = tLife[2] + tLife[4] + tLife[5]
		local nCurrentLife = tLife[1] + tLife[3] + tLife[5]
		tData.isWounded = (nMaxLife ~= nCurrentLife)
		
		if tData.lifeHash == "n/a" then
			tData.refs.Health:Show(true)
		end
		local nAvailableLife, nAvailableWidth = self:SetLifeBarWidth(tData.refs.Absorption, tLife[2] + tLife[5], tData.lifeWidth, tLife[5], tLife[5])
		self:SetShieldWidth(tData.refs.Shield, tLife[2], nAvailableWidth, tLife[4], tLife[3], 0)
		self:SetLifeBarWidth(tData.refs.Health, nAvailableLife, nAvailableWidth, tLife[2], tLife[1])
		
		tData.refs.LifeText:SetText(self:RenderShortNumber(tLife[1] + tLife[5]))
	end
	
	self.tNameplates[nUnitId].lifeHash = sLifeHash
end

function CombatPlates:SetShieldWidth(uWindow, nTotalNumber, nTotalPixels, nValueNumber, nCurrentNumber, nPixelsAdjustment)
	if nCurrentNumber == 0 then
		uWindow:SetAnchorOffsets(0, 0, 0, 0)
		return
	end
	
	local nValuePixels = math.ceil(nValueNumber / nTotalNumber * nTotalPixels)
	local nCurrentPixels = math.ceil(nCurrentNumber / nValueNumber * nValuePixels)
	
	if nCurrentPixels > nTotalPixels then
		nCurrentPixels = nTotalPixels
	end
	
	uWindow:SetAnchorOffsets(-(nCurrentPixels + nPixelsAdjustment), 0, -nPixelsAdjustment, 5)
end

function CombatPlates:SetLifeBarWidth(uWindow, nTotalNumber, nTotalPixels, nValueNumber, nCurrentNumber)
	if nCurrentNumber == 0 then
		uWindow:SetAnchorOffsets(0, 0, 0, 0)
		return nTotalNumber, nTotalPixels
	end
	
	local nValuePixels = math.ceil(nValueNumber / nTotalNumber * nTotalPixels)
	local nCurrentPixels = math.ceil(nCurrentNumber / nValueNumber * nValuePixels)
	
	uWindow:SetAnchorOffsets(0, 0, nCurrentPixels, 0)
	
	return nTotalNumber - nCurrentNumber, nTotalPixels - nCurrentPixels
end

function CombatPlates:UpdateDisposition(nUnitId)
	local tData = self.tNameplates[nUnitId]
	local nDisposition = tData.unit:GetDispositionTo(self.uPlayerUnit)
	local sDispHash = ""
	local sUnitType = tData.unit:GetType()
	
	if sUnitType == "Pet" then
		sDispHash = "p" .. nDisposition
	elseif sUnitType ~= "Player" then
		sDispHash = "x" .. nDisposition
	elseif tData.unit:IsPvpFlagged() then
		sDispHash = "t" .. nDisposition
	else
		sDispHash = "f" .. nDisposition
	end
	
	if tData.disposition == sDispHash then
		return
	end
	
	local uColor = self.tSettings.tColors.tDispositionPlayerAlternate[sDispHash]
	
	if uColor == nil then
		uColor = self.tSettings.tColors.tDisposition[nDisposition]
	end
	
	tData.refs.Health:SetBGColor(uColor)
	tData.disposition = sDispHash
end

--- nameplate partial updates - unit state ---

function CombatPlates:UpdateUnitState(nUnitId)
	local tData = self.tNameplates[nUnitId]
	local nVulnerabilityTime = tData.unit:GetCCStateTimeRemaining(Unit.CodeEnumCCState.Vulnerability)
	local nUnitState = self.CodeEnumUnitState.Ok
	local uStateWindow = tData.refs.State
	
	local nUnitMaxHealth = tData.unit:GetMaxHealth()
	local nLifeFraction = 1
	if nUnitMaxHealth ~= nil and nUnitMaxHealth > 0 then
		nLifeFraction = tData.unit:GetHealth() / tData.unit:GetMaxHealth()
	end
	
	if nVulnerabilityTime ~= nil and nVulnerabilityTime > 0 then
		nUnitState = self.CodeEnumUnitState.Vulnerable
		uStateWindow:SetText(string.format("%.1f", nVulnerabilityTime))
	elseif tData.unit:IsDead() then
		nUnitState = self.CodeEnumUnitState.Dead
		if tData.unitState ~= nUnitState then
			uStateWindow:SetText("xD")
		end
	elseif nLifeFraction <= self.tSettings.nHealthCriticalFraction then
		nUnitState = self.CodeEnumUnitState.Critical
	elseif nLifeFraction <= self.tSettings.nHealthLowFraction then
		nUnitState = self.CodeEnumUnitState.Low
	end
	
	if tData.unitState == nUnitState then
		return
	end
	
	if tData.unitState == self.CodeEnumUnitState.Dead then
		-- raised from the dead
		uStateWindow:SetText("")
	end
	
	uStateWindow:SetBGColor(self.tSettings.tColors.tUnitState[nUnitState])
	tData.unitState = nUnitState
end

function CombatPlates:UpdateCCArmor(nUnitId)
	local tData = self.tNameplates[nUnitId]
	
	if tData.unitState == self.CodeEnumUnitState.Vulnerable then
		if tData.ccArmor ~= "v" then
			tData.ccArmor = "v"
		end
		return
	end
	
	local nCcArmorMax = nil
	local nCcArmorCurrent = nil
	local nDashPercent = nil
	
	if tData.isMe then
		-- dash instead of interrupt armor
		nCcArmorMax = math.floor(tData.unit:GetMaxResource(7) / 100)
		nCcArmorCurrent = math.floor(tData.unit:GetResource(7) / 10) / 10
		nDashPercent = tData.unit:GetResource(7) % 100
	else
		nCcArmorMax = tData.unit:GetInterruptArmorMax()
		nCcArmorCurrent = tData.unit:GetInterruptArmorValue()
	end
	local bIsCasting = tData.unit:IsCasting()
	local sCcArmorHash = ""
	
	if bIsCasting and nCcArmorCurrent == 0 then
		sCcArmorHash = "c/" .. nCcArmorMax
	else
		sCcArmorHash = nCcArmorCurrent .. "/" .. nCcArmorMax
	end
	
	if bIsCasting then
		local nCastPercent = tData.unit:GetCastElapsed() / tData.unit:GetCastDuration()
		tData.refs.CastBar:SetProgress(nCastPercent)
	elseif tData.isMe and nDashPercent ~= 0 then
		bIsCasting = true
		tData.refs.CastBar:SetProgress(nDashPercent/100.0)
	end

	if tData.ccArmor == sCcArmorHash then
		return
	end
	
	if nCcArmorMax == -1 then
		tData.refs.State:SetText("inf")
	elseif bIsCasting and nCcArmorCurrent == 0 then
		tData.refs.State:SetText("!!")
	elseif nCcArmorMax ~= 0 then
		tData.refs.State:SetText(math.floor(nCcArmorCurrent))
	else
		tData.refs.State:SetText("")
	end
	
	tData.refs.CastBar:SetBGColor(self.tSettings.tColors.tUnitCastingInfo[bIsCasting])
	tData.ccArmor = sCcArmorHash
end

--- nameplate partial updates - name ---

function CombatPlates:UpdateName(nUnitId)
	local tData = self.tNameplates[nUnitId]
	local bFullName = tData.isMyTarget
	local sLevel = tData.unit:GetLevel() or "n/a"
	local sType = tData.unitTypeString
	local sName = ""
	
	if bFullName then
		sName = tData.unit:GetTitleOrName()
	else
		sName = tData.unit:GetName()
	end
	
	if sLevel ~= "n/a" then
		if sType ~= "" then
			sType = " " .. sType
		end
		tData.refs.Name:SetText(string.format("%s%s: %s", sLevel, sType, sName))
	else
		if sType ~= "" then
			sType = sType .. ": "
		end
		tData.refs.Name:SetText(string.format("%s%s", sType, sName))
	end
	
	local uGuildWindow = tData.refs.Guild
	local sGuild = tData.unit:GetGuildName()
	local sAffiliation = tData.unit:GetAffiliationName()
	
	if bFullName then
		if sGuild ~= nil and sGuild ~= "" then
			uGuildWindow:SetTextRaw("<" .. sGuild .. ">")
		elseif sAffiliation ~= nil and sAffiliation ~= "" then
			uGuildWindow:SetTextRaw(sAffiliation)
		else
			uGuildWindow:SetTextRaw("<-->")
		end
		uGuildWindow:Show(true)
	else
		uGuildWindow:SetText("")
		uGuildWindow:Show(false)
	end
end

function CombatPlates:UpdateUnitTypeString(nUnitId)
	local tData = self.tNameplates[nUnitId]
	local uUnit = tData.unit
	local sUnitType = uUnit:GetType()
	
	if sUnitType == "Player" then
		tData.isImportant = true
		tData.unitTypeString = self.tSettings.tClassNames[uUnit:GetClassId()]
		return
	end
	
	if sUnitType == "Pet" then
		tData.isImportant = true
		tData.unitTypeString = sUnitType
		return
	end
	
	local tUnitTypes = {}
	local nEliteness = uUnit:GetEliteness()
	local nRank = uUnit:GetRank()
	local tActivationState = uUnit:GetActivationState()
	local bIsBoss = false
	
	-- rank and eliteness check
	
	if nRank ~= Unit.CodeEnumRank.Elite and nRank ~= Unit.CodeEnumRank.Superior then
		-- nothing special here
	elseif nEliteness == Unit.CodeEnumEliteness.LargeRaid then
		if nRank == Unit.CodeEnumRank.Elite then 
			-- I'm guessing that's a standard elite unit, like city guard etc, not a boss
			table.insert(tUnitTypes, "Elite")
		else
			-- Other weird situations
			table.insert(tUnitTypes, "Semi-Elite")
		end
	elseif nEliteness == Unit.CodeEnumEliteness.SmallRaid then
		-- Perhaps that's an open world raid boss?
		table.insert(tUnitTypes, "Raid Boss")
		bIsBoss = true
	elseif nEliteness == Unit.CodeEnumEliteness.Group then
		-- those may or may not be bosses in instances and small open world ones
		if nRank == Unit.CodeEnumRank.Elite then
			table.insert(tUnitTypes, "Boss")
		else
			table.insert(tUnitTypes, "Mini-Boss")
		end
		bIsBoss = true
	end
	
	-- activation states check
	
	local bQuestNameAdded = false
	local bHasActivationState = false
	for sActivationName, tData in pairs(tActivationState) do
		if sActivationName:find("Quest") then
			if not bQuestNameAdded then
				table.insert(tUnitTypes, "Quest")
				bQuestNameAdded = true
			end
		else
			table.insert(tUnitTypes, sActivationName)
		end
		bHasActivationState = true
	end
	
	-- unit importance
	
	tData.isImportant = (bIsBoss or bHasActivationState)
	
	tData.unitTypeString = table.concat(tUnitTypes, ", ")
end

--- nameplate partial updates - icons, target marks, etc. ---

function CombatPlates:UpdateIcons(nUnitId)
	local tData = self.tNameplates[nUnitId]
	local tRewards = tData.unit:GetRewardInfo()
	local tAllIcons = {[""] = false, Quest = false, Challenge = false, PublicEvent = false, Soldier = false, Settler = false, Explorer = false, Scientist = false, ScientistSpell = false}
	local tIcons = {}
	local nIconsCount = 0
	
	if tRewards then
		for i, tRewardInfo in pairs(tRewards) do
			tAllIcons[self:GetIconTypeForReward(tRewardInfo)] = true
		end
		for sName, bEnabled in pairs(tAllIcons) do
			if bEnabled and sName ~= "" then
				table.insert(tIcons, sName)
				nIconsCount = nIconsCount + 1
			end
		end
	end
	
	local sIconsHash = table.concat(tIcons, "/")
	
	if sIconsHash == tData.icons then
		return
	end
	
	local uIconsWindow = tData.refs.IconsLine
	uIconsWindow:DestroyChildren()
	tData.icons = sIconsHash
	
	if nIconsCount == 0 then
		return
	end
	
	if nIconsCount <= self.tSettings.tIconsLimit then
		local nLeft, nTop, nRight, nBottom = uIconsWindow:GetAnchorOffsets()
		uIconsWindow:SetAnchorOffsets(nLeft, self.tSettings.tIconWindowTop + math.floor(self.tSettings.tIconSize / 2 * (self.tSettings.tIconsLimit - nIconsCount)), nRight, nBottom)
	end
	
	for i, sName in pairs(tIcons) do
		Apollo.LoadForm(self.uXml, "IconsShowcase." .. sName, uIconsWindow, self)
	end
	uIconsWindow:ArrangeChildrenVert()
end

function CombatPlates:GetIconTypeForReward(tRewardInfo)
	local sIconType = tRewardInfo.strType
	
	if sIconType == "Scientist" and tRewardInfo.splReward then
		return "ScientistSpell"
	end
	
	if sIconType == "Challenge" then
		-- that is a really terrible code copied from the original Nameplates, I shouldn't have to check that!
		local tAllChallenges = ChallengesLib.GetActiveChallengeList()
		for i, uChallengeData in pairs(tAllChallenges) do
			if tRewardInfo.idChallenge == uChallengeData:GetId() and uChallengeData:IsActivated() and not uChallengeData:IsInCooldown() and not uChallengeData:ShouldCollectReward() then
				return sIconType
			end
		end
		
		return ""
	end
	
	return sIconType
end

--- nameplate partial updates - self specifics ---

function CombatPlates:UpdateSprint(nUnitId)
	local tData = self.tNameplates[nUnitId]
	local nSprintMax = tData.unit:GetMaxResource(0)
	local nSprintCurrent = tData.unit:GetResource(0)
	local sSprintHash = nSprintCurrent .. "/" .. nSprintMax
	
	if tData.sprint == sSprintHash then
		return
	end
	
	local uSprintWindow = tData.refs.Sprint
	uSprintWindow:SetMax(nSprintMax)
	uSprintWindow:SetProgress(nSprintCurrent)
	
	tData.sprint = sSprintHash
end

--- conditions checks ---

function CombatPlates:ShouldNameplateBeVisible(nUnitId)
	local tData = self.tNameplates[nUnitId]
	local bCheckOccl = true
	
	if self.uPlayerWindow ~= nil then
		if self.uPlayerWindow:IsOccluded() then
			bCheckOccl = false
		end
	end
	
	return tData.window:IsOnScreen()
		and ((not bCheckOccl) or (not tData.window:IsOccluded()) or tData.unit:IsMounted())
		and tData.plateMode ~= self.CodeEnumMode.Hidden
		and (self:GetDistanceTo(tData.unit) <= self.tSettings.nDrawDistance or tData.isMyTarget)
end

--- nameplate partial updates - plate mode ---

function CombatPlates:UpdatePlateMode(nUnitId)
	local tData = self.tNameplates[nUnitId]
	local nPlateMode = self.CodeEnumMode.Standard
	
	if not tData.isWounded and not tData.isMe and not tData.isMyTarget and tData.disposition == "x2" then
		if tData.isImportant then
			nPlateMode = self.CodeEnumMode.Info
		else
			nPlateMode = self.CodeEnumMode.Hidden
		end
	end
	
	if tData.plateMode == nPlateMode then
		return
	end
	
	if tData.plateMode == self.CodeEnumMode.Hidden and self:ShouldNameplateBeVisible(nUnitId) then
		self:SetVisible(tData, true)
	elseif nPlateMode == self.CodeEnumMode.Hidden and tData.isVisible then
		self:SetVisible(tData, false)
	end
	
	if nPlateMode ~= self.CodeEnumMode.Hidden then
		local bShowLines = (nPlateMode == self.CodeEnumMode.Standard)
		tData.refs.LifeLine:Show(bShowLines)
		tData.refs.BuffsLine:Show(bShowLines)
		tData.refs.IconsLine:Show(bShowLines)
	end
	
	tData.plateMode = nPlateMode
end

function CombatPlates:SetVisible(tData, bIsVisible)
	tData.isVisible = bIsVisible
	tData.window:Show(bIsVisible)
	tData.refs.FlickerProtector:Show(bIsVisible)
end

--- generic helpers ---

function CombatPlates:GetDistanceTo(uUnit)
	local tPos1 = self.uPlayerUnit:GetPosition()
		
	local tPos2 = uUnit:GetPosition()

	return math.sqrt(math.pow(tPos1.x - tPos2.x, 2) + math.pow(tPos1.y - tPos2.y, 2) + math.pow(tPos1.z - tPos2.z, 2))
end

function CombatPlates:RenderShortNumber(nValue)
	if nValue < 1000 then
		return nValue
	end
	if nValue < 100000 then
		return string.format("%.1fk", math.ceil(nValue / 100) / 10)
	end
	if nValue < 1000000 then
		return math.ceil(nValue / 1000) .. "k"
	end
	if nValue < 10000000 then
		return string.format("%.1fm", math.ceil(nValue / 100000) / 10)
	end
	return math.ceil(nValue / 1000000) .. "m"
end

function CombatPlates:MovePixieLineToFractionHorizontal(uWindow, nPixieId, nFraction)
	local tPixie = uWindow:GetPixieInfo(nPixieId)
	
	local nOffset = uWindow:GetWidth() * nFraction
	if nOffset % 1 < 0.5 then
		nOffset = math.floor(nOffset)
	else
		nOffset = math.ceil(nOffset)
	end
	
	tPixie.loc.nOffsets[1] = nOffset
	tPixie.loc.nOffsets[3] = nOffset
	
	uWindow:UpdatePixie(nPixieId, tPixie)
end

--- update events - main ---

function CombatPlates:OnChangeWorld()
	self.uPlayerUnit = nil
end

function CombatPlates:OnUnitCreated(uUnit)
	if not uUnit:ShouldShowNamePlate()
		or uUnit:GetType() == "Mount"
		or uUnit:GetType() == "Plug"
		or uUnit:GetType() == "Simple"
		or uUnit:GetType() == "Collectible" 
		or uUnit:GetType() == "PinataLoot" then
		-- this type of unit will never have a nameplate
		return
	end

	local nUnitId = uUnit:GetId()

	if self.uPlayerUnit == nil then
		self.tUnitsBacklog[nUnitId] = uUnit
		--Print("Backlogged " .. nUnitId .. " (" .. uUnit:GetName() .. ")")
		return
	end

	-- why some units have this???
	--if --[[not uUnit:ShouldShowNamePlate() or--]] uUnit:GetType() == "Mount" or uUnit:GetType() == "Plug" or uUnit:GetType() == "Simple" then
		-- this unit will never have a nameplate
	--	return
	--end

	if self.tNameplates[nUnitId] ~= nil then
		-- unit already exists
		--Print("Added " .. nUnitId .. " (" .. uUnit:GetName() .. ")")
		return
	end

	self:AddNameplate(uUnit)
end

function CombatPlates:OnUnitDestroyed(uUnit)
	local nUnitId = uUnit:GetId()

	if self.uPlayerUnit == nil then
		self.tUnitsBacklog[nUnitId] = nil
		return
	end

	if self.tNameplates[nUnitId] == nil then
		return
	end

	self:RemoveNameplate(nUnitId)
end

function CombatPlates:AddUnitsFromBacklog()
	for nUnitId, uUnit in pairs(self.tUnitsBacklog) do
		if uUnit:IsValid() then
			self:OnUnitCreated(uUnit)
		end
	end
	
	self.tUnitsBacklog = {}
end

function CombatPlates:OnWorldLocationOnScreen(uHandler, uControl, bOnScreen)
	self:UpdateNameplateEssentials(uHandler:GetUnit():GetId())
end

function CombatPlates:OnTargetUnitChanged(uUnit)
	if uUnit == nil then
		if self.nTargetId ~= nil then
			self:UpdateTargetStatus(self.nTargetId, false)
			self.nTargetId = nil
		end
		return
	end
	
	local nUnitId = uUnit:GetId()
	
	if self.nTargetId == nUnitId then
		return
	end
	
	if self.nTargetId ~= nil then
		self:UpdateTargetStatus(self.nTargetId, false)
	end
	
	self:UpdateTargetStatus(nUnitId, true)
	if self.tNameplates[nUnitId] ~= nil then
		self:UpdatePlateMode(nUnitId)
	end
	self.nTargetId = nUnitId
end

--- update events - icon updates ---


function CombatPlates:OnUnitActivationTypeChanged(uUnit)
	local nUnitId = uUnit:GetId()
	if self.tNameplates[nUnitId] == nil then
		return
	end
	
	self:UpdateWholeNameplate(nUnitId)
end


--- one time updates ---
function CombatPlates:ConvertColorsToObjects()
	for i, tList in pairs(self.tSettings.tColors) do
		for j, tColor in pairs(tList) do
			tList[j] = ApolloColor.new(tColor)
		end
	end
end

--- Event Handlers ---
function CombatPlates:OnTarget( wndHandler, wndControl, eMouseButton)
	if wndHandler == wndControl then
		local idUnit = wndHandler:GetId()
		if self.tWindowLookup[idUnit] == nil or eMouseButton ~= GameLib.CodeEnumInputMouse.Left then
			return
		end
		
		local unitOwner = self.tWindowLookup[idUnit].unit
		if GameLib.GetTargetUnit() ~= unitOwner then
			GameLib.SetTargetUnit(unitOwner)
		end
		return true
	end
end

--- debug ---

function CombatPlates:debug(...)
	if not self.tSettings.bDebug then
		return
	end
	
	if arg.n == 1 then
		Print(arg[1])
		return
	end
	
	for i, value in pairs(arg) do
		if i ~= "n" then
			Print(value)
		end
	end
end

function CombatPlates:dump(name, value)
	SendVarToRover(name, value)
end

--- create object ---

local CombatPlatesInst = CombatPlates:new()
CombatPlatesInst:Init()
