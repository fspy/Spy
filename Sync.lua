-- Spy for Forever: share the Kill On Sight list with other players, live.
--
-- A hidden custom chat channel carries addon messages (C_ChatInfo, "CHANNEL"),
-- the same technique Happy Camper uses for camps. The messages never appear in
-- chat; only addons in the channel see them. Party, raid and whisper addon
-- messages work too and are used when the channel is unavailable.
--
-- The game may refuse a channel (crowded, locked or switched off) with
-- InvalidChannel; messages wait in a queue, are retried, and move to a backup
-- channel (SpyKOS, SpyKOSB, ... SpyKOSE). A private group should pick its own
-- channel name, e.g. /spysync channel spy-kos-my-guild.
--
-- What is shared: Kill On Sight entries, their reasons and the player's note.
-- Ignore and watch lists stay private. Everyone in the channel with the option
-- on can add and remove entries, so it is opt-in.
--
-- Conflicts use the server clock (GetServerTime, the same for every player): the
-- later change wins, removals leave a tombstone, and entries with the same
-- timestamp have their reasons merged.

local AceLocale = LibStub("AceLocale-3.0")
local L = AceLocale:GetLocale("Spy", true)

local PREFIX = "SpyKOS"
local PROTOCOL = 1
local MAX_MESSAGE = 250          -- the game truncates addon messages past 255
local SEND_INTERVAL = 1          -- seconds between addon messages
local MAX_RETRIES = 5
local JOIN_INTERVAL = 5
local HELLO_COOLDOWN = 20
local REQ_COOLDOWN = 10
local SNAP_COOLDOWN = 45
local SNAP_TIMEOUT = 180
local FLUSH_DELAY = 0.4
local MAX_SYNC_ENTRIES = 300
local NOTE_SYNC_LIMIT = 60
local TOMBSTONE_DAYS = 90

local RETRY_RESULTS = { [3] = true, [8] = true, [11] = true }
local INVALID_CHANNEL = (Enum and Enum.SendAddonMessageResult
	and Enum.SendAddonMessageResult.InvalidChannel) or 7

local reasonCode, codeReason = {}, {}

local function BuildReasonMaps()
	if next(reasonCode) then
		return
	end
	for category = 1, Spy_KOSReasonListLength or 0 do
		local data = Spy_KOSReasonList[category]
		if data and data.content then
			for index, text in ipairs(data.content) do
				local code = category .. "." .. index
				reasonCode[text] = code
				codeReason[code] = text
			end
		end
	end
end

local function Now()
	return (GetServerTime and GetServerTime()) or time()
end

local function State()
	SpyPerCharDB.SyncData = SpyPerCharDB.SyncData or {}
	local state = SpyPerCharDB.SyncData
	state.version = 1
	state.entries = state.entries or {}
	state.removed = state.removed or {}
	return state
end

local function Escape(text)
	return (tostring(text or ""):gsub("[%%~;|\n\r]", function(char)
		if char == "\n" then
			return "%0A"
		elseif char == "\r" then
			return "%0D"
		end
		return ("%%%02X"):format(char:byte())
	end))
end

