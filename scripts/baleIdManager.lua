--=======================================================================================================
-- BaleIdManager SCRIPT
--
-- Purpose:		Configure farmOwnerId for newly pressed bales
-- Author:		[F/A] derelky / Mmtrx
-- Changelog:
--  v1.0.0.0	initial by [F/A] derelky
--	v1.0.0.1	The filllevel of the baler can now be reset to 0, e.g. so you won't get a straw bale when you start with hay. The reset function is button in the GUI menu.
--				The currently active farm for which the bales are and the associated bale counter are displayed in the F1 menu.
--				In single player mode only the Farm1 counter, reset button, and baler empty button are active.
--				Problem solved that in combination with straw harvest no bale net was used
--				Added empty baler function
--				Stripped down menu with bale counter and clear baler for single player mode
--
--  v2.0.0.0	05.07.2023  (Mmtrx) adapted for FS22
--  v2.0.0.1	29.07.2023  external control (Göweil). Loaner indicator in farm list
--  v2.0.0.2	29.12.2023  compatible with moreNumFarms
--=======================================================================================================
baleIdManager = {}
baleIdManager.ModName = g_currentModName
baleIdManager.ModDirectory = g_currentModDirectory
baleIdManager.eventName = {}
baleIdManager.Version = "2.0.0.2"

addModEventListener(baleIdManager)

function baleIdManager.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Baler, specializations)
end

function baleIdManager.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getBaleFarm", baleIdManager.getBaleFarm)
    SpecializationUtil.registerFunction(vehicleType, "updateFarmID", baleIdManager.updateFarmID)
end

function baleIdManager.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "createBale", baleIdManager.createBale)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "dropBale", baleIdManager.dropBale)

    --SpecializationUtil.registerOverwrittenFunction(vehicleType, "onHUDInfoTriggerCallback", baleIdManager.onHUDInfoTriggerCallback)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "onBalerExternalControlCallback", baleIdManager.onBalerExternalControlCallback)
end

function baleIdManager.registerEventListeners(vehicleType)
	local functionNames = {	"onRegisterActionEvents", "onDraw", "onLoad", "saveToXMLFile", "onWriteStream","onReadStream" }
	
	for _, functionName in ipairs(functionNames) do
		SpecializationUtil.registerEventListener(vehicleType, functionName, baleIdManager)
	end
end

-------------------- event listeners -------------------------------------------------------
function baleIdManager:onLoad(savegame)
	debugPrint("* onLoad(savegame) %s %s",savegame,BaleIdManagerGuiloader.Gui.mTable.id)
	local spec = self.spec_baleidmanager	
	spec.FarmID = self:getOwnerFarmId()
	spec.FarmIDs = {}
	spec.ContractActive = false
	spec.balecounter = {}
	for i=1, FarmManager.MAX_NUM_FARMS do
		spec.balecounter[i] = 0
	end
	self.testing = BaleIdManagerGuiloader.Gui.testing 
	
	if self.testing then 
		spec.isMultiplayer = true  -- testing
	else
		spec.isMultiplayer = g_currentMission.missionDynamicInfo.isMultiplayer
	end
	if savegame ~= nil then
		local xmlFile = savegame.xmlFile
		local FarmID = savegame.key..".baleIdManager#FarmID"
		local UseContr = savegame.key..".baleIdManager#UseContr"
		
		local i = 0
            while true do
                local key = string.format("%s.baleIdManager.Farm(%d)", savegame.key, i)
                if not xmlFile:hasProperty(key) then
                    break
                end
                local farmbalecounter = xmlFile:getInt(key.."#index")
                local balecount = Utils.getNoNil(xmlFile:getInt(key.."#balecounter"),0)				
				spec.balecounter[farmbalecounter] = balecount
                i = i + 1
            end
		if spec.isMultiplayer then		
			spec.FarmID = Utils.getNoNil(xmlFile:getInt(FarmID), self:getOwnerFarmId())
			spec.ContractActive = Utils.getNoNil(xmlFile:getBool(UseContr), false)
		else
			spec.FarmID = FarmManager.SINGLEPLAYER_FARM_ID
			spec.ContractActive = false
		end

		BaleIdManagerGuiloader.Gui.mTable:initialize()
	end
