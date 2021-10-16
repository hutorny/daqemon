#!/usr/bin/lua
-- daqemon.lua - main executable file
-- This file is a part of DAQEMON application
-- Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
-- DAQEMON is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License v2
-- as published by the Free Software Foundation;
-- License:  https://opensource.org/licenses/GPL-2.0

package.path = package.path .. ';./lua/?.lua;/usr/lib/lua/daqemon/?.lua'
local mb   = require 'libmodbus'
local so   = require 'socket'
local log  = require 'log'
local dtype= require 'dtype'
local json = require 'cjson'
local dque = require 'dataque'
local fs   = require 'fs'
local util = require 'util'
local condef = require 'condef'

local version = "1.0"

local daqemon = {}
local models = {}

local debug = print

local config = {}

local options = {
  config = nil,
  action = {},
  delimiter = '\t',
}

local function ok(v, message)
  if v then return v, message end
  if message then
    message = util.tostr(message) ..  ". Terminating."
  else
    message = "Terminating."
  end
  print(message)
  os.exit(1)
end

function daqemon.init()
  log.i("\rdaqemon v%s is starting with libmodbus v%s", version, mb.version())
  config = daqemon.readcfg(options.config, condef)
  if options.interface then
    if config == nil then config = {} end
    config.interface = options.interface
  else
    ok(config, "Config is not available")
  end
  if config.daqemon then
    if config.daqemon.samplefile then fs.mkpath(config.daqemon.samplefile) end
    dque.init(config.daqemon)
  end
end

local function sleep(sec)
  if not pcall(so.sleep,sec) then
    log.e("Interrupted")
    return false
  end
  return true
end

