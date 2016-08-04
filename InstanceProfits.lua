-- TODO: Fix when logging in/out/reloading in an instance
-- TODO: Check for player repairing inside dungeon
-- TODO: Refactor and clean code into multiple LUA files
-- TODO: OPT: Add Auction Value option
-- TODO: OPT: Add option to enable/disable when in a group

---------
-- new --
---------
local strmatch, strgsub = string.match, string.gsub

local isInPvEInstance = false

local IGNORED_ZONES = { [1152]=true, [1330]=true, [1153]=true, [1154]=true, [1158]=true, [1331]=true, [1159]=true, [1160]=true };
local LOOT_ITEM_PATTERN = strgsub(LOOT_ITEM_SELF, "%%s", "(.+)")
local LOOT_ITEM_MULTIPLE_PATTERN = strgsub(strgsub(LOOT_ITEM_SELF_MULTIPLE, "%%s", "(.+)"), "%%d", "(%%d+)")
local LOOT_ITEM_PUSHED_PATTERN = strgsub(LOOT_ITEM_PUSHED_SELF, "%%s", "(.+)")
local LOOT_ITEM_PUSHED_MULTIPLE_PATTERN = strgsub(strgsub(LOOT_ITEM_PUSHED_SELF_MULTIPLE, "%%s", "(.+)"), "%%d", "(%%d+)")
local FILTER_BUTTONS = {}
local filteredDifficulties, tempFilters, globalSortedInstances, characterSortedInstances = {}, {}, {}, {}
local sortDir, tempSortDir = "nameA", "nameA"
local scrollframe, scrollbar = {}, {}

---------
-- old --
---------

local enteredAlive = true
instanceName, instanceDifficulty, instanceDifficultyName, startTime, startRepair = nil, nil, nil, 0, 0;
characterHistory, globalHistory, contentButtons, detailButtons = {}, {}, {}, {};
content, detailedContent = nil, nil;
contentButtonFrame, detailButtonFrame = nil, nil;
displayGlobal = false;
liveName = nil;
liveDifficulty = nil;
liveTime = nil;
liveLoot = nil;
liveVendor = nil;
detailedHeader, charDetails, acctDetails = nil, nil, nil;
local lootableItems = {};
local elapsedTime, lootedMoney, vendorMoney = 0, 0, 0;
local version = "0.5.1";
local repairTooltip = nil;

local frame = CreateFrame("FRAME", "InstanceProfitsFrame");
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA");
frame:RegisterEvent("PLAYER_ENTERING_WORLD");
frame:RegisterEvent("ADDON_LOADED");
frame:RegisterEvent("PLAYER_LOGOUT");
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED");

-- loot
frame:RegisterEvent("CHAT_MSG_LOOT");
frame:RegisterEvent("CHAT_MSG_MONEY");

function IP_PrintWelcomeMessage()
	print("|cFF00CCFF<IP>|r Instance Profit Tracker v. " .. version .. " loaded.");
	print("|cFF00CCFF<IP>|r Use \"/ip\" or \"/instanceprofit\" to display saved profit data.");
	print("|cFF00CCFF<IP>|r Use \"/ip live\" or \"/instanceprofit live\" to display the live tracker.");
end

function IP_CalculateRepairCost()
	repairTooltip = repairTooltip or CreateFrame("GameTooltip");
	local slots = {'HEADSLOT', 'NECKSLOT', 'SHOULDERSLOT',
	'BACKSLOT', 'CHESTSLOT', 'WRISTSLOT', 'HANDSSLOT',
	'WAISTSLOT', 'LEGSSLOT', 'FEETSLOT', 'FINGER0SLOT',
	'FINGER1SLOT', 'TRINKET0SLOT', 'TRINKET1SLOT',
	'MAINHANDSLOT', 'SECONDARYHANDSLOT'};
	local totalRepairCost = 0;
	for i, slot in ipairs(slots) do
		repairTooltip:ClearLines();
		local slotId, _ = GetInventorySlotInfo(slot);
		local hasItem, _, repairCost = repairTooltip:SetInventoryItem("player", slotId);
		if ((hasItem) and (repairCost) and (repairCost > 0)) then
			totalRepairCost = totalRepairCost + repairCost;
		end
	end
	return totalRepairCost;
end

function copperToString(copper)
	local gold = math.floor(copper/10000);
	local silver = math.floor((copper - gold*10000)/100);
	local remains = copper % 100;
	local lootedString = gold .. " gold, " .. silver .. " silver, and " .. remains .. " copper";
	return lootedString;
end

function timeToSmallString(seconds)
	local hours = math.floor(seconds/3600);
	seconds = seconds - (hours  * 3600);
	local minutes = math.floor(seconds/60);
	seconds = seconds - (minutes * 60);
	if hours < 10 then
		hours = "0" .. hours;
	end
	if minutes < 10 then
		minutes = "0" .. minutes;
	end
	if seconds < 10 then
		seconds = "0" .. seconds;
	end
	return hours .. ":" .. minutes .. ":" .. seconds;
end

function IsDungeonPartiallyCompleted()
	local _, _, numCriteria = C_Scenario.GetStepInfo()
	for i=1,numCriteria do
		if select(3,C_Scenario.GetCriteriaInfo(i)) then
			return true -- something completed
		end
	end
	return false;
end

function IP_ShowLiveTracker()
	InstanceProfits_LiveDisplay:Show();
	liveName = liveName or InstanceProfits_LiveDisplay:CreateFontString(nil, "ARTWORK","SystemFont_Small");
	liveDifficulty = liveDifficulty or InstanceProfits_LiveDisplay:CreateFontString(nil, "ARTWORK","SystemFont_Small");
	liveTime = liveTime or InstanceProfits_LiveDisplay:CreateFontString(nil, "ARTWORK","SystemFont_Small");
	liveLoot = liveLoot or InstanceProfits_LiveDisplay:CreateFontString(nil, "ARTWORK","SystemFont_Small");
	liveVendor = liveVendor or InstanceProfits_LiveDisplay:CreateFontString(nil, "ARTWORK","SystemFont_Small");
	liveName:SetText(instanceName);
	liveDifficulty:SetText(instanceDifficultyName);
	liveTime:SetText(liveTime:GetText() or "Time: 00:00:00");
	liveLoot:SetText("Looted: " .. GetMoneyString(lootedMoney));
	liveVendor:SetText("Vendor: " .. GetMoneyString(vendorMoney));
	local ofsy = -5;
	liveName:SetPoint("TOPLEFT", 5, ofsy);
	ofsy = ofsy - liveName:GetStringHeight() - 5;
	liveDifficulty:SetPoint("TOPLEFT", 5, ofsy);
	ofsy = ofsy - liveDifficulty:GetStringHeight() - 5;
	liveTime:SetPoint("TOPLEFT", 5, ofsy);
	ofsy = ofsy - liveTime:GetStringHeight() - 5;
	liveLoot:SetPoint("TOPLEFT", 5, ofsy);
	ofsy = ofsy - liveLoot:GetStringHeight() - 5;
	liveVendor:SetPoint("TOPLEFT", 5, ofsy);
