local tool_names = names.unit_tools

local script_data =
{
  button_actions = {},
  groups = {},
  selected_units = {},
  open_frames = {},
  units = {},
  --unit_groups_to_disband = {},
  indicators = {},
  unit_unselectable = {},
  debug = false,
  marked_for_refresh = {},
  last_selection_tick = {}
}

local checked_tables

local next_command_type =
{
  move = 1,
  patrol = 2,
  scout = 3,
  idle = 4,
  attack = 5,
  follow = 6,
  hold_position = 7
}

local script_events =
{
  on_unit_idle = script.generate_event_name(),
  on_unit_selected = script.generate_event_name(),
  on_unit_not_idle = script.generate_event_name()
}

local print = function(string)
  if not script_data.debug then return end
  local tick = game.tick
  log(tick.." | "..string)
  game.print(tick.." | "..string)
end

local insert = table.insert

local distance = function(position_1, position_2)
  local d_x = position_2.x - position_1.x
  local d_y = position_2.y - position_1.y
  return ((d_x * d_x) + (d_y * d_y)) ^ 0.5
end

local add_unit_indicators

local set_command = function(unit_data, command)
  unit_data.command = command
  local unit = unit_data.entity
  unit_data.destination = command.destination
  unit_data.destination_entity = command.destination_entity
  unit_data.target = command.target
  unit_data.in_group = nil
  unit.speed = command.speed or unit.prototype.speed
  unit.ai_settings.path_resolution_modifier = command.path_resolution_modifier or -2
  unit.ai_settings.do_separation = true
  unit.set_command(command)
  return add_unit_indicators(unit_data)
end

local retry_command = function(unit_data)
  --game.print("Unit failed a command, retrying at higher path resolution")
  local unit = unit_data.entity
  unit.ai_settings.path_resolution_modifier = math.min(unit.ai_settings.path_resolution_modifier + 1, 3)
  return pcall(unit.set_command, unit_data.command)
end

