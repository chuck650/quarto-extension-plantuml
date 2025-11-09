-- _extensions/plantuml/plantuml.lua
-- FIX: Replaced pandoc.utils.random_string with a custom function to resolve 
--      'attempt to call a nil value' error in older Pandoc/Quarto environments.

local PLANTUML_BIN_NAME = "plantuml"
local PLANTUML_BIN_PATH = nil
local DEBUG = false  -- Set to true to enable debug logging

-- Seed the random number generator once for unique ID generation
math.randomseed(os.time())

-- === UTILITY FUNCTIONS ===

-- Function to generate a simple unique ID using standard Lua math.random
local function generate_unique_id(length)
  local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
  local id = ""
  for i = 1, length do
    id = id .. chars:sub(math.random(1, #chars), math.random(1, #chars))
  end
  return id
end

-- Function to trim leading/trailing whitespace AND curly braces using gsub
local function trim(s)
  s = s:match("^%s*(.-)%s*$")
  s = string.gsub(s, "^%s*{(.*)}%s*$", "%1")
  s = s:match("^%s*(.-)%s*$")
  return s
end

-- Replacement for pandoc.utils.has_class
local function has_class(elem, class_name)
  local classes = elem.attr.classes
  if not classes then return false end
  for _, class in ipairs(classes) do
    local current_class_name = trim(tostring(class))
    if DEBUG then
      io.stderr:write("DEBUG: Comparing trimmed class '" .. current_class_name .. "' with target '" .. class_name .. "'.\n")
    end
    if current_class_name == class_name then
      if DEBUG then
        io.stderr:write("DEBUG: Match success. Class found: " .. class_name .. "\n")
      end
      return true
    end
  end
  return false
end

-- Function to safely find the executable in the system PATH using 'which'
local function find_plantuml_binary()
  local f = io.popen("which " .. PLANTUML_BIN_NAME)
  if f then
    PLANTUML_BIN_PATH = f:read("*a"):gsub("^%s*(.-)%s*$", "%1")
    f:close()
    if PLANTUML_BIN_PATH == "" or PLANTUML_BIN_PATH:find("not found") then
      PLANTUML_BIN_PATH = nil
    end
  end
  return PLANTUML_BIN_PATH
end

PLANTUML_BIN_PATH = find_plantuml_binary()

if not PLANTUML_BIN_PATH then
  io.stderr:write("WARN: PlantUML executable '" .. PLANTUML_BIN_NAME .. 
                  "' not found in system PATH. Diagrams will not render.\n")
  return {}
end

if DEBUG then
  io.stderr:write("INFO: PlantUML binary found at: " .. PLANTUML_BIN_PATH .. "\n")
end

-- Function to execute PlantUML and generate an SVG image
local function render_plantuml(source_code, output_filename)
  local tmp_puml_file = output_filename:gsub("%.svg$", ".puml")
  
  local file = io.open(tmp_puml_file, "w")
  if not file then 
    io.stderr:write("ERROR: Failed to open temporary source file.\n")
    return nil 
  end
  file:write(source_code)
  file:close()
  
  local command = string.format("%s -tsvg %s", PLANTUML_BIN_PATH, tmp_puml_file)
  if DEBUG then
    io.stderr:write("DEBUG: Executing command: " .. command .. "\n")
  end
  
  local exit_code = os.execute(command)
  
  os.remove(tmp_puml_file)

  local failed = false
  if type(exit_code) == "number" then
    if exit_code ~= 0 then
      failed = true
    end
  elseif type(exit_code) == "boolean" and not exit_code then
    failed = true
  end

  if failed then
    io.stderr:write("ERROR: PlantUML command failed. Return value: " .. tostring(exit_code) .. ".\n")
    return nil
  end
  
  if DEBUG then
    io.stderr:write("DEBUG: SVG successfully generated: " .. output_filename .. "\n")
  end
  return true
end

-- Main filter logic to process code blocks
local function plantuml_filter(elem)
  if DEBUG then
    io.stderr:write("DEBUG: Filter triggered for element type: " .. elem.t .. "\n")
  end
  
  if elem.t == "CodeBlock" then
    local classes = elem.attr.classes
    if DEBUG then
      local class_list = table.concat(classes or {}, ", ") 
      io.stderr:write("DEBUG: Processing CodeBlock. Found classes: [" .. class_list .. "]\n")
    end
    
    if has_class(elem, "plantuml") then
      if DEBUG then
        io.stderr:write("DEBUG: CodeBlock has 'plantuml' class. Proceeding with render.\n")
      end
      
      local attrs = elem.attr.attributes
      local source_code = ""
      local metadata = {}
      
      -- Parse the code block text to extract #| metadata lines
      local lines = {}
      local in_metadata = true
      
      for line in elem.text:gmatch("[^\r\n]+") do
        if in_metadata and line:match("^#|") then
          local meta_line = line:match("^#|%s*(.+)")
          if meta_line then
            local key, value = meta_line:match("^([^:]+):%s*(.+)")
            if key and value then
              -- Trim whitespace
              key = key:match("^%s*(.-)%s*$")
              value = value:match("^%s*(.-)%s*$")
              -- Remove quotes if present
              if value:sub(1,1) == '"' and value:sub(-1,-1) == '"' then
                value = value:sub(2, -2)
              end
              metadata[key] = value
              if DEBUG then
                io.stderr:write("DEBUG: Parsed metadata: " .. key .. " = " .. value .. "\n")
              end
            end
          end
        else
          in_metadata = false
          table.insert(lines, line)
        end
      end
      
      -- Merge parsed metadata with existing attributes
      for k, v in pairs(metadata) do
        attrs[k] = v
      end
      
      if DEBUG then
        io.stderr:write("DEBUG: Available attributes after parsing: ")
        for k, v in pairs(attrs) do
          io.stderr:write(k .. "=" .. tostring(v) .. " ")
        end
        io.stderr:write("\n")
        
        local identifier = metadata["label"] or elem.attr.identifier or ""
        io.stderr:write("DEBUG: Block identifier: " .. identifier .. "\n")
        io.stderr:write("DEBUG: Code block text length: " .. #elem.text .. "\n")
      end
      
      -- Check if we should read from an external file
      local file_path = attrs["file"] or attrs["filename"]
      
      if not file_path and elem.text:match("^%s*$") then
        io.stderr:write("WARN: Empty code block detected, but no file attribute found.\n")
      end
      
      if file_path then
        if DEBUG then
          io.stderr:write("DEBUG: File attribute found: " .. file_path .. "\n")
        end
        
        -- Handle Quarto project-relative paths (starting with /)
        if file_path:sub(1, 1) == "/" then
          local quarto_project_dir = os.getenv("QUARTO_PROJECT_DIR") or "."
          file_path = quarto_project_dir .. file_path
          if DEBUG then
            io.stderr:write("DEBUG: Converted to absolute path: " .. file_path .. "\n")
          end
        end
        
        if DEBUG then
          io.stderr:write("DEBUG: Attempting to read PlantUML source from file: " .. file_path .. "\n")
        end
        
        local file, err = io.open(file_path, "r")
        if file then
          source_code = file:read("*all")
          file:close()
          if DEBUG then
            io.stderr:write("DEBUG: Successfully read " .. #source_code .. " characters from file.\n")
            if #source_code > 0 then
              local preview = source_code:sub(1, math.min(100, #source_code))
              io.stderr:write("DEBUG: File content preview: " .. preview .. "...\n")
            end
          end
        else
          io.stderr:write("ERROR: Could not open file: " .. file_path .. "\n")
          if err then
            io.stderr:write("ERROR: " .. err .. "\n")
          end
          return elem
        end
      else
        source_code = table.concat(lines, "\n")
        if DEBUG then
          io.stderr:write("DEBUG: Using inline PlantUML source (" .. #source_code .. " characters).\n")
        end
      end
      
      if not source_code or source_code == "" then
        io.stderr:write("ERROR: No PlantUML source code found.\n")
        return elem
      end
      
      local label = attrs["label"] or "plantuml-" .. generate_unique_id(8)
      local output_svg_filename = label .. ".svg"
      
      if DEBUG then
        io.stderr:write("DEBUG: Output SVG filename: " .. output_svg_filename .. "\n")
      end

      if render_plantuml(source_code, output_svg_filename) then
        local image_path = output_svg_filename
        if DEBUG then
          io.stderr:write("DEBUG: Image path in AST set to: " .. image_path .. "\n")
        end
        
        local image_attr_list = {}
        for key, value in pairs(attrs) do
          if key ~= "fig-cap" and key ~= "label" and key ~= "file" and key ~= "filename" then
            table.insert(image_attr_list, {key, value})
          end
        end
        
        local image_inline = pandoc.Image({}, image_path, "", pandoc.Attr(label, {}, image_attr_list))
        local image_block = pandoc.Para({image_inline})
        local blocks_to_return = {image_block}

        if attrs["fig-cap"] then
          if DEBUG then
            io.stderr:write("DEBUG: Adding caption block.\n")
          end
          local caption_block = pandoc.Para({pandoc.Str(attrs["fig-cap"])})
          table.insert(blocks_to_return, caption_block)
        end
        
        if DEBUG then
          io.stderr:write("DEBUG: Wrapping content in final figure Div.\n")
        end
        local figure_attrs = pandoc.Attr(label, {"quarto-figure", "quarto-figure-center"}, {})
        local figure_div = pandoc.Div(blocks_to_return, figure_attrs)
        
        return figure_div
      else
        io.stderr:write("ERROR: Failed to render PlantUML diagram.\n")
      end
    else
      if DEBUG then
        io.stderr:write("DEBUG: Skipping CodeBlock. Class 'plantuml' not found. (Not rendered by filter)\n")
      end
    end
  end
  
  return elem 
end

return {{CodeBlock = plantuml_filter}}