##
##	GetMsSqlDump
##	Project site: http://getmssqldump.codeplex.com/
##	Homepage : http://blog.rollback.hu
##	
##	version 0.3, release candidate
##	Bitemo, Erik Gergely, Licensed under the Ms-RL (Microsoft Reciprocal License)

param (
$server = "localhost",
$db = "",
$table = "",
$query = "",
$username = "",
$password = "",
$file = "",
$dateformat = "yyyy-MM-dd HH:mm:ss.FF",
[switch]$append = $false,
[switch]$Overwrite = $false,
[switch]$noidentity = $false,
[switch]$debug = $false,
[switch]$help = $false
) # param


function ShowHelp {

# Prints help

@"
GetMsSqlDump v0.3 - A dumping tool for Microsoft SQL Servers, 
by <Bitemo, Erik Gergely>, 2009 http://blog.rollback.hu 

Usage: 
(powershell) GetMsSqlDump.ps1 [-server servername] [-db dbname] 
	-table tablename -query query [-username username -password password] 
	[-file filename] [-dateformat dateformat]
	[-append] [-noidentity] [-debug] [-help] [-?]

Parameters:
Name		Description					Default
servername      Name of database server to connect, port	localhost
		other than 1433 should be added with a comma
		(e.g. SQL01,1435)
dbname		Name of the database to read from. If missing,	[no default]
		the user's default database will be used.
tablename	Name of table(s) to dump. * can be used as      [no default]
		wildcard. Note  that the schema is part of
		the name.
query		Custom query submitted. 						[no default]
		Put it into double quotes. The insert commands will target
		the tablename specified in the tablename parameter.
username	SQL login name if SQL authentication is used	[no default]
		If no value given, Windows integrated
		authentication will be used.
password	Password of the SQL login above.		[no default]
filename	Destination of the dump. If omitted, dump will  [no default]
		be redirected to stdout.
dateformat	Format of datetime fields in tables. For  yyyy-MM-dd HH:mm:ss.FF
		details please refer to the detailed 
		help or MSDN "Custom DateTime Format Strings"
-append		If present, dump will be appended to the file
		specified by filename.
-noidentity	If present, identity values won't be dumped.
-debug		Prints way more characters to your screen than
		you'd like to.
-help		Prints this short help. Ignores all other 
		parameters.
-?		Just like help, as long as it is the only 
		parameter
"@
} # function ShowHelp


function debugw ($message, $print=1) {

# prints detailed info
# $print is parameter for development phase to enable/disable messages

 if ($debug -and $print) 
    {$message}
} # function debugw


function FieldToString ($row, $column){

# formats the cell in parameter into a string, based on its type
# this should be optimized for perfomance yet

 $thestring = ""
 if (@("System.String", "System.Boolean", "System.Char", "System.Guid", "System.Datetime") -contains $column.Datatype ) 
    {$quote = "'"}
 else
    {$quote = ""}

 if ($row.IsNull($column)) 
    {$thestring = 'NULL'}
 elseif ([string] $column.DataType -eq "System.DateTime")
    {
    $thestring = $quote + $row[$column].ToString($dateformat) + $quote
    }
 else 
    {$thestring = $quote + ([string] $row[$column] -replace "'","''") + $quote}

 $thestring
} # function FieldToString


function BuildConnectionString ($server, $db, $username, $password) {

# creates the connectionstring from the input parameters

 $connStr = "Data Source=$server;"
 if ($db) 
    { $connStr += "Initial Catalog=$db;"}
 if ($username) 
    {$connStr += "User ID=$username;Password=$password;"}
 else 
    {$connStr += "Integrated Security=SSPI;"}

 $connStr
} # function BuildConnectionString 


function WriteLine($line, $file) {

# Writes an insert command to the specified destination

 if (!$file)
    {$line}
 else 
    {
    $line | Out-File -FilePath $file -Append
    }
} # function WriteLine

##############

function BuildTableList($table, $connStr) {
#
# Retrieve list of tables to be scripted
#

 $table = $table -replace "\*","%"

	## 0.2 improvement: wildcard handling for all SQL versions
	$query = "if (cast(cast(serverproperty('productversion') as nvarchar(2)) as float) < 9) -- pre-SQL2005
	begin
	select o.xtype, u.name + '.' + o.name  oname
	from sysobjects o
	join sysusers u
	on o.uid = u.uid
	where o.xtype = 'U'
	and u.name + '.' + o.name like '" + $table + "'
	end
	else
	begin
	select s.name + '.' + t.name tname from sys.tables t join sys.schemas s
	on t.schema_id = s.schema_id
	where t.is_ms_shipped = 0
	and s.name + '.' + t.name like '" + $table + "'
	end"

 $conn = New-Object System.Data.SqlClient.SqlConnection $connStr
 $conn.Open()
 $cmd = New-Object System.Data.SqlClient.SqlCommand $query, $conn
 $adapter = New-Object System.Data.SqlClient.SqlDataAdapter
 $ds = New-Object System.Data.DataSet 
 $adapter.Selectcommand = $cmd
 $adapter.Fill($ds) | Out-Null
 $tables = @()
 foreach($t in $ds.Tables)
    {
    foreach ($row in $t.Rows)
        {
        $tables += $row["tname"]
        }
    }
 $ds.Dispose()
 $cmd.Dispose()
 $adapter.Dispose()
 $conn.Close()
 $tables
} # function BuildTableList

