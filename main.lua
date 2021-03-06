-- Max Downforce - main.lua
-- 2017-2019 Foppygames

-- =========================================================
-- includes
-- =========================================================

require "classes.banner"
require "classes.building"
require "classes.car"
require "classes.flag"
require "classes.flagger"
require "classes.grass"
require "classes.light"
require "classes.marker"
require "classes.pillar"
require "classes.sign"
require "classes.stadium"
require "classes.spark"
require "classes.tree"

local aspect = require("modules.aspect")
local controls = require("modules.controls")
local entities = require("modules.entities")
local horizon = require("modules.horizon")
local opponents = require("modules.opponents")
local perspective = require("modules.perspective")
local road = require("modules.road")
local schedule = require("modules.schedule")
local segments = require("modules.segments")
local sound = require("modules.sound")
local timer = require("modules.timer")
local tracks = require("modules.tracks")
local utils = require("modules.utils")

-- =========================================================
-- constants
-- =========================================================

local STATE_TITLE = 0
local STATE_RACE = 1
local STATE_GAME_OVER = 2

local VERSION = "1.1.1"
local LAP_COUNT = 10
local CAR_COUNT = 6
local TIME_AFTER_FINISHED = 5
local TIME_BEFORE_START = 2.5
local TIME_BEFORE_BEEPS = 0.7

-- =========================================================
-- variables
-- =========================================================

local state
local fullScreen = false
local textureOffset = 0
local player = nil
local playerX = 0
local playerSpeed = 0
local lap = 0
local progress = 0
local finished = false
local afterFinishedTimer = 0
local tunnelWallDistance = 0
local previousLastSegmentHadTunnel = false
local beepTimer = 0
local beepCounter = 0
local titleShineTimer = 0
local titleShineIndex = 0
local previousDisplayTime = nil
local previousRavineX = nil
local ravineMinX = nil
local ravineMinXY = nil
local selectedJoystick
local selectedTrack = nil

local imageTrophyBronze = nil
local imageTrophySilver = nil
local imageTrophyGold = nil
local imageGamepadModeR = nil
local imageGamepadModeL = nil

-- =========================================================
-- functions
-- =========================================================

function love.load()
	setupGame()
	switchToState(STATE_TITLE)
end

function setupGame()
	love.window.setTitle("Max Downforce")
	love.graphics.setDefaultFilter("nearest","nearest",1)
	love.graphics.setLineStyle("rough")
	love.graphics.setFont(love.graphics.newFont("Retroville_NC.ttf",10))
	
	imageTrophyBronze = love.graphics.newImage("images/trophy_bronze.png")
	imageTrophySilver = love.graphics.newImage("images/trophy_silver.png")
	imageTrophyGold = love.graphics.newImage("images/trophy_gold.png")
	imageGamepadModeR = love.graphics.newImage("images/gamepad_r.png")
	imageGamepadModeL = love.graphics.newImage("images/gamepad_l.png")

	Banner.init()
	Building.init()
	Car.init()
	Flag.init()
	Flagger.init()
	Grass.init()
	Light.init()
	Marker.init()
	Pillar.init()
	Sign.init()
	Spark.init()
	Stadium.init()
	Tree.init()
	
	aspect.init(fullScreen)
	entities.init()
	horizon.init()
	perspective.initZMapAndScaling()
	opponents.init()
	segments.init()
	sound.init()

	selectedJoystick = controls.init()
end

