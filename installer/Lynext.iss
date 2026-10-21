; Lynext installer — requires Inno Setup 6 to build.
#define AppName "Lynext"
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#define AppPublisher "RyanGXD"
#define AppExeName "Lynext.exe"

[Setup]
AppId={{9D3B5E67-7A21-4E8A-9D54-41C10D9B3C20}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\Lynext
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\artifacts
OutputBaseFilename=Lynext-Setup-{#AppVersion}-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppExeName}
SetupLogging=yes

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos:"; Flags: unchecked

[Files]
Source: "..\artifacts\publish\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; CI publishes this helper before compiling the installer. Local builds without it remain installable but cannot self-update until the helper is included.
Source: "..\artifacts\updater-publish\Lynext.Updater.exe"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\Lynext"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\Lynext"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Abrir Lynext"; Flags: postinstall nowait skipifsilent; Check: not IsLynextUpdate

[Code]
function IsLynextUpdate: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/LYNEXTUPDATE=1') = 0 then
    begin
      Result := True;
      Exit;
    end;
end;