end

function baleIdManager:saveToXMLFile(xmlFile, key)
	if self.spec_baleidmanager ~= nil then
		xmlFile:setInt(key.."#FarmID", self.spec_baleidmanager.FarmID)
		xmlFile:setBool(key.."#UseContr", self.spec_baleidmanager.ContractActive)
		
		for i=0, FarmManager.MAX_NUM_FARMS -1 do
			local baleIdManagerKey = string.format("%s.Farm(%d)", key, i)
			xmlFile:setInt(baleIdManagerKey.."#index", i+1)
			xmlFile:setInt(baleIdManagerKey.."#balecounter", self.spec_baleidmanager.balecounter[i+1])
		end
	end
end

function baleIdManager:onRegisterActionEvents(isSelected, isOnActiveVehicle)
	local spec = self.spec_baleidmanager	
	spec.actionEvents = {}
	if isSelected then
		local _, actionEventId = self:addActionEvent(spec.actionEvents, 'BALEID_CHANGE', self, baleIdManager.action_baleId_Change, false, true, false, true)
		g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_HIGH)
	end		
end

function baleIdManager:onDraw(isActiveForInput, isActiveForInputIgnoreSelection, isSelected)	
	local spec = self.spec_baleidmanager	
	local Farmname 
	if spec.FarmID == self:getActiveFarm() then
		Farmname = g_i18n:getText("OwnFarm")
	elseif self.testing then
		Farmname = string.format("Farm-%d", spec.FarmID) 	-- testing
	else
		Farmname = g_farmManager:getFarmById(spec.FarmID).name
	end
	
	if spec.isMultiplayer then
		g_currentMission:addExtraPrintText(string.format(g_i18n:getText("BaleIdCurrent"), Farmname));
	end
	g_currentMission:addExtraPrintText(string.format(g_i18n:getText("BaleIdCounter1"), spec.balecounter[spec.FarmID]));	
end

function baleIdManager:onWriteStream(streamId, connection)
    if not connection:getIsServer() then 
		local spec = self.spec_baleidmanager;
		for i=1,FarmManager.MAX_NUM_FARMS do
			streamWriteInt32(streamId, spec.balecounter[i]);
		end
		streamWriteInt8(streamId, spec.FarmID)
		streamWriteBool(streamId, spec.ContractActive)
	end;
end;

function baleIdManager:onReadStream(streamId, connection)
    if connection:getIsServer() then
		local spec = self.spec_baleidmanager;
		for i=1,FarmManager.MAX_NUM_FARMS do		
			spec.balecounter[i] = streamReadInt32(streamId);
		end
		spec.FarmID  = streamReadInt8(streamId)
		spec.ContractActive  = streamReadBool(streamId)
		
	end;
end;

