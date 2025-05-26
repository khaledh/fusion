#[
  GUID (Globally Unique Identifier) utilities.
]#

import std/strformat
import std/strutils

type
  Guid* {.packed.} = tuple
    part1: uint32
    part2: uint16
    part3: uint16
    part4: uint16
    part5: array[6, uint8]

proc parseGuid*(guid: string): Guid =
  let parts = guid.split("-")
  assert parts.len == 5
  result = (
    fromHex[uint32](parts[0]),
    fromHex[uint16](parts[1]),
    fromHex[uint16](parts[2]),
    fromHex[uint16](parts[3]),
    [fromHex[uint8](parts[4][0..1]), fromHex[uint8](parts[4][2..3]), fromHex[uint8](parts[4][4..5]),
     fromHex[uint8](parts[4][6..7]), fromHex[uint8](parts[4][8..9]), fromHex[uint8](parts[4][10..11])]
  )

proc `$`*(guid: Guid): string =
  result = &"{guid.part1:0>8x}-{guid.part2:0>4x}-{guid.part3:0>4x}-{guid.part4:0>4x}-"
  for byte in guid.part5:
    result &= &"{byte:0>2x}"
