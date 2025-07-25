local player, layout = ...
local pn = ToEnumShortString(player)
local mods = SL[pn].ActiveModifiers

-- don't allow MeasureCounter to appear in Casual gamemode via profile settings
if SL.Global.GameMode == "Casual"
or not mods.MeasureCounter
or mods.MeasureCounter == "None" then
	return
end

local multiplier = 1
if mods.MeasureCounter == "24th" then multiplier = 1.5 end
if mods.MeasureCounter == "32nd" then multiplier = 2 end

-- -----------------------------------------------------------------------

local PlayerState = GAMESTATE:GetPlayerState(player)
local streams, prevMeasure, streamIndex
-- Collection of the BitmapText actors used for the measure counters.
local bmt = {}

-- How many streams to "look ahead"
local lookAhead = mods.MeasureCounterLookahead
-- If you want to see more than 2 counts in advance, change the 2 to a larger value.
-- Making the value very large will likely impact fps. -quietly

-- Add a BitmapText actor for the "measures until empty break" counter
local emptyBreakCounter = nil

-- Function to find the next empty break and return the number of measures until it
local GetMeasuresUntilNextEmptyBreak = function(currMeasure, Measures, currentStreamIndex)
    -- Start from the current stream index
    local idx = currentStreamIndex
    local measuresUntilEmptyBreak = 0

    -- If we're currently in an empty break, return 0
    if Measures[idx] and Measures[idx].isBreak and Measures[idx].isEmpty then
        return 0
    end

    -- Calculate how many measures remain in the current segment
    if Measures[idx] then
        local segmentEnd = Measures[idx].streamEnd
        measuresUntilEmptyBreak = segmentEnd - currMeasure
    end

    -- Look ahead through future segments until we find an empty break
    idx = idx + 1
    while idx <= #Measures do
        if Measures[idx].isBreak and Measures[idx].isEmpty then
            -- Found an empty break
            return math.ceil(measuresUntilEmptyBreak)
        else
            -- Add the length of this segment to our counter
            measuresUntilEmptyBreak = measuresUntilEmptyBreak + (Measures[idx].streamEnd - Measures[idx].streamStart)
        end
        idx = idx + 1
    end

    -- If we get here, there are no more empty breaks in the song
    return -1
end


-- We'll want to reset each of these values for each new song in the case of CourseMode
local InitializeMeasureCounter = function()
	-- SL[pn].Streams is initially set (and updated in CourseMode)
	-- in ./ScreenGameplay in/MeasureCounterAndModsLevel.lua
	SL[pn].MeasuresCompleted = 0
	streams = SL[pn].Streams
	streamIndex = 1
	prevMeasure = -1

	for actor in ivalues(bmt) do
		actor:visible(true)
	end
end

-- Returns whether or not we've reached the end of this stream segment.
local IsEndOfStream = function(currMeasure, Measures, streamIndex)
	if Measures[streamIndex] == nil then return false end

	-- a "segment" can be either stream or rest
	local segmentStart = Measures[streamIndex].streamStart
	local segmentEnd   = Measures[streamIndex].streamEnd

	local currStreamLength = segmentEnd - segmentStart
	local currCount = math.floor(currMeasure - segmentStart) + 1

	return currCount > currStreamLength
end