local function Unescape(text)
	return (tostring(text or ""):gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

local function CopyReasons(reasons)
	local copy = {}
	for reason, value in pairs(reasons or {}) do
		if value then
			copy[reason] = value
		end
	end
	return copy
end

local function UnionReasons(left, right)
	local union = CopyReasons(left)
	for reason, value in pairs(right or {}) do
		if value then
			union[reason] = value
		end
	end
	return union
end

local function EncodeReasons(reasons)
	local parts = {}
	for reason, value in pairs(reasons or {}) do
		if value then
			parts[#parts + 1] = reasonCode[reason] or ("t" .. Escape(reason))
		end
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function DecodeReasons(text)
	local reasons = {}
	for token in (text or ""):gmatch("[^,]+") do
		if token:sub(1, 1) == "t" then
			local reason = Unescape(token:sub(2))
			if reason ~= "" then
				reasons[reason] = true
			end
		else
			local reason = codeReason[token]
			if reason then
				reasons[reason] = true
			end
		end
	end
	return reasons
end

local function EncodeEntry(name, entry)
	local note = tostring(entry.note or "")
	if #note > NOTE_SYNC_LIMIT then
		note = note:sub(1, NOTE_SYNC_LIMIT)
	end
	return table.concat({
		Escape(name),
		tostring(entry.added or 0),
		tostring(entry.updated or 0),
		EncodeReasons(entry.reasons),
		Escape(note),
	}, "~")
end

local function DecodeEntry(record)
	local name, added, updated, reasons, note = strsplit("~", record)
	if not name then
		return
	end
	name = Unescape(name)
	if name == "" then
		return
	end
	return name, {
		added = tonumber(added) or 0,
		updated = tonumber(updated) or 0,
		reasons = DecodeReasons(reasons),
		note = Unescape(note or ""),
	}
end

local function NoteStore()
	SpyDB.playerNotes = SpyDB.playerNotes or {}
	local realm = tostring(Spy.StoreRealm or Spy.RealmName or "?")
	SpyDB.playerNotes[realm] = SpyDB.playerNotes[realm] or {}
	return SpyDB.playerNotes[realm]
end

local function SetNote(name, text)
	if type(name) ~= "string" or name == "" or not SpyDB then
		return
	end
	local store = NoteStore()
	store[name] = (type(text) == "string" and text ~= "") and text or nil
end

local function Digest()
	local state = State()
	local parts = {}
	for name, entry in pairs(state.entries) do
		if not state.removed[name] then
			parts[#parts + 1] = name .. ":" .. tostring(entry.updated or 0)
		end
	end
	for name, timestamp in pairs(state.removed) do
		parts[#parts + 1] = name .. "!" .. tostring(timestamp)
	end
	table.sort(parts)
	local checksum, count = 5381, #parts
	for index = 1, #parts do
		local part = parts[index]
		for byte = 1, #part do
			checksum = (checksum * 33 + part:byte(byte)) % 4294967296
		end
	end
	return ("%08x"):format(checksum), count
end

local function GroupChannel()
	if IsInRaid() then
		return "RAID"
	end
	if GetNumGroupMembers() > 0 then
		return "PARTY"
	end
end

local function ShortName(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	return (Ambiguate and Ambiguate(name, "short")) or name
end

function Spy:SyncEnabled()
	return Spy.db and Spy.db.profile and Spy.db.profile.SyncKOS == true and Spy.IsEnabled ~= false
end

function Spy:SyncChannelName()
	local name = Spy.db and Spy.db.profile and Spy.db.profile.SyncChannel
	if type(name) ~= "string" then
		return nil
	end
	name = strtrim(name)
	return name ~= "" and name or nil
end

function Spy:SyncChannelNames()
	local base = self:SyncChannelName()
	if not base then
		return {}
	end
	return { base, base .. "B", base .. "C", base .. "D", base .. "E" }
end

function Spy:SyncActiveChannel()
	local names = self:SyncChannelNames()
	if self.SyncChannelIndex then
		local name = names[self.SyncChannelIndex]
		if name then
			local id = GetChannelName(name)
			if type(id) == "number" and id > 0 then
				return name, id
			end
		end
	end
	for index = 1, #names do
		local id = GetChannelName(names[index])
		if type(id) == "number" and id > 0 then
			self.SyncChannelIndex = index
			return names[index], id
		end
	end
end

function Spy:SyncJoinChannel(announce)
	if not self:SyncEnabled() or not self:SyncChannelName() then
		return
	end
	local _, id = self:SyncActiveChannel()
	if id then
		if announce then
			self:SyncHello(true)
		end
		return
	end
	local current = GetTime()
	if self.SyncJoinAt and current - self.SyncJoinAt < JOIN_INTERVAL then
		return
	end
	self.SyncJoinAt = current
	self.SyncChannelIndex = self.SyncChannelIndex or 1
	local names = self:SyncChannelNames()
	local name = names[self.SyncChannelIndex]
	if not name then
		return
	end
	pcall(JoinTemporaryChannel, name)
	if self.SyncDebug then
		DEFAULT_CHAT_FRAME:AddMessage(("|cff9933ff[Spy]|r sync: joining channel %s"):format(name))
	end
	if announce then
		C_Timer.After(2, function()
			Spy:SyncHello(true)
		end)
	end
end

function Spy:SyncNextChannel()
	local names = self:SyncChannelNames()
	self.SyncJoinTries = nil
	self.SyncChannelIndex = (self.SyncChannelIndex or 1) + 1
	if self.SyncChannelIndex > #names then
		self.SyncChannelFailed = true
		if not self.SyncChannelWarned then
			self.SyncChannelWarned = true
			DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncChannelFailed"])
		end
		return
	end
	self.SyncJoinAt = nil
	C_Timer.After(2, function()
		Spy:SyncJoinChannel(true)
	end)
end

-- A channel join can fail silently while the game is still settling its channel
-- list. This watcher keeps trying, and moves to a backup after three misses.
function Spy:SyncWatch()
	if not self:SyncEnabled() or not self:SyncChannelName() or self.SyncChannelFailed then
		return
	end
	local _, id = self:SyncActiveChannel()
	if id then
		self.SyncJoinTries = nil
		if not self.SyncHelloAt then
			self:SyncHello(true)
		end
		return
	end
	local current = GetTime()
	if self.SyncJoinAt and current - self.SyncJoinAt <= 12 then
		return
	end
	self.SyncJoinTries = (self.SyncJoinTries or 0) + 1
	if self.SyncJoinTries > 3 then
		self.SyncJoinTries = nil
		self:SyncNextChannel()
	else
		self.SyncJoinAt = nil
		self:SyncJoinChannel(false)
	end
end

-- Sending ----------------------------------------------------------------------

function Spy:SyncQueueMessage(chatType, body, target, priority)
	if not self:SyncEnabled() then
		return false
	end
	local message = PROTOCOL .. "|" .. body
	if #message > MAX_MESSAGE then
		return false
	end
	self.SyncQueue = self.SyncQueue or {}
	local item = {
		message = message,
		chatType = chatType,
		target = target,
		tries = 0,
		queuedAt = GetTime(),
	}
	if priority == "ALERT" then
		table.insert(self.SyncQueue, 1, item)
	else
		self.SyncQueue[#self.SyncQueue + 1] = item
	end
	self:SyncPumpLater(0)
	return true
end

function Spy:SyncPumpLater(delay)
	if self.SyncPumpTimer then
		return
	end
	self.SyncPumpTimer = true
	C_Timer.After(delay or SEND_INTERVAL, function()
		Spy.SyncPumpTimer = nil
		Spy:SyncPump()
	end)
end

function Spy:SyncPump()
	if not self:SyncEnabled() then
		self.SyncQueue = {}
		return
	end
	local queue = self.SyncQueue or {}
	local item = queue[1]
	if not item then
		return
	end
	if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		self:SyncPumpLater(2)
		return
	end

	local chatType, target = item.chatType, item.target
	if chatType == "CHANNEL" then
		local _, id = self:SyncActiveChannel()
		if not id then
			self:SyncJoinChannel(false)
			if self.SyncChannelFailed then
				-- Every channel was refused: use the group instead.
				table.remove(queue, 1)
				local group = GroupChannel()
				if group then
					item.chatType = group
					item.target = nil
					item.tries = 0
					item.queuedAt = GetTime()
					table.insert(queue, 1, item)
					self:SyncPumpLater(1)
				end
				return
			end
			-- The channel is still being joined. Keep the message, but not forever.
			if GetTime() - item.queuedAt > 300 then
				table.remove(queue, 1)
				return
			end
			self:SyncPumpLater(3)
			return
		end
		target = tostring(id)
	elseif chatType == nil then
		chatType = GroupChannel()
		if not chatType then
			table.remove(queue, 1)
			return
		end
	end

	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.message, chatType, target)
	if not ok then
		if self.SyncDebug then
			DEFAULT_CHAT_FRAME:AddMessage(("|cff9933ff[Spy]|r sync: send error: %s"):format(tostring(result)))
		end
		table.remove(queue, 1)
	else
		if self.SyncDebug then
			local operation = item.message:match("^%d+|([A-Z]+)|") or "?"
			DEFAULT_CHAT_FRAME:AddMessage(("|cff9933ff[Spy]|r sync: send %s %s %s result %s"):format(
				operation, tostring(chatType), tostring(target or "-"), tostring(result)))
		end
		if result == 0 or result == nil then
			table.remove(queue, 1)
		elseif result == INVALID_CHANNEL and chatType == "CHANNEL" then
			table.remove(queue, 1)
			self:SyncNextChannel()
		elseif RETRY_RESULTS[result] and item.tries < MAX_RETRIES then
			item.tries = item.tries + 1
		else
			table.remove(queue, 1)
		end
	end
	self:SyncPumpLater(SEND_INTERVAL)
end

function Spy:SyncPartnerNames()
	local partners = Spy.db and Spy.db.profile and Spy.db.profile.SyncPartners
	local names = {}
	if type(partners) ~= "table" then
		return names
	end
	for name, enabled in pairs(partners) do
		if enabled and type(name) == "string" and name ~= "" then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end

function Spy:SyncSend(body, priority, target)
	if target then
		return self:SyncQueueMessage("WHISPER", body, target, priority)
	end
	local sent = false
	if self:SyncChannelName() and not self.SyncChannelFailed then
		sent = self:SyncQueueMessage("CHANNEL", body, nil, priority) or sent
	else
		local group = GroupChannel()
		if group then
			sent = self:SyncQueueMessage(group, body, nil, priority) or sent
		end
	end
	-- Partners get the same message by whisper, so a broken channel is not fatal.
	for _, name in ipairs(self:SyncPartnerNames()) do
		if self:SyncQueueMessage("WHISPER", body, name, priority) then
			sent = true
		end
	end
	return sent
end

function Spy:SyncHello(force, target)
	if not self:SyncEnabled() then
		return
	end
	if not target then
		local current = time()
		if not force and self.SyncHelloAt and current - self.SyncHelloAt < HELLO_COOLDOWN then
			return
		end
		self.SyncHelloAt = current
	end
	self:SyncSend("HELLO|" .. (Digest()) .. "|" .. tostring(self.FactionName or ""), "NORMAL", target)
end

local function SplitRecords(records, limit)
	local chunks, current = {}, ""
	for index = 1, #records do
		local record = records[index]
		if #record > limit then
			-- Keep the entry valid: drop the note first, then cut if still too long.
			local withoutNote = record:match("^(.-~.-~.-~.-)~")
			if withoutNote then
				record = withoutNote
			end
		end
		if #record > limit then
			record = record:sub(1, limit)
		end
		local piece = current == "" and record or (";" .. record)
		if #current + #piece > limit then
			chunks[#chunks + 1] = current
			current = record
		else
			current = current .. piece
		end
	end
	if current ~= "" then
		chunks[#chunks + 1] = current
	end
	return chunks
end

function Spy:SyncSendSnapshot(reason, target)
	if not self:SyncEnabled() then
		return
	end
	if not target then
		local current = time()
		if reason ~= "manual" and self.SyncSnapshotAt and current - self.SyncSnapshotAt < SNAP_COOLDOWN then
			return
		end
		self.SyncSnapshotAt = current
	end

	local state = State()
	local records, sent = {}, 0
	for name, entry in pairs(state.entries) do
		if not state.removed[name] then
			if sent < MAX_SYNC_ENTRIES then
				records[#records + 1] = "E" .. EncodeEntry(name, entry)
				sent = sent + 1
			elseif not self.SyncWarnedTooMany then
				self.SyncWarnedTooMany = true
				DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncTooMany"]:format(MAX_SYNC_ENTRIES))
			end
		end
	end
	for name, timestamp in pairs(state.removed) do
		records[#records + 1] = "D" .. Escape(name) .. "~" .. tostring(timestamp)
	end
	table.sort(records)
	if #records == 0 then
		return
	end

	local digest = Digest()
	local faction = tostring(self.FactionName or "")
	local snapshot = tostring(time()) .. tostring(math.random(100, 999))
	local head = "SNAP|" .. snapshot .. "|"
	local tail = "|" .. digest .. "|" .. faction .. "|"
	local reserve = #tostring(PROTOCOL) + 2 + #head + 10 + #tail
	local chunks = SplitRecords(records, MAX_MESSAGE - reserve)
	for index = 1, #chunks do
		self:SyncSend(("%s%d/%d%s%s"):format(head, index, #chunks, tail, chunks[index]), "BULK", target)
	end
end

-- Applying ----------------------------------------------------------------------

function Spy:SyncApplyEntry(name, entry)
	local wasApplying = self.SyncApplying
	self.SyncApplying = true
	if not SpyPerCharDB.PlayerData[name] then
		self:UpdatePlayerStatus(name, nil, nil, nil, nil, self.EnemyFactionName, true, nil, nil)
	end
	SpyPerCharDB.KOSData[name] = entry.added
	local data = SpyPerCharDB.PlayerData[name]
	if data then
		data.kos = 1
		if not data.time or data.time > entry.added then
			data.time = entry.added
		end
		data.reason = next(entry.reasons) and CopyReasons(entry.reasons) or nil
	end
	if entry.note and entry.note ~= "" then
		SetNote(name, entry.note)
	end
	local state = State()
	state.entries[name] = {
		added = entry.added,
		updated = entry.updated,
		reasons = CopyReasons(entry.reasons),
		note = entry.note,
	}
	state.removed[name] = nil
	self.SyncApplying = wasApplying
end

function Spy:SyncMergeEntry(name, entry, source)
	if type(name) ~= "string" or name == "" then
		return false
	end
	local state = State()
	local removed = state.removed[name]
	if removed and removed > (entry.updated or 0) then
		return false
	end
	local current = state.entries[name]
	if current and (current.updated or 0) > (entry.updated or 0) then
		return false
	end
	if current and current.updated == entry.updated then
		entry.reasons = UnionReasons(current.reasons, entry.reasons)
		entry.note = entry.note ~= "" and entry.note or current.note
	end
	local added = entry.added or 0
	if current and (current.added or 0) > 0 then
		added = (added > 0 and math.min(added, current.added)) or current.added
	end
	if added == 0 then
		added = Now()
	end
	entry.added = added
	entry.updated = math.max((current and current.updated) or 0, entry.updated or 0)
	if entry.updated == 0 then
		entry.updated = added
	end
	self:SyncApplyEntry(name, entry)
	if self.SyncDebug then
		DEFAULT_CHAT_FRAME:AddMessage(("|cff9933ff[Spy]|r sync: %s %s from %s"):format(
			current and "updated" or "added", name, tostring(source or "?")))
	end
	return true
end

function Spy:SyncMergeRemoved(name, timestamp, source)
	if type(name) ~= "string" or name == "" then
		return false
	end
	local state = State()
	local current = state.entries[name]
	if current and (current.updated or 0) > timestamp then
		return false
	end
	local wasApplying = self.SyncApplying
	self.SyncApplying = true
	if SpyPerCharDB.KOSData[name] then
		self:RemoveKOSData(name)
	end
	self.SyncApplying = wasApplying
	state.entries[name] = nil
	state.removed[name] = math.max(state.removed[name] or 0, timestamp)
	if self.SyncDebug then
		DEFAULT_CHAT_FRAME:AddMessage(("|cff9933ff[Spy]|r sync: removed %s from %s"):format(name, tostring(source or "?")))
	end
	return true
end

function Spy:SyncRefresh()
	if InCombatLockdown() then
		self.SyncRefreshPending = true
		return
	end
	self.SyncRefreshPending = nil
	self:RegenerateKOSGuildList()
	if self.MainWindow then
		self:RefreshCurrentList()
	end
	if SpyStats and SpyStats.Recalulate then
		SpyStats:Recalulate()
	end
end

function Spy:SyncReceiveSnapshot(payload, source)
	local changed = false
	for record in (payload or ""):gmatch("[^;]+") do
		local kind = record:sub(1, 1)
		if kind == "E" then
			local name, entry = DecodeEntry(record:sub(2))
			if name and entry and self:SyncMergeEntry(name, entry, source) then
				changed = true
			end
		elseif kind == "D" then
			local name, timestamp = record:sub(2):match("^([^~]+)~(%d+)$")
			if name and timestamp and self:SyncMergeRemoved(Unescape(name), tonumber(timestamp), source) then
				changed = true
			end
		end
	end
	if changed then
		self:SyncRefresh()
	end
	return changed
end

function Spy:SyncHandleSnapshot(source, snapshot, index, total, digest, faction, payload)
	if not total or total < 1 or not index or index < 1 or index > total then
		return
	end
	local snapshots = self.SyncSnapshots or {}
	self.SyncSnapshots = snapshots
	local key = tostring(source or "?") .. "|" .. tostring(snapshot)
	local current = time()

	for id, data in pairs(snapshots) do
		if current - data.at > SNAP_TIMEOUT then
			snapshots[id] = nil
		end
	end

	local data = snapshots[key]
	if not data then
		data = { parts = {}, received = 0, at = current }
		snapshots[key] = data
	end
	if data.parts[index] == nil then
		data.parts[index] = payload or ""
		data.received = data.received + 1
	end
	data.total = total
	data.digest = digest
	data.faction = faction
	data.at = current
	if data.received < total then
		return
	end

	local parts = {}
	for part = 1, total do
		parts[#parts + 1] = data.parts[part] or ""
	end
	snapshots[key] = nil
	if faction ~= "" and self.FactionName and faction ~= self.FactionName then
		return
	end
	if self:SyncReceiveSnapshot(table.concat(parts), source) and Digest() ~= digest then
		C_Timer.After(math.random(5, 15), function()
			Spy:SyncHello(true)
		end)
	end
end

function Spy:SyncHandle(operation, rest, source, isWhisper)
	if operation == "HELLO" then
		local digest, faction = rest:match("^([0-9a-f]+)|(.*)$")
		if not digest or (faction ~= "" and self.FactionName and faction ~= self.FactionName) then
			return
		end
		if digest ~= (Digest()) then
			local current = time()
			if not self.SyncRequestAt or current - self.SyncRequestAt >= REQ_COOLDOWN then
				self.SyncRequestAt = current
				if isWhisper then
					self:SyncSend("REQ|" .. (Digest()), "NORMAL", source)
				else
					self:SyncSend("REQ|" .. (ShortName(source) or "*") .. "|" .. (Digest()), "NORMAL")
				end
			end
		end

	elseif operation == "REQ" then
		local target, digest
		if isWhisper then
			digest = rest
			target = source
		else
			target, digest = rest:match("^([^|]*)|([0-9a-f]+)$")
		end
		if not isWhisper and target and target ~= "" and target ~= "*"
			and ShortName(target) ~= ShortName(self.CharacterName) then
			return
		end
		if digest ~= (Digest()) then
			self:SyncSendSnapshot("requested by " .. tostring(source), isWhisper and source or nil)
		end

	elseif operation == "SNAP" then
		local snapshot, index, total, digest, faction, payload =
			rest:match("^([^|]*)|(%d+)/(%d+)|([0-9a-f]+)|([^|]*)|(.*)$")
		if not snapshot then
			return
		end
		self:SyncHandleSnapshot(source, snapshot, tonumber(index), tonumber(total), digest, faction, payload)

	elseif operation == "SET" then
		local name, entry = DecodeEntry(rest)
		if name and entry and self:SyncMergeEntry(name, entry, source) then
			self:SyncRefresh()
		end

	elseif operation == "DEL" then
		local name, timestamp = rest:match("^([^|]+)|(%d+)$")
		if name and timestamp and self:SyncMergeRemoved(Unescape(name), tonumber(timestamp), source) then
			self:SyncRefresh()
		end

	elseif operation == "PING" then
		self:SyncSend("PONG|" .. tostring(rest or ""), "NORMAL", isWhisper and source or nil)
		DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncPingReceived"]:format(tostring(source or "?")))

	elseif operation == "PONG" then
		DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncPongReceived"]:format(tostring(source or "?")))
	end
end

function Spy:SyncAddonEvent(event, prefix, message, channel, sender)
	if prefix ~= PREFIX or type(message) ~= "string" or sender == self.CharacterName then
		return
	end
	if self.SyncDebug then
		local operation = message:match("^%d+|([A-Z]+)|") or "?"
		DEFAULT_CHAT_FRAME:AddMessage(("|cff9933ff[Spy]|r sync: recv %s from %s via %s"):format(
			operation, tostring(sender), tostring(channel)))
	end
	if not self:SyncEnabled() then
		return
	end
	local protocol, operation, rest = message:match("^(%d+)|([A-Z]+)|(.*)$")
	if not protocol or tonumber(protocol) ~= PROTOCOL then
		return
	end
	self:SyncHandle(operation, rest, sender, channel == "WHISPER")
end

function Spy:SyncChannelNotice(event, notice, ...)
	local names = self:SyncChannelNames()
	if #names == 0 then
		return
	end
	local found
	for index = 1, select("#", ...) do
		local value = select(index, ...)
		if type(value) == "string" then
			for nameIndex = 1, #names do
				if value:lower() == names[nameIndex]:lower() then
					found = nameIndex
				end
			end
		end
	end
	if self.SyncDebug then
		DEFAULT_CHAT_FRAME:AddMessage(("|cff9933ff[Spy]|r sync: channel notice %s for %s"):format(
			tostring(notice), tostring(found or "?")))
	end
	if not found then
		return
	end
	if notice == "NOT_ALLOWED_IN_CHANNEL" or notice == "WRONG_PASSWORD" or notice == "BANNED" then
		if found == self.SyncChannelIndex then
			C_Timer.After(2, function()
				Spy:SyncNextChannel()
			end)
		end
	elseif notice == "YOU_JOINED" or notice == "YOU_CHANGED" then
		self.SyncChannelIndex = found
		self.SyncChannelFailed = nil
		self.SyncChannelWarned = nil
		self.SyncJoinTries = nil
		self.SyncJoinAt = nil
		self:SyncHello(true)
	end
end

-- Local changes -------------------------------------------------------------------

function Spy:SyncScheduleFlush()
	if self.SyncFlushPending then
		return
	end
	self.SyncFlushPending = true
	C_Timer.After(FLUSH_DELAY, function()
		Spy.SyncFlushPending = nil
		Spy:SyncFlush()
	end)
end

function Spy:SyncTouch(name)
	if self.SyncApplying or not SpyPerCharDB then
		return
	end
	local state = State()
	local current = Now()
	local added = SpyPerCharDB.KOSData[name]
	if added then
		local entry = state.entries[name]
		if not entry then
			entry = { added = added, reasons = {} }
			state.entries[name] = entry
		end
		entry.added = math.min(entry.added or added, added)
		entry.updated = current
		local data = SpyPerCharDB.PlayerData[name]
		entry.reasons = CopyReasons(data and data.reason)
		entry.note = self.PlayerNote and self:PlayerNote(name) or nil
		state.removed[name] = nil
	else
		if state.entries[name] then
			state.entries[name] = nil
			state.removed[name] = current
		end
	end
	self.SyncDirty = self.SyncDirty or {}
	self.SyncDirty[name] = true
	self:SyncScheduleFlush()
end

function Spy:SyncFlush()
	if not self:SyncEnabled() then
		return
	end
	local state = State()
	local dirty = self.SyncDirty or {}
	self.SyncDirty = {}
	for name in pairs(dirty) do
		local entry = state.entries[name]
		if entry and not state.removed[name] then
			self:SyncSend("SET|" .. EncodeEntry(name, entry), "ALERT")
		elseif state.removed[name] then
			self:SyncSend("DEL|" .. Escape(name) .. "|" .. tostring(state.removed[name]), "ALERT")
		end
	end
end

function Spy:SyncReconcile()
	local state = State()
	local current = Now()
	local seen = {}

	for name, added in pairs(SpyPerCharDB.KOSData or {}) do
		seen[name] = true
		local entry = state.entries[name]
		if not entry then
			-- Seeded entries keep their original age, so a member's first sync
			-- does not overwrite newer reasons from the channel.
			entry = { added = added or current, updated = added or current, reasons = {} }
			state.entries[name] = entry
		end
		local data = SpyPerCharDB.PlayerData[name]
		if data and data.reason then
			entry.reasons = CopyReasons(data.reason)
		end
		local note = self.PlayerNote and self:PlayerNote(name)
		if note then
			entry.note = note
		end
		state.removed[name] = nil
	end

	if state.initialized then
		for name in pairs(state.entries) do
			if not seen[name] and not state.removed[name] then
				state.entries[name] = nil
				state.removed[name] = current
			end
		end
	end
	state.initialized = true

	local cutoff = current - TOMBSTONE_DAYS * 86400
	for name, timestamp in pairs(state.removed) do
		if timestamp < cutoff then
			state.removed[name] = nil
		end
	end
end

-- Events -------------------------------------------------------------------------

function Spy:SyncGroupChanged()
	if not self:SyncEnabled() then
		return
	end
	C_Timer.After(3, function()
		Spy:SyncHello(true)
	end)
end

function Spy:SyncEnteredWorld()
	if not self:SyncEnabled() then
		return
	end
	self.SyncChannelIndex = nil
	self.SyncChannelFailed = nil
	self.SyncJoinTries = nil
	self.SyncJoinAt = nil
	self:SyncJoinChannel(false)
	C_Timer.After(6, function()
		Spy:SyncJoinChannel(true)
	end)
end

function Spy:SyncCombatEnded()
	if self.SyncRefreshPending then
		self:SyncRefresh()
	end
	if self.SyncQueue and #self.SyncQueue > 0 then
		self:SyncPumpLater(1)
	end
end

function Spy:SyncStatus()
	local digest, count = Digest()
	local transport
	if self:SyncChannelName() then
		local name, id = self:SyncActiveChannel()
		if id then
			local members = (GetNumChannelMembers and GetNumChannelMembers(id)) or 0
			transport = L["SyncViaChannel"]:format(name, members, #(self.SyncQueue or {}))
		else
			transport = L["SyncChannelWaiting"]:format(self:SyncChannelName())
		end
	elseif GroupChannel() then
		transport = L["SyncViaGroup"]:format(GroupChannel())
	else
		transport = L["SyncNoTransport"]
	end
	local partners = self:SyncPartnerNames()
	return L["SyncStatus"]:format(count, digest, self:SyncEnabled() and L["On"] or L["Off"],
		transport, #partners > 0 and table.concat(partners, ", ") or L["SyncNoPartners"])
end

function Spy:SyncInitialize()
	BuildReasonMaps()
	State()
	self:SyncReconcile()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	self:RegisterEvent("CHAT_MSG_ADDON", "SyncAddonEvent")
	self:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", "SyncChannelNotice")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "SyncGroupChanged")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "SyncEnteredWorld")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "SyncCombatEnded")
	if not self.SyncWatchTimer then
		self.SyncWatchTimer = C_Timer.NewTicker(10, function()
			Spy:SyncWatch()
		end)
	end
	C_Timer.After(6, function()
		Spy:SyncJoinChannel(false)
	end)
end

-- Local changes: journal them and broadcast the entry.
local baseToggleKOS = Spy.ToggleKOSPlayer
function Spy:ToggleKOSPlayer(kos, player)
	baseToggleKOS(self, kos, player)
	self:SyncTouch(player)
end

local baseSetKOSReason = Spy.SetKOSReason
function Spy:SetKOSReason(name, reason, other)
	baseSetKOSReason(self, name, reason, other)
	self:SyncTouch(name)
end

local baseSetPlayerNote = Spy.SetPlayerNote
function Spy:SetPlayerNote(name, text)
	baseSetPlayerNote(self, name, text)
	self:SyncTouch(name)
end

-- Options -----------------------------------------------------------------------

Spy.options.args.DataOptions.args.SyncKOS = {
	name = L["SyncKOS"],
	desc = L["SyncKOSDescription"],
	type = "toggle",
	order = 13,
	width = "full",
	get = function()
		return Spy.db.profile.SyncKOS == true
	end,
	set = function(_, value)
		Spy.db.profile.SyncKOS = value and true or false
		if value then
			Spy:SyncReconcile()
			Spy.SyncChannelIndex = nil
			Spy.SyncJoinTries = nil
			Spy.SyncJoinAt = nil
			Spy.SyncHelloAt = nil
			Spy:SyncJoinChannel(true)
		end
	end,
}

Spy.options.args.DataOptions.args.SyncChannel = {
	name = L["SyncChannel"],
	desc = L["SyncChannelDescription"],
	type = "input",
	order = 14,
	width = "full",
	get = function()
		return Spy.db.profile.SyncChannel or ""
	end,
	set = function(_, value)
		value = strtrim(value or "")
		Spy.db.profile.SyncChannel = value ~= "" and value or nil
		Spy.SyncChannelIndex = nil
		Spy.SyncChannelFailed = nil
		Spy.SyncChannelWarned = nil
		if value ~= "" then
			Spy:SyncJoinChannel(true)
		end
	end,
}

-- /spysync ----------------------------------------------------------------------

SLASH_SPYSYNC1 = "/spysync"
SlashCmdList["SPYSYNC"] = function(message)
	local command, argument = strtrim(message or ""):match("^(%S*)%s*(.*)$")
	command = command:lower()

	if command == "" or command == "status" then
		DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. Spy:SyncStatus())
	elseif command == "on" then
		Spy.db.profile.SyncKOS = true
		Spy:SyncReconcile()
		Spy.SyncChannelIndex = nil
		Spy.SyncJoinTries = nil
		Spy.SyncJoinAt = nil
		Spy.SyncHelloAt = nil
		Spy:SyncJoinChannel(true)
		DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncOn"])
	elseif command == "off" then
		Spy.db.profile.SyncKOS = false
		DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncOff"])
	elseif command == "now" then
		Spy:SyncJoinChannel(true)
		Spy:SyncHello(true)
		Spy:SyncSendSnapshot("manual")
		DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncNow"])
	elseif command == "channel" then
		local name = strtrim(argument or "")
		if name == "" then
			DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncChannelUsage"])
		elseif name:lower() == "off" then
			Spy.db.profile.SyncChannel = nil
			DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncChannelOff"])
		else
			Spy.db.profile.SyncChannel = name
			Spy.SyncChannelIndex = nil
			Spy.SyncChannelFailed = nil
			Spy.SyncChannelWarned = nil
			Spy.SyncJoinTries = nil
			Spy.SyncJoinAt = nil
			Spy.SyncHelloAt = nil
			Spy:SyncJoinChannel(true)
			DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncChannelJoined"]:format(name))
		end
	elseif command == "whisper" then
		local name = strtrim(argument or "")
		if name == "" then
			DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncWhisperUsage"])
		else
			Spy:SyncHello(true, name)
			Spy:SyncSendSnapshot("manual", name)
			DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncWhisperSent"]:format(name))
		end
	elseif command == "partner" then
		local name = ShortName(strtrim(argument or ""))
		if not name or name == "" then
			local partners = Spy:SyncPartnerNames()
			DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncPartnerList"]:format(
				#partners > 0 and table.concat(partners, ", ") or L["SyncNoPartners"]))
		elseif name:lower() == "off" or name:lower() == "clear" then
			Spy.db.profile.SyncPartners = {}
			DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncPartnersCleared"])
		else
			Spy.db.profile.SyncPartners = Spy.db.profile.SyncPartners or {}
			local enabled = not Spy.db.profile.SyncPartners[name]
			Spy.db.profile.SyncPartners[name] = enabled and true or nil
			if enabled then
				DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncPartnerAdded"]:format(name))
				Spy:SyncHello(true, name)
				Spy:SyncSendSnapshot("manual", name)
			else
				DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncPartnerRemoved"]:format(name))
			end
		end
	elseif command == "test" then
		local name, id = Spy:SyncActiveChannel()
		local metadata = C_AddOns and C_AddOns.GetAddOnMetadata
		local version = metadata and metadata("Spy", "Version") or "?"
		local lines = {
			L["SyncTestVersion"]:format(tostring(version), Spy.db.profile.SyncKOS and L["On"] or L["Off"]),
			L["SyncTestChannel"]:format(tostring(Spy:SyncChannelName() or "-"), tostring(id or "-"),
				tostring(Spy.SyncChannelIndex or "-"), tostring(Spy.SyncChannelFailed or false)),
			L["SyncTestState"]:format(#(Spy.SyncQueue or {}), (select(2, Digest())),
				#Spy:SyncPartnerNames() > 0 and table.concat(Spy:SyncPartnerNames(), ", ") or L["SyncNoPartners"]),
		}
		for _, line in ipairs(lines) do
			DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. line)
		end
		Spy:SyncJoinChannel(false)
		C_Timer.After(2, function()
			local active, activeID = Spy:SyncActiveChannel()
			if not activeID then
				DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncTestNoChannel"])
				return
			end
			local nonce = tostring(time()) .. tostring(math.random(100, 999))
			local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, "1|PING|" .. nonce, "CHANNEL", tostring(activeID))
			DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncTestPing"]:format(
				tostring(active), tostring(ok), tostring(result)))
			for _, partner in ipairs(Spy:SyncPartnerNames()) do
				local ok2, result2 = pcall(C_ChatInfo.SendAddonMessage, PREFIX, "1|PING|" .. nonce, "WHISPER", partner)
				DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncTestWhisper"]:format(
					partner, tostring(ok2), tostring(result2)))
			end
			DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncTestHint"])
		end)
	elseif command == "debug" then
		Spy.SyncDebug = not Spy.SyncDebug
		DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. (Spy.SyncDebug and L["SyncDebugOn"] or L["SyncDebugOff"]))
	else
		DEFAULT_CHAT_FRAME:AddMessage(L["SpySignatureColored"] .. L["SyncHelp"])
	end
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
	Spy:SyncInitialize()
end)