function switchToState(newState)
	if (state == STATE_RACE) then
		sound.stop(tracks.getSong())
		sound.stop(sound.CROWD)
	elseif (state == STATE_TITLE) then
		sound.stop(sound.TITLE_MUSIC)
	end

	state = newState
	
	entities.reset(tracks.hasRavine())
	
	if (state == STATE_TITLE) then
		math.randomseed(os.time())
		sound.play(sound.TITLE_MUSIC)
		titleShineIndex = 0
	elseif (state == STATE_RACE) then
		lap = 0
		progress = 0
		finished = false
		afterFinishedTimer = 0
		previousDisplayTime = nil
		
		horizon.reset()
		schedule.reset()
		segments.reset()
		segments.addFirst()
		opponents.reset()
		timer.reset(progress,TIME_BEFORE_START)
		TunnelEnd.reset()
	
		local startZ = perspective.zMap[30]
		local dz = (perspective.maxZ - perspective.minZ) / 13
		
		-- player not on first segment
		if ((CAR_COUNT * dz) > (segments.getFirstSegmentLength() * (perspective.maxZ - perspective.minZ))) then
			print("Warning: player not on first segment")
		end
		
		-- add cars from back to front
		for i = 1, CAR_COUNT do
			local z = startZ + dz * (i - 1)
			local x = 1
			if (i % 2 == 0) then
				z = z + dz / 2
				x = -1
			end
			if (i == 1) then
				player = entities.addCar(x,z,true,1,TIME_BEFORE_START)
			else
				entities.addCar(x,z,false,0.1,TIME_BEFORE_START)
			end
		end
		
		beepTimer = TIME_BEFORE_BEEPS
		beepCounter = 0
	elseif (state == STATE_GAME_OVER) then
		-- ...
	end
end

function love.update(dt)
	if (state == STATE_RACE) then
		if (beepTimer > 0) then
			beepTimer = beepTimer - dt
			if (beepTimer <= 0) then
				beepCounter = beepCounter + 1
				if (beepCounter == 3) then
					sound.play(sound.BEEP_2)
					beepTimer = 0
					
					-- reset music volume after possible countdown
					sound.setVolume(tracks.getSong(),sound.VOLUME_MUSIC)
					
					sound.play(tracks.getSong())
				else
					sound.play(sound.BEEP_1)
					beepTimer = (TIME_BEFORE_START - TIME_BEFORE_BEEPS) / 2
				end
			end
		end
		
		local playerX
		
		if (player ~= nil) then
			playerSpeed = player.speed
			playerX = player.x
		else
			playerSpeed = 0
			playerX = nil
		end
		
		-- update texture offset
		textureOffset = textureOffset + playerSpeed * dt
		if (textureOffset > 8) then
			textureOffset = textureOffset - 8
		end
		
		schedule.update(playerSpeed,dt)
		
		local entitiesUpdateResult = entities.update(playerSpeed,dt,segments.totalLength)
		
		sound.updateCrowdVolume(entitiesUpdateResult.stadiumNear,dt)
		
		if (entities.checkLap()) then
			-- reset music volume after possible countdown
			sound.setVolume(tracks.getSong(),sound.VOLUME_MUSIC)
			
			Sign.resetIndex()

			lap = lap + 1
			
			if (lap > 1) then
				sound.play(sound.LAP)
			end
			
			if (lap > LAP_COUNT) then
				timer.halt()
			
				if ((not finished) and (player ~= nil)) then
					-- turn player car into cpu car
					player:setIsPlayer(false)
					
					-- start count down after finish
					afterFinishedTimer = TIME_AFTER_FINISHED
				end
				finished = true
			else
				progress = lap / LAP_COUNT
				
				if (lap > 1) then
					timer.reset(progress,0)
				end
			end
		end
		
		opponents.update(playerSpeed,progress,entitiesUpdateResult.aiCarCount,dt)
		segments.update(playerSpeed,dt)
		horizon.update(segments.getAtIndex(1).ddx,playerSpeed,dt)
		
		local lastSegment = segments.getAtIndex(segments.getLastIndex())
		if (lastSegment.tunnel) then
			tunnelWallDistance = tunnelWallDistance + playerSpeed * dt
			while (tunnelWallDistance > 3) do
				tunnelWallDistance = tunnelWallDistance - 3
				entities.addTunnelEnd(perspective.maxZ - tunnelWallDistance)
			end
		elseif (previousLastSegmentHadTunnel) then
			tunnelWallDistance = 0
			TunnelEnd.reset()
		end
		previousLastSegmentHadTunnel = lastSegment.tunnel
		
		if (afterFinishedTimer > 0) then
			afterFinishedTimer = afterFinishedTimer - dt
			if (afterFinishedTimer <= 0) then
				switchToState(STATE_GAME_OVER)
			end
		end
		
		local timeOk = timer.update(dt)
		
		if (timer.isDangerous()) then
			local displayTime = timer.getDisplayTime()
			if (displayTime ~= previousDisplayTime) then
				local steps = timer.getTimeDangerous()
				local stepsTaken = steps - displayTime
				local volume = sound.VOLUME_COUNTDOWN_MIN + stepsTaken * ((sound.VOLUME_COUNTDOWN_MAX - sound.VOLUME_COUNTDOWN_MIN) / steps)
				sound.setVolume(sound.COUNTDOWN,volume)
				sound.setVolume(tracks.getSong(),sound.VOLUME_COUNTDOWN_MAX - volume)
				sound.play(sound.COUNTDOWN)
				previousDisplayTime = displayTime
			end
		end
		
		if (not timeOk) then
			switchToState(STATE_GAME_OVER)
		end
	elseif (state == STATE_TITLE) then
		titleShineTimer = titleShineTimer + 20 * dt
		if (titleShineTimer >= 1) then
			titleShineTimer = 0
			titleShineIndex = titleShineIndex + 1
			if (titleShineIndex > 150) then
				titleShineIndex = 0
			end
		end
	end
