-- ua.lua - Ukrainian multi-rate functions
-- This file is a part of DAQEMON application 
-- Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
-- DAQEMON is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License v2
-- as published by the Free Software Foundation;
-- License:  https://opensource.org/licenses/GPL-2.0

local rate = {}

-- Dual rate: 7:00-23:00 - x 1, otherwise x 0.5 
function rate.dual(localtime) 
  local t = os.date('*t', localtime).hour
  return (t >= 7 and t < 23) and 1 or 0.5
end

-- Triple rate: 8:00-11:00, 20:00-22:00 - x 1.5, 7:00-8:00, 11:00-20:00, 22:00-23:00 - x 1, otherwise x 0.4 
function rate.triple(localtime) 
  local t = os.date('*t', localtime).hour
  if (t >= 8 and t < 11) or (t >= 20 and t < 22) then return 1.5 end
  return (t >= 7 and t < 23) and 1 or 0.4
end

function rate.index()
  return {
    dual = "UA: Двозонний тариф",
    triple = "UA: Тризонний тариф"
  }
end

return rate
