import sequtils, strutils, os, terminal, packages/docutils/highlite, times
import editorstatus, ui, normalmode, gapbuffer, fileutils, editorview, unicodeext, independentutils, searchmode, highlight, commandview, window, movement, color, build

type replaceCommandInfo = tuple[searhWord: seq[Rune], replaceWord: seq[Rune]]

proc parseReplaceCommand(command: seq[Rune]): replaceCommandInfo =
  var numOfSlash = 0
  for i in 0 .. command.high:
    if command[i] == '/': numOfSlash.inc
  if numOfSlash == 0: return

  var searchWord = ru""
  var startReplaceWordIndex = 0
  for i in 0 .. command.high:
    if command[i] == '/':
      startReplaceWordIndex = i + 1
      break
    searchWord.add(command[i])
  if searchWord.len == 0: return

  var replaceWord = ru""
  for i in startReplaceWordIndex .. command.high:
    if command[i] == '/': break
    replaceWord.add(command[i])

  return (searhWord: searchWord, replaceWord: replaceWord)

proc isOpenMessageLogViweer(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"log"

proc isOpenBufferManager(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"buf"

proc isChangeCursorLineCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"cursorLine"

proc isListAllBufferCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"ls"

proc isWriteAndQuitAllBufferCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"wqa"

proc isForceAllBufferQuitCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"qa!"

proc isAllBufferQuitCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"qa"

proc isVerticalSplitWindowCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"vs"

proc isHorizontalSplitWindowCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"sv"

proc isLiveReloadOfConfSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"livereload"

proc isChangeThemeSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru "theme"

proc isTabLineSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"tab"
  
proc isSyntaxSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"syntax"

proc isTabStopSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"tabstop" and isDigit(command[1])

proc isAutoCloseParenSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"paren"

proc isAutoIndentSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"indent"

proc isLineNumberSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"linenum"

proc isStatusBarSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"statusbar"

proc isRealtimeSearchSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"realtimesearch"

proc isHighlightPairOfParenSettigCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"highlightparen"

proc isAutoDeleteParenSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"deleteparen"

proc isSmoothScrollSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"smoothscroll"

proc isSmoothScrollSpeedSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"scrollspeed" and isDigit(command[1])

proc isHighlightCurrentWordSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"highlightcurrentword"

proc isSystemClipboardSettingCommand(command: seq[seq[RUne]]): bool =
  return command.len == 2 and command[0] == ru"clipboard"

proc isHighlightFullWidthSpaceSettingCommand(command: seq[seq[RUne]]): bool =
  return command.len == 2 and command[0] == ru"highlightfullspace"

proc isMultipleStatusBarSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"multiplestatusbar"

proc isBuildOnSaveSettingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"buildonsave"

proc isTurnOffHighlightingCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"noh"

proc isDeleteCurrentBufferStatusCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"bd"

proc isDeleteBufferStatusCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"bd" and isDigit(command[1])

proc isChangeFirstBufferCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"bfirst"

proc isChangeLastBufferCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"blast"

proc isOpenBufferByNumber(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"b" and isDigit(command[1])

proc isChangeNextBufferCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"bnext"

proc isChangePreveBufferCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"bprev"

proc isJumpCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    prevMode = status.bufStatus[currentBufferIndex].prevMode
  return command.len == 1 and isDigit(command[0]) and (prevMode == Mode.normal or prevMode == Mode.logviewer)

proc isEditCommand(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"e"

proc isWriteCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  return command.len in {1, 2} and command[0] == ru"w" and status.bufStatus[currentBufferIndex].prevMode == Mode.normal

proc isQuitCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"q"

proc isWriteAndQuitCommand(status: EditorStatus, command: seq[seq[Rune]]): bool =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  return command.len == 1 and command[0] == ru"wq" and status.bufStatus[currentBufferIndex].prevMode == Mode.normal

proc isForceQuitCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"q!"

proc isShellCommand(command: seq[seq[Rune]]): bool =
  return command.len >= 1 and command[0][0] == ru'!'

proc isReplaceCommand(command: seq[seq[Rune]]): bool =
  return command.len >= 1  and command[0].len > 4 and command[0][0 .. 2] == ru"%s/"

proc isCreateWorkSpaceCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"cws"

proc isDeleteCurrentWorkSpaceCommand(command: seq[seq[Rune]]): bool =
  return command.len == 1 and command[0] == ru"dws"

proc isChangeCurrentWorkSpace(command: seq[seq[Rune]]): bool =
  return command.len == 2 and command[0] == ru"ws" and isDigit(command[1])

proc openMessageMessageLogViewer(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer("")
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(Mode.logviewer)

proc openBufferManager(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer("")
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(Mode.bufManager)

proc changeCursorLineCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on" : status.settings.view.cursorLine = true 
  elif command == ru"off": status.settings.view.cursorLine = false

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc verticalSplitWindowCommand(status: var EditorStatus) =
  status.verticalSplitWindow

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc horizontalSplitWindowCommand(status: var Editorstatus) =
  status.horizontalSplitWindow

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc liveReloadOfConfSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru "on": status.settings.liveReloadOfConf = true
  elif command == ru"off": status.settings.liveReloadOfConf = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc changeThemeSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"dark": status.settings.editorColorTheme = ColorTheme.dark
  elif command == ru"light": status.settings.editorColorTheme = ColorTheme.light
  elif command == ru"vivid": status.settings.editorColorTheme = ColorTheme.vivid
  elif command == ru"config": status.settings.editorColorTheme = ColorTheme.config

  changeTheme(status)
  status.resize(terminalHeight(), terminalWidth())
  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc tabLineSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.tabLine.useTab = true
  elif command == ru"off": status.settings.tabLine.useTab = false

  status.resize(terminalHeight(), terminalWidth())
  status.commandWindow.erase

proc syntaxSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.syntax = true
  elif command == ru"off": status.settings.syntax = false

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  let sourceLang = if status.settings.syntax: status.bufStatus[currentBufferIndex].language else: SourceLanguage.langNone
  status.bufStatus[currentBufferIndex].highlight = initHighlight($status.bufStatus[currentBufferIndex].buffer, sourceLang)

  status.commandWindow.erase
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc tabStopSettingCommand(status: var EditorStatus, command: int) =
  status.settings.tabStop = command

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc autoCloseParenSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.autoCloseParen = true
  elif command == ru"off": status.settings.autoCloseParen = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc autoIndentSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.autoIndent = true
  elif command == ru"off": status.settings.autoIndent = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc lineNumberSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru "on": status.settings.view.lineNumber = true
  elif command == ru"off": status.settings.view.lineNumber = false

  let numberOfDigitsLen = if status.settings.view.lineNumber: numberOfDigits(status.bufStatus[0].buffer.len) - 2 else: 0
  let useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view = initEditorView(status.bufStatus[0].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen)

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc statusBarSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.statusBar.useBar = true
  elif command == ru"off": status.settings.statusBar.useBar = false

  let numberOfDigitsLen = if status.settings.view.lineNumber: numberOfDigits(status.bufStatus[0].buffer.len) - 2 else: 0
  let useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view = initEditorView(status.bufStatus[0].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numberOfDigitsLen)

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc realtimeSearchSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.realtimeSearch= true
  elif command == ru"off": status.settings.realtimeSearch = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc highlightPairOfParenSettigCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.highlightPairOfParen = true
  elif command == ru"off": status.settings.highlightPairOfParen = false
 
  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc autoDeleteParenSettingCommand(status: var EditorStatus, command: seq[Rune]) =
  if command == ru"on": status.settings.autoDeleteParen = true
  elif command == ru"off": status.settings.autoDeleteParen = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc smoothScrollSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.smoothScroll = true
  elif command == ru"off": status.settings.smoothScroll = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc smoothScrollSpeedSettingCommand(status: var Editorstatus, speed: int) =
  if speed > 0: status.settings.smoothScrollSpeed = speed

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)
  
proc highlightCurrentWordSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.highlightOtherUsesCurrentWord = true
  if command == ru"off": status.settings.highlightOtherUsesCurrentWord = false
  
  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc systemClipboardSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.systemClipboard = true
  elif command == ru"off": status.settings.systemClipboard = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc highlightFullWidthSpaceSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.highlightFullWidthSpace = true
  elif command == ru"off": status.settings.highlightFullWidthSpace = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc buildOnSaveSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.buildOnSaveSettings.buildOnSave = true
  elif command == ru"off": status.settings.buildOnSaveSettings.buildOnSave = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc turnOffHighlightingCommand(status: var EditorStatus) =
  turnOffHighlighting(status)

  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc multipleStatusBarSettingCommand(status: var Editorstatus, command: seq[Rune]) =
  if command == ru"on": status.settings.statusBar.multipleStatusBar = true
  elif command == ru"off": status.settings.statusBar.multipleStatusBar = false

  status.commandWindow.erase

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc deleteBufferStatusCommand(status: var EditorStatus, index: int) =
  if index < 0 or index > status.bufStatus.high:
    status.commandWindow.writeNoBufferDeletedError(status.messageLog)
    status.changeMode(Mode.normal)
    return

  status.bufStatus.delete(index)

  if status.bufStatus.len == 0: addNewBuffer(status, "")
  elif status.bufferIndexInCurrentWindow > status.bufStatus.high:
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex = status.bufStatus.high 

  if status.bufStatus[status.bufferIndexInCurrentWindow].mode == Mode.ex: status.changeMode(status.bufStatus[status.bufferIndexInCurrentWindow].prevMode)
  else:
    status.commandWindow.erase
    status.changeMode(status.bufStatus[status.bufferIndexInCurrentWindow].mode)

proc changeFirstBufferCommand(status: var EditorStatus) =
  changeCurrentBuffer(status, 0)

  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc changeLastBufferCommand(status: var EditorStatus) =
  changeCurrentBuffer(status, status.bufStatus.high)

  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc opneBufferByNumberCommand(status: var EditorStatus, number: int) =
  if number < 0 or number > status.bufStatus.high: return

  changeCurrentBuffer(status, number)
  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc changeNextBufferCommand(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if currentBufferIndex == status.bufStatus.high: return

  changeCurrentBuffer(status, currentBufferIndex + 1)
  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc changePreveBufferCommand(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if currentBufferIndex < 1: return

  changeCurrentBuffer(status, currentBufferIndex - 1)

  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc jumpCommand(status: var EditorStatus, line: int) =
  jumpLine(status, line)

  status.commandWindow.erase
  status.changeMode(Mode.normal)

proc editCommand(status: var EditorStatus, filename: seq[Rune]) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if status.bufStatus[currentBufferIndex].countChange > 0 or countReferencedWindow(status.workSpace[status.currentWorkSpaceIndex].mainWindowNode, currentBufferIndex) == 0:
    status.commandWindow.writeNoWriteError(status.messageLog)
  else:
    status.changeMode(status.bufStatus[currentBufferIndex].prevMode)
    if existsDir($filename):
      try: setCurrentDir($filename)
      except OSError:
        status.commandWindow.writeFileOpenError($filename, status.messageLog)
        addNewBuffer(status, "")
      status.bufStatus.add(BufferStatus(mode: Mode.filer, lastSaveTime: now()))
    else: addNewBuffer(status, $filename)

    changeCurrentBuffer(status, status.bufStatus.high)

proc execCmdResultToMessageLog*(output: TaintedString, messageLog: var seq[seq[Rune]])=
  var line = ""
  for ch in output:
    if ch == '\n':
      messageLog.add(line.toRunes)
      line = ""
    else: line.add(ch)

proc buildOnSave(status: var Editorstatus) =
  status.commandWindow.writeMessageBuildOnSave(status.messageLog)

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    filename = status.bufStatus[currentBufferIndex].filename
    workspaceRoot = status.settings.buildOnSaveSettings.workspaceRoot
    command = status.settings.buildOnSaveSettings.command
    language = status.bufStatus[currentBufferIndex].language
    cmdResult = build(filename, workspaceRoot, command, language)

  cmdResult.output.execCmdResultToMessageLog(status.messageLog)

  if cmdResult.exitCode != 0: status.commandWindow.writeMessageFailedBuildOnSave(status.messageLog)
  else: status.commandWindow.writeMessageSuccessBuildOnSave(status.messageLog)

proc writeCommand(status: var EditorStatus, filename: seq[Rune]) =
  if filename.len == 0:
    status.commandWindow.writeNoFileNameError(status.messageLog)
    status.changeMode(Mode.normal)
    return

  try:
    let currentBufferIndex = status.bufferIndexInCurrentWindow
    saveFile(filename, status.bufStatus[currentBufferIndex].buffer.toRunes, status.settings.characterEncoding)
    let bufferIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
    status.bufStatus[bufferIndex].filename = filename
    status.bufStatus[currentBufferIndex].countChange = 0

    if status.settings.buildOnSaveSettings.buildOnSave: status.buildOnSave
    else: status.commandWindow.writeMessageSaveFile(filename, status.messageLog)
  except IOError:
    status.commandWindow.writeSaveError(status.messageLog)

  status.changeMode(Mode.normal)

proc quitCommand(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if status.bufStatus[currentBufferIndex].prevMode == Mode.filer:
    status.deleteBuffer(currentBufferIndex)
  else:
    if status.bufStatus[currentBufferIndex].countChange == 0 or status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.countReferencedWindow(currentBufferIndex) > 1:
      status.closeWindow(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    else:
      status.commandWindow.writeNoWriteError(status.messageLog)

  status.changeMode(Mode.normal)
proc writeAndQuitCommand(status: var EditorStatus) =
  try:
    let currentBufferIndex = status.bufferIndexInCurrentWindow
    status.bufStatus[currentBufferIndex].countChange = 0
    saveFile(status.bufStatus[currentBufferIndex].filename, status.bufStatus[currentBufferIndex].buffer.toRunes, status.settings.characterEncoding)
    status.closeWindow(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  except IOError:
    status.commandWindow.writeSaveError(status.messageLog)

  status.changeMode(Mode.normal)

proc forceQuitCommand(status: var EditorStatus) =
  status.closeWindow(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  status.changeMode(Mode.normal)

proc allBufferQuitCommand(status: var EditorStatus) =
  for i in 0 ..< status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow:
    let node = status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.searchByWindowIndex(i)
    if status.bufStatus[node.bufferIndex].countChange > 0:
      status.commandWindow.writeNoWriteError(status.messageLog)
      status.changeMode(Mode.normal)
      return

  exitEditor(status.settings)

proc forceAllBufferQuitCommand(status: var EditorStatus) = exitEditor(status.settings)

proc writeAndQuitAllBufferCommand(status: var Editorstatus) =
  for bufStatus in status.bufStatus:
    try: saveFile(bufStatus.filename, bufStatus.buffer.toRunes, status.settings.characterEncoding)
    except IOError:
      status.commandWindow.writeSaveError(status.messageLog)
      status.changeMode(Mode.normal)
      return

  exitEditor(status.settings)

proc shellCommand(status: var EditorStatus, shellCommand: string) =
  saveCurrentTerminalModes()
  exitUi()

  discard execShellCmd(shellCommand)
  discard execShellCmd("printf \"\nPress Enter\"")
  discard execShellCmd("read _")

  restoreTerminalModes()
  status.commandWindow.erase
  status.commandWindow.refresh

proc listAllBufferCommand(status: var Editorstatus) =
  let swapCurrentBufferIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
  status.addNewBuffer("")
  status.changeCurrentBuffer(status.bufStatus.high)

  for i in 0 ..< status.bufStatus.high:
    var line = ru""
    let
      currentMode = status.bufStatus[i].mode
      prevMode = status.bufStatus[i].prevMode
    if currentMode == Mode.filer or (currentMode == Mode.ex and prevMode == Mode.filer): line = getCurrentDir().toRunes
    else: line = status.bufStatus[i].filename & ru"  line " & ($status.bufStatus[i].buffer.len).toRunes

    let currentBufferIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
    if i == 0: status.bufStatus[currentBufferIndex].buffer[0] = line
    else: status.bufStatus[currentBufferIndex].buffer.insert(line, i)

  let
    useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    useTab = if status.settings.tabLine.useTab: 1 else: 0
    swapCurrentLineNumStting = status.settings.view.currentLineNumber
    currentBufferIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
  
  status.settings.view.currentLineNumber = false
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view = status.bufStatus[currentBufferIndex].buffer.initEditorView(terminalHeight() - useStatusBar - useTab - 1, terminalWidth())
  status.bufStatus[currentBufferIndex].currentLine = 0

  status.updateHighlight(currentBufferIndex)

  while true:
    status.update
    setCursor(false)
    let key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    if isResizekey(key): status.resize(terminalHeight(), terminalWidth())
    elif key.int == 0: discard
    else: break

  status.settings.view.currentLineNumber = swapCurrentLineNumStting
  status.changeCurrentBuffer(swapCurrentBufferIndex)
  status.deleteBufferStatusCommand(status.bufStatus.high)

  status.commandWindow.erase
  status.commandWindow.refresh
proc replaceBuffer(status: var EditorStatus, command: seq[Rune]) =
  let
    replaceInfo = parseReplaceCommand(command)
    currentBufferIndex = status.bufferIndexInCurrentWindow

  if replaceInfo.searhWord == ru"'\n'" and status.bufStatus[currentBufferIndex].buffer.len > 1:
    let startLine = 0

    for i in 0 .. status.bufStatus[currentBufferIndex].buffer.high - 2:
      let oldLine = status.bufStatus[currentBufferIndex].buffer[startLine]
      var newLine = status.bufStatus[currentBufferIndex].buffer[startLine]
      newLine.insert(replaceInfo.replaceWord, status.bufStatus[currentBufferIndex].buffer[startLine].len)
      for j in 0 .. status.bufStatus[currentBufferIndex].buffer[startLine + 1].high:
        newLine.insert(status.bufStatus[currentBufferIndex].buffer[startLine + 1][j], status.bufStatus[currentBufferIndex].buffer[startLine].len)
      if oldLine != newLine: status.bufStatus[currentBufferIndex].buffer[startLine] = newLine

      status.bufStatus[currentBufferIndex].buffer.delete(startLine + 1, startLine + 1)
  else:
    for i in 0 .. status.bufStatus[currentBufferIndex].buffer.high:
      let searchResult = searchBuffer(status, replaceInfo.searhWord)
      if searchResult.line > -1:
        let oldLine = status.bufStatus[currentBufferIndex].buffer[searchResult.line]
        var newLine = status.bufStatus[currentBufferIndex].buffer[searchResult.line]
        newLine.delete(searchResult.column, searchResult.column + replaceInfo.searhWord.high)
        newLine.insert(replaceInfo.replaceWord, searchResult.column)
        if oldLine != newLine: status.bufStatus[currentBufferIndex].buffer[searchResult.line] = newLine

  inc(status.bufStatus[currentBufferIndex].countChange)
  status.commandWindow.erase
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc createWrokSpaceCommand(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.createWrokSpace

proc changeCurrentWorkSpaceCommand(status: var Editorstatus, index: int) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

  status.changeCurrentWorkSpace(index)

proc deleteCurrentWorkSpaceCommand*(status: var Editorstatus) =
  let index = status.currentWorkSpaceIndex
  if 0 <= index and index < status.workSpace.len:
    for i in 0 ..< status.workSpace[index].numOfMainWindow:
      let node = status.workSpace[status.currentWorkSpaceIndex].mainWindowNode.searchByWindowIndex(i)
      ## Check if buffer has changed
      if status.bufStatus[node.bufferIndex].countChange > 0:
        status.commandWindow.writeNoWriteError(status.messageLog)
        status.changeMode(Mode.normal)
        return

    status.deleteWorkSpace(index)

proc exModeCommand*(status: var EditorStatus, command: seq[seq[Rune]]) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  if command.len == 0 or command[0].len == 0:
    status.changeMode(status.bufStatus[currentBufferIndex].prevMode)
  elif isJumpCommand(status, command):
    var line = ($command[0]).parseInt - 1
    if line < 0: line = 0
    if line >= status.bufStatus[currentBufferIndex].buffer.len: line = status.bufStatus[currentBufferIndex].buffer.high
    jumpCommand(status, line)
  elif isEditCommand(command):
    editCommand(status, command[1].normalizePath)
  elif isWriteCommand(status, command):
    writeCommand(status, if command.len < 2: status.bufStatus[currentBufferIndex].filename else: command[1])
  elif isQuitCommand(command):
    quitCommand(status)
  elif isWriteAndQuitCommand(status, command):
    writeAndQuitCommand(status)
  elif isForceQuitCommand(command):
    forceQuitCommand(status)
  elif isShellCommand(command):
    shellCommand(status, command.join(" ").substr(1))
  elif isReplaceCommand(command):
    replaceBuffer(status, command[0][3 .. command[0].high])
  elif isChangeNextBufferCommand(command):
    changeNextBufferCommand(status)
  elif isChangePreveBufferCommand(command):
    changePreveBufferCommand(status)
  elif isOpenBufferByNumber(command):
    opneBufferByNumberCommand(status, ($command[1]).parseInt)
  elif isChangeFirstBufferCommand(command):
    changeFirstBufferCommand(status)
  elif isChangeLastBufferCommand(command):
    changeLastBufferCommand(status)
  elif isDeleteBufferStatusCommand(command):
    deleteBufferStatusCommand(status, ($command[1]).parseInt)
  elif isDeleteCurrentBufferStatusCommand(command):
    deleteBufferStatusCommand(status, currentBufferIndex)
  elif isTurnOffHighlightingCommand(command):
    turnOffHighlightingCommand(status)
  elif isTabLineSettingCommand(command):
    tabLineSettingCommand(status, command[1])
  elif isStatusBarSettingCommand(command):
    statusBarSettingCommand(status, command[1])
  elif isLineNumberSettingCommand(command):
    lineNumberSettingCommand(status, command[1])
  elif isAutoIndentSettingCommand(command):
    autoIndentSettingCommand(status, command[1])
  elif isAutoCloseParenSettingCommand(command):
    autoCloseParenSettingCommand(status, command[1])
  elif isTabStopSettingCommand(command):
    tabStopSettingCommand(status, ($command[1]).parseInt)
  elif isSyntaxSettingCommand(command):
    syntaxSettingCommand(status, command[1])
  elif isChangeThemeSettingCommand(command):
    changeThemeSettingCommand(status, command[1])
  elif isChangeCursorLineCommand(command):
    changeCursorLineCommand(status, command[1])
  elif isVerticalSplitWindowCommand(command):
    verticalSplitWindowCommand(status)
  elif isHorizontalSplitWindowCommand(command):
    horizontalSplitWindowCommand(status)
  elif isAllBufferQuitCommand(command):
    allBufferQuitCommand(status)
  elif isForceAllBufferQuitCommand(command):
    forceAllBufferQuitCommand(status)
  elif isWriteAndQuitAllBufferCommand(command):
    writeAndQuitAllBufferCommand(status)
  elif isListAllBufferCommand(command):
    listAllBufferCommand(status)
  elif isOpenBufferManager(command):
    openBufferManager(status)
  elif isLiveReloadOfConfSettingCommand(command):
    liveReloadOfConfSettingCommand(status, command[1])
  elif isRealtimeSearchSettingCommand(command):
    realtimeSearchSettingCommand(status, command[1])
  elif isOpenMessageLogViweer(command):
    openMessageMessageLogViewer(status)
  elif isHighlightPairOfParenSettigCommand(command):
    highlightPairOfParenSettigCommand(status, command[1])
  elif isAutoDeleteParenSettingCommand(command):
    autoDeleteParenSettingCommand(status, command[1])
  elif isSmoothScrollSettingCommand(command):
    smoothScrollSettingCommand(status, command[1])
  elif isSmoothScrollSpeedSettingCommand(command):
    smoothScrollSpeedSettingCommand(status, ($command[1]).parseInt)
  elif isHighlightCurrentWordSettingCommand(command):
    highlightCurrentWordSettingCommand(status, command[1])
  elif isSystemClipboardSettingCommand(command):
    systemClipboardSettingCommand(status, command[1])
  elif isHighlightFullWidthSpaceSettingCommand(command):
    highlightFullWidthSpaceSettingCommand(status, command[1])
  elif isMultipleStatusBarSettingCommand(command):
    multipleStatusBarSettingCommand(status, command[1])
  elif isBuildOnSaveSettingCommand(command):
    buildOnSaveSettingCommand(status, command[1])
  elif isCreateWorkSpaceCommand(command):
    createWrokSpaceCommand(status)
  elif isChangeCurrentWorkSpace(command):
    changeCurrentWorkSpaceCommand(status, ($command[1]).parseInt)
  elif isDeleteCurrentWorkSpaceCommand(command):
    deleteCurrentWorkSpaceCommand(status)
  else:
    status.commandWindow.writeNotEditorCommandError(command, status.messageLog)
    status.changeMode(status.bufStatus[currentBufferIndex].prevMode)

proc exMode*(status: var EditorStatus) =
  const prompt = ":"
  var
    command = ru""
    exitInput = false
    cancelInput = false
    isSuggest = true

  status.searchHistory.add(ru"")

  while exitInput == false:
    let returnWord = status.getKeyOnceAndWriteCommandView(prompt, command, isSuggest)

    command = returnWord[0]
    exitInput = returnWord[1]
    cancelInput = returnWord[2]

    if cancelInput or exitInput: break
    elif status.settings.replaceTextHighlight and  command.len > 3 and command.startsWith(ru"%s/"):
      var keyword = ru""
      for i in 3 ..< command.len :
          if command[i] == ru'/': break
          keyword.add(command[i])
      status.searchHistory[status.searchHistory.high] = keyword
      let bufferIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
      status.bufStatus[bufferIndex].isHighlight = true
    else:
      let bufferIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
      status.bufStatus[bufferIndex].isHighlight = false

    let currentBufferIndex = status.bufferIndexInCurrentWindow
    status.updateHighlight(currentBufferIndex)
    status.resize(terminalHeight(), terminalWidth())
    status.update

  status.searchHistory.delete(status.searchHistory.high)
  let bufferIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
  status.bufStatus[bufferIndex].isHighlight = false
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.updateHighlight(currentBufferIndex)

  if cancelInput:
    status.commandWindow.erase
    status.changeMode(status.bufStatus[currentBufferIndex].prevMode)
  else:
    status.bufStatus[currentBufferIndex].buffer.beginNewSuitIfNeeded
    status.bufStatus[currentBufferIndex].tryRecordCurrentPosition

    exModeCommand(status, splitCommand($command))
