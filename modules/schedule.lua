-- Max Downforce - modules/schedule.lua
-- 2017-2018 Foppygames

local schedule = {}

-- =========================================================
-- includes
-- =========================================================

local entities = require("modules.entities")
local perspective = require("modules.perspective")
--local utils = require("modules.utils")

-- =========================================================
-- public constants
-- =========================================================

schedule.ITEM_BANNER_START = "banner_start"
schedule.ITEM_BUILDINGS_L = "buildings_l"
schedule.ITEM_BUILDINGS_R = "buildings_r"
schedule.ITEM_SIGN_L = "sign_l"
schedule.ITEM_SIGN_R = "sign_r"
schedule.ITEM_TREES_L = "trees_l"
schedule.ITEM_TREES_L_R = "trees_l_r"
schedule.ITEM_STADIUM_L = "stadium_l"
schedule.ITEM_STADIUM_R = "stadium_r"

-- =========================================================
-- private variables
-- =========================================================

local items = {}

-- =========================================================
-- private functions
-- =========================================================

function processItem(itemType,z)
	--[[
	if (itemType == schedule.ITEM_BUILDINGS_L) then
		entities.add(entities.TYPE_BUILDING,-900,z)
	elseif (itemType == schedule.ITEM_BUILDINGS_R) then
		entities.add(entities.TYPE_BUILDING,900,z)
	elseif (itemType == schedule.ITEM_BANNER_START) then
		entities.addBanner(entities.TYPE_BANNER_START,0,30,z)
	elseif (itemType == schedule.ITEM_TREES_L) then
		entities.add(entities.TYPE_TREE,-900,z)
	elseif (itemType == schedule.ITEM_TREES_L_R) then
		entities.addTree(-1500,z,145)
		entities.addTree(-1100,z-4,205)
		entities.addTree(-700,z-8,255)
		entities.addTree(700,z,255)
		entities.addTree(1100,z-4,205)
		entities.addTree(1500,z-8,145)
	elseif (itemType == schedule.ITEM_SIGN_L) then
		entities.add(entities.TYPE_SIGN,-700,z)
	elseif (itemType == schedule.ITEM_SIGN_R) then
		entities.add(entities.TYPE_SIGN,700,z)
	elseif (itemType == schedule.ITEM_STADIUM_L) then
		entities.add(entities.TYPE_STADIUM,-850,z)
	elseif (itemType == schedule.ITEM_STADIUM_R) then
		entities.add(entities.TYPE_STADIUM,850,z)
	end
	]]
end

-- =========================================================
-- public functions
-- =========================================================

-- note: z parameter is starting z for series of items
-- if z is smaller than maxZ this means items may have to be processed right away
function schedule.add(itemType,dz,count,z)
	if (count > 0) then
		if (items[itemType] ~= nil) then
			items[itemType].dz = dz
			items[itemType].count = count
		else
			items[itemType] = {
				dz = dz, -- distance between each item
				count = count, -- number of items, where -1 is unlimited
				distance = z - perspective.maxZ -- distance till next item
			}
		end
		
		-- process items right away
		if (z < perspective.maxZ) then
			repeat
				processItem(itemType,z)
				z = z + items[itemType].dz
				items[itemType].count = items[itemType].count - 1
			until (z >= perspective.maxZ) or (items[itemType].count <= 0)
			
			if (items[itemType].count <= 0) then
				items[itemType] = nil
			else
				-- set correct distance to next item
				items[itemType].distance = z - perspective.maxZ
			end
		end
	end
end

function schedule.update(playerSpeed,dt)
	for itemType,data in pairs(items) do
		data.distance = data.distance - playerSpeed * dt
		if (data.distance <= 0) then
			data.distance = data.dz
			processItem(itemType,perspective.maxZ)
			if (data.count ~= -1) then
				data.count = data.count - 1
				if (data.count <= 0) then
					items[itemType] = nil
				end
			end
		end
	end
end

return schedule