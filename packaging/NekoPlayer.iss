#ifndef Payload
 #error Payload required
#endif
#ifndef Destination
 #error Destination required
#endif
[Setup]
AppId={{43175CC1-9063-42A3-9F4E-53FE165B370A}
AppName=Neko Anime
AppVersion=0.3.1
AppVerName=Neko Anime 0.3.1 Stable
AppPublisher=SenpaiBorracho
DefaultDirName={localappdata}\Programs\Neko Anime
DefaultGroupName=Neko Anime
OutputDir={#Destination}
OutputBaseFilename=Neko_Anime_0.3.1_Stable_Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Neko_Anime_0.3.1_Stable.exe
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile=..\LICENSE
DisableProgramGroupPage=yes
CloseApplications=yes
CloseApplicationsFilter=neko_player_pc.exe,Neko_Anime_*.exe
[Languages]
Name: spanish; MessagesFile: compiler:Languages\Spanish.isl
[Tasks]
Name: desktopicon; Description: Crear acceso directo en el escritorio
[Files]
Source: {#Payload}\*; DestDir: {app}; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: {group}\Neko Anime 0.3.1 Stable; Filename: {app}\Neko_Anime_0.3.1_Stable.exe
Name: {autodesktop}\Neko Anime 0.3.1 Stable; Filename: {app}\Neko_Anime_0.3.1_Stable.exe; Tasks: desktopicon
[Run]
Filename: {app}\Neko_Anime_0.3.1_Stable.exe; Description: Abrir Neko Anime 0.3.1 Stable; Flags: postinstall nowait skipifsilent



