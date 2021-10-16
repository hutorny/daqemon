-- dataque.lua - simple file based data queue
-- This file is a part of DAQEMON application
-- Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
-- DAQEMON is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License v2
-- as published by the Free Software Foundation;
-- License:  https://opensource.org/licenses/GPL-2.0

local json = require("cjson")
local log  = require("log")
local fs   = require("fs")
local util = require("util")

local dataque = {
  delim  = ",\n",
  prolog = "[",
  epilog = "]\n",
  file   = nil,
  retention = 24, --retention period in hours, max 24
}

local suffix = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local max_retention = 24 * 3600
local last_hour = -1
local last_failed = -1
local file_list = {}

local function make_filename(hour)
  return string.format(dataque.file, suffix:sub(hour+1, hour+1))
end

local function append(filename, mode, text)
  local res = false
  local file, err = io.open(filename, mode)
  if file then
    if mode == "w" then
      log.i("Creating/rewriting retention file '%s'", filename)
      file:write(dataque.prolog)
    else
      file:seek('end', -#dataque.epilog)
      file:write(dataque.delim)
    end
    res, err = file:write(text)
    file:write(dataque.epilog)
    file:close()
  end
  return res, err
end

local function hour(time)
  return math.floor((time % max_retention) / 3600)
end

local function replace(filename)
  for i,v in ipairs(file_list) do
    if v == filename then table.remove(file_list,i) break end
  end
  table.insert(file_list,filename)
end

function dataque.add(data)
  if dataque.file == nil then return false end
  local curr = hour(os.time()) % dataque.retention
  local name = make_filename(curr)
  local mode = (last_hour == curr and "r+") or "w"
  local good, err = append(name, mode, json.encode(data))
  if not good then
    if curr ~= last_failed then
      log.e("Error writing to file '%s': %s", name, util.tostr(err))
      last_failed = curr
    end
    return false
  else
    if mode == "w" then replace(name) end
  end
  last_hour = curr
  last_failed = -1
  return true
end

function dataque.init(cfg)
  if not cfg then return end
  if type(cfg.retention) == type(1) then dataque.retention = cfg.retention end
  for k,v in pairs(cfg) do
    if type(dataque[k]) ~= 'function' then
      dataque[k] = v
    end
  end
  if not dataque.file then return false end
  fs.mkpath(dataque.file)
  file_list = fs.ls(dataque.file:format('*'),"tr")
  if #file_list ~= 0 then
    local lastfile = file_list[#file_list]
    local mtime = fs.mdate(lastfile)
    if mtime == nil then
      log.w("can't stat '%s'", lastfile)
      return
    end
    last_hour = hour(mtime)
  end
end

function dataque.empty()
  return #file_list == 0
end

function dataque.get()
  return file_list[1]
end

function dataque.remove()
  os.remove(file_list[1])
  table.remove(file_list,1)
  if #file_list == 0 then last_hour = 0 end
end

return dataque