' =====================================================================
' Portable Silent Launcher for WatchAndUpload.ps1
' Automatically discovers script path and launches hidden in background
' =====================================================================
Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Find current folder dynamically
currentFolder = fso.GetParentFolderName(WScript.ScriptFullName)
ps1Path = currentFolder & "\WatchAndUpload.ps1"

If Not fso.FileExists(ps1Path) Then
    MsgBox "Could not find WatchAndUpload.ps1 in: " & vbCrLf & currentFolder, vbCritical, "Error"
    WScript.Quit 1
End If

' Use pwsh.exe if available, otherwise powershell.exe
psExe = "powershell.exe"
If fso.FileExists(WshShell.ExpandEnvironmentStrings("%ProgramFiles%\PowerShell\7\pwsh.exe")) Then
    psExe = "pwsh.exe"
End If

command = psExe & " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1Path & """"
WshShell.Run command, 0, False
