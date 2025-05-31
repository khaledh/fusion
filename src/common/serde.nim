#[
  Serialization and deserialization of Nim objects.
]#

type
  Allocator* = proc (size: int): pointer {.closure.}

  # Fusion String
  FString* = object
    len*: int
    str*: cstring

converter toString*(fs: FString): string =
  $fs.str

proc buildString*(s: string, alloc: Allocator): FString =
  ## Allocate memory for an FString + its payload and copy the source string to it.
  ## 
  let data = alloc(s.len + 1)
  copyMem(data, s.cstring, s.len + 1)
  result = FString(len: s.len, str: cast[cstring](data))
