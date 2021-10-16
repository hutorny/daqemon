-- sim.lua - multirate tariff simulation
-- This file is a part of DAQEMON application 
-- Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
-- DAQEMON is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License v2
-- as published by the Free Software Foundation;
-- License:  https://opensource.org/licenses/GPL-2.0

local rate = {}

function rate.dual(localtime) 
  local t = os.date('*t', localtime).min
  return (t >= 7 and t < 23) and 1 or 0.5
end

function rate.triple(localtime) 
  local t = os.date('*t', localtime).min
  if (t >= 8 and t < 11) or (t >= 20 and t < 22) then return 1.5 end
  return (t >= 7 and t < 23) and 1 or 0.4
end

function rate.index()
  return {
    dual = "SIM: Dual rate tariff 7-23-7",
    triple = "SIM: Triple rate tariff"
  }
end

return rate
