local cli

-- ------- --
-- Helpers --
-- ------- --

local split = function(str, pat)
  local t = {}
  local fpat = "(.-)" .. pat
  local last_end = 1
  local s, e, cap = str:find(fpat, 1)
  while s do
    if s ~= 1 or cap ~= "" then
  table.insert(t,cap)
    end
    last_end = e+1
    s, e, cap = str:find(fpat, last_end)
  end
  if last_end <= #str then
    cap = str:sub(last_end)
    table.insert(t, cap)
  end
  return t
end

local buildline = function(words, size, overflow)
  -- if overflow is set, a word longer than size, will overflow the size
  -- otherwise it will be chopped in line-length pieces
  local line = ""
  if string.len(words[1]) > size then
    -- word longer than line
    if overflow then
      line = words[1]
      table.remove(words, 1)
    else
      line = words[1]:sub(1, size)
      words[1] = words[1]:sub(size + 1, -1)
    end
  else
    while words[1] and (#line + string.len(words[1]) + 1 <= size) or (line == "" and #words[1] == size) do
      if line == "" then
        line = words[1]
      else
        line = line .. " " .. words[1]
      end
      table.remove(words, 1)
    end
  end
  return line, words
end

local delimit = function(str, size, pad, overflow)
  pad = pad or 0

  local line = ""
  local out = ""
  local padstr = string.rep(" ", pad)
  local words = split(str, ' ')

  while words[1] do
    line, words = buildline(words, size, overflow)
    if out == "" then
      out = padstr .. line
    else
        out = out .. "\n" .. padstr .. line
    end
  end

  return out
end

function cli_error(msg)
  print(cli.name .. ": error: " .. msg .. '; re-run with --help for usage.')
  return false
end

-- -------- --
-- CLI Main --
-- -------- --

cli = {
  name = "",
  required = {},
  optional = {},
  args = {},
  colsz = { 0, 0 }, -- set to 0 for auto detect
  maxlabel = 0,
}

--- Assigns the name of the program which will be used for logging.
function cli:set_name(name)
  self.name = name
end

--- Defines a required argument.
--- Required arguments have no special notation and are order-sensitive.
--- *Note:* if `@ref` is omitted, the value will be stored in `args[@key]`.
--- *Aliases: `add_argument`*
---
--- ### Parameters
--- 1. **key**: the argument's "name" that will be displayed to the user
--- 1. **desc**: a description of the argument
--- 1. **ref**: optional; the table key that will be used to hold the value of this argument
---
--- ### Usage example
--- The following will parse the argument (if specified) and set its value in `args["root_path"]`:
--- `cli:add_arg("root", "path to where root scripts can be found", "root_path")`
function cli:add_arg(key, desc, ref)
  assert(type(key) == "string" and type(desc) == "string", "Key and description are mandatory arguments (Strings)")
  table.insert(self.required, { key = key, desc = desc, ref = ref or key, value = nil })
  if #key > self.maxlabel then self.maxlabel = #key end
end

--- Defines an optional argument.
--- Optional arguments can use 3 different notations, and can accept a value.
--- *Aliases: `add_option`*
---
--- ### Parameters
--- 1. **key**: the argument identifier, can be either `-key`, or `-key, --expanded-key`:
--- if the first notation is used then a value can be defined after a space (`'-key VALUE'`),
--- if the 2nd notation is used then a value can be defined after an `=` (`'key, --expanded-key=VALUE'`).
--- 1. **desc**: a description for the argument to be shown in --help
--- 1. **ref**: *optional*; override where the value will be stored, @see cli:add_arg
--- 1. **default**: *optional*; specify a default value (the default is "")
---
--- ### Usage example
--- The following option will be stored in `args["i"]` with a default value of `my_file.txt`:
--- `cli:add_option("-i, --input=FILE", "path to the input file", nil, "my_file.txt")`
function cli:add_opt(key, desc, ref, default)

  -- parameterize the key if needed, possible variations:
  -- 1. -key
  -- 2. -key VALUE
  -- 3. -key, --expanded
  -- 4. -key, --expanded=VALUE
  -- 5. --expanded
  -- 6. --expanded=VALUE

  assert(type(key) == "string" and type(desc) == "string", "Key and description are mandatory arguments (Strings)")
  assert(type(ref) == "string" or ref == nil, "Reference argument: expected a string or nil")
  assert(type(default) == "string" or default == nil or default == false, "Default argument: expected a string or nil")

  -- characters allowed are a-z, A-Z, 0-9
  -- extended + values also allow; # @ _ + - 
  local PAT12 = "^%-([%a%d]+)[ ]?([%a%d#@_%+%-%$]*)"                           -- matches 1 & 2, returns 2 captures
  local PAT34 = "^%-([%a%d]+), %-%-([%a%d#@_%+%-%$]+)[=]?([%a%d#@_%+%-%$]*)"   -- matches 3 & 4, returns 3 captures
  local PAT56 = "^%-%-([%a%d#@_%+%-%$]+)[=]?([%a%d#@_%+%-%$]*)"                -- matches 5 & 6, returns 2 captures
  local k, ek, v

  -- first try expanded, retry short+expanded, finally short only
  _, _, ek, v = key:find(PAT56)
  if not ek then
    _, _, k, ek, v = key:find(PAT34)
    if not ek then
      _, _, k, v = key:find(PAT12)
    end
  end

  -- below description of full entry record, nils included for reference
  local entry = {
    key = k,
    expanded_key = ek,
    ref = ref or ek or k,
    desc = desc,
    default = default,
    label = key,
    flag = (default == false),
    value = default,
  }

  table.insert(self.optional, entry)
  if entry.k then self.optional[entry.k] = entry end
  if entry.ek then self.optional[entry.ek] = entry end
  if #key > self.maxlabel then self.maxlabel = #key end
  
end

--- Define a flag argument (on/off). This is a convenience helper for cli.add_opt().
--- See cli.add_opt() for more information.
---
--- ### Parameters
-- 1. **key**: the argument's key
-- 1. **desc**: a description of the argument to be displayed in the help listing
-- 1. **ref**: optionally override where the key which will hold the value
function cli:add_flag(key, desc, ref)
  self:add_opt(key, desc, ref, false)
end


--- Parses the arguments found in #arg and returns a table with the populated values.
--- (NOTE: after succesful parsing, the module will delete itself to free resources)
---
--- ### Parameters
--- 1. **dump**: set this flag to dump the parsed variables for debugging purposes, alternatively 
--- set the first option to --__DEBUG__ (option with 2 trailing and leading underscores) to dump at runtime.
---
--- ### Returns
--- 1. a table containing the keys specified when the arguments were defined along with the parsed values.
function cli:parse_args(dump)

  local args = self.args
  
  -- starts with --help? display the help listing and abort!
  if args[1] and (args[1] == "--help" or args[1] == "-h") then
    return self:print_help()
  end

  -- starts with --__DUMP__ display set dump to true and dump the parse arguments
  if dump == nil then 
    dump = (args[1] and args[1] == "--__DUMP__")
    table.remove(args, 1)  -- delete it to prevent further parsing
  end
  
    local PAT12 = "^%-([%a%d]+)[ ]?([%a%d]*)"                  -- matches 1 & 2, returns 2 captures

  while args[1] do
    local entry = nil
    local opt = args[1]
    local _, _, optpref, optkey = opt:find("^(%-[%-]?)(.+)")   -- split PREFIX & NAME+VALUE
    local _, _, optkey, optval = optkey:find(".-[=](.+)")       -- Gets the value
    
    if not optref then
      break   -- no optional prefix, so options are done
    end

    if optkey and self.optional[optkey] then
        entry = self.optional[optkey]
    else
        return cli_error("unknown/bad option; "..opt)
    end

    table.remove(args,1)
    if optpref == "-" then
      if optval then
        return cli_error("short option does not allow value through '='; "..opt)
      end
      if entry.flag then
        optval = true
      else
        -- not a flag, value is in the next argument
        optval = args[1]
        table.remove(args, 1)
      end
    end
    
    entry.value = optval
  end

  -- missing any required arguments, or too many?
  if #args ~= #self.required then
    cli_error("bad number of arguments; " .. #self.required .. " argument(s) must be specified, not " .. #args)
    self:print_usage()
    return false
  end

  local results = {}
  for i, entry in ipairs(self.required) do
    results[entry.ref] = args[i]
  end
  for _, entry in pairs(self.optional) do
    if entry.key then results[entry.key] = entry.value end
    if entry.expanded_key then results[entry.expanded_key] = entry.value end
    results[entry.ref] = entry.value
  end

  if dump then
    for k,v in pairs(results) do print("  " .. expand(k, 15) .. " => " .. tostring(v)) end
  end
  
  if not _TEST then
    -- cleanup entire module, as it's single use
    -- remove from package.loaded table to enable the module to
    -- garbage collected.
    for k, v in pairs(package.loaded) do
      if v == cli then
        package.loaded[k] = nil
        break
      end
    end
    -- clear table in case user holds on to module table
    for k, _ in pairs(cli) do
      cli[k] = nil
    end
  end
  
  return results
end

--- Prints the USAGE heading.
---
--- ### Parameters
 ---1. **noprint**: set this flag to prevent the line from being printed
---
--- ### Returns
--- 1. a string with the USAGE message.
function cli:print_usage(noprint)
  -- print the USAGE heading
  local msg = "Usage: " .. tostring(self.name)
  if self.optional[1] then
    msg = msg .. " [OPTIONS] "
  end
  if self.required[1] then
    for _,entry in ipairs(self.required) do
      msg = msg .. " " .. entry.key .. " "
    end
  end

  if not noprint then print(msg) end
  return msg
end


--- Prints the HELP information.
---
--- ### Parameters
 ---1. **noprint**: set this flag to prevent the information from being printed
---
--- ### Returns
--- 1. a string with the HELP message.
function cli:print_help(noprint)

  local msg = self:print_usage(true) .. "\n"
  local col1 = self.colsz[1]
  local col2 = self.colsz[2]
  if col1 == 0 then col1 = o.maxlabel end
  col1 = col1 + 3     --add margins
  if col2 == 0 then col2 = 72 - col1 end
  if col2 <10 then col2 = 10 end
  
  local append = function(label, desc)
      label = "  " .. label .. string.rep(" ", col1 - (#label + 2))
      desc = delimit(desc, col2)   -- word-wrap
      desc = desc:gsub("\n", "\n" .. string.rep(" ", col1)) -- add padding
      
      msg = msg .. label .. desc .. "\n"
  end
  
  
  if self.required[1] then
    msg = msg .. "\nRequired arguments: \n"
    for _,entry in ipairs(self.required) do
      append(entry.key, entry.desc)
    end
  end

  if self.optional[1] then
    msg = msg .. "\nOptional arguments: \n"

    for _,entry in ipairs(self.optional) do
      local desc = entry.desc
      if not entry.flag and entry.default then
        desc = desc .. " (default: " .. entry.default .. ")"
      end
      append(entry.label, desc)
    end
  end

  if not noprint then print(msg) end
  return msg
end

--- Sets the amount of space allocated to the argument keys and descriptions in the help listing.
--- The sizes are used for wrapping long argument keys and descriptions.
--- ### Parameters
--- 1. **key_cols**: the number of columns assigned to the argument keys, set to 0 to auto detect (default: 0)
--- 1. **desc_cols**: the number of columns assigned to the argument descriptions, set to 0 to auto set the total width to 72 (default: 0)
function cli:set_colsz(key_cols, desc_cols)
  self.colsz = { key_cols or self.colsz[1], desc_cols or self.colsz[2] }
end


-- finalize setup
cli.version = "1.1-0"
for k,v in pairs(arg) do o.args[k] = v end

-- aliases
cli.add_argument = cli.add_arg
cli.add_option = cli.add_opt

-- test aliases for local functions
if _TEST then
  cli.split = split
  cli.delimit = delimit
end


return cli
