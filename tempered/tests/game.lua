local game = {}
local results = os.getenv("TC_RESULTS")

local rRAMG, RAMG_SRAM_ENABLE, RAMG_SRAM_DISABLE = 0x0000, 0x0A, 0x00
local SCREEN_WIDTH = 20
local OW_FACING = { DOWN = 0, UP = 4, LEFT = 8, RIGHT = 12 }
local MAPSTATUS_HANDLE = 2
local PLAYEREVENT_NONE = 0

local HOLD, RELEASE, TRIES = 2, 20, 500

local function log(msg)
	local f = io.open(results .. "/log.txt", "a")
	f:write(msg, "\n")
	f:close()
end

local sym = {}
for line in io.lines(os.getenv("TC_SYM")) do
	local bank, addr, name = line:match("^(%x+):(%x+) (%S+)")
	if bank then
		sym[name] = { bank = tonumber(bank, 16), addr = tonumber(addr, 16) }
	end
end

local charmap, seen = {}, {}
for b = 0, 255 do
	charmap[string.char(b)] = " "
end
for line in io.lines(os.getenv("TC_CHARMAP")) do
	local ch, val = line:match('^%s*charmap%s+"([^<].-)",%s*%$(%x%x)%s*;?')
	-- The first entry for a byte is the English one; Japanese ones come later.
	if ch and not seen[val] then
		seen[val] = true
		charmap[string.char(tonumber(val, 16))] = ch
	end
end

-- A symbol's memory domain and offset, in its own WRAMX bank whatever is mapped.
local function locate(name, offset)
	local s = assert(sym[name], "unknown symbol " .. name)
	local addr = s.addr + (offset or 0)
	if addr >= 0xFF80 then
		return emu.memory.hram, addr - 0xFF80
	end
	if addr < 0xD000 then
		return emu.memory.wram, addr - 0xC000
	end
	return emu.memory.wram, s.bank * 0x1000 + addr - 0xD000
end

local function read8(name)
	local d, o = locate(name)
	return d:read8(o)
end

-- Write a string's bytes to RAM, from a symbol on.
local function write(name, bytes)
	for i = 1, #bytes do
		local d, o = locate(name, i - 1)
		d:write8(o, bytes:byte(i))
	end
end

-- Whether the overworld loop is handling input and no script is running.
local function inOverworld()
	return read8("wMapStatus") == MAPSTATUS_HANDLE and read8("wScriptRunning") == PLAYEREVENT_NONE
end