end

function triggerInstance(name, difficulty, difficultyName, incCount)
	if incCount then
		startTime = time();
		instanceName = name;
		instanceDifficulty = difficulty;
		instanceDifficultyName = difficultyName;
		startRepair = IP_CalculateRepairCost();
		lootedMoney, vendorMoney = 0, 0;
	end
	local n = GetNumSavedInstances();
	local saved = IsDungeonPartiallyCompleted();
	if not saved then
		for i=1, n do
			local savedName, saveId, resets, savedDifficulty, locked = GetSavedInstanceInfo(i);
			if (savedName == instanceName and locked and difficulty > 1) then
				saved = true;
			end
		end
	end
	if (not saved and incCount) then
		if (characterHistory[name] == nil) then
			characterHistory[name] = {
				[difficultyName] = {
					['count'] = 1,
					['totalTime'] = 0,
					['totalRepair'] = 0,
					['totalLoot'] = 0,
					['totalVendor'] = 0
				}
			};
		elseif (characterHistory[name][difficultyName] == nil) then
			characterHistory[name][difficultyName] = {
				['count'] = 1,
				['totalTime'] = 0,
				['totalRepair'] = 0,
				['totalLoot'] = 0,
				['totalVendor'] = 0
			};
		else
			characterHistory[name][difficultyName]['count'] = characterHistory[name][difficultyName]['count'] + 1;
		end
		if (globalHistory[name] == nil) then
			globalHistory[name] = {
				[difficultyName] = {
					['count'] = 1,
					['totalTime'] = 0,
					['totalRepair'] = 0,
					['totalLoot'] = 0,
					['totalVendor'] = 0
				}
			};
		elseif (globalHistory[name][difficultyName] == nil) then
			globalHistory[name][difficultyName] = {
				['count'] = 1,
				['totalTime'] = 0,
				['totalRepair'] = 0,
				['totalLoot'] = 0,
				['totalVendor'] = 0
			};
		else
			globalHistory[name][difficultyName]['count'] = globalHistory[name][difficultyName]['count'] + 1;
		end
	end
	IP_ShowLiveTracker();
	print("You have entered the " .. difficultyName .. " version of " .. name);
	print("You have recorded your profits for this instance " .. characterHistory[name][difficultyName]['count'] .. " times on this character.");
	print("You have recorded your profits for this instance " .. globalHistory[name][difficultyName]['count'] .. " times on this account.");
end

function IP_DeleteInstanceData(instance, difficulty)
	if not displayGlobal then
		for key, value in pairs(characterHistory[instance][difficulty]) do
			globalHistory[instance][difficulty][key] = globalHistory[instance][difficulty][key] - value;
		end
		if (globalHistory[instance][difficulty]["count"] == 0) then
			globalHistory[instance][difficulty] = nil;
		end
		characterHistory[instance][difficulty] = nil;
	end
end

