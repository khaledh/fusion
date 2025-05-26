#[
  Serialization and deserialization of Nim objects.
]#

type
  Allocator* = proc (size: int): pointer {.closure.}

  # Fusion String
  FString* = object
    len*: int
    data*: cstring

converter toString*(fs: FString): string =
  $fs.data

proc buildString*(s: string, alloc: Allocator): FString =
  ## Allocate memory for an FString payload and copy the source string to it.
  ## 
  result.len = s.len
  result.data = cast[cstring](alloc(s.len + 1))
  copyMem(result.data, s.cstring, s.len + 1)
