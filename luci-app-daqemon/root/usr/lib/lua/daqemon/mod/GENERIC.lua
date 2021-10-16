-- GENERIC.lua - a generic model of electricity meter
-- This file is a part of DAQEMON application 
-- Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
-- DAQEMON is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License v2
-- as published by the Free Software Foundation;
-- License:  https://opensource.org/licenses/GPL-2.0

local dtype= require("dtype")

local GENERIC = {
  func = 'read_input_registers', -- MODDBUS function code 04
  dt = dtype.float32, -- all registers of the same type
  inputs = {
    meter     = 0x0100, -- active energy, kW*h
  }
}

function GENERIC.read(model, port, dev, inp)
  return read_modbus(port, dev.slaveid, inp, model.dt, model.func)
end

return GENERIC