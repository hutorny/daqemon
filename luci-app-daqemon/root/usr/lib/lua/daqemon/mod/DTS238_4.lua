local dtype= require("dtype")
local DTS238_4 = {
  func = 'read_registers', -- MODDBUS function code 03
  inputs = {
    meter     = 0x0000, -- active energy, kW*h
    export    = 0x0008, -- export energy, kW*h
    import    = 0x000A, -- import energy, kW*h
    voltage   = 0x000C, -- voltage, V
    current   = 0x000D, -- current, A	
    power     = 0x000E, -- active power, kW
    reactive  = 0x000F, -- reactive power, kVAR
    factor    = 0x0010, -- power factor
    frequency = 0x0011, -- frequency, Hz
	
  },
  dt = {
    [0x0000] = dtype.fixed32D2,
    [0x0008] = dtype.fixed32D2,
    [0x000A] = dtype.fixed32D2,
    [0x000C] = dtype.fixed16D1,
    [0x000D] = dtype.fixed16D2,
    [0x000E] = dtype.int16,
    [0x000F] = dtype.int16,
    [0x0010] = dtype.fixed16D3,
    [0x0011] = dtype.fixed16D2,
  }
}

function DTS238_4.read(model, port, dev, inp)
  return read_modbus(port, dev.slaveid, inp, model.dt[inp], model.func)
end

return DTS238_4