end

function love.keypressed(key)
	if (state == STATE_TITLE) then
		if (key == "t") then
			tracks.selectNextTrack()
		end
		if (key == "w") then
			fullScreen = not fullScreen
			aspect.init(fullScreen)
		end
		if (key == "c") then
			selectedJoystick = controls.selectNextAvailable()
		end
		if (key == "space") then
			switchToState(STATE_RACE)
		end
		if (key == "escape") then
			love.event.quit()
		end
	end
	if (state == STATE_RACE) then
		if (key == "escape") then
			switchToState(STATE_TITLE)
		end
	end
	if (state == STATE_GAME_OVER) then
		if (key == "space") then
			switchToState(STATE_TITLE)
		end
	end
end

function love.gamepadpressed(joystick,button)
	if (joystick == selectedJoystick) then
		if (state == STATE_TITLE) then
			if ((button == "a") or (button == "start")) then
				switchToState(STATE_RACE)
			end
		end
		if (state == STATE_RACE) then
			if (button == "back") then
				switchToState(STATE_TITLE)
			end
		end
		if (state == STATE_GAME_OVER) then
			if ((button == "a") or (button == "start")) then
				switchToState(STATE_TITLE)
			end
		end
	end
end

function love.joystickadded(joystick)
	selectedJoystick = controls.init()
end

function love.joystickremoved(joystick)
	selectedJoystick = controls.init()
end