local GetTextForMeasure = function(currBeat, currMeasure, Measures, streamIndex, isLookAhead)
	if currMeasure < 0 then
		if not isLookAhead then
			-- Measures[1] is guaranteed to exist as we check for non-empty tables at the start of Update() below.
			if not Measures[1].isBreak then
				-- currMeasure can be negative. If the first thing is a stream, then denote that "negative space" as a rest.
				return "(" .. math.floor((currBeat/4 * -1) + 1*multiplier) .. ")"
			else
				-- If the first thing is a break, then add the negative space to the existing break count
				local segmentStart = Measures[1].streamStart
				local segmentEnd   = Measures[1].streamEnd
				local currStreamLength = segmentEnd - segmentStart
				return "(" .. math.floor((math.floor(currBeat/4 * -1) + 1 + currStreamLength) * multiplier) .. ")"
			end
		else
			if not Measures[1].isBreak then
				-- Push all the stream segments back by one since we're adding an additional ephemeral break.
				streamIndex = streamIndex - 1
			end
		end
	end
	if Measures[streamIndex] == nil then return "" end

	-- A "segment" can be either stream or rest
	local segmentStart = Measures[streamIndex].streamStart
	local segmentEnd   = Measures[streamIndex].streamEnd

	local currStreamLength = math.floor((segmentEnd - segmentStart) * multiplier)
	local currCount = math.floor((currBeat/4 - segmentStart) * multiplier) + 1

	local text = ""
	if Measures[streamIndex].isBreak then
		if mods.MeasureCounterLookahead > 0 then
			if not isLookAhead then
				local remainingRest = currStreamLength - currCount + 1

				-- Ensure that the rest count is in range of the total length.
				text = "(" .. remainingRest .. ")"
			else
				text = "(" .. currStreamLength .. ")"
			end
		end
	else
		if not isLookAhead and currCount ~= 0 then
			text = tostring(currCount .. "/" .. currStreamLength)
		else
			text = tostring(currStreamLength)
		end
	end
	return text
end

local Update = function(self, delta)
	-- Check to make sure we even have any streams populated to display.
	if not streams or not streams.Measures or #streams.Measures == 0 then return end

	-- Things to look into:
	-- 1. Does PlayerState:GetSongPosition() take split timing into consideration?  Do we need to?
	-- 2. This assumes each measure is comprised of exactly 4 beats.  Is it safe to assume this?
	local currMeasure = (math.floor(PlayerState:GetSongPosition():GetSongBeatVisible()))/4
	local currBeat = (math.floor(PlayerState:GetSongPosition():GetSongBeatVisible()))

	-- If a new measure has occurred
	if currMeasure > prevMeasure then
		prevMeasure = currMeasure

		-- If we've reached the end of the stream, we want to get values for the next stream.
		if IsEndOfStream(currMeasure, streams.Measures, streamIndex) then
			streamIndex = streamIndex + 1
		end

		-- Update the "measures until empty break" counter if it exists
		if emptyBreakCounter then
			local measuresUntilEmptyBreak = GetMeasuresUntilNextEmptyBreak(currMeasure, streams.Measures, streamIndex)
			if measuresUntilEmptyBreak > 0 then
				-- Only show the counter if we're not currently in an empty break
				emptyBreakCounter:settext(measuresUntilEmptyBreak)
				emptyBreakCounter:diffuse(1, 1, 0, 1) -- Yellow color
			else
				-- If we're in an empty break or there are no more empty breaks, hide the counter
				emptyBreakCounter:settext("")
			end
		end

		for i=1,lookAhead+1 do
			-- Only the first one is the main counter, the other ones are lookaheads.
			local isLookAhead = i ~= 1
			-- We're looping forwards, but the BMTs are indexed in the opposite direction.
			-- Adjust indices accordingly.
			local adjustedIndex = lookAhead+2-i
			local text = GetTextForMeasure(currBeat, currMeasure, streams.Measures, streamIndex + i - 1, isLookAhead)
			bmt[adjustedIndex]:settext(text)
			-- We can hit nil when we've run out of streams/breaks for the song. Just hide these BMTs.
			if streams.Measures[streamIndex + i - 1] == nil then
				bmt[adjustedIndex]:visible(false)

			-- rest count
			elseif streams.Measures[streamIndex + i - 1].isBreak then
				-- Check if this is an empty break (no notes at all)
				if streams.Measures[streamIndex + i - 1].isEmpty then
					-- Empty breaks should be green
					if not isLookAhead then
						bmt[adjustedIndex]:diffuse(0.2, 0.9, 0.2, 1) -- Bright green for active empty breaks
					else
						bmt[adjustedIndex]:diffuse(0.1, 0.7, 0.1, 1) -- Darker green for lookahead empty breaks
					end
				else
					-- Non-empty breaks remain gray as before
					if not isLookAhead then
						bmt[adjustedIndex]:diffuse(0.5, 0.5, 0.5, 1)
					else
						bmt[adjustedIndex]:diffuse(0.4, 0.4, 0.4, 1)
					end
				end

			-- stream count
			else
				-- Make stream lookaheads be lighter than active streams.
				if not isLookAhead then
					if string.find(text, "/") then
						bmt[adjustedIndex]:diffuse(1, 1, 1, 1)
						SL[pn].MeasuresCompleted = SL[pn].MeasuresCompleted + 0.25
					else
						-- If this is a mini-break, make it lighter.
						bmt[adjustedIndex]:diffuse(0.5, 0.5, 0.5 ,1)
					end
				else
					bmt[adjustedIndex]:diffuse(0.45, 0.45, 0.45 ,1)
				end
			end
		end
	end
