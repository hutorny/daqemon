local dtype= require("dtype")
local DTS238_7 = {
  func = 'read_registers', -- MODDBUS function code 03
  inputs = {
    meter     = 0x0000, -- total  active energy, kW*h
    reactive  = 0x0004, -- total  reactive energy, kVARh
    frequency = 0x0011, -- frequency, Hz	

    voltageA  = 0x0080, -- phase A voltage, V
    voltageB  = 0x0081, -- phase B voltage, V
    voltageC  = 0x0082, -- phase C voltage, V

    currentA  = 0x0083, -- line A current, A
    currentB  = 0x0084, -- line B current, A
    currentC  = 0x0085, -- line C current, A
	
    power     = 0x0086, -- total  active power, kW
    powerA    = 0x0088, -- line A active power, kW
    powerB    = 0x0089, -- line B active power, kW
    powerC    = 0x008A, -- line C active power, kW

    reactive  = 0x008B, -- total  reactive power, VAR
    reactiveA = 0x008D, -- line A reactive power, VAR
    reactiveB = 0x008E, -- line B reactive power, VAR
    reactiveC = 0x008F, -- line V reactive power, VAR

    apparent  = 0x0090, -- total  apparent power, VA
    apparentA = 0x0092, -- line A apparent power, VA
    apparentB = 0x0093, -- line B apparent power, VA
    apparentC = 0x0094, -- line V apparent power, VA

    factor    = 0x0095, -- line A reactive power factor
    factorA   = 0x0096, -- line A reactive power factor
    factorB   = 0x0097, -- line B reactive power factor
    factorC   = 0x0098, -- line C reactive power factor
  },
  dt = {
    [0x0000] = dtype.fixed32D2,
    [0x0004] = dtype.fixed32D2,
    [0x0011] = dtype.fixed16D2,

    [0x0080] = dtype.fixed16D1,
    [0x0081] = dtype.fixed16D1,
    [0x0082] = dtype.fixed16D1,

    [0x0083] = dtype.fixed16D1,
    [0x0084] = dtype.fixed16D1,
    [0x0085] = dtype.fixed16D1,

    [0x0086] = dtype.fixed32D3,
    [0x0088] = dtype.fixed16D3,
    [0x0089] = dtype.fixed16D3,
    [0x008A] = dtype.fixed16D3,

    [0x008B] = dtype.fixed32D3,
    [0x008D] = dtype.fixed16D3,
    [0x008E] = dtype.fixed16D3,
    [0x008F] = dtype.fixed16D3,

    [0x0090] = dtype.fixed32D3,
    [0x0092] = dtype.fixed16D3,
    [0x0093] = dtype.fixed16D3,
    [0x0094] = dtype.fixed16D3,

    [0x0095] = dtype.fixed16D3,
    [0x0096] = dtype.fixed16D3,
    [0x0097] = dtype.fixed16D3,
    [0x0098] = dtype.fixed16D3,
  }
}

function DTS238_7.read(model, port, dev, inp)
  return read_modbus(port, dev.slaveid, inp, model.dt[inp], model.func)
end

return DTS238_7
