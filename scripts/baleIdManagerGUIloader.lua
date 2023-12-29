-- [F/A] derelky

BaleIdManagerGuiloader = {}

local modDirectory = g_currentModDirectory

function BaleIdManagerGuiloader:loadGUI()
	local noguilua = false
	local guiPath = modDirectory .."scripts/gui/"
	if g_gui ~= nil and g_gui.guis.baleIdManagerGui == nil then
		local luaPath = guiPath .. "baleIdManagerGui.lua"
		if fileExists(luaPath) then
			source(luaPath)
		else
			noguilua = true
			Logging.error("baleIdManager GUI Lua could not be loaded" )
		end
	
		if not noguilua then
			-- load my gui profiles 
			g_gui:loadProfiles(guiPath .. "guiProfiles.xml")
			local xmlPath = guiPath .. "baleIdManagerGui.xml"
			if fileExists(xmlPath) then
				local baleIdManagerGui = BaleIdManagerGui.new(nil, nil)
				g_gui:loadGui(xmlPath, "baleIdManagerGui", baleIdManagerGui)
				self.Gui = baleIdManagerGui
			else
				Logging.error("baleIdManager GUI XML could not be loaded" )
			end
		end
	end
end

BaleIdManagerGuiloader:loadGUI()
