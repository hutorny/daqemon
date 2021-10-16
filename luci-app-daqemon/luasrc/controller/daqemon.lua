-- daqemon.lua - LuCI controller
-- This file is a part of DAQEMON application
-- Copyright (C) 2020-2021 Eugene Hutorny <eugene@hutorny.in.ua>
-- DAQEMON is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License v2
-- as published by the Free Software Foundation;
-- License:  https://opensource.org/licenses/GPL-2.0

module("luci.controller.daqemon", package.seeall)

local daqemon_tmp = '/tmp/daqemon/'
local daqemon_root = '/usr/lib/lua/daqemon/'
local config_json = '/etc/daqemon/config.json'
local usbdir = '/sys/bus/usb-serial/devices/'
local staging_json = daqemon_tmp .. 'config.json'
local dashboard_ini = '/etc/daqemon/dashboard.ini'
local fs = require 'nixio.fs'

function index()
  local fs = require 'nixio.fs'
  local config_json = '/etc/daqemon/config.json'
  local staging_json = '/tmp/daqemon/config.json'
  local dashboard_ini = '/etc/daqemon/dashboard.ini'
  entry({"admin", "daqemon"}, template("daqemon"), _("Daqemon"), 90)
  local configured = fs.stat(config_json, 'type') == 'reg'
  if configured then
    entry({"admin", "daqemon", "status"}, call("action_status"), _("Status"),1).leaf = true
    if fs.stat(dashboard_ini, 'type') == 'reg' then
      entry({"admin", "daqemon", "dashboard"}, call("action_dashboard"), _("Dashboard"),5).leaf = true
    end
  end
  entry({"admin", "daqemon", "setup"}, call("action_setup"), _("Setup"), 10).leaf = true
  if configured or fs.stat(staging_json, 'type') == 'reg'  then
    entry({"admin", "daqemon", "configure"}, call("action_configure"), _("Configuration"), 30).dependent=false
  end
  entry({"admin", "daqemon", "rpc"}, call("daqemon_rpc"));
  entry({"admin", "daqemon", "log"}, call("daqemon_log"));
end

local function _(text)
  return text
end