function IP_DisplaySavedData()
	content = content or CreateFrame("Frame", nil, scrollframe[1]);
	contentButtonFrame = contentButtonFrame or CreateFrame("Frame", nil, content);
	contentButtonFrame:SetAllPoints(true);
	contentButtonFrame:SetWidth(20);
	detailButtonFrame = detailButtonFrame or CreateFrame("Frame", nil, content);
	detailButtonFrame:SetAllPoints(true);
	detailButtonFrame:SetWidth(20);
	content.text = content.text or content:CreateFontString(nil,"ARTWORK","SystemFont_Med1")
	content:SetHeight(10000);
	content:SetWidth(450);
	content.text:SetAllPoints(true)
	content.text:SetJustifyH("LEFT")
	content.text:SetJustifyV("TOP")
	content.text:SetTextColor(0,.8,1,1)
	local dataString = "\n";
	local i, j = 0, 0;
	local r, p, t = 0, 0, 0;
	if displayGlobal then
		local offy = 8
		for index, instance in pairs(globalSortedInstances) do
			data = globalHistory[instance]
			local firstPrint = true;
			for difficulty, values in pairs(data) do
				if filteredDifficulties[difficulty] == true then
					if firstPrint then									
						dataString = dataString .. instance .. "\n";
						j = j + 1;
						detailButtons[j] = detailButtons[j] or CreateFrame("Button", nil, detailButtonFrame, "UIPanelButtonTemplate");
						------------------------
						-- ElvUI Skin Support --
						------------------------
						if (IsAddOnLoaded("ElvUI") or IsAddOnLoaded("Tukui")) then
						  local c;
						  if ElvUI then
							local E, L, V, P, G, DF = unpack(ElvUI);
							c = E;
						  else
							local T, C, L, G = unpack(Tukui);
							c = T;
							c.TexCoords = {.08, .92, .08, .92};
						  end
						  local S = c:GetModule('Skins');
						  S:HandleButton(detailButtons[j]);
						end
						detailButtons[j]:SetPoint("TOPRIGHT", 0, offy * -1);
						detailButtons[j]:SetText("Details");
						detailButtons[j]:SetSize(60, 20);
						detailButtons[j]:SetNormalFontObject("GameFontNormal");
						detailButtons[j]:SetScript("OnClick", function(self, button, down)
							IP_ShowDetails(instance);
						end);
						detailButtons[j].tooltip_text = "View enhanced details of saved data for " .. instance;
						detailButtons[j]:SetScript("OnEnter", IP_TippedButtonOnEnter)
						detailButtons[j]:SetScript("OnLeave", IP_TippedButtonOnLeave)
						detailButtons[j]:Show();
						firstPrint = false;
					end
					dataString = dataString .. "    (" .. difficulty .. ") | " .. values['count'] .. " | " .. GetMoneyString(values['totalLoot'] + values['totalVendor'] - values['totalRepair']) .. " | " .. timeToSmallString(values['totalTime']) .. "\n";
					r = r + values['count']
					p = p + values['totalLoot'] + values['totalVendor'] - values['totalRepair']
					t = t + values['totalTime']
					content.text:SetText(dataString)
					offy = content.text:GetStringHeight() - 14;
				end
			end
			if not firstPrint then
				dataString = dataString .. "\n";
				content.text:SetText(dataString)
				offy = content.text:GetStringHeight() - 14;
			end
		end
		contentButtonFrame:Hide();
		detailButtonFrame:Show();
	else
		contentButtonFrame:Show();
		detailButtonFrame:Show();
		local offy = 8;
		for index, instance in pairs(characterSortedInstances) do
			data = characterHistory[instance]
			local firstPrint = true;
			for difficulty, values in pairs(data) do
				if filteredDifficulties[difficulty] == true then
					if firstPrint then
						dataString = dataString .. "       " .. instance .. "\n";
						j = j + 1;
						detailButtons[j] = detailButtons[j] or CreateFrame("Button", nil, detailButtonFrame, "UIPanelButtonTemplate");
						------------------------
						-- ElvUI Skin Support --
						------------------------
						if (IsAddOnLoaded("ElvUI") or IsAddOnLoaded("Tukui")) then
						  local c;
						  if ElvUI then
							local E, L, V, P, G, DF = unpack(ElvUI);
							c = E;
						  else
							local T, C, L, G = unpack(Tukui);
							c = T;
							c.TexCoords = {.08, .92, .08, .92};
						  end
						  local S = c:GetModule('Skins');
						  S:HandleButton(detailButtons[j]);
						end
						detailButtons[j]:SetPoint("TOPRIGHT", 0, offy * -1);
						detailButtons[j]:SetText("Details");
						detailButtons[j]:SetSize(60, 20);
						detailButtons[j]:SetNormalFontObject("GameFontNormal");
						detailButtons[j]:SetScript("OnClick", function(self, button, down)
							IP_ShowDetails(instance);
						end);
						detailButtons[j].tooltip_text = "View enhanced details of saved data for " .. instance;
						detailButtons[j]:SetScript("OnEnter", IP_TippedButtonOnEnter)
						detailButtons[j]:SetScript("OnLeave", IP_TippedButtonOnLeave)
						detailButtons[j]:Show();
						firstPrint = false;
					end
					i = i + 1;
					contentButtons[i] = contentButtons[i] or CreateFrame("Button", nil, contentButtonFrame, "UIPanelButtonTemplate");
					contentButtons[i]:SetPoint("TOPLEFT", 0, offy * -1);---28 * i + 16 + i * 4);
					contentButtons[i]:SetText("X");
					contentButtons[i]:SetSize(16, 16);
					contentButtons[i]:SetNormalFontObject("GameFontNormal");
					contentButtons[i]:SetScript("OnClick", function(self, button, down)
						StaticPopupDialogs["IP_Confirm_Delete"].OnAccept = function() 
							IP_DeleteInstanceData(instance, difficulty);
							IP_DisplaySavedData();
						end
						StaticPopup_Show("IP_Confirm_Delete", instance .. " (" .. difficulty .. ")");
					end);
					contentButtons[i].tooltip_text = "Delete saved data for " .. instance .. " (" .. difficulty .. ") for " .. GetUnitName("player");
					contentButtons[i]:SetScript("OnEnter", IP_TippedButtonOnEnter)
					contentButtons[i]:SetScript("OnLeave", IP_TippedButtonOnLeave)
					contentButtons[i]:Show();
					dataString = dataString .. "              (" .. difficulty .. ") " .. values['count'] .. " | " .. GetMoneyString(values['totalLoot'] + values['totalVendor'] - values['totalRepair']) .. " | " .. timeToSmallString(values['totalTime']) .. "\n";
					r = r + values['count']
					p = p + values['totalLoot'] + values['totalVendor'] - values['totalRepair']
					t = t + values['totalTime']
					content.text:SetText(dataString)
					offy = content.text:GetStringHeight() - 14;
				end
			end
			if not firstPrint then
				dataString = dataString .. "\n";
				content.text:SetText(dataString)
				offy = content.text:GetStringHeight() - 14;
			end
		end
		for k=i+1, table.getn(contentButtons) do
			-- We deleted some instance data, so we have some extra buttons
			contentButtons[k]:Hide();
		end
	end
	for l=j+1, table.getn(detailButtons) do
		-- We deleted some instance data, so we have some extra buttons
		detailButtons[l]:Hide();
	end
	dataString = dataString .. "Totals: \n           Runs: " .. r .. "\n           Profit: " .. GetMoneyString(p) .. "\n           Time: " .. timeToSmallString(t) .. "\n\n"
	content.text:SetText(dataString)
	local scrollMax = content.text:GetStringHeight();
	if scrollMax > 613 then
		scrollbar[1]:Show();
		scrollMax = scrollMax - 612;
	else
		scrollbar[1]:Hide();
		scrollMax = 1;
	end
	scrollbar[1]:SetMinMaxValues(1, scrollMax)
	scrollframe[1]:SetScrollChild(content)
end

function IP_TippedButtonOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(self.tooltip_text, nil, nil, nil, nil, true);
	GameTooltip:Show();
end

function IP_TippedButtonOnLeave()
	GameTooltip:Hide();
end

function IP_ToggleDisplayGlobal()
	displayGlobal = not displayGlobal;
	if (displayGlobal) then
		InstanceProfits_TableDisplay_ButtonToggleData:SetText("Show Character Data");
	else
		InstanceProfits_TableDisplay_ButtonToggleData:SetText("Show Account Data");
	end
	IP_DisplaySavedData();
end

