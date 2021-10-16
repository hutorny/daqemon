-- DDM18SD.lua - model of DDM18SD electricity meter
-- This file is a part of DAQEMON application 
-- Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
-- DAQEMON is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License v2
-- as published by the Free Software Foundation;
-- License:  https://opensource.org/licenses/GPL-2.0

local dtype= require("dtype")

local DDM18SD = {
  func = 'read_input_registers', -- MODDBUS function code 04
  dt = dtype.float32, -- all registers of the same type
  inputs = {
    voltage   = 0x0000, -- voltage, V
    current   = 0x0008, -- current, A
    power     = 0x0012, -- active power, kW
    reactive  = 0x001A, -- reactive power, VAR
    factor    = 0x002A, -- reactive power factor
    frequency = 0x0036, -- frequency, Hz
    meter     = 0x0100, -- active energy, kW*h
    meter_r   = 0x0400, -- reactive energy, kW*h
  }
}

function DDM18SD.read(model, port, dev, inp)
  return read_modbus(port, dev.slaveid, inp, model.dt, model.func)
end

return DDM18SD