local set_unit_idle
local scout_queue = {command_type = next_command_type.scout}
local set_scout_command = function(unit_data, failure, delay)
  unit_data.command_queue = {scout_queue}
  local unit = unit_data.entity
  if unit.type ~= "unit" then return end
  if failure and unit_data.fail_count > 10 then
    unit_data.fail_count = nil
    return set_unit_idle(unit_data, true)
  end
  if delay and delay > 0 then
    --print("Unit was delayed for some ticks: "..delay)
    return set_command(unit_data,
    {
      type = defines.command.stop,
      ticks_to_wait = delay
    })
  end
  --log(game.tick..": Issueing scout command for "..unit.name.." "..unit.unit_number)
  --unit.surface.create_entity{name = "explosion", position = unit.position}
  local position = unit.position
  local surface = unit.surface
  local chunk_x = math.floor(position.x / 32)
  local chunk_y = math.floor(position.y / 32)
  --unit.surface.request_to_generate_chunks(position, scout_range)
  local map_chunk_width = surface.map_gen_settings.width / 64
  local map_chunk_height = surface.map_gen_settings.height / 64
  local in_map = function(chunk_position)
    if map_chunk_width > 0 and (chunk_position.x > map_chunk_width or chunk_position.x < -map_chunk_width) then
      return false
    end
    if map_chunk_height > 0 and (chunk_position.y > map_chunk_height or chunk_position.y < -map_chunk_height) then
      return false
    end
    return true
  end
  local insert = table.insert
  local scout_range = 6
  local visible_chunks = {}
  local non_visible_chunks = {}
  local uncharted_chunks = {}
  local checked = {}
  local force = unit.force
  local is_charted = force.is_chunk_charted
  local is_visible = force.is_chunk_visible
  for X = -scout_range, scout_range do
    for Y = -scout_range, scout_range do
      local chunk_position = {x = chunk_x + X, y = chunk_y + Y}
      if in_map(chunk_position) then
        if (not is_charted(surface, chunk_position)) then
          insert(uncharted_chunks, chunk_position)
        elseif (not is_visible(surface, chunk_position)) then
          insert(non_visible_chunks, chunk_position)
        else
          insert(visible_chunks, chunk_position)
        end
      end
    end
  end
  local chunk
  local tile_destination
  local remove = table.remove
  local random = math.random
  local find_non_colliding_position = surface.find_non_colliding_position
  local name = unit.name
  repeat
    if not failure and #uncharted_chunks > 0 then
      index = random(#uncharted_chunks)
      chunk = uncharted_chunks[index]
      remove(uncharted_chunks, index)
      tile_destination = find_non_colliding_position(name, {(chunk.x * 32) + random(32), (chunk.y * 32) + random(32)}, 0, 4)
    elseif not failure and #non_visible_chunks > 0 then
      index = random(#non_visible_chunks)
      chunk = non_visible_chunks[index]
      remove(non_visible_chunks, index)
      tile_destination = find_non_colliding_position(name, {(chunk.x * 32) + random(32), (chunk.y * 32) + random(32)}, 0, 4)
    elseif #visible_chunks > 0 then
      index = random(#visible_chunks)
      chunk = visible_chunks[index]
      remove(visible_chunks, index)
      tile_destination = find_non_colliding_position(name, {(chunk.x * 32) + random(32), (chunk.y * 32) + random(32)}, 0, 4)
    else
      tile_destination = find_non_colliding_position(name, force.get_spawn_position(surface), 0, 4)
    end
  until tile_destination
  --print("Found destination script_data")
  --print(serpent.block({
  --  tile_destination = tile_destination,
  --  current_position = {unit.position.x, unit.position.y}
  --}))
  return set_command(unit_data,
  {
    type = defines.command.go_to_location,
    distraction = defines.distraction.by_enemy,
    destination = tile_destination,
    radius = 1,
    pathfind_flags =
    {
      allow_destroy_friendly_entities = false,
      cache = true,
      low_priority = true
    }
  })
end

local get_selected_units = function(player_index)
  local script_data = script_data.selected_units
  local selected = script_data[player_index] or {}
  for unit_number, entity in pairs (selected) do
    if not entity.valid then
      selected[unit_number] = nil
    end
  end
  script_data[player_index] = selected
  return selected
end

local make_unit_gui

local clear_indicators = function(unit_data)
  if not unit_data.indicators then return end
  local destroy = rendering.destroy
  for indicator, bool in pairs (unit_data.indicators) do
    destroy(indicator)
  end
  unit_data.indicators = nil
end

local is_idle = function(unit_number)
  local unit_data = script_data.units[unit_number]
  if not unit_data then return false end
  if unit_data.idle and not unit_data.player then return true end
end

local deselect_units = function(unit_data)
  clear_indicators(unit_data)
  if unit_data.player then
    script_data.marked_for_refresh[unit_data.player] = true
    unit_data.player = nil
  end
  --local entity = unit_data.entity
  --local unit_number = entity.unit_number
  --data.groups[unit_number] = nil
end

local shift_box = function(box, shift)
  local x = shift[1] or shift.x
  local y = shift[2] or shift.y
  local new =
  {
    left_top = {},
    right_bottom = {}
  }
  new.left_top.x = box.left_top.x + x
  new.left_top.y = box.left_top.y + y
  new.right_bottom.x = box.right_bottom.x + x
  new.right_bottom.y = box.right_bottom.y + y
  return new
end

local get_attack_range = function(prototype)
  local attack_parameters = prototype.attack_parameters
  if not attack_parameters then return end
  return attack_parameters.range
end

local highlight_box = function(indicators, box_color, source, box, players, surface)
  local indicators = indicators
  local draw_line = rendering.draw_line
  local insert = insert
  local width = 1
  local corner_length = util.radius(box) * 0.25
  local from_offset = {true, true}
  local to_offset = {true, true}
  local params =
  {
    color = box_color,
    width = width,
    from = source,
    to = source,
    from_offset = from_offset,
    to_offset = to_offset,
    surface = surface,
    players = players
  }

  local ltx = box.left_top.x
  local lty = box.left_top.y
  local rbx = box.right_bottom.x
  local rby = box.right_bottom.y

  from_offset[1] = ltx
  from_offset[2] = lty
  to_offset[1] = ltx
  to_offset[2] = lty + corner_length
  indicators[draw_line(params)] = true

  from_offset[1] = ltx
  from_offset[2] = lty
  to_offset[1] = ltx + corner_length
  to_offset[2] = lty
  indicators[draw_line(params)] = true

  from_offset[1] = rbx
  from_offset[2] = lty
  to_offset[1] = rbx
  to_offset[2] = lty + corner_length
  indicators[draw_line(params)] = true

  from_offset[1] = rbx
  from_offset[2] = lty
  to_offset[1] = rbx - corner_length
  to_offset[2] = lty
  indicators[draw_line(params)] = true

  from_offset[1] = ltx
  from_offset[2] = rby
  to_offset[1] = ltx
  to_offset[2] = rby - corner_length
  indicators[draw_line(params)] = true

  from_offset[1] = ltx
  from_offset[2] = rby
  to_offset[1] = ltx + corner_length
  to_offset[2] = rby
  indicators[draw_line(params)] = true

  from_offset[1] = rbx
  from_offset[2] = rby
  to_offset[1] = rbx
  to_offset[2] = rby - corner_length
  indicators[draw_line(params)] = true

  from_offset[1] = rbx
  from_offset[2] = rby
  to_offset[1] = rbx + corner_length
  to_offset[2] = rby
  indicators[draw_line(params)] = true
end

add_unit_indicators = function(unit_data)
  clear_indicators(unit_data)
  --if true then return end
  local player
  if unit_data.player then
    player = game.players[unit_data.player]
  end
  if not (player and player.valid and player.connected) then return end
  local indicators = {}
  unit_data.indicators = indicators
  local unit = unit_data.entity
  local surface = unit.surface
  local create_entity = surface.create_entity
  local render_index = player.index
  local insert = table.insert
  local position = unit.position
  local name = "highlight-box"
  local players = {player.index}
  if unit_data.in_group then
    indicators[rendering.draw_text
    {
      text="In group",
      surface=surface,
      target=unit,
      color={g = 0.5},
      scale_with_zoom=true
    }] = true
    return
  end
  local rendering = rendering
  local prototype = unit.prototype
  local box = prototype.collision_box
  local box = prototype.selection_box
  highlight_box(indicators, {g = 1}, unit, prototype.selection_box, players, surface)

  local gap_length = 1.5
  local dash_length = 0.5

  if unit_data.destination then
    indicators[rendering.draw_line
    {
      color = {b = 0.1, g = 0.5, a = 0.02},
      width = 1,
      to = unit,
      from = unit_data.destination,
      surface = unit.surface,
      players = players,
      gap_length = gap_length,
      dash_length = dash_length,
      draw_on_ground = true
    }] = true
  end

  if unit_data.destination_entity and unit_data.destination_entity.valid then
    indicators[rendering.draw_line
    {
      color = {b = 0.1, g = 0.5, a = 0.02},
      width = 1,
      to = unit,
      from = unit_data.destination_entity,
      surface = unit.surface,
      players = players,
      gap_length = gap_length,
      dash_length = dash_length,
      draw_on_ground = true
    }] = true
  end

  local position = unit_data.destination or unit.position
  for k, command in pairs (unit_data.command_queue) do

    if command.command_type == next_command_type.move then
      indicators[rendering.draw_line
      {
        color = {b = 0.1, g = 0.5, a = 0.02},
        width = 1,
        to = position,
        from = command.destination,
        surface = unit.surface,
        players = players,
        gap_length = gap_length,
        dash_length = dash_length,
        draw_on_ground = true
      }] = true
      position = command.destination
    end

    if command.command_type == next_command_type.patrol then
      for k = 1, #command.destinations do
        local to = command.destinations[k]
        local from = command.destinations[k + 1] or command.destinations[1]
        indicators[rendering.draw_line
        {
          color = {b = 0.5, g = 0.2, a = 0.05},
          width = 1,
          from = from,
          to = to,
          surface = unit.surface,
          players = players,
          gap_length = gap_length,
          dash_length = dash_length,
          draw_on_ground = true,
        }] = true
      end
    end

  end
  local target = unit_data.target
  if target and target.valid then
    highlight_box(indicators, {r = 1}, target, target.prototype.selection_box, players, surface)
  end
end

local stop = {type = defines.command.stop}
local idle_command = {type = defines.command.stop, radius = 1}
local hold_position_command = {type = defines.command.stop, speed = 0}

set_unit_idle = function(unit_data, send_event)
  unit_data.idle = true
  unit_data.command_queue = {}
  unit_data.destination = nil
  unit_data.target = nil
  local unit = unit_data.entity
  if unit.type == "unit" then
    unit.ai_settings.do_separation = false
    set_command(unit_data, idle_command)
    if send_event then
      script.raise_event(script_events.on_unit_idle, {entity = unit})
    end
  end
  return add_unit_indicators(unit_data)
end

local set_unit_not_idle = function(unit_data)
  unit_data.idle = false
  script.raise_event(script_events.on_unit_not_idle, {entity = unit_data.entity})
  return add_unit_indicators(unit_data)
end

local get_frame = function(player_index)
  local frame = script_data.open_frames[player_index]
  if not (frame and frame.valid) then
    script_data.open_frames[player_index] = nil
    return
  end
  return frame
end

local stop_group = function(player, queue)
  local group = get_selected_units(player.index)
  if not group then
    return
  end
  local idle_queue = {command_type = next_command_type.idle}
  local units = script_data.units
  for unit_number, unit in pairs (group) do
    local unit_data = units[unit_number]
    if queue and not unit_data.idle then
      insert(unit_data.command_queue, idle_queue)
    else
      set_unit_idle(unit_data, true)
    end
  end
  player.play_sound({path = tool_names.unit_move_sound})
end

local hold_position_group = function(player, queue)
  local group = get_selected_units(player.index)
  if not group then
    return
  end
  local hold_position_queue = {command_type = next_command_type.hold_position}
  local units = script_data.units
  for unit_number, unit in pairs (group) do
    local unit_data = units[unit_number]
    if queue and not unit_data.idle then
      table.insert(unit_data.command_queue, hold_position_queue)
    else
      if unit.type == "unit" then
        unit_data.command_queue = {}
        set_command(unit_data, hold_position_command)
        set_unit_not_idle(unit_data)
      else
        unit_data.command_queue = {hold_position_queue}
        add_unit_indicators(unit_data)
      end
    end
  end
  player.play_sound({path = tool_names.unit_move_sound})
end

local gui_actions =
{
  move_button = function(event)
    local player = game.players[event.player_index]
    if not (player and player.valid) then return end
    player.clean_cursor()
    player.cursor_stack.set_stack{name = tool_names.unit_move_tool}
  end,
  patrol_button = function(event)
    local player = game.players[event.player_index]
    if not (player and player.valid) then return end
    player.clean_cursor()
    player.cursor_stack.set_stack{name = tool_names.unit_patrol_tool}
  end,
  attack_move_button = function(event)
    local player = game.players[event.player_index]
    if not (player and player.valid) then return end
    player.clean_cursor()
    player.cursor_stack.set_stack{name = tool_names.unit_attack_move_tool}
  end,
  attack_button = function(event)
    local player = game.players[event.player_index]
    if not (player and player.valid) then return end
    player.clean_cursor()
    player.cursor_stack.set_stack{name = tool_names.unit_attack_tool}
  end,
  force_attack_button = function(event)
    local player = game.players[event.player_index]
    if not (player and player.valid) then return end
    player.clean_cursor()
    player.cursor_stack.set_stack{name = tool_names.unit_force_attack_tool}
  end,
  follow_button = function(event)
    local player = game.players[event.player_index]
    if not (player and player.valid) then return end
    player.clean_cursor()
    player.cursor_stack.set_stack{name = tool_names.unit_follow_tool}
  end,
  hold_position_button = function(event)
    hold_position_group(game.get_player(event.player_index), event.shift)
  end,
  stop_button = function(event)
    stop_group(game.get_player(event.player_index), event.shift)
  end,
  scout_button = function(event)
    local group = get_selected_units(event.player_index)
    if not group then
      return
    end
    local append = event.shift
    local scout_queue = {command_type = next_command_type.scout}
    local units = script_data.units
    for unit_number, unit in pairs (group) do
      local unit_data = units[unit_number]
      if append and not unit_data.idle then
        insert(unit_data.command_queue, scout_queue)
      else
        set_scout_command(unit_data, false, unit_number % 120)
        set_unit_not_idle(unit_data)
      end
    end
    game.get_player(event.player_index).play_sound({path = tool_names.unit_move_sound})
  end,
  exit_button = function(event)
    local group = get_selected_units(event.player_index)
    if not group then return end

    local units = script_data.units
    for unit_number, entity in pairs (group) do
      deselect_units(units[unit_number])
      group[unit_number] = nil
    end
    script_data.selected_units[event.player_index] = nil
    --The GUI should be destroyed in the on_tick anyway.
  end,
  selected_units_button = function(event, action)
    local unit_name = action.unit
    local group = get_selected_units(event.player_index)
    if not group then return end
    local right = (event.button == defines.mouse_button_type.right)
    local left = (event.button == defines.mouse_button_type.left)
    local units = script_data.units

    if right then
      if event.shift then
        local count = 0
        for unit_number, entity in pairs (group) do
          if entity.name == unit_name then
            count = count + 1
          end
        end
        local to_leave = math.ceil(count / 2)
        count = 0
        for unit_number, entity in pairs (group) do
          if entity.name == unit_name then
            if count > to_leave then
              deselect_units(units[unit_number])
              group[unit_number] = nil
            end
            count = count + 1
          end
        end
      else
        for unit_number, entity in pairs (group) do
          if entity.name == unit_name then
            deselect_units(units[unit_number])
            group[unit_number] = nil
            break
          end
        end
      end
    end

    if left then
      if event.shift then
        for unit_number, entity in pairs (group) do
          if entity.name == unit_name then
            deselect_units(units[unit_number])
            group[unit_number] = nil
          end
        end
      else
        for unit_number, entity in pairs (group) do
          if entity.name ~= unit_name then
            deselect_units(units[unit_number])
            group[unit_number] = nil
          end
        end
      end
    end
  end
}

local button_map =
{
  [tool_names.unit_move_tool] = "move_button",
  [tool_names.unit_patrol_tool] = "patrol_button",
  [tool_names.unit_attack_move_tool] = "attack_move_button",
  [tool_names.unit_attack_tool] = "attack_button",
  [tool_names.unit_force_attack_tool] = "force_attack_button",
  [tool_names.unit_follow_tool] = "follow_button",
  ["hold-position"] = "hold_position_button",
  ["stop"] = "stop_button",
  ["scout"] = "scout_button"
}

local button_map =
{
  move_button = {sprite = "utility/mod_dependency_arrow", tooltip = {tool_names.unit_move_tool}},
  patrol_button = {sprite = "utility/refresh", tooltip = {tool_names.unit_patrol_tool}},
  attack_move_button = {sprite = "utility/center", tooltip = {tool_names.unit_attack_move_tool}},
  --attack_button = {sprite = "item/"..tool_names.unit_attack_tool, tooltip = {tool_names.unit_attack_tool}},
  --force_attack_button = {sprte = "item/"..tool_names.unit_force_attack_tool, tooltip = {tool_names.unit_force_attack_tool}},
  --follow_button = {sprite = "item/"..tool_names.unit_follow_tool, tooltip = {tool_names.unit_follow_tool}},
  hold_position_button = {sprite = "utility/downloading", tooltip = {"hold-position"}},
  stop_button = {sprite = "utility/close_black", tooltip = {"stop"}},
  scout_button = {sprite = "utility/map", tooltip = {"scout"}}
}

make_unit_gui = function(player)
  local index = player.index
  local frame = get_frame(index)
  if not (frame and frame.valid) then return end
  local group = get_selected_units(index)
  if not group then return end
  util.deregister_gui(frame, script_data.button_actions)
  if not next(group) then
    frame.destroy()
    return
  end
  frame.clear()
  local header_flow = frame.add{type = "flow", direction = "horizontal"}
  header_flow.add{type = "label", caption = {"unit-control"}, style = "heading_1_label"}
  local pusher = header_flow.add{type = "flow", direction = "horizontal"}
  pusher.style.horizontally_stretchable = true
  local exit_button = header_flow.add{type = "sprite-button", style = "close_button", sprite = "utility/close_white"}
  --exit_button.style.height = 16
  --exit_button.style.width = 16

  util.register_gui(script_data.button_actions, exit_button, {type = "exit_button"})

  local map = {}
  for unit_number, ent in pairs (group) do
    local name = ent.name
    map[name] = (map[name] or 0) + 1
  end
  local tab = frame.add{type = "table", column_count = 6}
  local pro = game.entity_prototypes
  for name, count in pairs (map) do
    local ent = pro[name]
    local unit_button = tab.add{type = "sprite-button", sprite = "entity/"..name, tooltip = ent.localised_name, number = count, style = "slot_button"}
    util.register_gui(script_data.button_actions, unit_button, {type = "selected_units_button", unit = name})
  end
  local butts = frame.add{type = "table", column_count = 3}
  for action, param in pairs (button_map) do
    local button = butts.add{type = "sprite-button", sprite = param.sprite, tooltip = param.tooltip, style = "mini_button"}
    button.style.height = 32 + 8
    button.style.width = 32 + 8
    util.register_gui(script_data.button_actions, button, {type = action})
    --button.style.font = "default"
    --button.style.horizontally_stretchable = true
  end
  butts.style.horizontal_align = "center"
end

deregister_unit = function(entity)
  if not (entity and entity.valid) then return end
  local unit_number = entity.unit_number
  if not unit_number then return end
  local unit = script_data.units[unit_number]
  if not unit then return end
  script_data.units[unit_number] = nil

  deselect_units(unit)

  local group = unit.group
  if group then
    --game.print("Deregistered unit from group")
    group[unit_number] = nil
    --if table_size(group) == 0 then
  end
  local player_index = unit.player
  if not player_index then
    --game.print("No player index attached to unit info")
    return
  end
end

local double_click_delay = 30

local is_double_click = function(event)
  local this_area = event.area
  local radius = util.radius(this_area)
  if radius > 1 then return end
  local last_selection_tick = script_data.last_selection_tick[event.player_index]
  if not last_selection_tick then return end
  if (last_selection_tick + double_click_delay) < event.tick then return end
  return true
end

local select_similar_nearby = function(entity)
  --assume 1080p and 0.3 zoom
  local r = 32 * 4
  local origin = entity.position
  local area = {{origin.x - r, origin.y - r},{origin.x + r, origin.y + r}}
  return entity.surface.find_entities_filtered{area = area, force = entity.force, name = entity.name}
end

local unit_selection = function(event)
  local entities = event.entities
  if not entities then return end
  local append = (event.name == defines.events.on_player_alt_selected_area)
  local player = game.players[event.player_index]
  if not (player and player.valid) then return end
  local surface = player.surface
  local force = player.force
  local area = event.area
  local center = util.center(area)
  local index = player.index
  local units = script_data.units
  local group = get_selected_units(index)
  if not append then
    for unit_number, ent in pairs (group) do
      deselect_units(units[unit_number])
    end
    group = {}
  end

  local first_index, first = next(entities)
  if is_double_click(event) and first then
    entities = select_similar_nearby(first)
  end

  local map = script_data.unit_unselectable
  local time = game.create_profiler()
  for k, entity in pairs (entities) do
    if not map[entity.name] then
      local unit_index = entity.unit_number
      local unit_data = units[unit_index]
      deregister_unit(entity)
      group[unit_index] = entity
      units[unit_index] = unit_data or
      {
        entity = entity,
        command_queue = {},
        idle = true
      }
      units[unit_index].group = group
      units[unit_index].player = index
      add_unit_indicators(units[unit_index])
    end
  end
  script_data.selected_units[index] = group
  game.print({"", time, game.tick})

  local frame = get_frame(player.index) or player.gui.left.add{type = "frame", direction = "vertical", style = "quick_bar_window_frame"}
  script_data.open_frames[player.index] = frame
  script_data.last_selection_tick[player.index] = event.tick
  make_unit_gui(player)
end

local get_offset = function(entities)
  local map = {}
  local small = 1
  for k, entity in pairs (entities) do
    local name = entity.name
    if not map[name] then
      map[name] = entity.prototype
    end
  end
  local rad = util.radius
  local speed = math.huge
  local max = math.max
  local min = math.min
  for name, prototype in pairs (map) do
    small = max(small, rad(prototype.selection_box) * 2)
    if prototype.type == "unit" then
      speed = min(speed, prototype.speed)
    end
  end
  if speed == math.huge then speed = nil end
  return small, math.ceil((small * (table_size(entities) -1) ^ 0.5)), speed
end

local get_min_speed = function(entities)
  local map = {}
  local speed = math.huge
  for k, entity in pairs (entities) do
    local name = entity.name
    if not map[name] then
      map[name] = entity.prototype
    end
  end
  local min = math.min
  for name, prototype in pairs (map) do
    speed = min(speed, prototype.speed)
  end
  return speed
end
--1-6 = 1
--7-15 = 2
--16-28 = 3
local make_move_positions = function(group)
  --so, a rectangle, 6 times longer than wide...
  local size = table_size(group)
  local number_of_rows = math.floor((size ^ 0.5) / 1.5)
  local max_on_row = math.ceil(size / number_of_rows)
  local positions = {}
  local row_number = 0
  local remaining = size
  while remaining > 0 do
    local number_on_row = math.min(remaining, max_on_row)
    for k = 0, number_on_row - 1 do
      local something
      if k % 2 == 0 then
        something = k / 2
      else
        something = (- 1 - k) / 2
      end
      if number_on_row % 2 == 0 then
        something = something + 0.5
      end
      local position = {x = something, y = row_number}
      table.insert(positions, position)
      remaining = remaining - 1
    end
    row_number = row_number + 1
  end
  return positions
end

local center_of_mass = function(group)
  local x, y, k = 0, 0, 0
  for unit_number, unit in pairs (group) do
    local p = unit.position
    x = x + p.x
    y = y + p.y
    k = k + 1
  end
  return {x / k, y / k}
end

local make_move_command = function(param)
  local origin = param.position
  local distraction = param.distraction or defines.distraction.by_enemy
  local group = param.group
  local player = param.player
  local surface = player.surface
  local force = player.force
  local append = param.append
  local type = defines.command.go_to_location
  local find = surface.find_non_colliding_position
  local index
  local offset, radius, speed = get_offset(group)
  --local positions = make_move_positions(group)

  local size = table_size(group)
  local number_of_rows = math.floor((size ^ 0.5) / 1.5)
  local max_on_row = math.ceil(size / number_of_rows)
  local angle = util.angle(origin, center_of_mass(group)) - (0.25 * 2 * math.pi)
  cos = math.cos(angle)
  sin = math.sin(angle)

  local rotate = function(position)
   local x = (position.x * cos) - (position.y * sin)
   local y = (position.x * sin) + (position.y * cos)
   return {x = x, y = y}
  end

  local should_ajar = {}
  local remaining = size
  for k = 0, number_of_rows - 1 do
    if remaining < (max_on_row) then
      should_ajar[k] = remaining % 2 == 0
    else
      should_ajar[k] = max_on_row % 2 == 0
    end
    remaining = remaining - (max_on_row)
  end

  local y_adjust = 0.5 + (-0.5 * size) / max_on_row

  local insert = table.insert
  local current_row = 0
  local current_column = 0
  for unit_number, entity in pairs (group) do
    local position = {}
    position.y = current_row + y_adjust
    local something
    if current_column % 2 == 0 then
      something = current_column / 2
    else
      something = (- 1 - current_column) / 2
    end
    if should_ajar[current_row] then
      something = something + 0.5
    end
    position.x = something
    position.x = position.x * offset
    position.y = position.y * offset
    position = rotate(position)
    local destination = {origin.x + position.x, origin.y + position.y}
    --log(entity.unit_number.." = "..serpent.line(destination))
    local unit = (entity.type == "unit")
    local destination = find(entity.name, destination, 0, 0.5)
    local command = {
      command_type = next_command_type.move,
      type = type, distraction = distraction,
      radius = 0.5,
      destination = destination,
      speed = speed,
      pathfind_flags =
      {
        allow_destroy_friendly_entities = false,
        cache = false
      }
    }
    local unit_data = script_data.units[entity.unit_number]
    if append then
      if unit_data.idle and unit then
        set_command(unit_data, command)
      end
      insert(unit_data.command_queue, command)
    else
      unit_data.command_queue = {command}
      if unit then
        set_command(unit_data, command)
        unit_data.command_queue = {}
      else
        unit_data.command_queue = {command}
      end
    end
    set_unit_not_idle(unit_data)

    if current_column == (max_on_row - 1) then
      current_row = current_row + 1
      current_column = 0
    else
      current_column = current_column + 1
    end
  end
end



local move_units = function(event)
  local group = get_selected_units(event.player_index)
  if not group then
    script_data.selected_units[event.player_index] = nil
    return
  end
  local player = game.players[event.player_index]
  make_move_command{
    position = util.center(event.area),
    distraction = defines.distraction.none,
    group = group,
    append = event.name == defines.events.on_player_alt_selected_area,
    player = player
  }
  player.play_sound({path = tool_names.unit_move_sound})
end

local attack_move_units = function(event)
  local group = get_selected_units(event.player_index)
  if not group then
    script_data.selected_units[event.player_index] = nil
    return
  end
  local player = game.players[event.player_index]
  make_move_command{
    position = util.center(event.area),
    distraction = defines.distraction.by_enemy,
    group = group,
    append = event.name == defines.events.on_player_alt_selected_area,
    player = player
  }
  player.play_sound({path = tool_names.unit_move_sound})
end

local find_patrol_comand = function(queue)
  if not queue then return end
  for k, command in pairs (queue) do
    if command.command_type == next_command_type.patrol then
      return command
    end
  end
end


local process_command_queue

local make_patrol_command = function(param)
  local origin = param.position
  local distraction = param.distraction or defines.distraction.by_enemy
  local group = param.group
  local player = param.player
  local surface = player.surface
  local force = player.force
  local append = param.append
  local type = defines.command.go_to_location
  local find = surface.find_non_colliding_position
  local index
  local offset, radius, speed = get_offset(group)
  local insert = table.insert


  local size = table_size(group)
  local number_of_rows = math.floor((size ^ 0.5) / 1.5)
  local max_on_row = math.ceil(size / number_of_rows)
  local angle = util.angle(origin, center_of_mass(group)) - (0.25 * 2 * math.pi)
  cos = math.cos(angle)
  sin = math.sin(angle)

  local rotate = function(position)
   local x = (position.x * cos) - (position.y * sin)
   local y = (position.x * sin) + (position.y * cos)
   return {x = x, y = y}
  end

  local should_ajar = {}
  local remaining = size
  for k = 0, number_of_rows - 1 do
    if remaining < (max_on_row) then
      should_ajar[k] = remaining % 2 == 0
    else
      should_ajar[k] = max_on_row % 2 == 0
    end
    remaining = remaining - (max_on_row)
  end

  local insert = table.insert
  local current_row = 0
  local current_column = 0
  for unit_number, entity in pairs (group) do
    local position = {}
    position.y = current_row
    local something
    if current_column % 2 == 0 then
      something = current_column / 2
    else
      something = (- 1 - current_column) / 2
    end
    if should_ajar[current_row] then
      something = something + 0.5
    end
    position.x = something
    position.x = position.x * offset
    position.y = position.y * offset
    position = rotate(position)
    local destination = {origin.x + position.x, origin.y + position.y}
    --log(entity.unit_number.." = "..serpent.line(destination))
    local unit_data = script_data.units[unit_number]
    local unit = (entity.type == "unit")
    local next_destination = find(entity.name, destination, 0, 0.5)
    local patrol_command = find_patrol_comand(unit_data.command_queue)
    if patrol_command and append then
      insert(patrol_command.destinations, next_destination)
    else
      command =
      {
        command_type = next_command_type.patrol,
        destinations = {entity.position, next_destination},
        destination_index = "initial",
        speed = speed
      }
    end
    if not append then
      unit_data.command_queue = {command}
      set_unit_not_idle(unit_data)
      if unit then
        process_command_queue(unit_data)
      end
    end
    if append and not patrol_command then
      insert(unit_data.command_queue, command)
      if unit_data.idle and unit then
        process_command_queue(unit_data)
      end
    end
    add_unit_indicators(unit_data)

    if current_column == (max_on_row - 1) then
      current_row = current_row + 1
      current_column = 0
    else
      current_column = current_column + 1
    end
  end
end

local patrol_units = function(event)
  local group = get_selected_units(event.player_index)
  if not group then
    script_data.selected_units[event.player_index] = nil
    return
  end
  local player = game.players[event.player_index]
  make_patrol_command{
    position = util.center(event.area),
    distraction = defines.distraction.by_enemy,
    group = group,
    append = event.name == defines.events.on_player_alt_selected_area,
    player = player
  }
  player.play_sound({path = tool_names.unit_move_sound})
end

local quick_dist = function(p1, p2)
  return (((p1.x - p2.x) * (p1.x - p2.x)) + ((p1.y - p2.y) * (p1.y - p2.y)))
end

local attack_closest = function(unit_data, entities)
  local unit = unit_data.entity
  local position = unit.position
  local entities = entities
  local force = unit.force
  local surface = unit.surface
  if not checked_tables then checked_tables = {} end
  if not checked_tables[entities] then
    for k, ent in pairs (entities) do
      if not ent.valid then
        entities[k] = nil
      end
    end
    checked_tables[entities] = true
  end
  unit.speed = unit.prototype.speed
  local closest = unit.surface.get_closest(unit.position, entities)

  if closest and closest.valid then
    set_command(unit_data,
    {
      type = defines.command.attack,
      distraction = defines.distraction.none,
      target = closest
    })
    return true
  else
    return false
  end
end

local directions =
{
  [defines.direction.north] = {0, -1},
  [defines.direction.northeast] = {1, -1},
  [defines.direction.east] = {1, 0},
  [defines.direction.southeast] = {1, 1},
  [defines.direction.south] = {0, 1},
  [defines.direction.southwest] = {-1, 1},
  [defines.direction.west] = {-1, 0},
  [defines.direction.northwest] = {-1, -1},
}

local random = math.random
local follow_range = 10
local unit_follow = function(unit_data, next_command)
  --copy pasta from construction drone
  local target = next_command.target
  if not (target and target.valid) then
    return
  end

  local unit = unit_data.entity
  if unit == target then
    --Don't try to follow yourself.
    set_command(unit_data, stop)
    return
  end

  if distance(target.position, unit.position) > follow_range then
    set_command(unit_data,
    {
      type = defines.command.go_to_location,
      destination_entity = target,
      radius = follow_range
    })
    return
  end

  local check_time = random(20, 40)

  if target.type == "player" then
    local player = target.player
    if player then
      local state = player.walking_state
      if state.walking then
        local offset = directions[state.direction]
        local target_speed = target.character_running_speed
        local new_position = {unit.position.x + (offset[1] * check_time * target_speed), unit.position.y + (offset[2] * check_time * target_speed)}
        return set_command(unit_data,
        {
          type = defines.command.go_to_location,
          radius = 1,
          distraction = defines.distraction.by_enemy,
          destination = unit.surface.find_non_colliding_position(unit.name, new_position, 0, 1),
          speed = math.min(unit.prototype.speed, target_speed * (check_time / (check_time - 1)))
        })
      end
    end
  end

  if target.type == "unit" then
    if target.moving then
      --In factorio, north is 0 rad... so rotate back to east being 0 rad like math do
      local orientation = (target.orientation - corner_length5) * 2 * math.pi
      local offset = {math.cos(orientation), math.sin(orientation)}
      local target_speed = target.speed
      local new_position = {unit.position.x + (offset[1] * check_time * target_speed), unit.position.y + (offset[2] * check_time * target_speed)}
      return set_command(unit_data,
      {
        type = defines.command.go_to_location,
        radius = 1,
        distraction = defines.distraction.by_enemy,
        destination = unit.surface.find_non_colliding_position(unit.name, new_position, 0, 1),
        speed = math.min(unit.prototype.speed, target_speed * (check_time / (check_time - 1)))
      })
    end
  end

  --todo wander in a random direction...
  return set_command(unit_data,
  {
    type = defines.command.wander,
    distraction = defines.distraction.none,
    ticks_to_wait = check_time,
    speed = unit.prototype.speed * ((random() * 0.5) + 0.5)
  })
end

local make_attack_command = function(group, entities, append)
  local entities = entities
  if #entities == 0 then return end
  local script_data = script_data.units
  for unit_number, unit in pairs (group) do
    local commandable = (unit.type == "unit")
    local next_command =
    {
      command_type = next_command_type.attack,
      targets = entities
    }
    local unit_data = script_data[unit_number]
    if append then
      if unit_data.idle and commandable then
        attack_closest(unit_data, entities)
      end
      table.insert(unit_data.command_queue, next_command)
    else
      if commandable then
        attack_closest(unit_data, entities)
      end
      unit_data.command_queue = {next_command}
    end
    set_unit_not_idle(unit_data)
  end
end

local make_follow_command = function(group, target, append)
  if not (target and target.valid) then return end
  local script_data = script_data.units
  for unit_number, unit in pairs (group) do
    local commandable = (unit.type == "unit")
    local next_command =
    {
      command_type = next_command_type.follow,
      target = target
    }
    local unit_data = script_data[unit_number]
    if append then
      if unit_data.idle and commandable then
        unit_follow(unit_data, next_command)
      end
      table.insert(unit_data.command_queue, next_command)
    else
      if commandable then
        unit_follow(unit_data, next_command)
      end
      unit_data.command_queue = {next_command}
    end
    set_unit_not_idle(unit_data)
  end
end

local attack_units = function(event)
  local group = get_selected_units(event.player_index)
  if not group then
    script_data.selected_units[event.player_index] = nil
    return
  end
  local append = event.name == defines.events.on_player_alt_selected_area
  make_attack_command(group, event.entities, append)
  game.players[event.player_index].play_sound({path = tool_names.unit_move_sound})
end

local follow_entity = function(event)
  local group = get_selected_units(event.player_index)
  if not group then
    script_data.selected_units[event.player_index] = nil
    return
  end
  local target = event.entities[1]
  if not target then return end
  local append = event.name == defines.events.on_player_alt_selected_area
  make_follow_command(group, target, append)
  game.players[event.player_index].play_sound({path = tool_names.unit_move_sound})
end

local multi_attack_selection = function(event)
  -- A combi funciton for attack, and attack move. If there are selected units, its an attack command. No selected units, its attack move.
  local entities = event.entities
  if entities and #entities > 0 then
    return attack_units(event)
  end
  return attack_move_units(event)
end

local multi_move_selection = function(event)
  -- A combi funciton for move and follow.
  local entities = event.entities
  if entities and #entities > 0 then
    return follow_entity(event)
  end
  return move_units(event)
end

local selected_area_actions =
{
  [tool_names.unit_selection_tool] = unit_selection,
  [tool_names.deployer_selection_tool] = unit_selection,
  [tool_names.unit_move_tool] = multi_move_selection,
  [tool_names.unit_patrol_tool] = patrol_units,
  [tool_names.unit_attack_move_tool] = multi_attack_selection,
  --[tool_names.unit_attack_tool] = attack_units,
  --[tool_names.unit_force_attack_tool] = attack_units,
  --[tool_names.unit_follow_tool] = follow_entity,
}

local alt_selected_area_actions =
{
  [tool_names.unit_selection_tool] = unit_selection,
  [tool_names.deployer_selection_tool] = unit_selection,
  [tool_names.unit_move_tool] = multi_move_selection,
  [tool_names.unit_patrol_tool] = patrol_units,
  [tool_names.unit_attack_move_tool] = multi_attack_selection,
  --[tool_names.unit_attack_tool] = attack_units,
  --[tool_names.unit_force_attack_tool] = attack_units,
  --[tool_names.unit_follow_tool] = follow_unit,
}

local on_player_selected_area = function(event)
  local action = selected_area_actions[event.item]
  if not action then return end
  return action(event)
end

local on_player_alt_selected_area = function(event)
  local action = alt_selected_area_actions[event.item]
  if not action then return end
  return action(event)
end

local on_gui_click = function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player_data = script_data.button_actions[event.player_index]
  if not player_data then return end
  local action = player_data[element.index]
  if action then
    gui_actions[action.type](event, action)
    return true
  end
end

local on_entity_removed = function(event)
  checked_tables = nil
  deregister_unit(event.entity)
end

process_command_queue = function(unit_data, result)
  local entity = unit_data.entity
  if not (entity and entity.valid) then
    game.print("Entity is nil?? Please save the game and report it to Klonan!")
    return
  end
  local failed = (result == defines.behavior_result.fail)
  --print("Processing command queue "..entity.unit_number.." Failure = "..tostring(result == defines.behavior_result.fail))

  if failed then
    unit_data.fail_count = (unit_data.fail_count or 0) + 1
    if unit_data.fail_count < 5 then
      if retry_command(unit_data) then
        return
      end
    end
  end

  local command_queue = unit_data.command_queue
  local next_command = command_queue[1]

  if not (next_command) then
    entity.ai_settings.do_separation = true
    if not unit_data.idle then
      set_unit_idle(unit_data)
    end
    return
  end

  local type = next_command.command_type

  if type == next_command_type.move then
    --print("Move")
    set_command(unit_data, next_command)
    unit_data.destination = next_command.destination
    table.remove(command_queue, 1)
    return
  end

  if type == next_command_type.patrol then
    --print("Patrol")
    if next_command.destination_index == "initial" then
      next_command.destinations[1] = entity.position
      next_command.destination_index = 2
    else
      next_command.destination_index = next_command.destination_index + 1
    end
    local next_destination = next_command.destinations[next_command.destination_index]
    if not next_destination then
      next_command.destination_index = 1
      next_destination = next_command.destinations[next_command.destination_index]
    end
    set_command(unit_data,
    {
      type = defines.command.go_to_location,
      destination = entity.surface.find_non_colliding_position(entity.name, next_destination, 0, 0.5) or entity.position,
      radius = 1
    })
    return
  end

  if type == next_command_type.attack then
    --print("Attack")
    --game.print"Issuing attack command"
    if not attack_closest(unit_data, next_command.targets) then
      table.remove(command_queue, 1)
      process_command_queue(unit_data)
      --game.print"No targets found, removing attack command"
    end
    return
  end

  if type == next_command_type.idle then
    --print("Idle")
    unit_data.command_queue = {}
    return set_unit_idle(unit_data, true)
  end

  if type == next_command_type.scout then
    --print("Scout")
    return set_scout_command(unit_data, result == defines.behavior_result.fail)
  end

  if type == next_command_type.follow then
    --print("Follow")
    return unit_follow(unit_data, next_command)
  end

  if type == next_command_type.hold_position then
    --print("Hold position")
    return set_command(unit_data, hold_position_command)
  end

end

local on_ai_command_completed = function(event)
  --print("Ai command complete "..event.unit_number)
  local unit_data = script_data.units[event.unit_number]
  if unit_data then
    return process_command_queue(unit_data, event.result)
  end
  --[[
  local group_to_disband = script_data.unit_groups_to_disband[event.unit_number]
  if group_to_disband then
    --This group finished what it was doing, so we kill it.
    group_to_disband.destroy()
    script_data.unit_groups_to_disband[event.unit_number] = nil
    return
  end
  ]]
end

local check_indicators = function(tick)
  local indicators = script_data.indicators[tick]
  if not indicators then return end
  for k, ent in pairs (indicators) do
    if ent.valid then
      ent.destroy()
    end
  end
end

local check_refresh_gui = function()
  for player_index, bool in pairs (script_data.marked_for_refresh) do
    make_unit_gui(game.get_player(player_index))
    script_data.marked_for_refresh[player_index] = nil
  end
end

local on_tick = function(event)
  checked_tables = nil
  check_refresh_gui()
  --check_indicators(event.tick)
end

local suicide = function(event)
  local group = get_selected_units(event.player_index)
  if not group then return end
  local unit_number, entity = next(group)
  if entity then entity.die() end
end

local suicide_all = function(event)
  local group = get_selected_units(event.player_index)
  if not group then return end
  for unit_number, entity in pairs (group) do
    if entity and entity.valid then entity.die() end
  end
end

local on_entity_settings_pasted = function(event)
  --Copy pasting deployers recipe.
  local source = event.source
  local destination = event.destination
  if not (source and source.valid and destination and destination.valid) then return end
  local unit_data = script_data.units[source.unit_number]
  if not unit_data then return end
  script_data.units[destination.unit_number] = util.copy(unit_data)
end

local on_player_removed = function(event)
  local frame = script_data.open_frames[event.player_index]
  if (frame and frame.valid) then
    util.deregister_gui(frame, script_data.button_actions)
    frame.destroy()
  end
  script_data.open_frames[event.player_index] = nil
  local group = get_selected_units(event.player_index)
  local units = script_data.units
  if group then
    for unit_number, ent in pairs (group) do
      deselect_units(units[unit_number])
    end
  end
end

local NO_GROUP = true
local on_unit_added_to_group = function(event)
  local unit = event.unit
  if not (unit and unit.valid) then return end
  local group = event.group
  if not (group and group.valid) then return end
  local unit_data = script_data.units[unit.unit_number]
  if not unit_data then
    --We don't have anything to do with this unit, so we don't care
    return
  end
  if NO_GROUP then
    --this is the 'eff off' function
    --game.print("Told group to die! "..group.group_number.." - "..unit.unit_number)
    group.destroy()
    process_command_queue(unit_data)
    return
  end
  --[[
  --game.print("Unit added to group: "..unit.unit_number)
  unit_data.in_group = true
  add_unit_indicators(unit_data)
  --He took control of one of our units! lets keep track of this group and set this guy a command when the group finishes its command
  if script_data.unit_groups_to_disband[group.group_number] then
    --He's already on the hit list.
    return
  end
  script_data.unit_groups_to_disband[group.group_number] = group
  --game.print("Group added to hit list: "..group.group_number)
  ]]
end

local on_unit_removed_from_group = function(event)
  if NO_GROUP then return end
  local unit = event.unit
  if not (unit and unit.valid) then return end
  local unit_data = script_data.units[unit.unit_number]
  if unit_data and unit_data.in_group then
    --game.print("Unit removed from group: "..unit.unit_number)
    return process_command_queue(unit_data)
  end
end

local validate_some_stuff = function()
  local units = script_data.units
  for unit_number, unit_data in pairs (units) do
    local entity = unit_data.entity
    if not (entity and entity.valid) then
      units[unit_number] = nil
    end
  end

  --[[
  local groups = script_data.unit_groups_to_disband
  for group_number, group in pairs (groups) do
    if not (group and group.valid) then
      groups[group_number] = nil
    end
  end
  ]]
end

local set_map_settings = function()
  if remote.interfaces["wave_defense"] then return end
  local settings = game.map_settings

  --settings.path_finder.max_steps_worked_per_tick = 10000
  settings.path_finder.max_steps_worked_per_tick = 400

  --settings.path_finder.start_to_goal_cost_multiplier_to_terminate_path_find = 1000
  --settings.path_finder.short_request_max_steps = 200
  --settings.path_finder.min_steps_to_check_path_find_termination = 500
  settings.path_finder.max_clients_to_accept_any_new_request = 1000
  settings.path_finder.use_path_cache = false
  --settings.path_finder.short_cache_size = 0
  --settings.path_finder.long_cache_size = 0
  settings.steering.moving.force_unit_fuzzy_goto_behavior = true
  settings.steering.default.force_unit_fuzzy_goto_behavior = true
  --settings.steering.moving.radius = 0
  --settings.steering.moving.default = 0
  settings.max_failed_behavior_count = 5
  --settings.steering.moving.force_unit_fuzzy_goto_behavior = true
  --settings.steering.moving.radius = 1
  --settings.steering.moving.separation_force = 0.1
  --settings.steering.moving.separation_factor = 1
end

local on_entity_spawned = function(event)
  local source = event.spawner
  local unit = event.entity
  if not (source and source.valid and unit and unit.valid) then return end
  if unit.type ~= "unit" then return end
  --print("Unit deployed: "..unit.name)
  local source_data = script_data.units[source.unit_number]
  if not source_data then return end

  --print("Unit deployer source queue found: ")
  --print(serpent.block(source_data))
  local queue = source_data.command_queue
  local unit_data =
  {
    entity = unit,
    command_queue = util.copy(queue),
    idle = false
  }
  script_data.units[unit.unit_number] = unit_data
  local random = math.random
  local r = source.get_radius() + unit.get_radius()
  local offset = function()
    return (random() * r * 2) - r
  end
  for k, command in pairs (unit_data.command_queue) do
    if command.command_type == next_command_type.move then
      command.destination = {x = command.destination.x + offset(), y = command.destination.y + offset()}
    end
    if command.command_type == next_command_type.patrol then
      for k, destination in pairs (command.destinations) do
        destination = {x = destination.x + offset(), y = destination.y + offset()}
      end
    end
  end
  unit.release_from_spawner()
  return process_command_queue(unit_data)
end

local stop_hotkey = function(event)
  stop_group(game.get_player(event.player_index))
end

local queue_stop_hotkey = function(event)
  stop_group(game.get_player(event.player_index), true)
end

local hold_position_hotkey = function(event)
  hold_position_group(game.get_player(event.player_index))
end

local queue_hold_position_hotkey = function(event)
  hold_position_group(game.get_player(event.player_index), true)
end

local events =
{
  [defines.events.on_player_selected_area] = on_player_selected_area,
  [defines.events.on_entity_settings_pasted] = on_entity_settings_pasted,
  [defines.events.on_player_alt_selected_area] = on_player_alt_selected_area,
  [defines.events.on_gui_click] = on_gui_click,
  [defines.events.on_entity_died] = on_entity_removed,
  [defines.events.on_robot_mined_entity] = on_entity_removed,
  [defines.events.on_player_mined_entity] = on_entity_removed,
  [defines.events.script_raised_destroy] = on_entity_removed,
  [defines.events.on_ai_command_completed] = on_ai_command_completed,
  [defines.events.on_tick] = on_tick,
  --[defines.event.on_player_created] = on_player_created
  --[defines.events[names.hotkeys.unit_move]] = gui_actions.move_button,
  [names.hotkeys.suicide] = suicide,
  [names.hotkeys.suicide_all] = suicide_all,
  [names.hotkeys.stop] = stop_hotkey,
  [names.hotkeys.queue_stop] = queue_stop_hotkey,
  [names.hotkeys.hold_position] = hold_position_hotkey,
  [names.hotkeys.queue_hold_position] = queue_hold_position_hotkey,
  [defines.events.on_player_died] = on_player_removed,
  [defines.events.on_player_left_game] = on_player_removed,
  [defines.events.on_player_changed_force] = on_player_removed,
  [defines.events.on_unit_added_to_group] = on_unit_added_to_group,
  --[defines.events.on_unit_removed_from_group] = on_unit_removed_from_group,
  [defines.events.on_player_changed_surface] = on_player_removed,
  [defines.events.on_surface_deleted] = validate_some_stuff,
  [defines.events.on_surface_cleared] = validate_some_stuff,
  [defines.events.on_entity_spawned] = on_entity_spawned
}

remote.add_interface("unit_control", {
  register_unit_unselectable = function(entity_name)
    script_data.unit_unselectable[entity_name] = true
  end,
  get_events = function()
    return script_events
  end,
  set_debug = function(bool)
    script_data.debug = bool
  end,
  set_map_settings = function()
    set_map_settings()
  end
})

local unit_control = {}

unit_control.on_init = function()
  global.unit_control = script_data
  set_map_settings()
  unit_control.on_event = handler(events)
end

unit_control.on_configuration_changed = function(configuration_changed_data)
  script_data.marked_for_refresh = script_data.marked_for_refresh or {}
  script_data.last_selection_tick = script_data.last_selection_tick or {}
  set_map_settings()
end

unit_control.get_events = function() return events end

unit_control.on_load = function()
  script_data = global.unit_control
  unit_control.on_event = handler(events)
end

return unit_control
