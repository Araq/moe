import os, terminal, strutils, unicodeext, times, algorithm
import editorstatus, ui, fileutils, editorview, gapbuffer, highlight, commandview, highlight, window, color

type PathInfo = tuple[kind: PathComponent, path: string, size: int64, lastWriteTime: times.Time]

type Sort = enum
  name = 0
  fileSize = 1
  time = 2

type FileRegister = object
  copy: bool
  cut: bool
  originPath: string
  filename: string

type FilerStatus = object
  register: FileRegister
  searchMode: bool
  viewUpdate: bool
  dirlistUpdate: bool
  dirList: seq[PathInfo]
  sortBy: Sort

proc tryExpandSymlink(symlinkPath: string): string =
  try: return expandSymlink(symlinkPath)
  except OSError: return ""

proc searchFiles(status: var EditorStatus, dirList: seq[PathInfo]): seq[PathInfo] =
  setCursor(true)
  let command = getCommand(status, "/")

  if command.len == 0:
    status.commandWindow.erase
    status.commandWindow.refresh
    return @[]

  let str = command[0].join("")
  result = @[]
  for dir in dirList:
    if dir.path.contains(str): result.add dir

proc deleteFile(status: var EditorStatus, filerStatus: var FilerStatus) =
  setCursor(true)
  let command = getCommand(status, "Delete file? 'y' or 'n': ")

  if command.len == 0:
    status.commandWindow.erase
    status.commandWindow.refresh
  elif (command[0] == ru"y" or command[0] == ru"yes") and command.len == 1:
    let currentBufferIndex = status.bufferIndexInCurrentWindow
    if filerStatus.dirList[status.bufStatus[currentBufferIndex].currentLine].kind == pcDir:
      try:
        removeDir(filerStatus.dirList[status.bufStatus[currentBufferIndex].currentLine].path)
        status.commandWindow.writeMessageDeletedFile(filerStatus.dirList[status.bufStatus[currentBufferIndex].currentLine].path, status.messageLog)
      except OSError:
        status.commandWindow.writeRemoveDirError(status.messageLog)
    else:
      if tryRemoveFile(filerStatus.dirList[status.bufStatus[currentBufferIndex].currentLine].path):
        status.commandWindow.writeMessageDeletedFile(filerStatus.dirList[status.bufStatus[currentBufferIndex].currentLine].path, status.messageLog)
      else:
        status.commandWindow.writeRemoveFileError(status.messageLog)

proc sortDirList(dirList: seq[PathInfo], sortBy: Sort): seq[PathInfo] =
  case sortBy:
  of name:
    return dirList.sortedByIt(it.path)
  of fileSize:
    result = @[(pcDir, "../", 0.int64, getLastModificationTime(getCurrentDir()))]
    result.add dirList[1 .. dirList.high].sortedByIt(it.size).reversed
  of time:
    result = @[(pcDir, "../", 0.int64, getLastModificationTime(getCurrentDir()))]
    result.add dirList[1 .. dirList.high].sortedByIt(it.lastWriteTime)

proc refreshDirList(sortBy: Sort): seq[PathInfo] =
  result = @[(pcDir, "../", 0.int64, getLastModificationTime(getCurrentDir()))]
  for list in walkDir("./"):
    if list.kind == pcLinkToFile or list.kind == pcLinkToDir:
      if tryExpandSymlink(list.path) != "": result.add (list.kind, list.path, 0.int64, getLastModificationTime(getCurrentDir()))
    else:
      if list.kind == pcFile:
        try: result.add (list.kind, list.path, getFileSize(list.path), getLastModificationTime(list.path))
        except OSError, IOError: discard
      else: result.add (list.kind, list.path, 0.int64, getLastModificationTime(list.path))
    result[result.high].path = $(result[result.high].path.toRunes.normalizePath)
  return sortDirList(result, sortBy)