function IP_UpdateTime(self, elapsed)
	elapsedTime = elapsedTime + elapsed;
	if (not isInPvEInstance) then
		if startTime > 0 and not enteredAlive then
			-- We were in an instance, but aren't anymore because we died. Don't count time spent dead as time in instance
			if elapsedTime >= 1 then
				elapsedTime = elapsedTime - 1
				startTime = startTime + 1
			end
		else
			elapsedTime = 0;
		end
	elseif (elapsedTime >= 1) then
		if instanceDifficultyName == nil or instanceDifficultyName == "" then
			name, typeOfInstance, instanceDifficulty, instanceDifficultyName, _, _, _, _, _ = GetInstanceInfo();
			liveDifficulty:SetText(instanceDifficultyName);
			triggerInstance(name, instanceDifficulty, instanceDifficultyName, enteredAlive);
		end
		elapsedTime = elapsedTime - 1;
		liveTime:SetText("Time: " .. timeToSmallString(difftime(time(), startTime)));
	end
end

function saveInstanceData()
	local totalTime = difftime(time(), startTime);
	local endRepair = IP_CalculateRepairCost();
	characterHistory[instanceName][instanceDifficultyName]['totalTime'] = characterHistory[instanceName][instanceDifficultyName]['totalTime'] + totalTime;
	characterHistory[instanceName][instanceDifficultyName]['totalRepair'] = characterHistory[instanceName][instanceDifficultyName]['totalRepair'] + (endRepair - startRepair);
	characterHistory[instanceName][instanceDifficultyName]['totalLoot'] = characterHistory[instanceName][instanceDifficultyName]['totalLoot'] + lootedMoney;
	characterHistory[instanceName][instanceDifficultyName]['totalVendor'] = characterHistory[instanceName][instanceDifficultyName]['totalVendor'] + vendorMoney;
	globalHistory[instanceName][instanceDifficultyName]['totalTime'] = globalHistory[instanceName][instanceDifficultyName]['totalTime'] + totalTime;
	globalHistory[instanceName][instanceDifficultyName]['totalRepair'] = globalHistory[instanceName][instanceDifficultyName]['totalRepair'] + (endRepair - startRepair);
	globalHistory[instanceName][instanceDifficultyName]['totalLoot'] = globalHistory[instanceName][instanceDifficultyName]['totalLoot'] + lootedMoney;
	globalHistory[instanceName][instanceDifficultyName]['totalVendor'] = globalHistory[instanceName][instanceDifficultyName]['totalVendor'] + vendorMoney;
	if (characterHistory[instanceName][instanceDifficultyName]['fastestRun'] == nil or characterHistory[instanceName][instanceDifficultyName]['fastestRun'] > totalTime) then
		characterHistory[instanceName][instanceDifficultyName]['fastestRun'] = totalTime
	end
	if (characterHistory[instanceName][instanceDifficultyName]['mostLoot'] == nil or characterHistory[instanceName][instanceDifficultyName]['mostLoot'] < lootedMoney) then
		characterHistory[instanceName][instanceDifficultyName]['mostLoot'] = lootedMoney
	end
	if (characterHistory[instanceName][instanceDifficultyName]['mostVendor'] == nil or characterHistory[instanceName][instanceDifficultyName]['mostVendor'] < vendorMoney) then
		characterHistory[instanceName][instanceDifficultyName]['mostVendor'] = vendorMoney
	end
	if (globalHistory[instanceName][instanceDifficultyName]['fastestRun'] == nil or globalHistory[instanceName][instanceDifficultyName]['fastestRun'] > totalTime) then
		globalHistory[instanceName][instanceDifficultyName]['fastestRun'] = totalTime
	end
	if (globalHistory[instanceName][instanceDifficultyName]['mostLoot'] == nil or globalHistory[instanceName][instanceDifficultyName]['mostLoot'] < lootedMoney) then
		globalHistory[instanceName][instanceDifficultyName]['mostLoot'] = lootedMoney
	end
	if (globalHistory[instanceName][instanceDifficultyName]['mostVendor'] == nil or globalHistory[instanceName][instanceDifficultyName]['mostVendor'] < vendorMoney) then
		globalHistory[instanceName][instanceDifficultyName]['mostVendor'] = vendorMoney
	end
	local timeString = math.floor(totalTime/60) .. " minutes and " .. (totalTime % 60) .. " seconds";
	local lootedString = copperToString(lootedMoney);
	print("You have exited your instance after spending " .. timeString .. " inside.");
	print("You earned " .. lootedString .. " from mobs");
	print("and " .. copperToString(vendorMoney) .. " from looted items that you can vendor.");
	print("Your gear will take " .. copperToString(endRepair - startRepair) .. " to be repaired. This makes your total profit " .. copperToString(lootedMoney + vendorMoney - (endRepair - startRepair)));
	IP_SortData(sortDir);
	IP_DisplaySavedData();
end

function IP_ClearCharacterData()
	for instance, data in pairs(characterHistory) do
		for difficulty, values in pairs(data) do
			globalHistory[instance][difficulty]['totalTime'] = globalHistory[instance][difficulty]['totalTime'] - values['totalTime'];
			globalHistory[instance][difficulty]['totalRepair'] = globalHistory[instance][difficulty]['totalRepair'] - values['totalRepair'];
			globalHistory[instance][difficulty]['totalLoot'] = globalHistory[instance][difficulty]['totalLoot'] - values['totalLoot'];
			globalHistory[instance][difficulty]['totalVendor'] = globalHistory[instance][difficulty]['totalVendor'] - values['totalVendor'];
			globalHistory[instance][difficulty]['count'] = globalHistory[instance][difficulty]['count'] - values['count'];
			if (globalHistory[instance][difficulty]["count"] == 0) then
				globalHistory[instance][difficulty] = nil;
			end
		end
	end
	characterHistory = {};
	IP_SortData(sortDir);
	IP_DisplaySavedData();
end

function IP_ShowFilters()
	InstanceProfits_FilterOptions:Show();
	InstanceProfits_FilterOptions:SetFrameStrata("HIGH")
	InstanceProfits_FilterOptions:Raise()
	table.foreach(FILTER_BUTTONS, 
		function(k,v) 
			if filteredDifficulties[k] == true then
				_G[v]:SetChecked(true)
			else
				_G[v]:SetChecked(false)
			end
		end
	)
