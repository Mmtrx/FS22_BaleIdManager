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
function debugPrint(text, ...)
	if BaleIdManagerGui.debug then
		Logging.info(text,...)
	end
end
BaleIdManagerGui = {}
BaleIdManagerGui.BUILD_ID = 3
BaleIdManagerGui.testing = false
BaleIdManagerGui.debug = false

local BaleIdManagerGui_mt = Class(BaleIdManagerGui, YesNoDialog)

BaleIdManagerGui.CONTROLS = {
	SET_FARMID_CHANGE_ID = "setFarmIDChange",
	CONTRACTSTATE = "setContractorstate",
	VEHICLE_NAME = "vehiclename",
	VEHICLE_IMAGE = "vehicleImage",
	BALEFILLLEVEL = "balefilllevel",
	"mTable",
}

function BaleIdManagerGui.new(target, custom_mt)
	local self = YesNoDialog.new(target, custom_mt or BaleIdManagerGui_mt)
	self:registerControls(BaleIdManagerGui.CONTROLS)
	self.isServer = g_server ~= nil
	return self
end

-- Init menu display elements, called once when gui is opened
function BaleIdManagerGui:initDisplays(vehicle)
	--spec.FarmID, spec.FarmIDs, spec.ContractActive, spec.isMultiplayer
	self.target = vehicle
	local spec = vehicle.spec_baleidmanager
	self.vehicleSpec = spec
	self.balecounter = spec.balecounter
	self.guifarmID = spec.FarmID
	self.guifarmIDs = spec.FarmIDs 	-- all farms I can access

	--disable multitext menus for single player
	self.setContractorstate:setVisible(false)
	self.setFarmIDChange:setVisible(false)

	if spec.isMultiplayer then
		self.guicontractactive = spec.ContractActive
		self.setContractorstate:setIsChecked(self.guicontractactive)
		self.setContractorstate:setVisible(true)

		-- need to set the farm.names, and save index to names:
		local texts = {}
		local test = vehicle.testing
		for i, farmId in ipairs(self.guifarmIDs) do
			if test then
				texts[i] = string.format("Farm-%d", farmId)
			else
				texts[i] = g_farmManager:getFarmById(farmId).name
			end
		end
		self.setFarmIDChange:setTexts(texts)

		local findex = table.findListElementFirstIndex(self.guifarmIDs, self.guifarmID, 0)
		if findex == 0 then
			-- lost loaner status for self.guifarmID. Reset to own farm
			local myId = vehicle:getActiveFarm()
			self.guifarmID = myId
			vehicle:updateFarmID(myId, self.guicontractactive, false)
			
			findex = table.findListElementFirstIndex(self.guifarmIDs, myId, 0)
			if findex == 0 then
				Logging.error("%s: can't find my own farmId: %d", g_currentModName, self.guifarmID)
				return
			end
		end
		self.setFarmIDChange:setState(findex, true)	
		self.setFarmIDChange:setVisible(self.guicontractactive)
	end

	-- Init baler name/ image/ fillType elements, called once when gui is opened
	local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName:lower())	
	if storeItem ~= nil then
		local name = vehicle:getName()
		local brand = g_brandManager:getBrandByIndex(vehicle:getBrand())
		if brand ~= nil then
			name = brand.title .. " " .. name
		end
		self.vehiclename:setText(name)
		self.vehicleImage:setImageFilename(storeItem.imageFilename)
	end
	self:changefilltype(vehicle)

	self.callback = vehicle.updateFarmID  			-- to be called on menu close

	-- Init balecount table
	if not self.mTable.isInitialized then
		self.mTable:initialize()
	end
	self:updateMTable(spec.balecounter)
end

function BaleIdManagerGui:update(dt)
	BaleIdManagerGui:superClass().update(self, dt)
end

function BaleIdManagerGui:onClickContractorChange(index)
	self.guicontractactive = self.setContractorstate:getIsChecked()
	self.setFarmIDChange:setVisible(self.guicontractactive)
	self.vehicleSpec.ContractActive = self.guicontractactive
end

function BaleIdManagerGui:onClickFarmIDChange(index)
	self.guifarmID = self.guifarmIDs[self.setFarmIDChange:getState()]
	-- updateFarmID() on baler only when gui is closed via "ok" button
end

function BaleIdManagerGui:onClickclearbaler()
	if self.target ~= nil then
		self.resetfillbaler(self.target)		
		self.balefilllevel:setText("0")
	end
end

function BaleIdManagerGui:onClickReset(button)
	--Logging.info("** click button %s", self.mTable.mouseRow)
	local index = self.mTable.mouseRow
	local balecounter = self.balecounter

	-- if last row: reset all
	if index > #self.guifarmIDs then
		for _, i in ipairs(self.guifarmIDs) do
			balecounter[i] = 0
		end
	else
		balecounter[index] = 0
	end
	self:updateMTable(balecounter)
end

function BaleIdManagerGui:onClickOk()
	if self.target ~= nil and self.callback ~= nil then
		-- updateFarmID() on baler, and send baleIdManagerEvent to other clients:
		self.callback(self.target, self.guifarmID, self.guicontractactive, false )
	end
	self:close()
end

function BaleIdManagerGui:onClickBack(forceBack, usedMenuButton)
	self:close()
end