proc initFileRegister(): FileRegister =
  result.copy = false
  result.cut= false
  result.originPath = ""
  result.filename = ""

proc initFilerStatus*(): FilerStatus =
  result.register = initFileRegister()
  result.viewUpdate = true
  result.dirlistUpdate = true
  result.dirList = newSeq[PathInfo]()
  result.sortBy = name
  result.searchMode = false

proc updateDirList*(filerStatus: var FilerStatus): FilerStatus =
  filerStatus.dirList = @[]
  filerStatus.dirList.add refreshDirList(filerStatus.sortBy)
  filerStatus.viewUpdate = true
  filerStatus.dirlistUpdate = false
  return filerStatus

proc keyDown(filerStatus: var FilerStatus, currentLine: var int) =
  if currentLine < filerStatus.dirList.high:
    inc(currentLine)
    filerStatus.viewUpdate = true

proc keyUp(filerStatus: var FilerStatus, currentLine: var int) =
  if currentLine > 0:
    dec(currentLine)
    filerStatus.viewUpdate = true

proc moveToTopOfList(filerStatus: var FilerStatus, currentLine: var int) =
  currentLine = 0
  filerStatus.viewUpdate = true

proc moveToLastOfList(filerStatus: var FilerStatus, currentLine: var int) =
  currentLine = filerStatus.dirList.high
  filerStatus.viewUpdate = true

proc copyFile(filerStatus: var FilerStatus, currentLine: int) =
  filerStatus.register.copy = true
  filerStatus.register.cut = false
  filerStatus.register.filename = filerStatus.dirList[currentLine].path
  filerStatus.register.originPath = getCurrentDir() / filerStatus.dirList[currentLine].path

proc cutFile(filerStatus: var FilerStatus, currentLine: int) =
  filerStatus.register.copy = false
  filerStatus.register.cut = true
  filerStatus.register.filename = filerStatus.dirList[currentLine].path
  filerStatus.register.originPath = getCurrentDir() / filerStatus.dirList[currentLine].path

proc pasteFile(commandWindow: var Window, filerStatus: var FilerStatus, messageLog: var seq[seq[Rune]]) =
  try:
    copyFile(filerStatus.register.originPath, getCurrentDir() / filerStatus.register.filename)
    filerStatus.dirlistUpdate = true
    filerStatus.viewUpdate = true
  except OSError:
    commandWindow.writeCopyFileError(messageLog)
    return

  if filerStatus.register.cut:
    if tryRemoveFile(filerStatus.register.originPath / filerStatus.register.filename): filerStatus.register.cut = false
    else: commandWindow.writeRemoveFileError(messageLog)

proc createDir(status: var EditorStatus, filerStatus: var FilerStatus) =
  let dirname = getCommand(status, "New file name: ")

  try:
    createDir($dirname[0])
    filerStatus.dirlistUpdate = true
  except OSError: status.commandWindow.writeCreateDirError(status.messageLog)
   
