#[
  Port I/O
]#

proc portOut8*(port: uint16, data: uint8) =
  asm """
    out %0, %1
    :
    :"Nd"(`port`), "a"(`data`)
  """

proc portOut16*(port: uint16, data: uint16) =
  asm """
    out %0, %1
    :
    :"Nd"(`port`), "a"(`data`)
  """

proc portOut32*(port: uint16, data: uint32) =
  asm """
    out %0, %1
    :
    :"Nd"(`port`), "a"(`data`)
  """

proc portIn8*(port: uint16): uint8 =
  asm """
    in %0, %1
    :"=a"(`result`)
    :"Nd"(`port`)
  """

proc portIn16*(port: uint16): uint16 =
  asm """
    in %0, %1
    :"=a"(`result`)
    :"Nd"(`port`)
  """

proc portIn32*(port: uint16): uint32 =
  asm """
    in %0, %1
    :"=a"(`result`)
    :"Nd"(`port`)
  """
