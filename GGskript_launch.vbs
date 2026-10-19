' GGskript v2: start the control panel hidden (no console window)
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName) & "\"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "GGskript_gui.ps1""", 0, False
