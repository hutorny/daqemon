-- emoncms.lua - functions implementing communication with EmonCMS backend
-- This file is a part of DAQEMON application
-- Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
-- DAQEMON is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License v2
-- as published by the Free Software Foundation;
-- License:  https://opensource.org/licenses/GPL-2.0

local so   = require("socket")
local mime = require("mime")
local json = require("cjson")
local http = require("socket.http")
local ltn12= require("ltn12")
local util = require("util")
local log  = require("log")
local emoncms = {}

local config = {
  url = 'https://emoncms.org/',
  retry_period = 20,
  headers = {
    authorization = 'Bearer %s',
  },
  action = {
    create = 'device/create.json?nodeid=%s&name=%s&description=%s&type=%s',
    init   = 'device/init.json?id=%d',
    submit = 'input/post?node=%s&fulljson=%s', -- node, data
    setproc= 'input/process/set?inputid=',
    bulk   = 'input/batch/%s',
    ping   = 'feed/buffersize.json',
    register = "?embed=1#register",
    api_help = 'user/view',
    profiles = 'device/template/',
    node    = 'device/',
    inputs  = 'input/',
    feeds   = 'feed/',
    processes = 'process/',
    dashboard = 'dashboard/'
  },
  template = {
    init = 'template='
  }
}

-- commonly used strings
local REALTIME      = 'DataType::REALTIME'
local ENGINE        = 0
local CREATE        = 'create'
local DAILY         = 'DataType::DAILY'
local FEEDID        = 2
local LOG_JOIN_FEED = 'process__log_to_feed_join'
local LOG_FEED      = 'process__log_to_feed'
local METER2KWHD    = 'process__kwh_to_kwhd'
local METER2MRKWHD  = nil
local KWHD2COST     = nil
local NAME_ARG      = '%s'
local KWHD_ARG      = '%sd'
local MRKWHD_ARG    = '%sr'
local TAG_ARG       = '%0.0s%s'
local NODE_ARG      = '%0.0s%0.0s%s'
local PHPTIMESERIES = 2
local MYSQLALT      = 11

local function input_template(description)
  return {
      name        = NAME_ARG,
      node        = NODE_ARG,
      description = description,
      processList = {{
         process  = LOG_FEED,
         arguments= {type = FEEDID, value = NAME_ARG }
      }},
      action      = CREATE,
      id          = -1,
    }
end

local function meter_template(description)
  return {
      name        = NAME_ARG,
      node        = NODE_ARG,
      description = description,
      processList = {{
        process  = LOG_JOIN_FEED,
        arguments= {type = FEEDID, value = NAME_ARG }
       }, {
         process    = METER2KWHD,
         arguments  = {type = FEEDID, value = KWHD_ARG },
       }, METER2MRKWHD and {
         process    = METER2MRKWHD,
         arguments  = {type = FEEDID, value = MRKWHD_ARG },
      }},
      action      = CREATE,
      id          = -1,
    }
end


local function realtime_template(unit)
  return {
      name        = NAME_ARG,
      tag         = TAG_ARG,
      type        = REALTIME,
      engine      = ENGINE,
      unit        = unit,
      action      = CREATE,
      id          = -1,
    }
end

local function daily_template(unit)
  if ENGINE == MYSQLALT then
  return {
      name        = KWHD_ARG,
      tag         = TAG_ARG,
      type        = DAILY,
      engine      = ENGINE,
      unit        = unit,
      action      = CREATE,
      id          = -1,
    }
  else
  return {
      name        = KWHD_ARG,
      tag         = TAG_ARG,
      type        = DAILY,
      engine      = PHPTIMESERIES,
      unit        = unit,
      action      = CREATE,
      id          = -1,
      options     = {interval=86400},
    }
  end
end

local function multirate_template(unit)
  return {
      name        = MRKWHD_ARG,
      tag         = TAG_ARG,
      type        = REALTIME,
      engine      = ENGINE,
      unit        = unit,
      action      = CREATE,
      id          = -1,
    }
end

local function unit_template(description, unit, meter)
  local desc = description .. (unit and (', ' .. unit)  or '')
  return {
    inputs = {
      meter and meter_template(desc) or input_template(desc)
    },
    feeds = {
      realtime_template(unit),
      meter and daily_template(unit ..'d') or nil,
      meter and METER2MRKWHD and multirate_template(unit ..'d') or nil
    }
  }
end

local last_success_connect = 0
local last_fail_connect = 0

local function know_active()
  return os.time() - last_success_connect < 5*60
end

local function time_to_retry()
  return (os.time() - last_fail_connect) > (config.retry_period *60)
end

local function is_good(good)
  if good then
      last_success_connect = os.time()
      last_fail_connect = 0
  else
      last_success_connect = 0
      last_fail_connect = os.time()
  end
  return good
end

function emoncms.alive(force)
  if force then return emoncms.ping() end
  return know_active() or (time_to_retry() and emoncms.ping())
end