local function is_json(filename)
  local jsn = '.json'
  return filename:sub(-#jsn) == jsn
end


local function saveto(filename, data)
  local file, res, msg, text
  if not filename then
    filename = 'stdout'
    file = io.stdout
    data = util.tostr(data,'\n') .. '\n'
  else
    if is_json(filename) and data then data = json.encode(data) else data = util.tostr(data,'\n') end
    file, msg = io.open(filename, 'w')
  end
  if file and data then
    res, msg = file:write(data);
  end
  if file and file ~= io.stdout then file:close() end
  if file and res then return true end
  log.e("Error writing to '%s': %s", filename, util.tostr(msg))
  return false
end

local function aquire(port, data, input)
  local good, value = input.dev.model.read(input.dev.model, port, input.dev, input.inp)
  if not good then
    log.w("Error reading from '%s:%s'", input.device, input.input)
    data[input.name] = { error = value }
    return 0
  else
    data[input.name] = value
    return 1
  end
end

local max_interval = 0

local scheduler = {
  terminated = false,
  SLOT = 60
}

function scheduler.curr_period()
  return math.floor(scheduler.timestamp()/scheduler.SLOT)
end

function scheduler.next_time(next, curr)
  return (next + curr) * scheduler.SLOT
end

function scheduler.timestamp()
    return os.time()
end

function scheduler.logtime() end
function scheduler.finished() end

function scheduler.sleep(till)
  if scheduler.terminated then return false end
  if till <= os.time() then return true end
  return sleep(till - os.time())
end

function scheduler.terminate()
  scheduler.terminated = true
end

local simulator = {
  count = -1,
  time = os.time({year=2018, month=1, day=1})
}

local last_logged = 0
function simulator.logtime()
  local d = os.date('*t', simulator.timestamp())
  if last_logged ~= d.day then
    local eol = '\r'
    if d.day == 2 and last_logged ~= 0 then eol = "\n" end;
    io.write(string.format(eol.."Simulating %s",os.date("%Y-%m-%d",simulator.timestamp())))
    io.flush()
    last_logged = d.day
  end
end

function simulator.finished()
  local d = os.date('*t', simulator.timestamp())
  io.write(string.format("\nFinished   %s\n",os.date("%Y-%m-%d %X",simulator.timestamp())))
  io.flush()
end


function simulator.activate()
  log.w("Running simulation")
  scheduler.logtime = simulator.logtime
  scheduler.sleep = simulator.sleep
  scheduler.timestamp = simulator.timestamp
  scheduler.finished = simulator.finished
end

function simulator.timestamp()
  return simulator.time
end

function simulator.sleep(till)
  if scheduler.terminated then return false end
  simulator.time = till
  simulator.count = simulator.count - 1
  if simulator.count == 0 then return false end
  return sleep(0)
end

local function first_run(live)
  local curr = scheduler.curr_period()
  local min = math.huge
  local next = 0
  for i, v in pairs(config.queue) do
     local rem = curr % i
     if live or v.qos ~= 0 then
       min = math.min(min, scheduler.next_time(i, curr))
     end
  end
  return math.min(min, scheduler.next_time(max_interval, curr))
end

local function collect(port, live, force)
  local data = { time = scheduler.timestamp() } -- Local time stamp
  local curr = scheduler.curr_period()
  local min = math.huge
  local count = 0
  local queid = -1

  -- Rates are calculated using local time
  if type(config.daqemon.rate) == 'function' then
    data.rate = config.daqemon.rate(data.time)
  end

  for i, v in pairs(config.queue) do
     local rem = curr % i
     if force or (rem == 0 and (live or v.qos ~= 0)) then
       for j, inp in ipairs(v) do
         if live or inp.qos ~= 0 then
           local aquired = aquire(port, data, inp)
           if aquired and queid < i then queid = i end
           count = count + aquired
         end
       end
     else
     end
     if (live or v.qos ~= 0) then
       min = math.min(min, scheduler.next_time(i, curr))
     end
  end
  if force then return  0, data end
  if queid ~= -1 and config.daqemon.samplefile then
    local file = string.format(config.daqemon.samplefile, queid)
    if not saveto(file, data) then config.daqemon.samplefile = nil end
  end
  for i, v in pairs(data) do if type(v) == type({}) then data[i] = nil end end
  if count == 0 then
    if live or force then log.w("Nothing collected") end
    data = nil
  end
  local next = math.min(min, scheduler.next_time(max_interval, curr))
  log.i("Next collect in %d seconds", next - scheduler.timestamp())
  return  next, data
end

function daqemon.run()
  ok(daqemon.validate(config), "Config is not valid")
  local api = config.server.api
  local port = daqemon.connect()
  if options.simulated then simulator.activate() end
  if api.alive() then
    config.server.initialized = api.init(config.inputs, config.client.meta)
    while not dque.empty() and api.alive() do
      if api.batch(dque.get()) then dque.remove() else break end
    end
  end
  scheduler.logtime()
  local first = first_run(api.alive())
  local delay = first - scheduler.timestamp()
  if delay > 0 then
    log.t("Sleep %d sec till start of the first even period", delay)
    if not scheduler.sleep(first) then return end
  end
  while true do
    scheduler.logtime()
    if not config.server.initialized and api.alive() then
      config.server.initialized = api.init(config.inputs)
    end
    local next, data = collect(port, api.alive())
    while not dque.empty() and api.alive(true) do
      if api.batch(dque.get()) then dque.remove() else break end
    end
    if data then
      if not api.submit(data) then
        log.e("Error sending data")
        if not dque.add(data) then
          log.t("Sleep %d sec till next retry", config.server.retry_period*60)
          if not sleep(config.server.retry_period*60) then return end
        end
      end
    end
    collectgarbage('collect')
    if not scheduler.sleep(next) then return scheduler.finished() end
  end
end

local function bind(interface)
  for k,v in pairs(interface) do
    if mb[k] and v then -- Add other possible interfaces when available
      interface.open = mb[k]
      interface.params = v
      log.i("Found modbus interface %s with parameters %s", k, table.concat(v, ","))
      return true
    else
      log.w("Invalid modbus interface %s", k)
    end
  end
  return false
end

function daqemon.connect(ignore_error)
  if config.port or options.simulated then return config.port or options.simulated end
  local interface = options.interface
  if not interface then
    interface = config.interface
    if not interface.open then
      bind(interface)
    end
  end
  if not interface.params then
     log.e("Invalid modbus interface %s", util.tostr(interface))
     return false
  end
  log.t("Connecting with %s", util.tostr(interface.params))
  config.port = interface.open(unpack(interface.params))
  if not config.port or not config.port:connect() then
    log.e("Error connecting with %s", util.tostr(interface.params))
    if not ignore_error then os.exit(1) end
  else
    return config.port
  end
end


local current_slave = -1

function read_modbus(port, slave, reg, dt, func)
  if current_slave ~= slave then
    current_slave = slave
    port:set_slave(current_slave)
    ok(sleep(0.1), "Interrupted") -- workaround for a known issue in libmodbus when polling multiple slaves
  end
  local base_address = reg
  local ok, regs, err = false
  if func == nil then
    err = "Missing function"
  elseif func == 'read_input_registers' or tonumber(func) == 4 then
    ok, regs, err = pcall(function() return port:read_input_registers(base_address, dt.size/2) end)
  elseif func == 'read_registers' or tonumber(func) == 3 then
    ok, regs, err = pcall(function() return port:read_registers(base_address, dt.size/2) end)
  else
    err = "Invalid function " + util.tostr(func)
  end
  if not ok then
    log.t(util.tostr(err or regs))
    scheduler.terminate()
    return false, err or regs
  end
  if not regs then return false, err end
  return true, dt.from(regs)
end

local function load_server(server)
  local valid = true
  if server.api then return valid end
  if server == nil or server.type == nil then
    log.e("server.type is missing")
    valid = false
  else
    valid, server.api = pcall(require, server.type)
    if not valid or server.api == nil or type(server.api) ~= type({}) then
      log.e("server type '%s' is not supported", server.type)
      valid = false
    end
  end
  return valid
end

local function is_multirate(rate)
  return rate and rate ~= '' and rate ~= 'none'
end

local function remove_placeholders(cfg)
    if cfg.client and cfg.client.meta then
      if cfg.client.meta.feeds then
        table.remove(cfg.client.meta.feeds, 1)
      end
      if cfg.client.meta.inputs then
        table.remove(cfg.client.meta.inputs, 1)
      end
    end
    if cfg.interface.slaveids then
      table.remove(cfg.interface.slaveids, 1)
    end
end

function daqemon.readcfg(filename, cfgdef)
  local cfg = cfgdef and json.decode(json.encode(cfgdef))
  -- Removing zero entries used for save validation
  if cfg then remove_placeholders(cfg) end
  if filename and #filename ~= 0 then
    if is_json(filename) then
      log.i("Reading json configuration from '%s'", filename)
      local f, err = io.open(filename, 'rb')
      if f then
        local data = f:read('*all')
        if not data then
          log.e("Error reading configuration file %s", filename)
          return nil, "Error reading configuration file" .. filename
        end
        cfg = json.decode(data)
      else
        if not cfgdef then ok(f, err) end
      end
    else
      log.i("Reading lua configuration from '%s'", filename)
      local good, lua = pcall(loadfile,filename)
      if not good or type(lua) ~= 'function' then
        log.e("Error reading configuration from '%s' ", filename)
        log.i(lua)
        return nil
      end
      cfg = cfg or {}
      setfenv(lua, cfg)
      lua()
    end
  end
  if load_server(cfg.server) and cfg.server.api then
    cfg.processes = cfg.server.api.getprocesses(cfg.client.meta, is_multirate(cfg.daqemon.rate))
    cfg.server.api.augument(cfg.server)
  end
  return cfg
end

function daqemon.savecfg(filename, config, source)
  if not config then
    return { success = false, message = "Missing config parameter"}
  end
  local default = daqemon.readcfg(source, condef, true)
  local file = io.open(filename, 'w')
  if not file then
    return { success = false, message = "Error writing to " .. filename }
  end
  local api
  config.processes = nil
  -- if default then return { success = true, config = default } end
  if config.server and not config.server.type then config.server.type = default.server.type end
  if config.server and load_server(config.server) and config.server.api then
    api = config.server.api
    api.strip(config.server)
  end
  local result, errors = util.assignto(default, config, {valid=true,inputs=true,devices=true,interface={slaveids=true}} )
  file:write(json.encode(result))
  file:close()
  if api then api.augument(result.server) end
  return {
    success = true,
    config = result,
    errors = (#errors > 0 and errors) or nil,
    message = (#errors > 0 and "Some properties were ignored") or nil
  }
end

local function max(a,b)
  if a == nil then return b elseif b == nil then return a end
  return math.max(a,b)
end

local function enqueue(cfg, inp)
  if cfg.queue == nil then cfg.queue = {} end
  if type(inp.interval) ~= type(1) or inp.interval <= 0  then
    log.w("Input '%s' has invalid interval %s", inp.name, util.tostr(inp.interval))
  else
    if cfg.queue[inp.interval] == nil then cfg.queue[inp.interval] = { } end
    table.insert(cfg.queue[inp.interval], inp)
    if inp.qos then cfg.queue[inp.interval].qos = max(cfg.queue[inp.interval].qos,inp.qos) end
    max_interval = math.max(max_interval, inp.interval)
  end
  return true
end

local function invalid_reader()
  log.w("Invalid reader is used")
  return false
end

local function load_rate_function(name)
  if name == nil or #name == 0 then return nil end
  local parts = name:split('%.')
  local fun, mod
  mod = 'rate/' .. parts[1]
  fun = parts[2]
  local good, lib = pcall(require, mod )
  if not good then
    log.e("Unkown rate function '%s', no module '%s'", name, mod)
    return nil
  end
  if fun ~= nil then
    if type(lib) ~= type({}) then
      log.e("Invalid rate module '%s' of type '%s', expected '%s'", mod, type(lib), type({}))
      return nil
    end
    fun = lib[fun]
  end
  if type(fun) ~= 'function' then
     log.e("Invalid rate function '%s' of type '%s', expected 'function'", name, type(fun))
     return nil
  end
  return fun
end

local function load_model(name)
    if models[name] then return models[name] end
    local good, model = pcall(require, 'mod/' .. name)
    if not good then
      log.e("Error loading device model '%s'", name)
      return nil
    end
    if model == nil or type(model.read) ~= 'function' then
        log.e("Model '%s' does not implement read", name)
        model.read = invalid_reader
    elseif model.func == nil then
        log.e("Model '%s' does not set func", name)
        model.read = invalid_reader
    end
    models[name] = model
    return model
end

function daqemon.load_models(names)
  local res = {}
  for i, name in ipairs(names) do
    res[i] = load_model(name)
    res[i].name = name
  end
  return res
end

function daqemon.validate(cfg)
  local valid = load_server(cfg.server)
  valid = valid and cfg.server.api.validate and cfg.server.api.validate(cfg.server, cfg.client)
  if cfg.daqemon.rate then
    cfg.daqemon.rate = load_rate_function(cfg.daqemon.rate)
    cfg.server.multirate = true
  end
  if not cfg.interface.open then bind(cfg.interface) end
  if not options.simulated and (cfg.interface.open == nil or type(cfg.interface.open) ~= 'function') then
    log.e("No valid interface specified")
    valid = false
  end
  for k,v in pairs(cfg.devices) do
    v.tag     = v.tag or v[1]
    v.model   = v.model or v[2]
    v.slaveid = v.slaveid or v[3]
    v.model = load_model(v.model)
  end
  util.array2map(cfg.devices, 'name')
  local hashad = false
  for k,v in pairs(cfg.inputs) do
    if type(v) ~= type({}) or (v.device == nil and v[1] == nil) then
      log.w("Invalid input %s={%s}", k, util.tostr(v))
    else
      local inp = {
        device   = v.device or v[1],
        input    = v.input or v[2],
        interval = v.interval or v[3],
        qos      = v.qos or v[4],
        tag      = v.tag or v[5],
        name     = v.name or k,
      }
      cfg.inputs[k] = inp
      if cfg.devices[inp.device] == nil then
        log.e("Input %s refers to unknown device '%s'", k, util.tostr(inp.device))
      elseif options.simulated and not cfg.devices[inp.device].model.simulator then
        print(util.tostr(inp.device), util.tostr(cfg.devices[inp.device]))
        log.w("Ignoring input %s from non-simulated device '%s' in simulation mode", k, util.tostr(inp.device))
      else
        inp.dev = cfg.devices[inp.device]
        if inp.dev.model ~= nil then
          inp.inp = inp.dev.model.inputs[inp.input]
          inp.tag = inp.tag or inp.dev.tag
        end
        if inp.inp == nil then
          log.e("Input %s refers to unknown device input '%s'", k, util.tostr(inp.input))
        else
          if enqueue(cfg,inp) then hashad = true end
        end
      end
    end
  end
  util.array2map(cfg.inputs, 'name')
  if not hashad then
    log.w("No valid input configured")
  end
  return valid and hashad
end

function daqemon.test_device(interface, slaveid, model, inputs)
  if not bind(interface) then return { success = false, message = "Invalid interface" } end
  local port = interface.open(unpack(interface.params))
  if not port or not port:connect() then
    return { success = false, message = "Error connecting to the MODBUS interface" }
  end
  if not model then
    local good, res = read_modbus(port, slaveid, 0x0100, dtype.float32)
    if good then return { success = true, inputs = { x0100 = res } } end
    return { success = false, message = "Error reading " .. slaveid .. " @ 0x0100 :" .. tostring(res) }
  end
  local device = load_model(model)
  if not device then return { success = false, message = "Invalid model " .. model } end
  if not inputs or #inputs == 0 then inputs = util.keys(device.inputs) end
  local data = {}
  local dev = { slaveid = slaveid }
  for k, v in ipairs(inputs) do
    local input = device.inputs[v]
    local ok, res = true, "invalid"
    if input then ok, res = device.read(device, port, dev, input) end
    data[v] = res
  end
  return { success = true, inputs = data }
end

function daqemon.test_modbus()
  local device, model = options.model
  if model == nil and config.devices then
    for k, d in pairs(config.devices) do
      if d.slaveid == options.slaveid then device = d.model; model = d[2]; break; end
    end
  end
  local port = daqemon.connect()
  if not port then return end
  log.i("Reading %s at %d", (model or "MODBUS"), options.slaveid)
  local good, res, ok
  if device and device.inputs then
    local w = 0
    for k, inp in pairs(device.inputs) do w = math.max(#k,w) end
    for k, inp in pairs(device.inputs) do
      ok, res = device.read(device, port, options, inp)
      print(k .. string.rep(' ', w -#k + 1) .. tostring(res))
      good = good and ok
    end
  else
    good, res = read_modbus(port, options.slaveid, 0, dtype.int16, 4)
    if not good then
    good, res = read_modbus(port, options.slaveid, 0, dtype.int16, 3)
    end
    print(res)
  end
  if not good and not options.simulated then os.exit(1) end
end

function daqemon.scan_modbus()
  local port = daqemon.connect()
  if not port and not options.simulated then os.exit(1) end
  log.i("Scanning MODBUS%s%s devices",options.scancount and " for " or "",
    options.scancount and tostring(options.scancount) or "")
  if not options.scancount then options.scancount = 247 end
  local dlm, sep = '',''
  for i = 1, 247 do
    log.i("Reading MODBUS at %d", i)
    local good, res = read_modbus(port, i, 0, dtype.int16, 4)
    if not good then
      good, res = read_modbus(port, i, 0, dtype.int16, 3)
    end
    log.t("Result %s", util.tostr(res))
    if options.scanprogress and i % 5 == 0 then
      io.stderr:write(sep, i)
      sep = ','
    end
    if good then
      if options.scantotext then
        print(i)
      else
        io.write(dlm,i)
        io.flush()
        dlm = ','
      end
      options.scancount = options.scancount - 1;
      if options.scancount == 0 then break end
    end
  end
  if options.scanprogress then  io.stderr:write(sep, 250) end
end

function daqemon.test_server()
  ok(daqemon.validate(config))
  log.i("Testing server %s at %s", config.server.type, config.server.url)
  local api = config.server.api
  local port = daqemon.connect()
  local next, data = collect(port, true, true)
  if not api.submit(data) then
     log.e("Error sending data")
     os.exit(1)
  else
     print("Success")
  end
end

function daqemon.print()
    ok(daqemon.validate(config))
    local port = daqemon.connect()
    local next, data = collect(port, true, true)
    saveto(nil, data)
end

function daqemon.dump_profile(justreturn)
  daqemon.validate(config)
  local profile = config.server.api.dump(config.inputs, config.client.meta)
  if not justreturn then print(profile) end
  return profile
end

local function convert_values(values)
  if values == nil then return nil end;
  local n = #values
  for i, v in ipairs(values) do
    local number = tonumber(v)
    local fals = v == 'FALSE'
    local tru = v == 'TRUE'
    if number ~= nil then
      values[i] = number
    elseif fals or tru then
      values[i] = tru
    elseif values[i] == 'NULL' then
      values[i] = nil
    end
  end
  return values
end

local function process_line(line)
  local values = line:split(options.delimiter)
  return convert_values(values)
end

local function process_record(fields, line)
  local values = convert_values(line:split(options.delimiter))
  local n, obj = #fields, {}
  for i, k in ipairs(fields) do obj[k] = values[i] end
  return obj
end


function daqemon.process_file()
  local file = ok(io.open(options.datafile, 'r'))
  local line = ok(file:read('*line'))
  local fields = line:split(options.delimiter)
  local api = config.server.api
  local start = os.time()
  local count = 0
  local tag = util.basename(options.datafile)
  log.i("Processing file '%s'", options.datafile)
  if tonumber(fields[0]) ~= nil then
    fields = nil
  else
    local inputs = {}
    for i, k in ipairs(fields) do
      if k ~= 'time' and k ~= 'rate' then
        inputs[k] = { tag = tag }
      end
    end
    api.init(inputs)
    line = file:read('*line')
  end
  if fields then
    while line ~= nil do
      local data = process_record(fields,line)
      if not api.submit(data) then break end
      line = file:read('*line')
      count = count + 1
    end
  else
    while line ~= nil do
      local data = process_line(line)
      if not api.submit(data) then break end
      line = file:read('*line')
      count = count + 1
    end
  end
  local elapsed = os.time() - start
  log.i("Processing %d rows finished in %d sec, %g rows/sec ", count, elapsed, count/elapsed)
end

local function is_library()
  if luci then return true end
  return arg == nil or type(arg)~=type({}) or type(arg[0])~=type('')
end

if is_library() then
  log.e = log.void
  return daqemon
end

local function isbad(opt, next)
  if opt:sub(3,3) == '' then return false end
  print(string.format("Invalid option '%s'", opt))
  options.invalid = true
  return next and next:sub(1,1) == '-' and 1 or 2
end

local function setverbosity(v)
    local b, e = string.find("01234newit", v)
    if b == nil then
      print(string.format("Invalid option value '%s'", v))
      return false
    end
    log.setlevel(v)
    return true
end

local dict = {}

local function parse_string_option(opt, next)
  if opt:sub(3,3) == '' then
    if next and next:sub(1,1) ~= '-' then
      return 2, next
    else
      return 1, nil
    end
  else
    return 1, opt:sub(3)
  end
end

function dict.c(opt, next) -- config file
  local res, cfg
  if opt:sub(1,1) ~= '-' then
    cfg = opt
    res = 1
  else
    res, cfg = parse_string_option(opt, next)
  end
  if cfg ~= nil then
    options.config = cfg
    return res
  end
  options.invalid = true
  print(string.format("Invalid option value '%s'"), next or '')
  return res
end

function dict.v(opt, next) -- verbosity
  if opt:sub(3,3) == '' then
    if next:sub(1,1) == '-' then setverbosity('i') return 1 end
    if setverbosity(next) then return 2 end
  else
    if setverbosity(opt:sub(3,3)) then return 1 end
  end
  print(string.format("Invalid option '%s %s'", opt, next:sub(1,1) ~= '-' and next or ''))
  options.invalid = true
  return next:sub(1,1) == '-' and 1 or 2
end

function dict.m(opt, next) -- test modbus
  local res, val = parse_string_option(opt, next)
  if val == nil then
    print(string.format("MODBUS slave id is required for '%s'", opt))
    return res
  end
  val = val:split(',')
  local slaveid = tonumber(val[1])
  if slaveid == nil then
    print(string.format("Invalid MODBUS slave id: %s", val[1]))
    options.invalid = true
  else
    options.slaveid = slaveid
    table.insert(options.action, daqemon.test_modbus)
  end
  if val[2] then
    options.model = val[2]
  end
  return res
end

function dict.t(opt, next) -- test server
  local bad = isbad(opt, next)
  if bad ~= false then return bad end
  table.insert(options.action, daqemon.test_server)
  return 1
end

function dict.s(opt, next) -- scan modbus
  local res, val = parse_string_option(opt, next)
  if val ~= nil then
    val = val:split(',')
    local count = tonumber(val[1])
    if count ~= nil then
      options.scancount = count
    else
      if val[2] == nil then val[2] = val[1] end
    end
    options.scantotext = true
    if val[2] then
      if val[2]:sub(1,1) == 'l' then
        options.scanprogress = true
        options.scantotext = false
      end
    end
  end
  table.insert(options.action, daqemon.scan_modbus)
  return res
end

function dict.d(opt, next) -- dump profile registration
  local bad = isbad(opt, next)
  if bad ~= false then return bad end
  table.insert(options.action, daqemon.dump_profile)
  return 1
end

function dict.p(opt, next) -- print
  local bad = isbad(opt, next)
  if bad ~= false then return bad end
  table.insert(options.action, daqemon.print)
  return 1
end

function dict.S(opt, next) -- execute simulation
  --local bad = isbad(opt, next)
  local res, val = parse_string_option(opt, next)
  options.simulated = true
  if val == nil then return res end
  val = val:split(',')
  local count = tonumber(val[1])
  if count ~= nil then
    simulator.count = count
  else
    if val[2] == nil then val[2] = val[1] end
  end
  if val[2] then
    simulator.time = util.parse(val[2])
    if simulator.time == nil then
      option.invalid = true
      print(string.format("Invalid date time '%s'", val[2]))
    end
  end
  if simulator.time then
    simulator.time = simulator.time
  else
   simulator.time = os.time()
  end
  return res
end

function dict.f(opt, next) -- data file
  local res, cfg = parse_string_option(opt, next)
  if cfg ~= nil then
    options.datafile = cfg
    table.insert(options.action, daqemon.process_file)
    return res
  end
  options.invalid = true
  print("File name is required for '%s'", opt)
  return res
end

function dict.i(opt, next) -- data file
  local res, cfg = parse_string_option(opt, next)
  if cfg ~= nil then
    options.interface = { open = mb.new_rtu, params = cfg:split(',') }
    return res
  else
    return res
  end
  options.invalid = true
  print(string.format("Port spec is required for '%s'", opt))
  return res
end

function dict.l(opt, next) -- list models
  local bad = isbad(opt, next)
  if bad ~= false then return bad end
  local dir = '/usr/lib/lua/daqemon/mod/'
  local handle = assert(io.popen('cd ' .. dir .. ' && ls -1 *.lua')) 
  local files = string.split(assert(handle:read('*a')), '\n')
  local models = {}
  for i, m in ipairs(files) do
    if #m > 0 then
      models[#models+1] = m:split('%.')[1]
    end
  end
  local models = daqemon.load_models(models);
  local res = {}
  for i,v in ipairs(models) do
    print(v.name)
  end
  return 1
end

function dict.h(opt, next) -- print help
  local bad = isbad(opt, next)
  if bad ~= false then return bad end
  print([[NAME
    DAQEMON - a service for MODBUS data acquisition
              Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
SYNOPSIS
    daqemon [OPTION] [FILE]
DESCRIPTION
  FILE      - configuration file. With no FILE empty configuration is used
 -c FILE    - same as FILE, specifies a configuration file
 -v<L>      - sets logging verbosity level L=0..4
 -m<ID>[,<model>]- tests reading from MODBUS device with given slave ID and model
 -t         - tests server connection
 -S<N>,date - run using simulated time, N specifies count of cycles to run
 -f FILE    - reads data from a tab-separated file and submits them to the server
 -s[N]      - scans MODBUS for [N] available devices and prints their ids
 -i PORT    - uses given serial port and port properties, e.g. /dev/ttyUSB0,9600,even
 -d         - dumps device profile registration
 -p         - prints acquired data
 -l         - list available models
]])
  os.exit(0)
end

local function parse_args()
  local i = 1
  while i <= #arg do
    if arg[i]:sub(1,1) == '-' then
      local opt = dict[arg[i]:sub(2,2)]
      if opt == nil then
        options.invalid = true
        print(string.format("Invalid option '%s'. Use -h for help", arg[i]))
        i = i + 1
      else
        i = i + opt(arg[i], arg[i+1])
      end
    else
      i = i + dict.c(arg[i])
    end
  end
  if next(options.action) == nil then options.action = { daqemon.run } end
  return options.invalid ~= true
end
if os.getenv('DAQEMON_TEST') == '1' then log.print = log.short end
if not parse_args() then os.exit(1) end
daqemon.init()
for i, run in pairs(options.action) do run() end
