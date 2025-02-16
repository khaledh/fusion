#[
  Serialization and deserialization of Nim objects.
]#

type
  Allocator* = proc (size: int): pointer {.closure.}
  PackedObj* {.packed.} = object
    len*: int
    payload*: UncheckedArray[byte]

proc serialize*(s: string, alloc: Allocator): ptr PackedObj =
  ## Serialize a string
  ## 
  ## Arguments:
  ##   s (in): string
  ##   alloc (in): memory allocator
  ##
  ## Returns:
  ##   pointer to the serialized object

  let payloadSize = s.len + 1
  result = cast[ptr PackedObj](alloc(sizeof(result.len) + payloadSize))
  result.len = payloadSize
  copyMem(result.payload.addr, cast[pointer](s.cstring), payloadSize)

proc deserialize*(obj: ptr PackedObj): string =
  ## Deserialize a string
  ## 
  ## Arguments:
  ##   obj (in): pointer to the serialized object
  ##
  ## Returns:
  ##   deserialized string

  assert obj != nil

  result = $cast[cstring](obj.payload.addr)