-- The screen's tiles as text, a row of SCREEN_WIDTH tiles per line.
local function screenText()
	local d, o = locate("wTilemap")
	local rows = {}
	for row in d:readRange(o, sym.wTilemapEnd.addr - sym.wTilemap.addr):gmatch(("."):rep(SCREEN_WIDTH)) do
		rows[#rows + 1] = row:gsub(".", charmap)
	end
	return table.concat(rows, "\n")
end

--- Whether text is anywhere on the screen.
---@param text string
---@return boolean
function game.screenHas(text)
	return screenText():find(text, 1, true) ~= nil
end

--- Save a screenshot to <results>/<name>.png.
---@param name string
function game.screenshot(name)
	emu:screenshot(results .. "/" .. name .. ".png")
end

--- Press a key once, as pressUntil does: released RELEASE frames, then held
--- HOLD frames.
---@param name string a key in C.GB_KEY, such as "A" or "UP"
---@param desc string for the log
function game.press(name, desc)
	local frames = 0
	game.pressUntil(name, desc, function()
		frames = frames + 1
		return frames > RELEASE + HOLD
	end)
end

--- Save the emulator's whole state to a file.
---@param path string
function game.saveState(path)
	assert(emu:saveStateFile(path), "could not save state to " .. path)
end

--- Load the emulator's whole state from a file written by game.saveState.
---@param path string
function game.loadState(path)
	assert(emu:loadStateFile(path), "could not load state from " .. path)
end

--- Let some frames pass.
---@param frames integer
function game.wait(frames)
	for _ = 1, frames do
		coroutine.yield()
	end
end

--- Press a key (released RELEASE frames, then held HOLD frames) until fn() is
--- true, giving up after TRIES total presses. fn() is checked every frame and
--- the key released immediately once it is true.
---@param name string a key in C.GB_KEY, such as "A" or "UP"
---@param desc string for the log
---@param fn fun(): boolean
function game.pressUntil(name, desc, fn)
	local keys = 1 << assert(C.GB_KEY[name], "unknown key " .. name)
	for frame = 0, TRIES * (RELEASE + HOLD) do
		if fn() then
			emu:setKeys(0)
			return log(string.format("reached '%s' after %d presses", desc, frame // (RELEASE + HOLD)))
		end
		emu:setKeys(frame % (RELEASE + HOLD) >= RELEASE and keys or 0)
		coroutine.yield()
	end
	error("could not reach '" .. desc .. "'", 0)
end

--- Press the direction until the player's x/y has changed n times.
---@param dir string "UP", "DOWN", "LEFT" or "RIGHT"
---@param n integer
---@param desc string for the log
function game.walk(dir, n, desc)
	local function position()
		return read8("wXCoord") * 256 + read8("wYCoord")
	end
	local moved, last = 0, position()
	game.pressUntil(dir, desc, function()
		if position() ~= last then
			moved, last = moved + 1, position()
		end
		return moved >= n and inOverworld()
	end)
end

--- Press the direction until the player faces it.
---@param dir string "UP", "DOWN", "LEFT" or "RIGHT"
---@param desc string for the log
function game.face(dir, desc)
	game.pressUntil(dir, desc, function()
		return read8("wPlayerDirection") == OW_FACING[dir]
	end)
end

--- Play from power-on to the bedroom, taking every default.
function game.newGame()
	game.pressUntil("START", "main menu", function()
		return game.screenHas("NEW GAME")
	end)
	game.pressUntil("A", "gender prompt", function()
		return game.screenHas("Boy")
	end)
	game.pressUntil("A", "name prompt", function()
		return game.screenHas("NEW NAME")
	end)
	game.pressUntil("DOWN", "default name", function()
		return game.screenHas("▶CHRIS")
	end)
	game.pressUntil("A", "name saved", function()
		return not game.screenHas("NEW NAME")
	end)
	game.pressUntil("B", "overworld", function()
		return inOverworld() and not game.screenHas("┌")
	end)
end

--- Run a script from the overworld and wait until it's done. Also fix the RNG,
--- animation timer and which third of the screen VBlank copies next, so test
--- results will be stable even if newGame took a different number of frames.
---@param script string bytes of pokecrystal's script commands
function game.runScript(script)
	-- Queue the script as in LoadMemScript, from the enemy party's RAM, which
	-- is free outside of battle. The script is in RAM, so its ROM bank doesn't
	-- matter.
	local addr = sym.wOTPartyMons.addr
	assert(#script <= sym.wOTPartyMonOTs.addr - addr, "script too long")
	write("wOTPartyMons", script)
	write("wMapReentryScriptBank", "\1")
	write("wMapReentryScriptAddress", string.pack("<I2", addr))
	write("wMapReentryScriptQueueFlag", "\1")
	write("hRandomAdd", "R")
	write("hRandomSub", "N")
	write("hVBlankCounter", "\0")
	write("hBGMapThird", "\0")
	game.pressUntil("B", "script", function()
		return read8("wMapReentryScriptQueueFlag") == 0 and inOverworld() and read8("wLandmarkSignTimer") == 0
	end)
end

--- Save through the Start menu and write cartridge RAM to a .sav file.
---@param path string
function game.save(path)
	game.pressUntil("START", "start menu", function()
		return game.screenHas("SAVE")
	end)
	game.pressUntil("DOWN", "save highlighted", function()
		return game.screenHas("▶SAVE")
	end)
	game.pressUntil("A", "save prompt", function()
		return game.screenHas("save the game?")
	end)
	game.pressUntil("A", "save saved", function()
		return game.screenHas("saved")
	end)
	emu:write8(rRAMG, RAMG_SRAM_ENABLE)
	local sram = emu.memory.sram:readRange(0, emu.memory.sram:size())
	emu:write8(rRAMG, RAMG_SRAM_DISABLE)
	local f = io.open(path, "wb")
	f:write(sram)
	f:close()
end

--- Run fn one frame at a time, then exit mGBA with its result.
---@param fn fun()
function game.run(fn)
	local co, frame = coroutine.create(fn), 0
	callbacks:add("frame", function()
		frame = frame + 1
		local ok, err = coroutine.resume(co)
		if ok and coroutine.status(co) ~= "dead" then
			return
		end
		log(ok and string.format("pass at frame %d", frame) or "error: " .. tostring(err))
		if not ok then
			pcall(function()
				log(string.format(
					"player at map %d:%d (%d,%d)",
					read8("wMapGroup"),
					read8("wMapNumber"),
					read8("wXCoord"),
					read8("wYCoord")
				))
				local f = io.open(results .. "/final.txt", "w")
				f:write(screenText(), "\n")
				f:close()
				game.screenshot("final")
			end)
		end
		os.exit(ok and 0 or 1)
	end)
end

return game
