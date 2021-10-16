-- DTS6619.lua - model of DTS6619 electricity meter
-- This file is a part of DAQEMON application 
-- Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
-- DAQEMON is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License v2
-- as published by the Free Software Foundation;
-- License:  https://opensource.org/licenses/GPL-2.0

local dtype= require("dtype")

local DTS6619 = {
  func = 'read_input_registers', -- MODDBUS function code 04
  dt = dtype.float32, -- all registers of the same type
  inputs = {
    voltageA  = 0x0000, -- phase A voltage, V
    voltageB  = 0x0002, -- phase B voltage, V
    voltageC  = 0x0004, -- phase C voltage, V
    currentA  = 0x0008, -- line A current, A
    currentB  = 0x000A, -- line B current, A
    currentC  = 0x000C, -- line C current, A
    power     = 0x0010, -- total  active power, kW
    powerA    = 0x0012, -- line A active power, kW
    powerB    = 0x0014, -- line B active power, kW
    powerC    = 0x0016, -- line C active power, kW
    reactive  = 0x0018, -- total  reactive power, VAR
    reactiveA = 0x001A, -- line A reactive power, VAR
    reactiveB = 0x001C, -- line B reactive power, VAR
    reactiveC = 0x001E, -- line V reactive power, VAR
    factorA   = 0x002A, -- line A reactive power factor
    factorB   = 0x002C, -- line B reactive power factor
    factorC   = 0x002E, -- line C reactive power factor
    frequency = 0x0036, -- frequency, Hz
    meter     = 0x0100, -- total active energy, kW*h
    meter_r   = 0x0400, -- reactive energy, kW*h
  }
}

function DTS6619.read(model, port, dev, inp)
  return read_modbus(port, dev.slaveid, inp, model.dt, model.func)
end

return DTS6619