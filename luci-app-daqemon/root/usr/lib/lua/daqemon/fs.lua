-- fs.lua - basic file system
-- This file is a part of DAQEMON application 
-- Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
-- DAQEMON is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License v2
-- as published by the Free Software Foundation;
-- License:  https://opensource.org/licenses/GPL-2.0

local fs = {}
local popen = io.popen

function fs.mkdir(path)
  os.execute("mkdir -p '" .. path .. "'")
end

function fs.mkpath(filename)
  os.execute("mkdir -p `dirname '" .. filename .. "'`")
end

function fs.ls(dirname, sortorder)
  local cmd = string.format("ls -1%s %s 2> /dev/null", sortorder or '', dirname)
  local files = {}
  local pfile = popen(cmd)
  for filename in pfile:lines() do table.insert(files,filename) end
  return files
end

function fs.mdate(filename)
   return io.popen(string.format("date -r '%s' +%%s 2> /dev/null",filename)):read()
end

return fs