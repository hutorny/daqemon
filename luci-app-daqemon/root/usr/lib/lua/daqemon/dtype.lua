--[[
 dtype.lua - data type dictionary and conversion functions
 This file is a part of DAQEMON application
 Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
 DAQEMON is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License v2
 as published by the Free Software Foundation;
 License:  https://opensource.org/licenses/GPL-2.0 
 ]]

local bit = require("bit")

local function int16_from1x16(r) return r[1] end
local function int32_from2x16(r) return bit.lshift(r[1],16) + r[2] end

local function fixed32D1_from2x16(r) return int32_from2x16(r) / 10. end
local function fixed32D2_from2x16(r) return int32_from2x16(r) / 100. end
local function fixed32D3_from2x16(r) return int32_from2x16(r) / 1000. end
local function fixed16D3_from1x16(r) return r[1] / 1000. end
local function fixed16D2_from1x16(r) return r[1] / 100. end
local function fixed16D1_from1x16(r) return r[1] / 10. end

local function float32_from2x16(r)
  if r[1] == 0 and r[2] == 0 then return 0.0 end -- special case: zero
  local sign     = bit.band(r[1], 0x8000) == 0 and 1 or -1   -- bit  31
  local exponent = bit.rshift(bit.band(r[1], 0x7F80),7)      -- bits 30..23
  local fraction = bit.lshift(bit.band(r[1],0x7F),16) + r[2] -- bits 22..0
  if exponent == 0xFF then
    if fraction == 0 then return math.huge * 0 end -- special case: NaN
    return  math.huge * sign                       -- special case: infinity
  end
  local mantissa = 1+math.ldexp(fraction, -23)
  return math.ldexp(mantissa, exponent - 127)
end

return {
  int16        = {size=2, from=int16_from1x16},
  fixed16D1    = {size=2, from=fixed16D1_from1x16},
  fixed16D2    = {size=2, from=fixed16D2_from1x16},
  fixed16D3    = {size=2, from=fixed16D3_from1x16},
  int32        = {size=4, from=int32_from2x16},
  fixed32D1    = {size=4, from=fixed32D1_from2x16},
  fixed32D2    = {size=4, from=fixed32D2_from2x16},
  fixed32D3    = {size=4, from=fixed32D3_from2x16},
  float32      = {size=4, from=float32_from2x16}
}