function BaleIdManagerGui.resetfillbaler(vehicle, noEventSend)
	local spec = vehicle.spec_baler
	local specDLC = vehicle.spec_extendedBaler
	local isServer = g_server ~= nil
	if not noEventSend then		
		if isServer then
			g_server:broadcastEvent(BaleClearEvent.new(vehicle), nil, nil, vehicle);
		else
			g_client:getServerConnection():sendEvent(BaleClearEvent.new(vehicle));
		end
	end;
	if isServer then
		vehicle:addFillUnitFillLevel(vehicle:getOwnerFarmId(), spec.fillUnitIndex, -math.huge, 
			vehicle:getFillUnitFillType(spec.fillUnitIndex), ToolType.UNDEFINED)
		if specDLC ~= nil then
			vehicle:addFillUnitFillLevel(vehicle:getOwnerFarmId(), specDLC.fillUnitIndex, -math.huge, 
				vehicle:getFillUnitFillType(specDLC.fillUnitIndex), ToolType.UNDEFINED)
		end			
	end		
end

function BaleIdManagerGui:changefilltype(vehicle)
	if vehicle ~= nil then
		local spec = vehicle.spec_baler
		local specDLC = vehicle.spec_extendedBaler
						
		local filltypeindex = vehicle:getFillUnitFillType(spec.fillUnitIndex)
		local filltype = g_fillTypeManager:getFillTypeByIndex(filltypeindex)
		local filltypetext = ""
		local currentFillLevel = vehicle:getFillUnitFillLevel(spec.fillUnitIndex)
		if specDLC ~=nil and currentFillLevel==0 then
			currentFillLevel = vehicle:getFillUnitFillLevel(specDLC.fillUnitIndex)
			filltypeindex = vehicle:getFillUnitFillType(specDLC.fillUnitIndex)
			filltype = g_fillTypeManager:getFillTypeByIndex(filltypeindex)
		end
		if filltype.name ~= "UNKNOWN" then
			filltypetext = filltype.title or filltype.name
		end
		self.balefilllevel:setText(
			string.format("%0.f l  %s", currentFillLevel, filltypetext))
	end	
end

-------------------- functions for mTable --------------------------------------------------
function BaleIdManagerGui:getMData(balecounter)
	-- return data rows for farms bale count table
	-- {c1="MyFarm",c2="5",c3= "reset-button"}
	local data = {}
	local myId = self.target:getActiveFarm()
	for _, farm in ipairs(g_farmManager:getFarms()) do
		if farm.farmId ~= FarmManager.SPECTATOR_FARM_ID then 
			local isLoaner = ""
			if g_currentMission.accessHandler:canFarmAccessOtherId(myId, farm.farmId) then	
				isLoaner = "y"		
			end
			local row = {
			loaner = isLoaner,
			c1 = farm.name,
			c2 = balecounter[farm.farmId] or 0,
			c3 = "",
			}
			table.insert(data, row)
		end
	end
	-- testing: ------------------------------
	if self.target.testing then
		for i = 2,FarmManager.MAX_NUM_FARMS do
			local row = {
				loaner = i%2 == 1 or "",
				c1 = string.format("Farm %d", i),c2 = balecounter[i] or 0,c3 = "",
				}
			table.insert(data, row)
		end
	end
	if #data > 1 then 
		table.insert(data, {loaner = "", c1 = "", c2 = "Reset all", c3=""})
	end
	return data
end
function BaleIdManagerGui:updateMTable(balecounter)
	local bt = self.mTable
	bt:clearData()
	local mData = self:getMData(balecounter)
	for i=1, #mData do
		self:buildRow(bt, bt.columnNames, mData[i], mData[i].loaner ~= "", mData[i].c2 ~= 0)
	end
	bt:updateView(true)
end
function BaleIdManagerGui:buildRow(bt, cols, values, isLoaner, resetVisible)
	-- adds a row to table bt, inits col cells to values 
	-- bt.columnnames = {"c1","c2","c3"}
	-- local id = string.combine(values.c1:split(" "),"") -- id only optional for new row
	local row = TableElement.DataRow.new(nil, cols )
	bt:addRow(row) 									-- this makes bt.data[bt.numActiveRows] = row
	local ixRow = bt.numActiveRows
	for c, value in pairs(values) do 
		bt:setCellText(ixRow, cols[c], tostring(value))
	end

	-- show loaner flag, if player has loaner state for farm:
	bt:setCellVisibility(ixRow, "loaner", isLoaner)
	-- enable c3 reset button, if c2 > 0:
	bt:setCellVisibility(ixRow, "c3", resetVisible)
end

-------------------- Clear Event -----------------------------------------------------------
BaleClearEvent = {};
BaleClearEvent_mt = Class(BaleClearEvent, Event);

InitEventClass(BaleClearEvent, "BaleClearEvent");

function BaleClearEvent.emptyNew()
	local self = Event.new(BaleClearEvent_mt);
	return self;
end;

function BaleClearEvent.new(vehicle)
	local self = BaleClearEvent.emptyNew();
	self.vehicle = vehicle;
	return self;
end;

function BaleClearEvent:readStream(streamId, connection)
	self.vehicle = NetworkUtil.readNodeObject(streamId);
	self:run(connection);
end;

function BaleClearEvent:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.vehicle);
end;

function BaleClearEvent:run(connection)	
	if self.vehicle ~= nil then
		if not connection:getIsServer() then
			g_server:broadcastEvent(BaleClearEvent.new(self.vehicle), nil, connection, self.vehicle);
		end;
		BaleIdManagerGui.resetfillbaler(self.vehicle, true);
	end;
end;