end

function IP_Checkbutton_OnLoad(checkbutton, difficultyNum)
	local name = GetDifficultyInfo(difficultyNum);
	FILTER_BUTTONS[name] = checkbutton:GetName();
	_G[checkbutton:GetName() .. "Text"]:SetText(name);
	filteredDifficulties[name] = true
	tempFilters[name] = true
end

function IP_Checkbutton_OnClick(checkbutton)
	local name = _G[checkbutton:GetName() .. "Text"]:GetText();
	if checkbutton:GetChecked() == true then
		tempFilters[name] = true
	else
		tempFilters[name] = false
	end
end

function IP_FilterApply()
	table.foreach(tempFilters, 
		function(k,v) 
			filteredDifficulties[k] = v
		end
	)
	sortDir = tempSortDir;
	InstanceProfits_FilterOptions:Hide();
	InstanceProfits_TableDisplay:Show();
	IP_SortData(sortDir)
	IP_DisplaySavedData();
end

function IP_FilterCancel()
	table.foreach(filteredDifficulties, 
		function(k,v) 
			tempFilters[k] = v
		end
	)
	if tempSortDir ~= sortDir then
		tempSortDir = sortDir;
		UIDropDownMenu_SetSelectedValue(UIDROPDOWNMENU_OPEN_MENU, sortDir);
	end
	InstanceProfits_FilterOptions:Hide();
end

function IP_SortData(field)
	characterSortedInstances = {}
	globalSortedInstances = {}
	for n in pairs(characterHistory) do table.insert(characterSortedInstances, n) end
	for n in pairs(globalHistory) do table.insert(globalSortedInstances, n) end
	if field == "nameA" then
		table.sort(characterSortedInstances)
		table.sort(globalSortedInstances)
	elseif field == "nameD" then
		table.sort(characterSortedInstances, function(a,b) return a > b end)
		table.sort(globalSortedInstances, function(a,b) return a > b end)
	elseif field == "timeA" then 
		table.sort(globalSortedInstances, 
			function(a,b)
				local timeA = 0
				local timeB = 0
				for difficulty, data in pairs(globalHistory[a]) do
					timeA = timeA + data["totalTime"]
				end
				for difficulty, data in pairs(globalHistory[b]) do
					timeB = timeB + data["totalTime"]
				end
				return timeA < timeB;
			end
		)
		table.sort(characterSortedInstances, 
			function(a,b)
				local timeA = 0
				local timeB = 0
				for difficulty, data in pairs(characterHistory[a]) do
					timeA = timeA + data["totalTime"]
				end
				for difficulty, data in pairs(characterHistory[b]) do
					timeB = timeB + data["totalTime"]
				end
				return timeA < timeB;
			end
		)
		elseif field == "timeD" then 
		table.sort(globalSortedInstances, 
			function(a,b)
				local timeA = 0
				local timeB = 0
				for difficulty, data in pairs(globalHistory[a]) do
					timeA = timeA + data["totalTime"]
				end
				for difficulty, data in pairs(globalHistory[b]) do
					timeB = timeB + data["totalTime"]
				end
				return timeA > timeB;
			end
		)
		table.sort(characterSortedInstances, 
			function(a,b)
				local timeA = 0
				local timeB = 0
				for difficulty, data in pairs(characterHistory[a]) do
					timeA = timeA + data["totalTime"]
				end
				for difficulty, data in pairs(characterHistory[b]) do
					timeB = timeB + data["totalTime"]
				end
				return timeA > timeB;
			end
		)
	elseif field == "profitA" then 
		table.sort(globalSortedInstances, 
			function(a,b)
				local profitA = 0
				local profitB = 0
				for difficulty, data in pairs(globalHistory[a]) do
					profitA = profitA + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				for difficulty, data in pairs(globalHistory[b]) do
					profitB = profitB + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				return profitA < profitB;
			end
		)
		table.sort(characterSortedInstances, 
			function(a,b)
				local profitA = 0
				local profitB = 0
				for difficulty, data in pairs(characterHistory[a]) do
					profitA = profitA + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				for difficulty, data in pairs(characterHistory[b]) do
					profitB = profitB + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				return profitA < profitB;
			end
		)
	elseif field == "profitD" then 
		table.sort(globalSortedInstances, 
			function(a,b)
				local profitA = 0
				local profitB = 0
				for difficulty, data in pairs(globalHistory[a]) do
					profitA = profitA + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				for difficulty, data in pairs(globalHistory[b]) do
					profitB = profitB + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				return profitA > profitB;
			end
		)
		table.sort(characterSortedInstances, 
			function(a,b)
				local profitA = 0
				local profitB = 0
				for difficulty, data in pairs(characterHistory[a]) do
					profitA = profitA + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				for difficulty, data in pairs(characterHistory[b]) do
					profitB = profitB + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				return profitA > profitB;
			end
		)
	end
end

function IP_BuildSortDropdown()
	local info = UIDropDownMenu_CreateInfo();
	info.text = "Name (Asc)";
	info.value = "nameA";
	info.func = IP_SortSelect;
	UIDropDownMenu_AddButton(info)
	info = UIDropDownMenu_CreateInfo();
	info.text = "Name (Desc)";
	info.value = "nameD";
	info.func = IP_SortSelect;
	UIDropDownMenu_AddButton(info)
	info = UIDropDownMenu_CreateInfo();
	info.text = "Profit (Asc)";
	info.value = "profitA";
	info.func = IP_SortSelect;
	UIDropDownMenu_AddButton(info)
	info = UIDropDownMenu_CreateInfo();
	info.text = "Profit (Desc)";
	info.value = "profitD";
	info.func = IP_SortSelect;
	UIDropDownMenu_AddButton(info)
	info = UIDropDownMenu_CreateInfo();
	info.text = "Time (Asc)";
	info.value = "timeA";
	info.func = IP_SortSelect;
	UIDropDownMenu_AddButton(info)
	info = UIDropDownMenu_CreateInfo();
	info.text = "Time (Desc)";
	info.value = "timeD";
	info.func = IP_SortSelect;
	UIDropDownMenu_AddButton(info)
end

