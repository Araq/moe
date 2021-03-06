import strformat, terminal, deques
import editorstatus, editorview, ui, gapbuffer, unicodeext, fileutils, commandview, undoredostack, window, movement, editor, searchmode, color

proc writeDebugInfo(status: var EditorStatus, str: string = "") =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.commandWindow.erase

  status.commandWindow.write(0, 0, "debuf info: ", EditorColorPair.commandBar)
  status.commandWindow.append(fmt"currentLine: {status.bufStatus[currentBufferIndex].currentLine}, currentColumn: {status.bufStatus[currentBufferIndex].currentColumn}")
  status.commandWindow.append(fmt", cursor.y: {status.bufStatus[currentBufferIndex].cursor.y}, cursor.x: {status.bufStatus[currentBufferIndex].cursor.x}")
  status.commandWindow.append(fmt", {str}")

  status.commandWindow.refresh

proc searchOneCharactorToEndOfLine(bufStatus: var BufferStatus, rune: Rune) =
  let line = bufStatus.buffer[bufStatus.currentLine]

  if line.len < 1 or isEscKey(rune) or (bufStatus.currentColumn == line.high): return

  for col in bufStatus.currentColumn + 1 ..< line.len:
    if line[col] == rune:
      bufStatus.currentColumn = col
      break

proc searchOneCharactorToBeginOfLine(bufStatus: var BufferStatus, rune: Rune) =
  let line = bufStatus.buffer[bufStatus.currentLine]

  if line.len < 1 or isEscKey(rune) or (bufStatus.currentColumn == 0): return

  for col in countdown(bufStatus.currentColumn - 1, 0):
    if line[col] == rune:
      bufStatus.currentColumn = col
      break

proc searchNextOccurrence(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]
  
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].isHighlight = true
  status.updateHighlight(currentBufferIndex)

  keyRight(status.bufStatus[currentBufferIndex])
  let searchResult = searchBuffer(status, keyword)
  if searchResult.line > -1:
    jumpLine(status, searchResult.line)
    for column in 0 ..< searchResult.column: keyRight(status.bufStatus[currentBufferIndex])
  elif searchResult.line == -1:
    keyLeft(status.bufStatus[currentBufferIndex])

proc searchNextOccurrenceReversely(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]
  
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].isHighlight = true
  status.updateHighlight(currentBufferIndex)

  keyLeft(status.bufStatus[currentBufferIndex])
  let searchResult = searchBufferReversely(status, keyword)
  if searchResult.line > -1:
    jumpLine(status, searchResult.line)
    for column in 0 ..< searchResult.column: keyRight(status.bufStatus[currentBufferIndex])
  elif searchResult.line == -1:
    keyRight(status.bufStatus[currentBufferIndex])

proc turnOffHighlighting*(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].isHighlight = false
  status.updateHighlight(currentBufferIndex)