function love.draw()
	aspect.apply()
	
	if (state == STATE_TITLE) then
		local title = "MAX DOWNFORCE"
		love.graphics.push()
		love.graphics.scale(2,2)
		for i = 1, string.len(title) do
			local diff = math.abs(i - titleShineIndex)
			if (diff > 1) then
				love.graphics.setColor(1,0,0)
			elseif (diff == 1) then
				love.graphics.setColor(1,0.5,0.5)
			else
				love.graphics.setColor(1,1,1)
			end
			love.graphics.print(string.sub(title,i,i),8 + i * 10,8)	
		end
		love.graphics.pop()
		
		love.graphics.setColor(0.1,0.1,0.3)
		love.graphics.print(VERSION,272,6)
		
		love.graphics.setColor(1,1,1)
		love.graphics.print("Written by Robbert Prins",75,50)
		love.graphics.print("Music from PlayOnLoop.com",70,70)
		
		love.graphics.setColor(0.470,0.902,1)
		love.graphics.print("T = track: '"..tracks.getSelectedTrackName().."'",75,95)
		love.graphics.print("W = windowed / full screen",75,110)
		
		-- more than one control method available
		if (controls.getAvailableCount() > 1) then
			love.graphics.setColor(0.470,0.902,1)
			love.graphics.print("C = controls: "..controls.getSelected().label,75,125)
		-- one control method available (note: assuming there is never less than one)
		else
			love.graphics.setColor(1,1,1)
			love.graphics.print("Controls: "..controls.getSelected().label,75,125)
		end

		if (controls.getSelected().type == controls.GAMEPAD) then
			love.graphics.setColor(1,1,1)
			if (controls.getSelected().mode == controls.GAMEPAD_MODE_R) then
				love.graphics.draw(imageGamepadModeR,225,125)
			else
				love.graphics.draw(imageGamepadModeL,225,125)
			end
		end

		love.graphics.setColor(1,1,1)
		love.graphics.print(controls.getSelected().startText,90+controls.getSelected().startTextDx,150)
		
		love.graphics.setColor(1,1,0)
		love.graphics.print("Foppygames 2019",102,175)
	end
	
	if (state == STATE_RACE) then
		local ravine = tracks.hasRavine()

		-- draw sky
		tracks.getSelectedTrack().drawSky()

		-- draw horizon
		horizon.draw()

		-- draw ravine
		if (ravine) then
			if (ravineMinX ~= nil) then
				love.graphics.setColor(0.25,0.18,0.015)
				love.graphics.rectangle("fill",ravineMinX,ravineMinXY,aspect.GAME_WIDTH-ravineMinX,aspect.GAME_HEIGHT-ravineMinXY)	
			end
		end

		-- initial vertical position of drawing of road
		local screenY = aspect.GAME_HEIGHT-0.5
		
		if (player ~= nil) then
			playerX = player.x
		end
		
		-- initial horizontal position of drawing of road
		local screenX = aspect.GAME_WIDTH/2 - playerX*perspective.scale[1]
		
		-- correction to always make road point to horizontal center of horizon
		local perspectiveDX = (aspect.GAME_WIDTH/2-screenX)/perspective.GROUND_HEIGHT
				
		-- assuming segments contains at least one segment!
		local segmentIndex = 1
		local lastSegmentIndex = segments.getLastIndex()
		local segment = segments.getAtIndex(segmentIndex)
		
		local dx = 0

		entities.resetForDraw()	
		
		-- values for interpolating entity positions
		local previousZ = perspective.minZ
		local previousScreenX = screenX
		local previousScreenY = screenY
		local previousScale = perspective.scale[1]
		
		previousRavineX = nil
		ravineMinX = nil

		-- draw road
		for i = 1, perspective.GROUND_HEIGHT do
			local z = perspective.zMap[i]
			
			-- set colors
			local roadColor = 0.28
			local curbColorVariant = 1
			local grassColorVariant = 1
			if (((z + textureOffset) % 8) > 4) then
				if (not (segment.tunnel and ravine)) then
					roadColor = 0.30
				end
				grassColorVariant = 2
				curbColorVariant = 2
			end
			
			if (segmentIndex < lastSegmentIndex) then
				if (z > segments.getAtIndex(segmentIndex+1).z) then
					segmentIndex = segmentIndex + 1
					segment = segments.getAtIndex(segmentIndex)
				end
			end
			
			if (segment.tunnel) then
				if (ravine) then
					roadColor = roadColor / 1.4
				else
					roadColor = roadColor / 2.8
				end
			end

			local roadWidth = road.ROAD_WIDTH * perspective.scale[i]
			local curbWidth = road.CURB_WIDTH * perspective.scale[i]
			local stripeWidth = road.STRIPE_WIDTH * perspective.scale[i]
			local roadX = screenX - roadWidth / 2
			local ravineX = roadX - road.RAVINE_ROADSIDE_WIDTH * perspective.scale[i]
			
			if (ravine) then
				if ((previousRavineX ~= nil) and (ravineX < previousRavineX)) then
					if ((ravineMinX == nil) or (ravineX < ravineMinX)) then
						ravineMinX = ravineX
						ravineMinXY = screenY
					end
				end
			end

			previousRavineX = ravineX

			-- update entities x,y,scale
			entities.setupForDraw(z,screenX,screenY,perspective.scale[i],previousZ,previousScreenX,previousScreenY,previousScale,segment)
			
			-- draw grass
			if (grassColorVariant == 1) then
				if (ravine) then
					love.graphics.setColor(0.5,0.36,0.03)
				else
					love.graphics.setColor(0.45,0.8,0.25)
				end
			else
				if (ravine) then
					love.graphics.setColor(0.45,0.31,0.01)
				else
					love.graphics.setColor(0.36,0.6,0.20)
				end
			end
			if (ravine) then	
				if (not segment.tunnel) then
					love.graphics.line(ravineX,screenY,aspect.GAME_WIDTH,screenY)	
				else
					love.graphics.line(ravineX,screenY,roadX,screenY)
					love.graphics.setColor(0,0,0)
					love.graphics.line(roadX,screenY,aspect.GAME_WIDTH,screenY)
				end
			else
				if (segment.tunnel) then
					love.graphics.setColor(0,0,0)
				end
				love.graphics.line(0,screenY,aspect.GAME_WIDTH,screenY)
			end
			
			-- draw tarmac
			if (ravine) then
				if (not segment.tunnel) then
					love.graphics.setColor(roadColor*1.4,roadColor,roadColor)
				else
					love.graphics.setColor(roadColor*1.2,roadColor,roadColor*1.3)
				end
			else
				if (not segment.tunnel) then
					love.graphics.setColor(roadColor*1.22,roadColor,roadColor)
				else
					love.graphics.setColor(roadColor,roadColor,roadColor*1.3)
				end
			end
			love.graphics.line(roadX,screenY,roadX+roadWidth,screenY)

			-- experiment: draw tunnel roof as upside down black road
			-- Note: cancelled for now, would work together with reversed order drawing
			-- so tunnel walls are drawn as part of drawing road instead of using entities
			--[[
			if (segment.tunnel) then
				love.graphics.setColor(1,0,0)
				local roofY = screenY - (200 * perspective.scale[i])
				love.graphics.line(x,roofY,x+roadWidth,roofY)
			end
			]]--

			-- draw curbs when not in tunnel
			if (not segment.tunnel) then
				if (curbColorVariant == 1) then
					if (ravine) then
						love.graphics.setColor(0.1,0.263,0.8)
					else
						love.graphics.setColor(1,0.263,0)
					end
				elseif (curbColorVariant == 2) then
					love.graphics.setColor(1,0.95,0.95)
				end
				love.graphics.line(roadX,screenY,roadX+curbWidth,screenY)
				love.graphics.line(roadX+roadWidth-curbWidth,screenY,roadX+roadWidth,screenY)
			end
				
			-- draw stripes
			if (curbColorVariant ~= 1) then
				if (segment.tunnel) then
					if (ravine) then
						love.graphics.setColor(0.9,0.9,0)
					else
						love.graphics.setColor(0.8,0.8,0)
					end
				else
					love.graphics.setColor(1,0.95,0.95)
				end
				love.graphics.line(screenX-stripeWidth/2,screenY,screenX+stripeWidth/2,screenY)
			end
			
			previousZ = z
			previousScreenX = screenX
			previousScreenY = screenY
			previousScale = perspective.scale[i]
			
			-- no hills, just decrease y by one
			screenY = screenY - 1
			
			-- update the change that is applied to x
			dx = dx + segment.ddx * perspective.zMap[i] * (perspective.zMap[i] / 6) * ((perspective.scale[1]-perspective.scale[i])*2.5)
			
			-- apply the change to x and apply perspective correction 
			screenX = screenX + dx + perspectiveDX
		end
		
		entities.draw()
		
		-- on screen info: player speed
		if (player ~= nil) then
			love.graphics.setColor(0.471,0.902,1)
			love.graphics.print("SPEED",aspect.GAME_WIDTH-60,10)
			love.graphics.print(player:getSpeedAsKMH(),aspect.GAME_WIDTH-80,25)
			love.graphics.print("km/h",aspect.GAME_WIDTH-50,25)
		end
		
		-- on screen info: current lap
		love.graphics.setColor(0.471,0.902,1)
		love.graphics.print("LAP",20,10)
		love.graphics.print(math.max(lap,1),20,25)
		love.graphics.print("/ "..LAP_COUNT,40,25)
		if (lap == LAP_COUNT) then
			love.graphics.print("FINAL LAP",20,40)
		elseif (lap > LAP_COUNT) then
			love.graphics.print("RACE OVER",20,40)
		end
		
		-- on screen info: time
		love.graphics.setColor(1,1,0)
		love.graphics.print("TIME",aspect.GAME_WIDTH/2-20,10)
		local timeScale = 1
		if (timer.isDangerous()) then
			timeScale = 2
		end
		love.graphics.push()
		love.graphics.scale(timeScale,timeScale)
		love.graphics.print(timer.getDisplayTime(),(aspect.GAME_WIDTH/2-12)/timeScale,25/timeScale)
		love.graphics.pop()
	end
	
	if (state == STATE_GAME_OVER) then
		love.graphics.setColor(1,1,1)
		if (not finished) then
			love.graphics.push()
			love.graphics.scale(2,2)
			love.graphics.print("GAME OVER",45,20)
			love.graphics.pop()
			
			-- still in first lap
			if (lap < 2) then
				love.graphics.print("Don't give up!",120,70)
			-- beyond first lap
			else
				love.graphics.setColor(1,1,0)
				-- in second lap
				if (lap == 2) then
					love.graphics.print("You completed 1 full lap",85,70)
					love.graphics.setColor(1,1,1)
					love.graphics.print("Well done!",131,95)
				-- beyond second lap
				else
					love.graphics.print("You completed "..(lap-1).." full laps",80,70)
					-- completed more than one lap
					if (lap > 2) then
						love.graphics.setColor(1,1,1)
						
						-- completed nine laps
						if (lap == 10) then
							love.graphics.print("You win the silver cup!",89,95)
							love.graphics.draw(imageTrophySilver,aspect.GAME_WIDTH/2-imageTrophySilver:getWidth()/2,120)
						-- completed eight laps
						elseif (lap == 9) then
							love.graphics.print("You win the bronze cup!",85,95)
							love.graphics.draw(imageTrophyBronze,aspect.GAME_WIDTH/2-imageTrophyBronze:getWidth()/2,120)
						-- completed between two and seven laps
						else
							love.graphics.print("Well done!",131,95)
						end
					end
				end
			end
		else
			love.graphics.push()
			love.graphics.scale(2,2)
			love.graphics.print("CONGRATULATIONS!",15,20)
			love.graphics.pop()
			love.graphics.setColor(1,1,0)
			love.graphics.print("You finished the race",92,70)
			love.graphics.setColor(1,1,1)
			love.graphics.print("You win the gold cup!",95,95)
			love.graphics.draw(imageTrophyGold,aspect.GAME_WIDTH/2-imageTrophyGold:getWidth()/2,120)
			love.graphics.setColor(0.471,0.902,1)
			love.graphics.print("You may consider yourself a member of",30,150)
			love.graphics.print("an elite group of grand prix racers",40,170)
		end
	end
	
	aspect.letterbox()
end