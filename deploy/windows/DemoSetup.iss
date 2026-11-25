[Setup]
AppId=TradoCraftDemo
AppName=TradoCraft Demo
AppVersion={#MyVersion}
DefaultDirName={localappdata}\Programs\TradoCraft Demo
DefaultGroupName=TradoCraft Demo
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=tradocraft-demo-windows-x64-setup
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\Start TradoCraft Demo.exe

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Start TradoCraft Demo"; Filename: "{app}\Start TradoCraft Demo.exe"
Name: "{group}\Reset TradoCraft Demo"; Filename: "{app}\Start TradoCraft Demo.exe"; Parameters: "--reset"