end

-- I'm not crazy about special-casing "Wendy" to use
-- _wendy small for the Measure/Rest counter, but
-- I'm hesitant to visually alter a feature that
-- so many players have become so reliant on...
local font = mods.ComboFont
if font == "Wendy" or font == "Wendy (Cursed)" then
	font = "Wendy/_wendy small"
else
	font = "_Combo Fonts/" .. font .. "/"
end

-- -----------------------------------------------------------------------

local af = Def.ActorFrame{
	InitCommand=function(self)
		self:xy(GetNotefieldX(player), layout.y)
		self:queuecommand("SetUpdate")
	end,
	SetUpdateCommand=function(self) self:SetUpdateFunction( Update ) end,

	CurrentSongChangedMessageCommand=function(self)
		InitializeMeasureCounter()
	end,
}

-- We iterate backwards since we want the lookaheads to be drawn first in the case the
-- main measure counter expands into them.
for i=lookAhead+1,1,-1 do
	af[#af+1] = LoadFont(font)..{
		InitCommand=function(self)
			-- Add to the collection of BMTs so our AF's update function can easily access them.
			bmt[#bmt+1] = self

			local width = GetNotefieldWidth()
			local NumColumns = GAMESTATE:GetCurrentStyle():ColumnsPerPlayer()
			local columnWidth = width/NumColumns
			if mods.MeasureCounterLeft then
				columnWidth = columnWidth*4/3
			end

			-- Have descending zoom sizes for each new BMT we add.
			self:zoom(0.35 - 0.05 * (i-1)):shadowlength(1):horizalign(center)
			if mods.MeasureCounterVert then
				self:addy(20 * (i-1))
			else
				self:x(columnWidth/lookAhead*2 * (i-1))
			end

			if mods.MeasureCounterLeft then
				self:addx(-columnWidth)
			end
		end
	}
end

-- Add the "measures until empty break" counter
af[#af+1] = LoadFont(font)..{
	InitCommand=function(self)
		-- Store the reference to the counter
		emptyBreakCounter = self

		-- Only show the counter if the ShowEmptyBreakCountdown option is enabled
		if not mods.ShowEmptyBreakCountdown then
			self:visible(false)
			return
		end

		local width = GetNotefieldWidth()
		local NumColumns = GAMESTATE:GetCurrentStyle():ColumnsPerPlayer()
		local columnWidth = width/NumColumns

		-- Position it below the measure counter
		self:zoom(0.3):shadowlength(1):horizalign(center)
		self:y(20) -- Position it below the main counter

		-- If the measure counter is on the left, position this counter on the left too
		if mods.MeasureCounterLeft then
			self:x(-columnWidth)
		else
			self:x(0)
		end

		-- Initialize with empty text
		self:settext("")
	end
}

return af
