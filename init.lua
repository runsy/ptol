--
-- Ptolomey King Protector
-- License:GPLv3
--
local modname = minetest.get_current_modname()
local S = minetest.get_translator(modname)
local modpath = minetest.get_modpath(modname)
local ptol = {}
ptol.settings = {}
ptol.players = {}
ptol.warnings = {}
local static_spawnpoint = minetest.setting_get_pos("static_spawnpoint")

--Settings

local settings = Settings(modpath .. "/ptol.conf")
ptol.settings.shape = settings:get("shape") or "box"
ptol.settings.radius = tonumber(settings:get("radius")) or 120
ptol.settings.world_center = minetest.string_to_pos(settings:get("world_center")) or static_spawnpoint or {x=0, y=0, z=0}
ptol.settings.allowed_angle = tonumber(settings:get("allowed_angle")) or 45
ptol.settings.time = tonumber(settings:get("time")) or 1

local function player_inside_sphere(player_pos, ptol_level)
	player_pos.y = player_pos.y - 1
	--If sphere's centre coordinates is (cx,cy,cz) and its radius is r,
	--then point (x,y,z) is in the sphere if (x−cx)2+(y−cy)2+(z−cz)2<r2.
	local distance_to_center = math.sqrt((player_pos.x - ptol.settings.world_center.x)^2+
		(player_pos.y - ptol.settings.world_center.y)^2 +
		(player_pos.z - ptol.settings.world_center.z)^2)
	--minetest.chat_send_all(tostring(ptol_level))
	if (ptol.settings.radius * ptol_level) >= distance_to_center then
		return true
	else
		return false
	end
end

local function player_inside_box(player_pos, ptol_level)
	player_pos.y = player_pos.y - 1
	local radius = ptol.settings.radius * ptol_level
	local p1 = {
		x = ptol.settings.world_center.x - radius,
		y = ptol.settings.world_center.y - radius,
		z = ptol.settings.world_center.z - radius,
	}
	local p2 = {
		x = ptol.settings.world_center.x + radius,
		y = ptol.settings.world_center.y + radius,
		z = ptol.settings.world_center.z + radius,
	}
	if (p1.x <= player_pos.x) and (player_pos.x <= p2.x)
		and (p1.y <= player_pos.y) and (player_pos.y <= p2.y)
			and (p1.z <= player_pos.z) and (player_pos.z <= p2.z) then
				return true
	else
		return false
	end
end

--Freeze Player Code

function ptol.is_frozen(player)
	return ptol.players[player:get_player_name()]
end

minetest.register_entity("ptol:freeze", {
	-- This entity needs to be visible otherwise the frozen player won't be visible.
	initial_properties = {
		visual = "sprite",
		visual_size = { x = 0, y = 0 },
		textures = {"ptol_blank.png"},
		physical = false, -- Disable collision
		pointable = false, -- Disable selection box
		makes_footstep_sound = false,
	},

	on_step = function(self, dtime)
		local player = self.pname and minetest.get_player_by_name(self.pname)
		if not player or not ptol.is_frozen(player) then
			self.object:remove()
			return
		end
	end,

	on_activate = function(self, staticdata, dtime_s) --on_activate, required
		if dtime_s > 0 then --loaded, nor new
			self.object:remove()
		end
	end,

	set_frozen_player = function(self, player)
		self.pname = player:get_player_name()
		player:set_attach(self.object, "", {x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
		ptol.players[self.pname] = self.object
	end,
})

function ptol.freeze(player)
	local parent = player:get_attach()
	if parent and parent:get_luaentity() and
			parent:get_luaentity().set_frozen_player then
		-- Already attached
		return
	end
	local obj = minetest.add_entity(player:get_pos(), "ptol:freeze")
	obj:get_luaentity():set_frozen_player(player)
	ptol.show_warning(player)
	minetest.sound_play("ptol_warning", {to_player = player:get_player_name(), gain = 1.0, max_hear_distance = 10,})
end

function ptol.unfreeze(player)
	local player_name = player:get_player_name()
	ptol.players[player_name]:remove() --remove the entity
	ptol.players[player_name] = nil --remove the player registry
	ptol.remove_warning(player)
end

function ptol.show_warning(player)
	local hud_id = player:hud_add({
		hud_elem_type = "text",
		position = {x = 0.5, y = 0.5},
		offset = {x = 0,   y = 0},
		text = S("You have reached the limits of your world.\nTurn around and go back where you came from."),
		alignment = {x = 0, y = 0}, -- center aligned
		scale = {x = 100, y = 100}, -- covered later
	})
	ptol.warnings[player:get_player_name()] = hud_id
end

function ptol.remove_warning(player)
	player:hud_remove(ptol.warnings[player:get_player_name()])
end

minetest.register_on_leaveplayer(function(player)
	if ptol.is_frozen(player) then
		ptol.unfreeze(player)
	end
end)

local timer = 0

minetest.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer <= ptol.settings.time then
		return
	else
		timer = 0
	end
	for _, player in pairs(minetest.get_connected_players()) do
		local player_pos = player:get_pos()
		local ptol_level = player:get_meta():get_int("ptol:level")
		if ptol_level == 0 then
			ptol_level = 1
		end
		--minetest.chat_send_all(tostring(ptol_level))
		local player_inside
		if ptol.settings.shape == "sphere" then
			player_inside = player_inside_sphere(player_pos, ptol_level)
		else
			player_inside = player_inside_box(player_pos, ptol_level)
		end
		local frozen = ptol.is_frozen(player)
		if not player_inside then
			local dir_to_center = vector.direction(player_pos, ptol.settings.world_center)
			local player_dir = player:get_look_dir()
			local angle_to_center = math.deg(vector.angle(dir_to_center, player_dir))
			--minetest.chat_send_all(tostring(angle_to_center))
			--minetest.chat_send_all(tostring(angle_to_center)..":"..tostring(ptol.settings.allowed_angle))
			local controls = player:get_player_control()
			local not_allowed_control = false
			if controls["down"] or controls["right"] or controls["left"] then
				not_allowed_control = true
			end
			if not(frozen) and ((angle_to_center > ptol.settings.allowed_angle) or not_allowed_control) then
				ptol.freeze(player)
				--minetest.chat_send_all("freeze")
			elseif frozen and (angle_to_center <= ptol.settings.allowed_angle) and not(not_allowed_control) then
				ptol.unfreeze(player)
				--minetest.chat_send_all("unfreeze")
			end
		else
			if frozen then
				ptol.unfreeze(player)
			end
		end
	end
end)

--COMMANDS

minetest.register_chatcommand("ptol", {
	privs = {
        server = true,
    },
	description = "Ptolomey Commands",
    func = function(name, param)
		local player_name, value
		local i = 0
		for word in string.gmatch(param, "([%a%d_-]+)") do
			if i == 0 then
				player_name = word
			else
				value = word
			end
			i = i + 1
		end
		local player = minetest.get_player_by_name(player_name)
		if not player then
			return true, "Error: The player does not exist or not online."
		end
		local level = tonumber(value)
		if not level then
			return true, "Error: Value of the level missed."
		end
		player:get_meta():set_int("ptol:level", level)
		minetest.chat_send_player(name, "The level for "..player_name.." ".."set to".." "..value)
    end,
})