function http.get(req, headers)
  local body = {}
  local res, code = http.request{
      url=req, headers=headers,
      sink=ltn12.sink.table(body) }
  if is_good(res) then
    return code, util.tostr(body)
  else
    return false, util.tostr(code)
  end
end

function http.post(req, payload, headers)
  local body = {}
  local source = (io.type(payload) and ltn12.source.file(payload))
                                    or ltn12.source.string(payload)
  local res, code = http.request{
      url=req, method='POST',
      source=source,
      headers=headers,
      sink=ltn12.sink.table(body) }
  if is_good(res) then
    return code, util.tostr(body)
  else
    return false, util.tostr(code)
  end
end

local function parse_json_response(code, resp)
  if code == false then return false, resp end
  if code <  200 then return false, code end
  if code > 204 then return false, code end
  if #resp == 0 then return false, "empty response" end
  local ok, res = pcall(json.decode, resp)
  return ok, ok and res or resp
end

local function escape(...)
    local escaped = {}
    local args = {...}
    for i,v in ipairs(args) do
      if type(v) == type({}) then v = json.encode(v)
      else if type(v) == type('') then v = so.url.escape(v)
      else v = util.tostr(v) end end
      table.insert(escaped, v)
    end
    return next(escaped) and escaped or nil
end

local function GET(action, ...)
    local escaped = escape(...)
    local req = config.url .. (escaped and string.format(action, unpack(escaped)) or action)
    local ok, resp, res
    return parse_json_response(http.get(req, config.headers))
end

local function payload_len(payload)
    if type(payload) == type('') then return #payload end
    if io.type(payload) then
      local pos = payload:seek()
      local len = payload:seek('end')
      payload:seek('set',pos)
      return len
    end
    return nil
end