function IP_SortSelect(self, arg1, arg2, checked)
	if not checked then
		UIDropDownMenu_SetSelectedValue(UIDROPDOWNMENU_OPEN_MENU, self.value);
		tempSortDir = self.value;
	end
end

function copperToSmallString(copper) 
	local goldString = "";
	if copper < 0 then
		copper = math.abs(copper);
		goldString = "";
	end
	local gold = math.floor(copper/10000);
	copper = copper - gold * 10000;
	local silver = math.floor(copper/100);
	copper = copper - silver * 100;
	goldString = goldString .. gold .. "|TInterface\\MoneyFrame\\UI-GoldIcon:10:10:0:-7|t" .. silver .. "|TInterface\\MoneyFrame\\UI-SilverIcon:10:10:0:-7|t" .. copper .. "|TInterface\\MoneyFrame\\UI-CopperIcon:10:10:0:-7|t";
	return goldString;
end

function IP_ShowDetails(instanceName)
	detailedContent = detailedContent or CreateFrame("Frame", nil, scrollframe[2]);
	detailedContent:SetHeight(10000);
	detailedContent:SetWidth(550);
	InstanceProfits_DetailedDisplay:Show()
	InstanceProfits_DetailedDisplay:SetFrameStrata("HIGH")
	InstanceProfits_DetailedDisplay:Raise()
	detailedHeader = detailedHeader or InstanceProfits_DetailedDisplay:CreateFontString(nil, "ARTWORK","SystemFont_Huge2");
	charDetails = charDetails or detailedContent:CreateFontString(nil, "ARTWORK","NumberFontNormal");
	acctDetails = acctDetails or detailedContent:CreateFontString(nil, "ARTWORK","NumberFontNormal");
	local charText = GetUnitName("player") .. "\n";
	local acctText = "Account\n";
	local runs, vendor, loot, repair, seconds, difficulties = 0, 0, 0, 0, 0, 0
	if characterHistory[instanceName] ~= nil then
		for difficulty, data in pairs(characterHistory[instanceName]) do
			if difficulty ~= "" then
				charText = charText .. "\n";
				difficulties = difficulties + 1
				runs = runs + data["count"]
				vendor = vendor + data["totalVendor"]
				loot = loot + data["totalLoot"]
				repair = repair + data["totalRepair"]
				seconds = seconds + data["totalTime"]
				charText = charText .. difficulty .. "\n" ..  data["count"] .. " runs in " .. math.floor(data["totalTime"]/60) .. " minutes and " .. (data["totalTime"] % 60) .. " seconds\n";
				charText = charText .. "Vendor Price of Items: " .. copperToSmallString(data["totalVendor"]) .. "\n";
				charText = charText .. "Gold Looted: " .. copperToSmallString(data["totalLoot"]) .. "\n";
				charText = charText .. "Cost to Repair: " .. copperToSmallString(data["totalRepair"]) .. "\n";
				charText = charText .. "Average Profit per Run: " .. copperToSmallString(math.floor((data["totalVendor"] + data["totalLoot"] - data["totalRepair"])/data["count"])) .. "\n";
				charText = charText .. "Average Profit per Hour: " .. copperToSmallString(math.floor((data["totalVendor"] + data["totalLoot"] - data["totalRepair"])/(data["totalTime"]/3600))) .. "\n";
			end
		end
		if difficulties > 1 then
			charText = charText .. "\nGrand Total\n" ..  runs .. " runs in " .. math.floor(seconds/60) .. " minutes and " .. (seconds % 60) .. " seconds\n";
			charText = charText .. "Vendor Price of Items: " .. copperToSmallString(vendor) .. "\n";
			charText = charText .. "Gold Looted: " .. copperToSmallString(loot) .. "\n";
			charText = charText .. "Cost to Repair: " .. copperToSmallString(repair) .. "\n";
			charText = charText .. "Average Profit per Run: " .. copperToSmallString(math.floor((vendor + loot - repair)/runs)) .. "\n";
			charText = charText .. "Average Profit per Hour: " .. copperToSmallString(math.floor((vendor + loot - repair)/(seconds/3600))) .. "\n";
		end
	end
	runs, vendor, loot, repair, seconds, difficulties = 0, 0, 0, 0, 0, 0
	if globalHistory[instanceName] ~= nil then
		for difficulty, data in pairs(globalHistory[instanceName]) do
			if difficulty ~= "" then
			acctText = acctText .. "\n";
			difficulties = difficulties + 1
			runs = runs + data["count"]
			vendor = vendor + data["totalVendor"]
			loot = loot + data["totalLoot"]
			repair = repair + data["totalRepair"]
			seconds = seconds + data["totalTime"]
			acctText = acctText .. difficulty .. "\n" ..  data["count"] .. " runs in " .. math.floor(data["totalTime"]/60) .. " minutes and " .. (data["totalTime"] % 60) .. " seconds\n";
			acctText = acctText .. "Vendor Price of Items: " .. copperToSmallString(data["totalVendor"]) .. "\n";
			acctText = acctText .. "Gold Looted: " .. copperToSmallString(data["totalLoot"]) .. "\n";
			acctText = acctText .. "Cost to Repair: " .. copperToSmallString(data["totalRepair"]) .. "\n";
			acctText = acctText .. "Average Profit per Run: " .. copperToSmallString(math.floor((data["totalVendor"] + data["totalLoot"] - data["totalRepair"])/data["count"])) .. "\n";
			acctText = acctText .. "Average Profit per Hour: " .. copperToSmallString(math.floor((data["totalVendor"] + data["totalLoot"] - data["totalRepair"])/(data["totalTime"]/3600))) .. "\n";
			end
		end
		if difficulties > 1 then
			acctText = acctText .. "\nGrand Total\n" ..  runs .. " runs in " .. math.floor(seconds/60) .. " minutes and " .. (seconds % 60) .. " seconds\n";
			acctText = acctText .. "Vendor Price of Items: " .. copperToSmallString(vendor) .. "\n";
			acctText = acctText .. "Gold Looted: " .. copperToSmallString(loot) .. "\n";
			acctText = acctText .. "Cost to Repair: " .. copperToSmallString(repair) .. "\n";
			acctText = acctText .. "Average Profit per Run: " .. copperToSmallString(math.floor((vendor + loot - repair)/runs)) .. "\n";
			acctText = acctText .. "Average Profit per Hour: " .. copperToSmallString(math.floor((vendor + loot - repair)/(seconds/3600))) .. "\n";
		end
	end
	detailedHeader:SetText(instanceName);
	charDetails:SetText(charText);
	acctDetails:SetText(acctText);
	local ofsy = -30;
	detailedHeader:SetPoint("TOP", 0, ofsy);
	ofsy = ofsy - detailedHeader:GetStringHeight();
	charDetails:SetPoint("TOPLEFT", 15, 0);
	acctDetails:SetPoint("TOPRIGHT", -15, 0);
	local scrollMax = acctDetails:GetStringHeight();
	if scrollMax > 353 then
		scrollbar[2]:Show();
		scrollMax = scrollMax - 353;
	else
		scrollbar[2]:Hide();
		scrollMax = 1;
	end
	scrollbar[2]:SetMinMaxValues(1, scrollMax)
	scrollframe[2]:SetScrollChild(detailedContent)
