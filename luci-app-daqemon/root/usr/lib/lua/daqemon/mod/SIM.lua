-- SIM.lua - simulation device
-- This file is a part of DAQEMON application 
-- Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
-- DAQEMON is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License v2
-- as published by the Free Software Foundation;
-- License:  https://opensource.org/licenses/GPL-2.0

local dtype= require 'dtype'

local SIM = {
  dt = dtype.float32,
  func = '',
  simulator = true,
  inputs = {
    random = 0,
    monotonic = 1,
    discrete  = 2,
  }
}

math.randomseed(os.time())

local function load(inp)
  local f, err = io.open('/tmp/daqemon.'..inp..'.sim', 'r')
  if not f then return 0 end
  local v = f:read('*number')
  f:close()
  return v or 0
end

local function save(inp, value)
  local f, err = io.open('/tmp/daqemon.'..inp..'.sim', 'w')
  if not f then return 0 end
  f:write(value)
  f:close()
end

local monotonic = {}

local function rnd(a,b)
  if math.random() < 0.86 then return 0 end
  if a < 1 and a > 0 then
    return a * math.random(1,b/a)
  else
    return math.random(a,b)
  end
end

local function compute(port, inp)
  if inp == 2 then return rnd(200,1000) or 0 end
  if inp == 1 then monotonic[port] = monotonic[port] + rnd(0.01,0.1); return monotonic[port] end
  if inp == 0 then return math.random(100) end
  return nil
end


function SIM.read(model, port, dev, inp)
  if inp == 1 and monotonic[dev.slaveid] == nil then monotonic[dev.slaveid] = load(dev.slaveid) end
  local val = compute(dev.slaveid, inp)
  if inp == 1 then save(dev.slaveid, val) end
  return val ~= nil, val
end

return SIM