local function list_rates()
  local fs = require 'nixio.fs'
  local dir = daqemon_root .. 'rate/'
  local rates = { {id="none", name="Flat"} }
  local files = fs.dir(dir)
  if not files then return rates end
  for i in files do
    local name = i:split('%.')[1]
    local ok, rate = pcall(require, 'rate/' .. name)
    if ok and rate then
      if type(rate.index) == 'function' then
        local index = rate.index()
        for k,v in pairs(index) do
          if type(rate[k]) == 'function' then
            rates[1+#rates] = { id = name .. '.' .. k, name = v }
          end
        end
      else
        for k,v in pairs(rate) do
          if type(v) == 'function' then
            rates[1+#rates] = { id = name .. '.' .. k,  name = name .. '.' .. k }
          end
        end
      end
    else
    end
  end
  return rates
end

local function list_models()
  local fs = require 'nixio.fs'
  local daqemon = require 'daqemon'
  local dir = daqemon_root .. 'mod/'
  local files = fs.dir(dir)
  local models = {}
  for i in files do
    models[#models+1] = i:split('%.')[1]
  end
  local models = daqemon.load_models(models);
  local res = {}
  for i,v in ipairs(models) do
    res[#res+1] = { name = v.name, inputs = v.inputs }
  end
  return res
end

local function list_tty()
  local fs = require 'nixio.fs'
  local syspath = '/sys/class/tty/'
  local list = {}
  local cmdline = fs.readfile('/proc/cmdline')
  for tty in fs.dir(syspath) do
    local irq = fs.readfile(syspath .. tty .. '/irq', 16)
    irq = tonumber(irq)
    local dev = '/dev/' .. tty
    if irq ~= nil and irq > 0 and cmdline:find(tty) == nil and fs.stat(dev, 'type') == 'chr' then
      list[#list+1] = dev
    end
  end
  return list
end
local function list_interfaces(withuart)
  local fs = require 'nixio.fs'
  local dirs = {
    usbdir,
    '/sys/bus/serial/devices/'
  }
  local result = {}
  if withuart then
    result = list_tty()
  end
  for i, dir in ipairs(dirs) do
    list = fs.dir(dir)
    if list then
      for i in list do
        local dev = '/dev/' .. i
        if fs.stat(dev, 'type') == 'chr' then
          result[#result+1] = dev
        end
      end
    end
  end
  return result
end

local function read_ids(scanfile)
  local scan = io.open(scanfile,'r')
  if scan then
    local text = scan:read('*all')
    scan:close()
    if text then
      ids = text:split(',')
      for i = 1,#ids do ids[i] = tonumber(ids[i]) end
      return ids
    end
  end
end

local function prepare_config(config)
  return config
end

local function load_config()
  local util = require 'luci.util'
  package.path = package.path .. ';' .. daqemon_root .. '?.lua;' .. daqemon_root .. 'lua/?.lua'
  local u = require 'util'
  local log = require 'log'
  local condef = require 'condef'
  local fs = require 'nixio.fs'
  local config = { persist = false, errors = {}, modbus = {}, daqemon = {}, config = {}}
  log.e = function(fmt, ...) config.errors[1+#config.errors] = string.format(fmt,...) end
  local daqemon = require 'daqemon'
  config.staging = fs.stat(staging_json, 'type') == 'reg'
  config.persist = fs.stat(config_json, 'type') == 'reg'
  local cfgfile = (config.staging and staging_json) or (config.persist and config_json) or nil
  config.config = daqemon.readcfg(cfgfile, condef)
  if config.config == nil then
    config.errors[1+#config.errors] = _("Error reading configuration from ") .. cfgfile
  end
  config.modbus = {}
  local ok, ifc, err = pcall(list_interfaces, false)
  if ok then
    config.modbus.interfaces = ifc
    if not util.contains(ifc,config.config.interface.new_rtu[1]) then
      table.insert(config.modbus.interfaces, 1,config.config.interface.new_rtu[1])
    end
  else
    config.errors[1+#config.errors] = _("Error listing interfaces")
  end
  config.modbus.baudrates = {
          75,    110,   134,   150,   300,   600,
        1200,   1800,  2400,  4800,  7200,  9600,
       14400,  19200, 38400, 56000, 57600,
      115200, 128000,
  }
  config.modbus.parities = { N = 'none', E = 'even', O = 'odd' }
  config.daqemon.rates  = list_rates()
  config.daqemon.models = list_models()
  fs.mkdirr(daqemon_tmp)
  if not config.daqemon.rate then config.daqemon.rate = 'none' end
  config.modbus.slaveids = read_ids(daqemon_tmp .. 'modbus.scan')
  log.e = log.void
  return config
end

local function runtimedata(sampledata)
  local fs = require 'nixio.fs'
  local json = require 'cjson'
  local files = fs.glob(sampledata)
  local inputs = {}
  local thetime = 0
  for f in files do
    local text = fs.readfile(f)
    local data = text and json.decode(text)
    if type(data) == type({}) then
      local time = data.time or 0
      if thetime < time then thetime = time end
        for input, value in pairs(data) do
      if input ~= 'time' then
        if inputs[input] == nil or inputs[input].time < time then
        inputs[input] = {time = time, value = value}
        end
      end
        end
    end
  end
  local result = { data = {}, meta = {
	time = thetime,
	now = os.time(),
	datetime = (thetime > 0 and os.date("%Y-%m-%d %X",thetime)) or "",
	rate = inputs.rate and inputs.rate.value
  }}
  for input, tuple in pairs(inputs) do
    if input ~= 'rate' then
      result.data[1+#result.data] = {
        input = input,
        value = type(tuple.value) == type(1) and tuple.value,
        error = type(tuple.value) == type({}) and tuple.value.error
      }
    end
  end
  return result
end

local function service_action(action)
  local initd = '/etc/init.d/daqemon'
  local fs = require 'nixio.fs'
  if fs.access(initd) then
    return os.execute('env -i ' .. initd .. ' ' .. action .. ' >/dev/null') == 0
  end
  return false
end

local function service_running()
    local status = io.popen('ubus call service list | jsonfilter -e \'@["daqemon"]\''):read('*all')
    if status == nil or status == '' or status == '{ }' or status == '{}' then return false end
    local json = require 'cjson'
    status = json.decode(status)
    return status.instances ~= nil
       and status.instances.instance1 ~= nil
       and status.instances.instance1.running
end

local sampledata = '/var/run/daqemon/data-*.json'

local function make_status()
  local fs = require 'nixio.fs'
  local config = load_config()
  local data = runtimedata(sampledata)
  local dev = config.config.interface.new_rtu[1]
  local available = dev and fs.stat(dev, 'type') == 'chr'
  return {
    config = { server = config.config.server},
    port = {dev = dev, available = available },
    service = { enabled = service_action('enabled'), running = service_running() },
    meta = data.meta,
    data = data.data,
  }
end

local function write_hotplug(device)
  local hotplug = '/etc/hotplug.d/usb/40-daqemon'
  if device == nil then
    os.remove(hotplug)
    return
  end
  local text = '#!/bin/sh\n# This file is auto-generated, do not edit it\n'
        .. daqemon_root .. 'daqemon-hotplug.sh ' .. device .. '\n'
  local f = io.open(hotplug, 'w')
  if f ~= nil then
    f:write(text)
    f:close()
  end
end

local function  clean_luci_cache()
  local fs = require 'nixio.fs'
  fs.remove('/tmp/luci-indexcache')
end

local function resolve_usb(dev)
  local parts = dev:split('/')
  local usbdev = usbdir .. parts[3]
  local devpath = io.popen('readlink -f ' .. usbdev):read()
  local util = require 'util'
  parts = devpath:split('/')
  parts[#parts] = nil
  parts[#parts] = nil
  parts[2] = nil
  return util.join(parts,'/')
end


function action_setup(mode)
  local config = load_config()
  luci.template.render("daqemon", {DATA=config,VIEW='setup.htm'})
end

function action_configure(mode)
  local config = load_config()
  luci.template.render("daqemon", {DATA=config,VIEW='config.htm'})
end

function action_status(mode)
  local status = make_status()
  luci.template.render("daqemon", {DATA=status,VIEW='status.htm'})
end

function action_dashboard(mode)
  local config = load_config()
  local html, url = 'dashboard.htm', nil
  local view, logo = html, ''
  local ini = io.open(dashboard_ini,'r')
  if ini then url = ini:read() ini:close() end
  if url and url ~= '' then view = nil logo= 'top' end
  luci.template.render("daqemon", {DATA={url=url, logo=logo, server=config.config.server},VIEW=view,ALT=html})
end

local daqrpc = {}

function daqrpc.status()
  return { enabled = service_action('enabled'), running = service_running() }
end

function daqrpc.enable(enable)
  return { enabled = service_action(enable and 'enable' or 'disable'), running = service_running() }
end

function daqrpc.start(start)
  service_action(start and 'start' or 'stop')
  return { enabled = service_action('enabled'), running = service_running() }
end

function daqrpc.restart()
  service_action('restart')
  return { enabled = service_action('enabled'), running = service_running() }
end


function daqrpc.erase()
  local fs = require 'nixio.fs'
  local success = false
  local config_bak = staging_json .. '.bak'
  if fs.stat(config_json, 'type') == 'reg' then
    fs.remove(config_bak)
    success = fs.move(config_json, config_bak)
  end
  fs.remove(dashboard_ini)
  clean_luci_cache()
  service_action('stop')
  service_action('disable')
  success = success or fs.remove(config_json)
  return { success = success, enabled = service_action('enabled'), running = service_running() }
end

function daqrpc.reset()
  local fs = require 'nixio.fs'
  local success = fs.remove(staging_json)
  return { success = success }
end

function daqrpc.listports()
  local success, ports, message = pcall(list_interfaces, true)
  return { success = success, ports = ports, message = message }
end

function daqrpc.queuelen()
  local count = io.popen('grep -s "^" /var/run/daqemon/q-* | wc -l'):read()
  return { success = true, queue = tonumber(count) }
end

function daqrpc.scan(interface, count)
  local fs = require 'nixio.fs'
  local scanfile, statfile = daqemon_tmp .. 'modbus.scan',  daqemon_tmp .. 'modbus.stat'
  if not interface then
      local ids, done, progr = {}, false, 0
      if fs.stat(scanfile, 'type') ~= 'reg' then
        return { success=false, message=_("No scan results available") }
      end
      ids = read_ids(scanfile)
      local stat = io.open(statfile,'r')
      if stat then
        local text = stat:read('*all')
        stat:close();
        if text and #text > 0 then
          text = text:split(',')
          progr = tonumber(text[#text])
          if progr then
            done = progr >= 247
            progr = math.ceil((progr * 100) / 250)
          else
            progr = 0
          end
        end
      end
      return { success=true, ids=ids, done=done, stat=progr }
  end
  if service_running() then
    return { success=false, message=_("Unable to scan when the daqemon service is running") }
  end
  if count then
    count = tonumber(count)
  end
  local ifc = interface:split(',')
  if fs.stat(ifc[1], 'type') ~= 'chr' then
    return { success=false, message="Serial device is not available: " .. ifc[1] }
  end
  if not count then count = 250 end
  fs.mkdir(daqemon_tmp)
  local cmd = string.format('(env -i /usr/bin/daqemon -v0 -i %s -s %d,l > %s 2> %s)&', interface, count, scanfile, statfile)
  if os.execute(cmd) == 0 then
    return { success=true }
  else
    return { success=false, message=_("Error starting") .. ' /usr/bin/daqemon' }
  end
end

local function load_daqemon()
  package.path = package.path .. ';/usr/lib/lua/daqemon/?.lua'
  return require 'daqemon'
end

function daqrpc.saveconfig(config, persist)
  local fs = require 'nixio.fs'
  local daqemon = load_daqemon()
  if config.daqemon and config.daqemon.rate == 'none' then config.daqemon.rate = nil end
  local cfgfile = (persist and config_json) or staging_json
  local dirname = fs.dirname(cfgfile)
  local staging = fs.stat(staging_json, 'type') == 'reg'
  fs.mkdirr(dirname)
  local result = daqemon.savecfg(cfgfile, config, (staging and staging_json) or config_json)
  if persist then
    service_action('enable')
    service_action('restart')
    if config.interface and config.interface.new_rtu and string.match(config.interface.new_rtu[1], 'ttyUSB') then
      write_hotplug(resolve_usb(config.interface.new_rtu[1]))
    else
      write_hotplug(nil)
    end
    fs.remove(staging_json)
    clean_luci_cache()
  end
  return result
end

function daqrpc.readconfig()
  return load_config()
end

function daqrpc.test(interface, slaveid, model, inputs)
  local daqemon = load_daqemon()
  return daqemon.test_device(interface, slaveid, model, inputs)
end

function daqrpc.sampledata()
  local data = runtimedata(sampledata)
  return { success = true, data = data }
end

function daqrpc.dashboards(present)
  local fs = require 'nixio.fs'
  if present then
    io.open(dashboard_ini,'a'):close()
  else
    if fs.stat(dashboard_ini,'size') == 0 then fs.remove(dashboard_ini) end
  end
  return { success = true }
end

function daqrpc.dashboard(url)
  local ini = io.open(dashboard_ini,'w')
  if not ini then return { success= false } end
  ini:write(url)
  ini:close()
  return { success= true }
end

function daqemon_rpc()
  local http = require 'luci.http'
  local jsonrpc = require 'luci.jsonrpc'
  local ltn12   = require 'luci.ltn12'

  http.prepare_content('application/json')
  ltn12.pump.all(jsonrpc.handle(daqrpc, http.source()), http.write)
end

function daqemon_log()
  local http = require 'luci.http'
  local ltn12   = require 'luci.ltn12'
  http.prepare_content('text/plain; charset=utf-8')
  local pipe = io.popen('logread -e daqemon | grep -E daemon.[[:alpha:]]*[[:space:]]daqemon')
  ltn12.pump.all(ltn12.source.file(pipe), http.write)
end