proc openFileOrDir(status: var EditorStatus, filerStatus: var FilerStatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    kind = filerStatus.dirList[status.bufStatus[currentBufferIndex].currentLine].kind
    path = filerStatus.dirList[status.bufStatus[currentBufferIndex].currentLine].path

  case kind
  of pcFile, pcLinkToFile:
    addNewBuffer(status, path)
  of pcDir, pcLinkToDir:
    try:
      setCurrentDir(path)
      filerStatus.dirlistUpdate = true
    except OSError: status.commandWindow.writeFileOpenError(path, status.messageLog)

proc setDirListColor(kind: PathComponent, isCurrentLine: bool): EditorColorPair =
  if isCurrentLine: result = EditorColorPair.currentFile
  else:
    case kind
    of pcFile: result = EditorColorPair.file
    of pcDir: result = EditorColorPair.dir
    of pcLinkToDir, pcLinkToFile: result = EditorColorPair.pcLink

proc initFilelistHighlight[T](dirList: seq[PathInfo], buffer: T, currentLine: int): Highlight =
  for index, dir in dirList:
    let color = setDirListColor(dir.kind, index == currentLine)
    result.colorSegments.add(ColorSegment(firstRow: index, firstColumn: 0, lastRow: index, lastColumn: buffer[index].len, color: color))

proc fileNameToGapBuffer(bufStatus: var BufferStatus, currentWin: WindowNode, settings: EditorSettings, filerStatus: FilerStatus) =
  bufStatus.buffer = initGapBuffer[seq[Rune]]()

  for index, dir in filerStatus.dirList:
    let
      filename = dir.path
      kind = dir.kind
    bufStatus.buffer.add(filename.toRunes)

    let oldLine =  bufStatus.buffer[index]
    var newLine =  bufStatus.buffer[index]
    if kind == pcDir and 0 < index: newLine.add(ru"/")
    elif kind == pcLinkToFile: newLine.add(ru"@ -> " & expandsymLink(filename).toRunes)
    elif kind == pcLinkToDir: newLine.add(ru"@ -> " & expandsymLink(filename).toRunes & ru"/")
    if oldLine != newLine: bufStatus.buffer[index] = newLine
  
  let useStatusBar = if settings.statusBar.useBar: 1 else: 0
  let numOfFile = filerStatus.dirList.len
  bufStatus.highlight = initFilelistHighlight(filerStatus.dirList, bufStatus.buffer, bufStatus.currentLine)
  currentWin.view = initEditorView(bufStatus.buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numOfFile)

proc updateFilerView*(status: var EditorStatus, filerStatus: var FilerStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  fileNameToGapBuffer(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, status.settings, filerStatus)
  status.resize(terminalHeight(), terminalWidth())
  status.update
  filerStatus.viewUpdate = false

proc initFileDeitalHighlight[T](buffer: T): Highlight =
  for i in 0 ..< buffer.len:
    result.colorSegments.add(ColorSegment(firstRow: i, firstColumn: 0, lastRow: i, lastColumn: buffer[i].len, color: EditorColorPair.defaultChar))

proc writefileDetail(status: var Editorstatus, numOfFile: int, fileName: string) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.bufStatus[currentBufferIndex].buffer = initGapBuffer[seq[Rune]]()

  let fileInfo = getFileInfo(fileName, false)
  status.bufStatus[currentBufferIndex].buffer.add(ru"name        : " & fileName.toRunes)

  if fileInfo.kind == pcFile: status.bufStatus[currentBufferIndex].buffer.add(ru"kind        : " & ru"File")
  elif fileInfo.kind == pcDir: status.bufStatus[currentBufferIndex].buffer.add(ru"kind        : " & ru"Directory")
  elif fileInfo.kind == pcLinkToFile: status.bufStatus[currentBufferIndex].buffer.add(ru"kind        : " & ru"Symbolic link to file")
  elif fileInfo.kind == pcLinkToDir: status.bufStatus[currentBufferIndex].buffer.add(ru"kind        : " & ru"Symbolic link to directory")

  status.bufStatus[currentBufferIndex].buffer.add(("size        : " & $fileInfo.size & " bytes").toRunes)
  status.bufStatus[currentBufferIndex].buffer.add(("permissions : " & substr($fileInfo.permissions, 1, ($fileInfo.permissions).high - 1)).toRunes)
  status.bufStatus[currentBufferIndex].buffer.add(("create time : " & $fileInfo.creationTime).toRunes)
  status.bufStatus[currentBufferIndex].buffer.add(("last write  : " & $fileInfo.lastWriteTime).toRunes)
  status.bufStatus[currentBufferIndex].buffer.add(("last access : " & $fileInfo.lastAccessTime).toRunes)

  status.bufStatus[currentBufferIndex].highlight = initFileDeitalHighlight(status.bufStatus[currentBufferIndex].buffer)

  let
    useStatusBar = if status.settings.statusBar.useBar: 1 else: 0
    tmpCurrentLine = status.bufStatus[currentBufferIndex].currentLine

  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view = initEditorView(status.bufStatus[currentBufferIndex].buffer, terminalHeight() - useStatusBar - 1, terminalWidth() - numOfFile)
  status.bufStatus[currentBufferIndex].currentLine = 0

  status.update
  setCursor(false)
  while isResizekey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.getKey):
    status.resize(terminalHeight(), terminalWidth())
    status.update
    setCursor(false)

  status.bufStatus[currentBufferIndex].currentLine = tmpCurrentLine

proc changeSortBy(filerStatus: var FilerStatus) =
  case filerStatus.sortBy:
  of name: filerStatus.sortBy = fileSize
  of fileSize: filerStatus.sortBy = time
  of time: filerStatus.sortBy = name

  filerStatus.dirlistUpdate = true

proc searchFileMode(status: var EditorStatus, filerStatus: var FilerStatus) =
  filerStatus.searchMode = true
  filerStatus.dirList = searchFiles(status, filerStatus.dirList)
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].currentLine = 0
  filerStatus.viewUpdate = true
  if filerStatus.dirList.len == 0:
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.erase
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.write(0, 0, "not found", EditorColorPair.commandBar)
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.refresh
    discard getKey(status.commandWindow)
    status.commandWindow.erase
    status.commandWindow.refresh
    filerStatus.dirlistUpdate = true

