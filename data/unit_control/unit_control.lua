local util = require("data/util/tf_util")
local tools = require("shared").unit_tools
local path = util.path("data/unit_control/")

local unit_selection_tool =
{
  type = "selection-tool",
  name = tools.unit_selection_tool,
  localised_name = tools.unit_selection_tool,
  selection_mode = {"friend", "entity-with-health"},
  alt_selection_mode = {"friend", "entity-with-health"},
  entity_type_filters = {"unit"},
  alt_entity_type_filters = {"unit"},
  selection_cursor_box_type = "copy",
  alt_selection_cursor_box_type = "pair",
  icon = path.."unit_select.png",
  icon_size = 128,
  stack_size = 1,
  flags = {},
  show_in_library = true,
  selection_color = {g = 1},
  alt_selection_color = {g = 1, b = 1},
  draw_label_for_cursor_render = true,
}

local deploy_filter = {}
--Until someone complains, by default all unit spawners will be 'deployers'.
for name, prototype in pairs (data.raw["unit-spawner"]) do
  table.insert(deploy_filter, name)
end

local deployer_selection_tool =
{
  type = "selection-tool",
  name = tools.deployer_selection_tool,
  localised_name = tools.deployer_selection_tool,
  selection_mode = {"friend", "entity-with-health"},
  alt_selection_mode = {"friend", "entity-with-health"},
  entity_filters = deploy_filter,
  alt_entity_filters = deploy_filter,
  selection_cursor_box_type = "copy",
  alt_selection_cursor_box_type = "pair",
  icon = path.."deployer_select.png",
  icon_size = 128,
  stack_size = 1,
  flags = {},
  show_in_library = true,
  selection_color = {g = 1},
  alt_selection_color = {g = 1, b = 1},
  draw_label_for_cursor_render = true,
}

local unit_move_tool =
{
  type = "selection-tool",
  name = tools.unit_move_tool,
  localised_name = tools.unit_move_tool,
  selection_mode = {"friend", "enemy"},
  alt_selection_mode = {"enemy", "friend"},
  selection_cursor_box_type = "entity",
  alt_selection_cursor_box_type = "not-allowed",
  icon = path.."unit_move_tool.png",
  icon_size = 258,
  stack_size = 1,
  flags = {"only-in-cursor"},
  selection_color = {a = 0},
  alt_selection_color = {a = 0},
}

local unit_patrol_tool =
{
  type = "selection-tool",
  name = tools.unit_patrol_tool,
  localised_name = tools.unit_patrol_tool,
  selection_mode = {"friend", "enemy"},
  alt_selection_mode = {"enemy", "friend"},
  selection_cursor_box_type = "entity",
  alt_selection_cursor_box_type = "not-allowed",
  icon = path.."unit_move_tool.png",
  icon_size = 258,
  stack_size = 1,
  flags = {"only-in-cursor"},
  selection_color = {a = 0},
  alt_selection_color = {a = 0},
}

local move_confirm_sound =
{
  name = tools.unit_move_sound,
  type = "sound",
  filename = "__core__/sound/armor-insert.ogg",
  volume = 2
}

local light =
{
  name = "range_stencil",
  type = "sprite",
  filename = "__core__/sound/armor-insert.ogg",
  volume = 2
}

local unit_attack_move_tool =
{
  type = "selection-tool",
  name = tools.unit_attack_move_tool,
  localised_name = tools.unit_attack_move_tool,
  selection_mode = {"friend", "enemy"},
  alt_selection_mode = {"enemy", "friend"},
  selection_cursor_box_type = "entity",
  alt_selection_cursor_box_type = "not-allowed",
  icon = path.."unit_attack_move_tool.png",
  icon_size = 258,
  stack_size = 1,
  flags = {"only-in-cursor"},
  selection_color = {a = 0},
  alt_selection_color = {a = 0},
}

local unit_attack_tool =
{
  type = "selection-tool",
  name = tools.unit_attack_tool,
  localised_name = tools.unit_attack_tool,
  selection_mode = {"enemy", "entity-with-force"},
  alt_selection_mode = {"enemy", "entity-with-force"},
  selection_cursor_box_type = "not-allowed",
  alt_selection_cursor_box_type = "not-allowed",
  icon = path.."unit_attack_tool.png",
  icon_size = 258,
  stack_size = 1,
  flags = {"only-in-cursor"},
  selection_color = {r = 1},
  alt_selection_color = {r = 1},
}

local unit_force_attack_tool =
{
  type = "selection-tool",
  name = tools.unit_force_attack_tool,
  localised_name = tools.unit_force_attack_tool,
  selection_mode = {"not-same-force", "entity-with-health"},
  alt_selection_mode = {"not-same-force", "entity-with-health"},
  selection_cursor_box_type = "not-allowed",
  alt_selection_cursor_box_type = "not-allowed",
  icon = path.."unit_attack_tool.png",
  icon_size = 258,
  stack_size = 1,
  flags = {"only-in-cursor"},
  selection_color = {r = 1},
  alt_selection_color = {r = 1},
}

local unit_follow_tool =
{
  type = "selection-tool",
  name = tools.unit_follow_tool,
  localised_name = tools.unit_follow_tool,
  selection_mode = {"friend", "any-entity"},
  alt_selection_mode = {"friend", "any-entity"},
  selection_cursor_box_type = "copy",
  alt_selection_cursor_box_type = "copy",
  icon = path.."unit_attack_tool.png",
  icon_size = 258,
  stack_size = 1,
  flags = {"only-in-cursor"},
  selection_color = {g = 1},
  alt_selection_color = {g = 1},
}

local select_units_shortcut =
{
  type = "shortcut",
  name = tools.select_units_shortcut,
  order = "y",
  action = "create-blueprint-item",
  localised_name = tools.unit_selection_tool,
  --technology_to_unlock = "construction-robotics",
  item_to_create = tools.unit_selection_tool,
  style = "blue",
  icon =
  {
    filename = path.."unit_select_shortcut.png",
    size = 128,
    priority = "extra-high-no-scale",
    flags = {"icon"}
  }
}

local select_deployers_shortcut =
{
  type = "shortcut",
  name = tools.select_deployers_shortcut,
  order = "z",
  action = "create-blueprint-item",
  localised_name = tools.deployer_selection_tool,
  --technology_to_unlock = "construction-robotics",
  item_to_create = tools.deployer_selection_tool,  style = "red",
  icon =
  {
    filename = path.."deployer_select_shortcut.png",
    size = 128,
    priority = "extra-high-no-scale",
    flags = {"icon"}
  }
}

data:extend{
  unit_selection_tool,
  deployer_selection_tool,
  move_confirm_sound,
  unit_move_tool,
  unit_patrol_tool,
  unit_attack_move_tool,
  unit_force_attack_tool,
  unit_follow_tool,
  unit_attack_tool,
  select_units_shortcut,
  select_deployers_shortcut
}
