import unittest
import moepkg/[filermode, editorstatus, ui, highlight, color]

test "Update directory list":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].mode = Mode.filer
  var filerStatus = initFilerStatus()
  filerStatus = filerStatus.updateDirList
  status.updateFilerView(filerStatus)

test "Check highlight in filer mode":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].mode = Mode.filer
  var filerStatus = initFilerStatus()
  filerStatus = filerStatus.updateDirList
  status.updateFilerView(filerStatus)

  check(status.bufStatus[0].highlight[0].color == EditorColorPair.currentFile)
