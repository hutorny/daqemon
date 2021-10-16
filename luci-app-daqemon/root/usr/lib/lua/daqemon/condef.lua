return {
-- DAQEMON Default configuration file
-- DAQEMON supports lua and json configuration files formats.
-- json format is aiming computer assisted configuration,
-- while lua is more friendly for manual editing: it allows comments, open lists,
-- and provides more comprehensive error reporting
server = {
  type = 'emoncms',
  url = '',
  apikey   = '',
  retry_period = 20, -- 20 min between server pings
},

client = {
  nodeid   = '',
  location = '',
  name     = '',
  type     = 'daqemon',
  description = '',
  deviceid = '',
  meta = {
    engine = 0,
    processes = {
      log = "process__log_to_feed",
      logjoin = "process__log_to_feed_join",
      dailyusage = 'process__kwh_to_kwhd',
      multirate = '',
    },
    feeds = {0},
    inputs = {0},
  }
},

daqemon = {
  -- optional data sample file for latest values
  samplefile = '/var/run/daqemon/data-%d.json',
  rate = '',
  retention = 0, --retention period in hours
  -- optional data buffering file name pattern for handling server outage
  file = '/var/run/daqemon/q-%s',
},

interface = {
  new_rtu = {'/dev/ttyUSB0', 9600, 'even', 8, 1},
  slaveids = {0}
},

devices = {
--name =    { "tag", "model", <slave id> },
},

inputs = {
--input name = { "device", "input", <interval>, <qos>, <tag> },
},

valid = false
}