proc undo(bufStatus: var BufferStatus, currentWin: WindowNode) =
  if not bufStatus.buffer.canUndo: return
  bufStatus.buffer.undo
  bufStatus.revertPosition(bufStatus.buffer.lastSuitId)
  if bufStatus.currentColumn == bufStatus.buffer[bufStatus.currentLine].len and bufStatus.currentColumn > 0:
    (bufStatus.currentLine, bufStatus.currentColumn) = bufStatus.buffer.prev(bufStatus.currentLine, bufStatus.currentColumn)
  currentWin.view.reload(bufStatus.buffer, min(currentWin.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc redo(bufStatus: var BufferStatus, currentWin: WindowNode) =
  if not bufStatus.buffer.canRedo: return
  bufStatus.buffer.redo
  bufStatus.revertPosition(bufStatus.buffer.lastSuitId)
  currentWin.view.reload(bufStatus.buffer, min(currentWin.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc writeFileAndExit(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if status.bufStatus[currentBufferIndex].filename.len == 0:
    status.commandwindow.writeNoFileNameError(status.messageLog)
    status.changeMode(Mode.normal)
  else:
    try:
      saveFile(status.bufStatus[currentBufferIndex].filename, status.bufStatus[currentBufferIndex].buffer.toRunes, status.settings.characterEncoding)
      status.closeWindow(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    except IOError:
      status.commandWindow.writeSaveError(status.messageLog)

proc forceExit(status: var Editorstatus) = status.closeWindow(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)

proc normalCommand(status: var EditorStatus, key: Rune) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if status.bufStatus[currentBufferIndex].cmdLoop == 0: status.bufStatus[currentBufferIndex].cmdLoop = 1

  let
    cmdLoop = status.bufStatus[currentBufferIndex].cmdLoop
    currentBuf = currentBufferIndex

  if isControlK(key):
    moveNextWindow(status)
  elif isControlJ(key):
    movePrevWindow(status)
  elif isControlV(key):
    status.changeMode(Mode.visualBlock)
  elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
    for i in 0 ..< cmdLoop: keyLeft(status.bufStatus[currentBufferIndex])
  elif key == ord('l') or isRightKey(key):
    for i in 0 ..< cmdLoop: keyRight(status.bufStatus[currentBufferIndex])
  elif key == ord('k') or isUpKey(key):
    for i in 0 ..< cmdLoop: keyUp(status.bufStatus[currentBufferIndex])
  elif key == ord('j') or isDownKey(key) or isEnterKey(key):
    for i in 0 ..< cmdLoop: keyDown(status.bufStatus[currentBufferIndex])
  elif key == ord('x') or isDcKey(key):
    yankString(status, min(cmdLoop, status.bufStatus[currentBufferIndex].buffer[status.bufStatus[currentBufferIndex].currentLine].len - status.bufStatus[currentBufferIndex].currentColumn))
    for i in 0 ..< min(cmdLoop, status.bufStatus[currentBufferIndex].buffer[status.bufStatus[currentBufferIndex].currentLine].len - status.bufStatus[currentBufferIndex].currentColumn):
      status.bufStatus[currentBufferIndex].deleteCurrentCharacter(status.settings.autoDeleteParen, status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  elif key == ord('^'):
    moveToFirstNonBlankOfLine(status.bufStatus[currentBufferIndex])
  elif key == ord('0') or isHomeKey(key):
    moveToFirstOfLine(status.bufStatus[currentBufferIndex])
  elif key == ord('$') or isEndKey(key):
    moveToLastOfLine(status.bufStatus[currentBufferIndex])
  elif key == ord('-'):
    moveToFirstOfPreviousLine(status.bufStatus[currentBufferIndex])
  elif key == ord('+'):
    moveToFirstOfNextLine(status.bufStatus[currentBufferIndex])
  elif key == ord('g'):
    if getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window) == ord('g'): moveToFirstLine(status)
  elif key == ord('G'):
    moveToLastLine(status)
  elif isPageUpkey(key) or isControlU(key):
    for i in 0 ..< cmdLoop: pageUp(status)
  elif isPageDownKey(key): ## Page down and Ctrl - F
    for i in 0 ..< cmdLoop: pageDown(status)
  elif key == ord('w'):
    for i in 0 ..< cmdLoop: moveToForwardWord(status.bufStatus[currentBufferIndex])
  elif key == ord('b'):
    for i in 0 ..< cmdLoop: moveToBackwardWord(status.bufStatus[currentBufferIndex])
  elif key == ord('e'):
    for i in 0 ..< cmdLoop: moveToForwardEndOfWord(status.bufStatus[currentBufferIndex])
  elif key == ord('z'):
    let key = getkey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    if key == ord('.'): moveCenterScreen(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif key == ord('t'): scrollScreenTop(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif key == ord('b'): scrollScreenBottom(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  elif key == ord('o'):
    for i in 0 ..< cmdLoop: openBlankLineBelow(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    status.updateHighlight(currentBufferIndex)
    status.changeMode(Mode.insert)
  elif key == ord('O'):
    for i in 0 ..< cmdLoop: openBlankLineAbove(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    status.updateHighlight(currentBufferIndex)
    status.changeMode(Mode.insert)
  elif key == ord('d'):
    let key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    if key == ord('d'):
      yankLines(status, status.bufStatus[currentBufferIndex].currentLine, min(status.bufStatus[currentBufferIndex].currentLine + cmdLoop - 1, status.bufStatus[currentBufferIndex].buffer.high))
      for i in 0 ..< min(cmdLoop, status.bufStatus[currentBufferIndex].buffer.len - status.bufStatus[currentBufferIndex].currentLine):
        deleteLine(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, status.bufStatus[currentBufferIndex].currentLine)
    elif key == ord('w'): deleteWord(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif key == ('$') or isEndKey(key):
      status.bufStatus[currentBufferIndex].deleteCharacterUntilEndOfLine(status.settings.autoDeleteParen, status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif key == ('0') or isHomeKey(key):
      status.bufStatus[currentBufferIndex].deleteCharacterBeginningOfLine(status.settings.autoDeleteParen, status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  elif key == ord('y'):
    let key = getkey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    if key == ord('y'): yankLines(status, status.bufStatus[currentBufferIndex].currentLine, min(status.bufStatus[currentBufferIndex].currentLine + cmdLoop - 1, status.bufStatus[currentBufferIndex].buffer.high))
    elif key == ord('w'): yankWord(status, cmdLoop)
  elif key == ord('p'):
    pasteAfterCursor(status)
  elif key == ord('P'):
    pasteBeforeCursor(status)
  elif key == ord('>'):
    for i in 0 ..< cmdLoop: addIndent(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, status.settings.tabStop)
  elif key == ord('<'):
    for i in 0 ..< cmdLoop: deleteIndent(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, status.settings.tabStop)
  elif key == ord('J'):
    joinLine(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  elif key == ord('r'):
    if cmdLoop > status.bufStatus[currentBufferIndex].buffer[status.bufStatus[currentBufferIndex].currentLine].len - status.bufStatus[currentBufferIndex].currentColumn: return

    let ch = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    for i in 0 ..< cmdLoop:
      if i > 0:
        inc(status.bufStatus[currentBufferIndex].currentColumn)
        status.bufStatus[currentBufferIndex].expandedColumn = status.bufStatus[currentBufferIndex].currentColumn
      status.bufStatus[currentBufferIndex].replaceCurrentCharacter(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, status.settings.autoIndent, status.settings.autoDeleteParen, ch)
  elif key == ord('n'):
    searchNextOccurrence(status)
  elif key == ord('N'):
    searchNextOccurrenceReversely(status)
  elif key == ord('f'):
    let key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    searchOneCharactorToEndOfLine(status.bufStatus[currentBufferIndex], key)
  elif key == ord('F'):
    let key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    searchOneCharactorToBeginOfLine(status.bufStatus[currentBufferIndex], key)
  elif key == ord('R'):
    status.changeMode(Mode.replace)
  elif key == ord('i'):
    status.changeMode(Mode.insert)
  elif key == ord('I'):
    status.bufStatus[currentBufferIndex].currentColumn = 0
    status.changeMode(Mode.insert)
  elif key == ord('v'):
    status.changeMode(Mode.visual)
  elif key == ord('a'):
    let lineWidth = status.bufStatus[currentBufferIndex].buffer[status.bufStatus[currentBufferIndex].currentLine].len
    if lineWidth == 0: discard
    elif lineWidth == status.bufStatus[currentBufferIndex].currentColumn: discard
    else: inc(status.bufStatus[currentBufferIndex].currentColumn)
    status.changeMode(Mode.insert)
  elif key == ord('A'):
    status.bufStatus[currentBufferIndex].currentColumn = status.bufStatus[currentBufferIndex].buffer[status.bufStatus[currentBufferIndex].currentLine].len
    status.changeMode(Mode.insert)
  elif key == ord('u'):
    undo(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  elif isControlR(key):
    redo(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  elif key == ord('Z'):
    let key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    if  key == ord('Z'): writeFileAndExit(status)
    elif key == ord('Q'): forceExit(status)
  else:
    discard

proc normalMode*(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].cmdLoop = 0
  status.resize(terminalHeight(), terminalWidth())
  var countChange = 0

  changeCursorType(status.settings.normalModeCursor)

  while status.bufStatus[currentBufferIndex].mode == Mode.normal and status.workSpace[status.currentWorkSpaceIndex].numOfMainWindow > 0:
    if status.bufStatus[currentBufferIndex].countChange > countChange:
      status.updateHighlight(currentBufferIndex)
      countChange = status.bufStatus[currentBufferIndex].countChange

    status.update

    var key: Rune = ru'\0'
    while key == ru'\0':
      status.eventLoopTask
      key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    status.bufStatus[currentBufferIndex].buffer.beginNewSuitIfNeeded
    status.bufStatus[currentBufferIndex].tryRecordCurrentPosition

    if isEscKey(key):
      let keyAfterEsc = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
      if isEscKey(keyAfterEsc):
        turnOffHighlighting(status)
        continue
      else: key = keyAfterEsc

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
    elif key == ord('/'):
      status.changeMode(Mode.search)
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif isDigit(key):
      let num = ($key)[0]
      if status.bufStatus[currentBufferIndex].cmdLoop == 0 and num == '0':
        normalCommand(status, key)
        continue

      status.bufStatus[currentBufferIndex].cmdLoop *= 10
      status.bufStatus[currentBufferIndex].cmdLoop += ord(num)-ord('0')
      status.bufStatus[currentBufferIndex].cmdLoop = min(100000, status.bufStatus[currentBufferIndex].cmdLoop)
      continue
    else:
      normalCommand(status, key)
      status.bufStatus[currentBufferIndex].cmdLoop = 0
