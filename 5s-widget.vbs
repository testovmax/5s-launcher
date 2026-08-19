' 5s-widget.vbs - starts the 5S desktop widget silently, with no console window.
' Point the desktop / startup shortcut at THIS file.
Dim fso, here
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("Wscript.Shell").Run _
  "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\5s-widget.ps1""", 0, False
