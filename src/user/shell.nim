#[
  Fusion Shell
]#
import std/[options, strformat, strutils]

import common/[debugcon]
import syslib/[channels, os]

const
  ConsoleOutputChannelId = 1
  ConsoleInputChannelId = 2
  ShellMessages = [
    "Fusion OS\n",
    "(c) 2024-2025 Khaled Hammouda\n",
  ]
  HelpMessages = [
    "Available commands:\n",
    "  help:          Show this help message\n",
    "  echo:          Echo the input\n",
    "  exit, quit:    Exit the shell\n",
  ]

proc main(): int {.exportc.} =
  let conOutCh = channels.open[string](ConsoleOutputChannelId, mode = ChannelMode.Write)
  let conInCh = channels.open[string](ConsoleInputChannelId, mode = ChannelMode.Read)
  defer:
    conOutCh.close()
    conInCh.close()

  if conOutCh.id < 0 or conInCh.id < 0:
    debugln "Failed to open console channel"
    return 1

  conOutCh.sendBatch(ShellMessages)

  while true:
    conOutCh.send("\n> ")
    conOutCh.send("\xff")  # end of output (for now)
    let inputOpt = channels.recv[string](conInCh)
    if inputOpt.isSome:
      let input = inputOpt.get
      if input.len > 0:
        let parts = input.split(" ")
        let cmd = parts[0]
        if cmd == "help":
          conOutCh.sendBatch(HelpMessages)
        elif cmd == "echo":
          conOutCh.send(parts[1..^1].join(" ") & "\n")
        elif cmd == "exit" or cmd == "quit":
          break
        else:
          conOutCh.send(&"{cmd}: Unknown command\n")

  return 0
