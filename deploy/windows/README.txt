TradoCraft Demo for Windows x64

Extract the entire ZIP to a writable folder and open Start TradoCraft Demo.exe.
The setup EXE installs for the current user and creates Start menu shortcuts.
Choose a writable install or extraction path with ASCII characters only.
Spaces are supported. Avoid percent signs and exclamation marks in the path.
The demo uses fictitious data and runs on this PC without an internet connection.
Open Tutorial from the account menu to start the guided walkthrough.

Close the app to stop the local backend. Your work is kept in
%LOCALAPPDATA%\TradoCraft\Demo. Logs are in the logs folder there. Demo mail is
written to the instance\outbox folder. Uninstalling the application keeps your
demo data. To start over, close the demo and use Reset TradoCraft Demo from the
Start menu or open Reset TradoCraft Demo.cmd from the extracted folder.
Reset asks before erasing the demo database, files and local tutorial progress.

This release is for a single standard user on a Windows x64 PC. It uses local
demonstration sign-in and must stay on loopback. Do not put real data in it.

TradoCraft source and license: https://github.com/TradoCraft/TradoCraft


Release verification

Before the first public release, test both packages on a clean Windows 11 x64
machine using a standard account with networking disabled. Verify the UI opens
with tutorial data, quotation PDFs render, an order or stock action persists,
and a queued email appears in the local outbox. Relaunch, reinstall, and reset.
Check that the launcher and installer show no UAC prompt, and that stopping the
demo leaves no processes or ports behind. The build workflow tests the extracted
ZIP's API, migration, worker heartbeat, quotation PDF, persistence and reset.