end

function IP_InitScrollFrames()
	local scrollableFrames = {"InstanceProfits_TableDisplay", "InstanceProfits_DetailedDisplay"}
	for i, frameName in pairs(scrollableFrames) do
		--scrollframe
		scrollframe[i] = CreateFrame("ScrollFrame", nil, _G[frameName])
		scrollframe[i]:SetPoint("TOPLEFT", 10, -60)
		scrollframe[i]:SetPoint("BOTTOMRIGHT", -10, 45)
		scrollframe[i]:SetSize(500, 650)
		scrollframe[i]:EnableMouseWheel(true)

		--scrollbar
		scrollbar[i] = CreateFrame("Slider", nil, scrollframe[i], "UIPanelScrollBarTemplate")
		scrollbar[i]:SetPoint("TOPLEFT", _G[frameName], "TOPRIGHT", 4, -16)
		scrollbar[i]:SetPoint("BOTTOMLEFT", _G[frameName], "BOTTOMRIGHT", 4, 16)
		scrollbar[i]:SetMinMaxValues(1, 200)
		scrollbar[i]:SetValueStep(1)
		scrollbar[i].scrollStep = 1
		scrollbar[i]:SetValue(0)
		scrollbar[i]:SetWidth(16)
		scrollbar[i]:SetScript("OnValueChanged",
			function (self, value)
				self:GetParent():SetVerticalScroll(value)
			end
		)
		local scrollbg = scrollbar[i]:CreateTexture(nil, "BACKGROUND")
		scrollbg:SetAllPoints(scrollbar[i])
		scrollbg:SetTexture(0, 0, 0, 0.4)
		scrollframe[i]:SetScript("OnMouseWheel", function(self, delta)
			local current = scrollbar[i]:GetValue()

			if IsShiftKeyDown() and (delta > 0) then
			  scrollbar[i]:SetValue(0)
			elseif IsShiftKeyDown() and (delta < 0) then
			  scrollbar[i]:SetValue(200)
			elseif (delta < 0) then
			  scrollbar[i]:SetValue(current + 20)
			elseif (delta > 0) and (current > 1) then
			  scrollbar[i]:SetValue(current - 20)
			end
		end)
	end
end

