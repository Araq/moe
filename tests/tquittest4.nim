import unittest
import moepkg/editorstatus, moepkg/unicodeext, moepkg/exmode

test "All buffer quit command":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.verticalSplitWindow
  status.resize(100, 100)

  const command = @[ru"qa"]
  status.exModeCommand(command)
