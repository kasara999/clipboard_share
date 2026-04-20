[Setup]
AppName=ClipSync
AppVersion={#AppVersion}
AppPublisher=kasara
DefaultDirName={autopf}\ClipSync
DefaultGroupName=ClipSync
OutputDir=installer_output
OutputBaseFilename=ClipSync-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\clipboard_share.exe

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\ClipSync"; Filename: "{app}\clipboard_share.exe"
Name: "{commondesktop}\ClipSync"; Filename: "{app}\clipboard_share.exe"

[Run]
Filename: "{app}\clipboard_share.exe"; Description: "ClipSyncを起動"; Flags: nowait postinstall skipifsilent