local function POST(action, headers, payload, ...)
    local escaped = escape(...)
    if type(payload) == type({}) then payload = json.encode(payload) end
    local req = config.url .. (escaped and string.format(action, unpack(escaped)) or action)
    local hdrs = {}
    hdrs['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8'
    hdrs['Content-Length'] =  payload_len(payload)
    util.mergeto(hdrs, config.headers, headers)
    local ok, resp, res
    return parse_json_response(http.post(req, payload, hdrs))
end


function emoncms.submit(data)
  local st, resp = GET(config.action.submit, config.client.nodeid, data)
  if st and type(resp) == type({}) and resp.success then return true end
  local msg = resp
  if type(resp) == type({}) then msg = util.tostr(resp.message)
  else msg = resp and util.tostr(resp) or util.tostr(st)
  end
  log.w("Submit failed: %s", msg)
  return false
end

local batch_headers = {}
batch_headers['Content-Type'] = 'application/json; charset=UTF-8'


function emoncms.batch(filename)
  if filename == nil then return false end
  log.i("Batch processing file '%s'", filename)
  local file, err = io.open(filename, "r")
  if file == nil then
    log.e("Error reading from file %s", err)
    return false
  end
  local st, resp = POST(config.action.bulk, batch_headers, file, config.client.nodeid)
  if st and resp and resp.success then return true end
  log.e("Batch failed: %s", (st and resp and resp.message) or (resp and util.tostr(resp)) or util.tostr(st))
end

local function isvalid(str)
  local s, r = pcall(json.decode,str)
  if s and type(r) == type(0) then return true end
  log.e("Server response on ping is unexpected")
  log.i("Server response was:", str)
  return false
end

function emoncms.ping()
  if config.action.ping == nil then
    log.i("server.action.test is not specified, skipping connection test")
    return true
  end
  local url = config.url .. config.action.ping
  local code, data = http.get(url, config.headers)
  if code == 200 then
    return isvalid(data)
  end
  if code == false or code < 100 then
    log.e("Server is not responding: %s", util.tostr(data))
    return false
  end
  log.e("Server is not responding OK, status: %d", code)
  log.i("Response:\n", data)
  return false
end

function emoncms.augument(server)
  if server == nil then return end
  server.url = util.any(server.url, config.url)
  server.uri = {
    register = config.action.register,
    api_help = config.action.api_help,
    profiles = config.action.profiles,
    node     = config.action.node,
    inputs   = config.action.inputs,
    feeds    = config.action.feeds,
    submit   = string.format(config.action.submit,'{0}','{1}'),
    setproc  = config.action.setproc,
    processes= config.action.processes,
    dashboard= config.action.dashboard,
  }
  server.api = nil
end

function emoncms.strip(server)
  if server == nil then return end
  server.uri = nil
  server.api = nil
end

function emoncms.getprocesses(meta, multirate)
  local list = {
   { id          = 'log',
     method      = (meta and meta.processes and meta.processes.log) or 'process__log_to_feed',
     name        = "Log to feed",
     description = "Logs data to a timeseries feed. Recommended for power, voltage, current",
     input_types = {'power', 'voltage', 'current'},
     sort        = 10,
   },
   { id          = 'dailyusage',
     method      = (meta and meta.processes and meta.processes.dailyusage) or METER2KWHD,
     name        = "Daily kWh",
     description = "Converts meter readings in kWh to daily usage",
     input_types = {'meter', 'meter_r'},
     sort        = 20,
   },
-- Uncomment when implemented
--   { id          = 'dailycost',
--     method      = (meta and meta.processes and meta.processes.dailycost) or KWHD2COST,
--     name        = "Daily cost",
--     description = "Converts daily usage in kWh to currency",
--     input_types = {'meter', 'meter_r'},
--     sort        = 30,
--   },
   }
  if not (meta and meta.processes) then return list end
  if meta.engine ~= MYSQLALT or meta.processes.log ~= meta.processes.logjoin then list[#list+1] =
   { id          = 'logjoin',
     method      = meta.processes.logjoin or 'process__log_to_feed_join',
     name        = "Log to feed join",
     description = "Logs data to a timeseries feed. Recommended for power, voltage, current",
     input_types = {'power', 'voltage', 'current'},
     sort        = 15,
   }
  end
  if multirate and (meta.processes.multirate or METER2MRKWHD) then list[#list+1] =
   { id          = 'multirate',
     method      = meta.processes.multirate or METER2MRKWHD,
     name        = "Daily multirate kWh",
     description = "Converts meter readings in kWh to daily usage with multple rates",
     input_types = {'meter', 'meter_r'},
     sort        = 25,
   }
  end
  return list
end

function emoncms.validate(server, client)
  if server == nil or server.url == nil then
    log.w("server.url is missing, using '%s'",config.url)
  else
    config.url = util.any(server.url, config.url)
    config.retry_period = util.any(server.retry_period, config.retry_period)
  end
  if client == nil or server.apikey == nil then
    log.e("server.apikey is missing")
    return false
  else
    config.headers.authorization = string.format(config.headers.authorization, server.apikey)
  end
  config.client = client
  return true
end

local function clone_and_subst(obj, ...)
  if obj == nil then return nil end
  local clone = {}
  for k, v in pairs(obj) do
    if type(v) == type({}) then
      v = clone_and_subst(v, ...)
    else
      if type(v) == type('') and string.find(v, '%%') then
        v = string.format(v, ...)
      end
    end
    clone[k] = v
  end
  return clone
end

local function normalize_input_name(name)
  -- Normalizing name
  local parts = name:split('_')
  local unit = parts[2] or '_'
  return name, unit
end

local function build_input(template, name, ...)
  local inp, templ = normalize_input_name(name)
  return clone_and_subst(template[templ] or template._, inp, ...)
end

local function build_inputs(inputs)
  local template = {
    kWh = unit_template("Electricity meter", 'kWh', true),
    W   = unit_template("Power consumption", 'W'),
    kW  = unit_template("Power consumption", 'kW'),
    VAR = unit_template("Reactive power", 'VAR'),
    A   = unit_template("Current consumption", 'A'),
    V   = unit_template("Mains voltage", 'V'),
    _   = unit_template("Input"),
  }

  local result = { inputs = {}, feeds = {}}
  for name, cfg in pairs(inputs) do
    local input = build_input(template, name or '', cfg.tag or '', config.client.nodeid)
    if input == nil then
      log.e("Error preparing input profile '%s' '%s'",cfg.tag, name)
    else
      util.appendto(result.inputs,input.inputs)
      util.appendto(result.feeds,input.feeds)
    end
  end
  return json.encode(result)
end

local function usemeta(meta)
    ENGINE = meta.engine or ENGINE
    if meta.processes then
      LOG_JOIN_FEED = meta.processes.logjoin or LOG_JOIN_FEED
      LOG_FEED      = meta.processes.log or LOG_FEED
      METER2KWHD    = meta.processes.dailyusage or METER2KWHD
      METER2MRKWHD  = meta.processes.multirate or METER2MRKWHD
    end
end

function emoncms.init(inputs, meta)
  if type(inputs) ~= type({}) then
    log.e("Invalid inputs: %s", tostring(inputs))
    return false
  end
  if type(meta) == type({}) then usemeta(meta) end
  if not know_active() then
    if not emoncms.ping() then return false end
  end
  log.i("Initializing node profile %s", config.client.nodeid)
  local ok, resp = GET(config.action.create, config.client.nodeid, config.client.name,
                   config.client.description, config.client.type)
  if not ok then
    log.e("Error initializing node profile %s", config.client.nodeid)
    log.i("Server response is: %s", util.tostr(resp))
    return false
  end
  if type(resp) == type(1) then
    local payload = config.template.init .. build_inputs(inputs)
    local ok, resp = POST(config.action.init, nil, payload, resp)
    if ok and resp.success == true then return true end
    log.e("Error configuring inputs and devices")
    log.i("Server response is: %s", util.tostr(resp))
    return false
  end
  log.t("create device response is: %s", util.tostr(resp))
  -- perhaps device already exists
  if type(resp) == type({}) and resp.success == false then return true end
  return false
end

function emoncms.dump(inputs, meta)
  if type(meta) == type({}) then usemeta(meta) end
  return build_inputs(inputs)
end

return emoncms