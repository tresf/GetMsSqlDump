$mysql_version = $args[0]
$mysql_service = $args[1]
replace_all.ps1 "C:\ProgramData\MySQL\MySQL Server $mysql_version\my.ini" "# enable-named-pipe" "enable-named-pipe"
Restart-Service $mysql_service
