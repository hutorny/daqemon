-- util.lua - utility and auxiliary functions
-- This file is a part of DAQEMON application 
-- Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
-- DAQEMON is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License v2
-- as published by the Free Software Foundation;
-- License:  https://opensource.org/licenses/GPL-2.0

local util = {}

-- split - splits a string by delimiter
function string:split(delimiter)
  local result = {}
  local from  = 1
  local delim_from, delim_to = string.find( self, delimiter, from  )
  while delim_from do
    table.insert( result, string.sub( self, from , delim_from-1 ) )
    from  = delim_to + 1
    delim_from, delim_to = string.find( self, delimiter, from  )
  end
  table.insert( result, string.sub( self, from  ) )
  return result
end

-- concatenates arrays and values, (concat exists and joins by string)
function util.appendto(result, ...)
  local others={...}
  for _,a in ipairs(others) do
    if type(a) == type({}) then
      for i,v in ipairs(a) do table.insert(result, v) end
    else
      table.insert(result, a)
    end
  end
  return result
end

-- merges tables into result
function util.mergeto(result, ...)
  local others={...}
  for _,a in ipairs(others) do
    if type(a) == type({}) then
      for k,v in pairs(a) do result[k] = v end
    else
      assert(a==nil,"Argument is not a table")
    end
  end
  return result
end

-- assign values from source into result by keys from result
function util.assignto(result, source, force, errors)
  if not errors then errors = {} end
  for k,v in pairs(source) do
    if type(result[k]) == type(v) or (force and force[k] == true) then
      if (not force or force[k] ~= true) and type(result[k]) == type({}) 
          and not(#(result[k]) == 1 and result[k][1] == 0) then
        result[k] = util.assignto(result[k], v, force and force[k], errors);
      else
        result[k] = v
      end
    else
      table.insert(errors, 'Ignoring property ' .. k)
    end
  end
  return result, errors
end

function util.contains(array, value)
  for k,v in pairs(source) do
    if v == value then return true end
  end
  return false
end

function util.join(t, dlm)
  local s = ""
  local d = ""
  for k,v in pairs(t) do
    if type(k) == type("") then
      s = s .. d .. k .. '=' .. tostring(v)
    else
      s = s .. d .. tostring(v)
    end
    d = dlm
  end
  return s
end

function util.tostr(v, dlm)
  if type(v) == type({}) then return util.join(v, dlm or ",") end
  return tostring(v)
end

function util.any(a,b,c,d,e)
  if     a ~= nil then return a
  elseif b ~= nil then return b
  elseif c ~= nil then return c
  elseif d ~= nil then return d
  elseif e ~= nil then return e end
  return nil
end

function util.basename(filename)
  local parts = filename:split('/')
  local name = parts[#parts]
  local parts = name:split('%.')
  return parts[1]
end

-- converts an array to key-value map 
function util.array2map(array, keyprop)
  for k,v in ipairs(array) do
    if v[keyprop] then  array[v[keyprop]] = v end
    array[k] = nil
  end
end

function util.keys(obj)
  local res = {}
  for k,v in pairs(obj) do res[#res+1] = k end
  return res
end

local datepattern = "(%d+)[%-|/](%d%d?)[%-|/](%d%d?)(%a?)(.*)"
local timepattern = "(%d%d?):(%d%d?):?(%d*)(%a?)"

-- Parses date from string in canonical YYYY-MM-DDThh:mm:ssZ
-- or shortened formats, such as Y/M/D, YY-M-DTh:, etc
-- Last Z indicates UTC, otherwise local time is assumed
function util.parse(strdate)
  local r = { year = 0, month = 0, day = 0, hour = 0, min = 0, sec = 0 }
  local t, z
  r.year, r.month, r.day, z, t = strdate:match(datepattern)
  if not (r.year and r.month and r.day) then return nil end
  if t ~= nil and #t > 0 then
    r.hour, r.min, r.sec, z = t:match(timepattern)
    if not (r.hour and r.min) then return nil end
    if not r.sec then r.sec = 0 end 
  end
  for k,v in pairs(r) do if type(v) == type('') then r[k] = tonumber(v) end end
  if( r.year < 100 ) then r.year = r.year + 2000 end
  local time = os.time(r)
  if z ~= 'Z' then return time end -- Local time
  local ldt = os.date('*t', time)
  ldt.isdst = false
  return time - os.difftime(os.time(os.date('!*t', time)) ,os.time(ldt))
end

local function utest(str, expected)
  local t = util.parse(str)
  if t == expected then return 0 end
  print('Mismatch : "' .. str .. '" => ', t, t and os.date("%Y-%m-%dT%X",t) or 'NIL', 'expected ' .. expected)
  return 1;
end

local function unit_test()
  local c = 0
  c = c + utest("2000-12-31 22:00Z",   978300000)
  c = c + utest("2001-1-1Z",           978307200)
  c = c + utest("2002-01-1 10:11:10Z", 1009879870)
  c = c + utest("2002-1-01 10:12:10Z", 1009879930)
  c = c + utest("2007-6-8 11:0Z",      1181300400)
  c = c + utest("2008-3-18  12:00:00Z",1205841600)
  c = c + utest("2009-09-18 22:00:00Z",1253311200)
  c = c + utest("2010-10-30 23:00:00Z",1288479600)
  c = c + utest("2017-04-18 22:00Z",    1492552800)
  c = c + utest("2019-12-31 22:00:00Z",1577829600)
  c = c + utest("2019-12-31 23:00:01Z",1577833201)
  c = c + utest("2020-1-1   23:00Z",   1577919600)
  c = c + utest("2020-12-30 23:00:00Z",1609369200)  
    
  c = c + utest("2001-1-1",           978300000)
  c = c + utest("2001-1-01 02:00",    978307200)
  c = c + utest("2002-01-1 12:11:10",1009879870)
  c = c + utest("2002-01-01 12:12:10",1009879930)
  c = c + utest("2007-6-8 14:00",     1181300400)
  c = c + utest("2008-3-18 14:00",    1205841600)
  c = c + utest("2009-09-19 01:00",   1253311200)
  c = c + utest("2010-10-31 02:00:00",1288479600)
  c = c + utest("2017-4-19  01:00:00",1492552800)
  c = c + utest("2020-01-01 00:00",   1577829600)
  c = c + utest("2020-1-1 01:00:01",  1577833201)
  c = c + utest("2020-01-02 01:00:00",1577919600)
  c = c + utest("2020-12-31 01:00:00",1609369200)
  
  if c ~= 0 then 
    print(c .. ' unit tests failed')
    os.exit(1)
  end
end

return util