##	END OF FUNCTIONS
##
###########################################################################
##
##
##	SCRIPT BODY STARTS HERE
##

## To provide duration info -debug
$start = Get-Date

## Help and exit
if ($help -or !$table -or ($args.count -eq 1 -and $args[0] -eq "-?"))
	{
	ShowHelp
	Exit
	}

if ($append -and $overwrite)
## This combo makes no sense, commiting suicide...
	{
	Write-Error "You can't specify both -Append and -Overwrite. Remove one of them and rerun the command"
	Exit
	}
if ($file)
    {
    ## Let's check for the file and scream if it exists. Oh, and commit suicide.
    if (!$overwrite -and !$append -and (Test-Path $file))
	{
	Write-Error "File $file already exists. 
	Please specify -Overwrite if you want to replace it or -Append if you want to
	add the dump to the end of the file."
	Exit
	}

    ## Let's initialize the file before we start working / check if we can use the file
    if ($append)
	{
	"" | Out-File $file -Append
	}
    else
	{
	"" | Out-File $file
	}
    }
		

$connString = BuildConnectionString $server $db $username $password
$conn = New-Object System.Data.SqlClient.SqlConnection $connString
   debugw ("Connection string is: " + $conn.ConnectionString)
$conn.Open()
   debugw ("Connection state is " + $conn.State + " (should be open)")
$cmd = New-Object System.Data.SqlClient.SqlCommand "", $conn
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$ds = New-Object System.Data.DataSet 
$adapter.SelectCommand = $cmd

   debugw "Building table list..."
#########

if ($query) {
if (!$table) {$table = 'Qry'}
} # if ($query)


##########


## IF we're using wildcards, we should pull out the table list
## otherwise we'll just create a single-element array

if ($table.Contains("*"))
	{
	$tables = BuildTableList $table $connString
	}
else
	{
	$tables = @($table)
	}
   debugw "The following table(s) will be dumped:"
   debugw $tables

## Loop through the collection of tables and do whatever must be done with them

foreach ($obj in $tables) 
	{

## construct the select query and issue the command 
## if we use a custom query, we'll use that for producing the data
	$command = "select * from " + $obj
	if ($query){$command = $query;}
	$adapter.SelectCommand.CommandText = $command
	$ds = New-Object System.Data.DataSet 
## fill the dataset
	$adapter.Fill($ds) | Out-Null 
## read the schema - needed for identity info
	$adapter.FillSchema($ds, "Mapped") | Out-Null


## We expect a single table in the collection - except for custom queries
## In case of multiple resultsets, we're going to incrementally rename them
$resultsets = 0
$originalobj = $obj
	foreach ($tbl in $ds.Tables) 
		{ 
## Every subsequent result set will be dumped as records in the table <table>_<resultset ordinal>
		if ($resultsets -gt 0) {$obj = "$($originalobj)_$($resultsets)"}
	WriteLine "" $file
	WriteLine "-- Table $obj  / scripted at $(Get-Date) on server $server, database $db" $file
	WriteLine "" $file

## Creating the first part of the insert statements
		$insertheader = "INSERT INTO " + $obj + "("

## we can't remove identity column if it's part of primary key
## so we remove the primary key first
		foreach ($col in $tbl.Columns)
			{
			if ($col.AutoIncrement -and $noidentity)
				{
				debugw "Removing identity column $col "
				$tbl.PrimaryKey = $null
				$tbl.Columns.Remove($col)
## break is recommended otherwise .NET would get angry that we changed the collection
## while it was being used - besides, maximum one identity is allowed per table
				break
				}
			}
		"Writing $obj... (" + $tbl.Rows.Count.ToString() + " rows)"
		foreach ($column in $tbl.Columns)
## add the colum names to the insert statement skeleton
			{
			$insertheader += $column.ColumnName + ", "
			}
		$insertheader = $insertheader -replace ", $", ") VALUES("
## let's start the real data extract, row by row
		foreach($row in $tbl.Rows)
			{
			$vals = ""
			foreach($column in $tbl.Columns)
				{
				$vals += (FieldToString $row $column) + ", "
			        }
			$vals = $insertheader + ($vals -replace ", $",")") 
			WriteLine $vals $file
			}
## increment the resultset counter
			$resultsets++
		} # foreach ($tbl in $ds.Tables)
## drop the dataset
	$ds.Dispose(); 
	} #foreach $obj in $tables

## Final cleanup
 $cmd.Dispose()
 $adapter.Dispose()
 $ds.Dispose()
 $conn.Close()

## print out runtime - debug
$run = (Get-Date) - $start
debugw "Load was $run" 
