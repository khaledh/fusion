#[
  Device Manager
]#

import std/tables

import drivers/bga
import drivers/pci

type
  PciDeviceInitializer = proc (dev: PciDeviceConfig) {.nimcall.}

let
  # map of (vendorId, deviceId) to device initializer
  PciDeviceInitializers: Table[(uint16, uint16), PciDeviceInitializer] = {
    (0x1234'u16, 0x1111'u16): bga.pciInit,
  }.toTable


proc devmgrInit*() =
  for dev in enumeratePciBus(0):
    let key = (dev.vendorId, dev.deviceId)
    if PciDeviceInitializers.hasKey(key):
      let devInit = PciDeviceInitializers[key]
      if not devInit.isNil:
        devInit(dev)