proc filerMode*(status: var EditorStatus) =
  var filerStatus = initFilerStatus()
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  while status.bufStatus[currentBufferIndex].mode == Mode.filer:
    if filerStatus.dirlistUpdate:
      filerStatus = updateDirList(filerStatus)
      status.bufStatus[currentBufferIndex].currentLine = 0

    if filerStatus.viewUpdate: updateFilerView(status, filerStatus)

    setCursor(false)
    let key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    status.bufStatus[currentBufferIndex].buffer.beginNewSuitIfNeeded
    status.bufStatus[currentBufferIndex].tryRecordCurrentPosition
    
    if key == ord(':'): status.changeMode(Mode.ex)

    elif isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
      filerStatus.viewUpdate = true

    elif key == ord('/'): searchFileMode(status, filerStatus)

    elif isEscKey(key):
      if filerStatus.searchMode == true:
        filerStatus.dirlistUpdate = true
        filerStatus.searchMode = false
    elif key == ord('D'):
      deleteFile(status, filerStatus)
    elif key == ord('i'):
      writeFileDetail(status, filerStatus.dirList.len, filerStatus.dirList[status.bufStatus[currentBufferIndex].currentLine][1])
      filerStatus.viewUpdate = true
    elif key == 'j' or isDownKey(key):
      keyDown(filerStatus, status.bufStatus[currentBufferIndex].currentLine)
    elif key == ord('k') or isUpKey(key):
      keyUp(filerStatus, status.bufStatus[currentBufferIndex].currentLine)
    elif key == ord('g'):
      moveToTopOfList(filerStatus, status.bufStatus[currentBufferIndex].currentLine)
    elif key == ord('G'):
      moveToLastOfList(filerStatus, status.bufStatus[currentBufferIndex].currentLine)
    elif key == ord('y'):
      copyFile(filerStatus, status.bufStatus[currentBufferIndex].currentLine)
    elif key == ord('C'):
      cutFile(filerStatus, status.bufStatus[currentBufferIndex].currentLine)
    elif key == ord('p'):
      pasteFile(status.commandWindow, filerStatus, status.messageLog)
    elif key == ord('s'):
      changeSortBy(filerStatus)
    elif key == ord('N'):
      createDir(status, filerStatus)
    elif isControlJ(key):
      movePrevWindow(status)
    elif isControlK(key):
      moveNextWindow(status)
    elif isEnterKey(key):
      openFileOrDir(status, filerStatus)