-------------------- overwritten functions -------------------------------------------------
function baleIdManager:createBale(superFunc, baleFillType, fillLevel, ...)
	local ret = superFunc(self, baleFillType, fillLevel, ...)
	if ret then 
    	local spec = self.spec_baler
		local bale = spec.bales[#spec.bales]
		if bale.baleObject ~= nil then 
			bale.baleObject:setOwnerFarmId(self:getBaleFarm(), true)
		end
	end
	return ret
end

function baleIdManager:dropBale(superFunc, baleIndex)
	superFunc(self, baleIndex)
	local counter = self.spec_baleidmanager.balecounter
	local bf = self:getBaleFarm()
	counter[bf] = counter[bf] + 1 
end

function baleIdManager:onBalerExternalControlCallback(superf, triggerId, otherId, onEnter, onLeave, onStay)
	if g_currentMission.player ~= nil and otherId == g_currentMission.player.rootNode then
		local spec = self.spec_baleidmanager
		if onEnter then
			spec.isPlayerInRange = true
			local _ = nil
			spec.actionEvents = {}
			_, spec.actionEventId = self:addActionEvent(spec.actionEvents, 'BALEID_CHANGE', self, baleIdManager.action_baleId_Change, false, true, false, true)
			g_inputBinding:setActionEventTextPriority(spec.actionEventId, GS_PRIO_HIGH)
		else
		-- remove K action
			g_inputBinding:removeActionEventsByTarget(self)
			spec.actionEventId = nil
		end
		superf(self, triggerId, otherId, onEnter, onLeave, onStay)
	end
end

-------------------- new functions ---------------------------------------------------------
function baleIdManager:getBaleFarm()
	local spec = self.spec_baleidmanager	
	if spec.isMultiplayer then
		return spec.FarmID
	end
	return self:getActiveFarm()
end

function baleIdManager:updateFarmID(FarmIDnew, ContractActive, noEventSend)
	-- set spec.FarmID, spec.ContractActive
	local spec = self.spec_baleidmanager
	local FarmID = self:getActiveFarm()
	if ContractActive then
		FarmID = FarmIDnew					
	end
	spec.FarmID = FarmID
	spec.ContractActive = ContractActive

	if noEventSend then return end 
	baleIdManagerEvent.sendEvent(self, FarmID, ContractActive)
end

function baleIdManager:action_baleId_Change(actionName, keyStatus, arg3, arg4, arg5)
	local spec = self.spec_baleidmanager	
	spec.FarmIDs = {}
	if spec.isMultiplayer then
		local myID = self:getActiveFarm()
		for i=1,FarmManager.MAX_NUM_FARMS do
			if g_currentMission.accessHandler:canFarmAccessOtherId(myID, i) then
				table.insert(spec.FarmIDs,i)
			end
		end
	else
		table.insert(spec.FarmIDs, 1)
	end
	if self.testing then
		spec.FarmIDs = {5,8,2,1} 
	end
    local dialog = g_gui:showDialog("baleIdManagerGui")
    local gui = BaleIdManagerGuiloader.Gui 
    if dialog ~= nil then
    	gui:initDisplays(self)
    end
end

-- MP Events -------------------------------------------------------------------------------
baleIdManagerEvent = {}
baleIdManagerEvent_mt = Class(baleIdManagerEvent, Event)

InitEventClass(baleIdManagerEvent, "baleIdManagerEvent")

function baleIdManagerEvent.emptyNew()
    local self = Event.new(baleIdManagerEvent_mt)
	self.className = "baleIdManagerEvent"
    return self
end
function baleIdManagerEvent.new(object, FarmID, ContractActive)
    local self = baleIdManagerEvent.emptyNew()
    self.object = object
	self.FarmID = FarmID
	self.ContractActive = ContractActive
    return self
end

function baleIdManagerEvent:readStream(streamId, connection)
	self.object = NetworkUtil.readNodeObject(streamId)
	self.FarmID  = streamReadInt8(streamId)
	self.ContractActive  = streamReadBool(streamId)
	self:run(connection)
end

function baleIdManagerEvent:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.object)
	streamWriteInt8(streamId, self.FarmID)
	streamWriteBool(streamId, self.ContractActive)
end

function baleIdManagerEvent:run(connection)
	self.object:updateFarmID(self.FarmID, self.ContractActive, true)
    if not connection:getIsServer() then
        g_server:broadcastEvent(baleIdManagerEvent.new(self.object, self.FarmID,self.ContractActive), nil, connection, self.object)
    end
end

function baleIdManagerEvent.sendEvent(vehicle, FarmID, ContractActive)
	if g_server ~= nil then
		g_server:broadcastEvent(baleIdManagerEvent.new(vehicle, FarmID, ContractActive), nil, nil, vehicle)
	else
		g_client:getServerConnection():sendEvent(baleIdManagerEvent.new(vehicle, FarmID, ContractActive))
	end
end
