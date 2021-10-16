-- log.lua - simple logging facilities
-- This file is a part of DAQEMON application 
-- Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
-- DAQEMON is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License v2
-- as published by the Free Software Foundation;
-- License:  https://opensource.org/licenses/GPL-2.0

local log = {}

function log.void(fmt, ...) end

log.level = { trace = "t", info = "i", warn = "w", error = "e",  none = "n" }

function log.setlevel(lvl)
  log.t = string.find("t4",    lvl) and log.print or log.void
  log.i = string.find("ti43",   lvl) and log.print or log.void
  log.w = string.find("tiw432",  lvl) and log.print or log.void
  log.e = string.find("tiwe4321", lvl) and log.print or log.void
end

function log.unixtime(dlm, fin)
  return os.date("%Y-%m-%d"..(dlm or "T").."%X"..(fin or ""))
end

function log.print(fmt, ...)
  local arg = { ... }
  if type(fmt) == type('') then
    if string.find(fmt, '%%') and #arg > 0 then
      print(log.unixtime(' ',' ') .. string.format(fmt, ...))
    else
      print(log.unixtime(' ',' ') .. fmt, ...)
    end
  else
    print(log.unixtime(' '), fmt, ...)
  end
  return log
end

function log.short(fmt, ...)
  local arg = { ... }
  if type(fmt) == type('') then
    if string.find(fmt, '%%') and #arg > 0 then
      print(string.format(fmt, ...))
    else
      print(fmt, ...)
    end
  else
    print(fmt, ...)
  end
  return log
end

log.t = log.void
log.i = log.void
log.w = log.void
log.e = log.print

return log