function eventHandler(self, event, ...)
	local arg1, arg2 = ...
	if event == "ADDON_LOADED" and arg1 == "InstanceProfits" then
		------------------------
		-- ElvUI Skin Support --
		------------------------
		if (IsAddOnLoaded("ElvUI") or IsAddOnLoaded("Tukui")) then
		  local c;
		  if ElvUI then
			local E, L, V, P, G, DF = unpack(ElvUI);
			c = E;
		  else
			local T, C, L, G = unpack(Tukui);
			c = T;
			c.TexCoords = {.08, .92, .08, .92};
		  end
		  local S = c:GetModule('Skins');
		  
		  -- Skin the InstanceProfits_LiveDisplay Frame and all Buttons
		  InstanceProfits_LiveDisplay:SetHeight(90);
		  InstanceProfits_LiveDisplay_ButtonClose:ClearAllPoints();
		  InstanceProfits_LiveDisplay_ButtonClose:SetPoint("TOPRIGHT", InstanceProfits_LiveDisplay, "TOPRIGHT", -5, -5);
		  InstanceProfits_LiveDisplay_ButtonDetails:ClearAllPoints();
		  InstanceProfits_LiveDisplay_ButtonDetails:SetPoint("TOPRIGHT", InstanceProfits_LiveDisplay, "TOPRIGHT", -5, -25);
		  InstanceProfits_LiveDisplay_ButtonDetails:SetWidth(16)
		  InstanceProfits_LiveDisplay_ButtonDetails:SetHeight(16)
		  InstanceProfits_LiveDisplay_ButtonDetails.Text:SetText("H")
		  InstanceProfits_LiveDisplay:StripTextures(true);
		  InstanceProfits_LiveDisplay:CreateBackdrop("Transparent");
		  S:HandleButton(InstanceProfits_LiveDisplay_ButtonClose);
		  S:HandleButton(InstanceProfits_LiveDisplay_ButtonDetails);
		  
		  -- Skin the InstanceProfits_TableDisplay Frame, all Buttons and the Scroll Bar
		  InstanceProfits_TableDisplay:StripTextures(true);
		  InstanceProfits_TableDisplay:CreateBackdrop("Transparent");
		  S:HandleButton(InstanceProfits_TableDisplay_TitleBar_ButtonClose);
		  InstanceProfits_TableDisplay_TitleBar:SetBackdropColor(128/255, 128/255, 128/255, 0.75);
		  InstanceProfits_TableDisplay_TitleBar_TitleString:SetTextColor(1, 1, 1);
		  S:HandleButton(InstanceProfits_TableDisplay_ButtonToggleData);
		  S:HandleButton(InstanceProfits_TableDisplay_ButtonClose);
		  S:HandleButton(InstanceProfits_TableDisplay_ButtonFilter);
		  S:HandleButton(InstanceProfits_TableDisplay_ButtonResetChar);
		  
		  -- Skin the InstanceProfits_FilterOptions Frame and all Buttons
		  InstanceProfits_FilterOptions:StripTextures(true);
		  InstanceProfits_FilterOptions:CreateBackdrop("Transparent");
		  InstanceProfits_FilterOptions_TitleBar:SetBackdropColor(128/255, 128/255, 128/255, 0.75);
		  InstanceProfits_FilterOptions_TitleBar_TitleString:SetTextColor(1, 1, 1);
		  S:HandleButton(InstanceProfits_FilterOptions_TitleBar_ButtonClose);
		  S:HandleButton(InstanceProfits_FilterOptions_ButtonSave);
		  S:HandleDropDownBox(InstanceProfits_FilterOptions_SortDropDown);
		  S:HandleCheckBox(InstanceProfits_FilterOptionsNormalFilter);
		  S:HandleCheckBox(InstanceProfits_FilterOptionsHeroicFilter);
		  S:HandleCheckBox(InstanceProfits_FilterOptionsTenManFilter);
		  S:HandleCheckBox(InstanceProfits_FilterOptionsTwentyFiveFilter);
		  S:HandleCheckBox(InstanceProfits_FilterOptionsTenHeroicFilter);
		  S:HandleCheckBox(InstanceProfits_FilterOptionsTwentyFiveHeroicFilter);
		  
		  -- Skin the InstanceProfits_DetailedDisplay Frame and all Buttons
		  InstanceProfits_DetailedDisplay:StripTextures(true);
		  InstanceProfits_DetailedDisplay:CreateBackdrop("Transparent");
		  S:HandleButton(InstanceProfits_DetailedDisplay_ButtonClose);
		  
		end
		instanceName = "|cFFFF0000Not in instance|r";
		instanceDifficultyName = instanceName;
		InstanceProfits_TableDisplay:Hide();
		InstanceProfits_LiveDisplay:Hide();
		InstanceProfits_FilterOptions:Hide();
		InstanceProfits_DetailedDisplay:Hide()

		characterHistory = _G["IP_InstanceRunsCharacterHistory"] or {};
		globalHistory = _G["IP_InstanceRunsGlobalHistory"] or {};
		filteredDifficulties = _G["IP_DifficultyFilters"] or filteredDifficulties;

		IP_PrintWelcomeMessage();
		IP_InitScrollFrames();
		
		IP_SortData("nameA")
		StaticPopupDialogs["IP_Confirm_Delete"] = {
			text = "Are you sure you want to delete all data for %s? This action cannot be undone.",
			button1 = "Yes",
			button2 = "No",
			OnAccept = function() end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3
		}						

		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_ENTERING_WORLD" then
		local inInstance, instanceType = IsInInstance()
		local wasInPvEInstance = isInPvEInstance
		isInPvEInstance = inInstance and (instanceType == "party" or instanceType == "raid")

		if isInPvEInstance then -- entered instance
			local name, typeOfInstance, difficulty, difficultyName, _, _, _, instanceMapId = GetInstanceInfo()

			if not IGNORED_ZONES[instanceMapId] then
				triggerInstance(name, difficulty, difficultyName, enteredAlive);
			end
			enteredAlive = true
		else -- entered something else
			if wasInPvEInstance ~= isInPvEInstance then -- we actually left instance
				enteredAlive = not UnitIsDeadOrGhost("player"); -- Check if we were a ghost when exiting
				if enteredAlive then
					saveInstanceData();
				end
			end
		end
	elseif event == "CHAT_MSG_LOOT" and isInPvEInstance then
		local itemLink, quantity = strmatch(arg1, LOOT_ITEM_MULTIPLE_PATTERN)
		if not itemLink then
			itemLink, quantity = strmatch(arg1, LOOT_ITEM_PUSHED_MULTIPLE_PATTERN)
			if not itemLink then
				quantity, itemLink = 1, strmatch(arg1, LOOT_ITEM_PATTERN)
				if not itemLink then
					quantity, itemLink = 1, strmatch(arg1, LOOT_ITEM_PUSHED_PATTERN)
					if not itemLink then
						return
					end
				end
			end
		end

		quantity = tonumber(quantity or 1)
		local name, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemLink)

		if name then
			vendorMoney = vendorMoney + (vendorPrice * quantity)
		else
			lootableItems[name] = (lootableItems[name] or 0) + quantity;
		end

		liveVendor:SetText("Vendor: " .. GetMoneyString(vendorMoney))
	elseif event == "GET_ITEM_INFO_RECEIVED" and isInPvEInstance then
		local name, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(arg1);
		vendorMoney = vendorMoney + (vendorPrice * (lootableItems[name] or 0));
		lootableItems[name] = 0;

		liveVendor:SetText("Vendor: " .. GetMoneyString(vendorMoney))
	elseif event == "CHAT_MSG_MONEY" and isInPvEInstance then
		local goldPattern = GOLD_AMOUNT:gsub('%%d', '(%%d*)')
		local silverPattern = SILVER_AMOUNT:gsub('%%d', '(%%d*)')
		local copperPattern = COPPER_AMOUNT:gsub('%%d', '(%%d*)')
		local gold = tonumber(string.match(arg1, goldPattern) or 0)
		local silver = tonumber(string.match(arg1, silverPattern) or 0)
		local copper = tonumber(string.match(arg1, copperPattern) or 0)
		lootedMoney = lootedMoney + (gold * 100 * 100) + (silver * 100) + copper
		liveLoot:SetText("Looted: " .. GetMoneyString(lootedMoney));
	elseif event == "PLAYER_LOGOUT" then
		if isInPvEInstance or not enteredAlive then
			saveInstanceData();
		end
		_G["IP_InstanceRunsCharacterHistory"] = characterHistory;
		_G["IP_InstanceRunsGlobalHistory"] = globalHistory;
		_G["IP_DifficultyFilters"] = filteredDifficulties;
	end
end
frame:SetScript("OnEvent", eventHandler);

SLASH_INSTANCEPROFITS1, SLASH_INSTANCEPROFITS2, SLASH_INSTANCEPROFITS3 = '/ip', '/instanceprofit', '/instanceprofits';
function SlashCmdList.INSTANCEPROFITS(msg, editbox)
	if msg == 'live' then
		IP_ShowLiveTracker();
	elseif msg == 'filter' then
		IP_ShowFilters()
	else
		InstanceProfits_TableDisplay:Show();
		IP_DisplaySavedData();
	end
end
