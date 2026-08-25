[Setup]
AppId={{DA3F45DE-00B2-4EFC-81B0-BA101DCA73E8}
AppName=AnimeWitcher
AppVersion={#AppVersion}
AppPublisher=AnimeWitcher
AppPublisherURL=https://github.com/Fares669/AnimeWitcher
AppSupportURL=https://github.com/Fares669/AnimeWitcher
AppUpdatesURL=https://github.com/Fares669/AnimeWitcher
DefaultDirName={autopf}\AnimeWitcher
DefaultGroupName=AnimeWitcher
DisableProgramGroupPage=yes
OutputBaseFilename=AnimeWitcher-Windows-{#AppArch}-Setup-{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\..\runner\resources\app_icon.ico
#if AppArch == "x64"
  ArchitecturesAllowed=x64compatible
  ArchitecturesInstallIn64BitMode=x64compatible
#else
  ArchitecturesAllowed={#AppArch}
  ArchitecturesInstallIn64BitMode={#AppArch}
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#AppDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AnimeWitcher"; Filename: "{app}\animewitcher.exe"
Name: "{autodesktop}\AnimeWitcher"; Filename: "{app}\animewitcher.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\animewitcher.exe"; Description: "{cm:LaunchProgram,AnimeWitcher}"; Flags: nowait postinstall skipifsilent
