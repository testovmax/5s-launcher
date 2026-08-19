' 5s-launcher.vbs - starts 5S Launcher silently, with no console window.
' Point the desktop shortcut at THIS file instead of 5s-launcher.ps1.
Dim fso, here
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("Wscript.Shell").Run _
  "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\5s-launcher.ps1""", 0, False
