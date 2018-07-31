#requires -version 2

<#
.SYNOPSIS
   GetMsSqlDump - A MySQL-like dumping tool for Microsoft SQL
.DESCRIPTION
   A MySQL-like dumping tool for Microsoft SQL
.LINK
   https://github.com/tresf/GetMsSqlDump
.PARAMETER server
   Name of database server to connect, port other than 1433 should be added with a comma (e.g. SQL01,1435)
.PARAMETER db
   Name of the database to connect to. If missing, the user's default database will be used
.PARAMETER table
   Name of table(s) to dump. You can use the * (asterisk) as wildcard which will be translated into the % wildcard during pattern matching.
.PARAMETER query
   An arbitrary SQL query which returns one or more result set(s)
.PARAMETER username
   SQL login name if SQL authentication is used. If no value given, Windows integrated authentication will be used.
.PARAMETER password
   SQL login password if SQL authentication is used and if -username is provided.
.PARAMETER file
   Destination of the dump file. If omitted, dump will be redirected to stdout.  See also -overwrite and -append.
.PARAMETER dateformat
   Format of datetime fields in tables (e.g. yyyy-MM-dd HH:mm:ss.FF)
.PARAMETER format
   Destination database dump format to influence platform-specific commands.  (e.g. mysql, mssql)
.PARAMETER buffer
   Number of records to hold in memory before writing to file, affects performance.
.PARAMETER append
   Appends output to the specified file.  Cannot be combined with -overwrite.
.PARAMETER overwrite
   Overwrites the specified -file.  Cannot be combined with -append.
.PARAMETER noidentity
   If present, identity values won't be written to the output.
.PARAMETER allowdots
   Allow dots in target table name/disables default behavior to replace dots with underscores.
.PARAMETER pointfromtext
   Attempts to convert SqlGeography POINT(x y) values using PointFromText() WKT (well-known-text) conversion
.PARAMETER noautocommit
   Instructs the dump file to commit all lines at once.  May speed up processing time.  Ignored if -format is not provided.
.PARAMETER condense
   Condense multiple INSERT INTO statements into single statements. Significant performance boost; debugging becomes difficult.
.PARAMETER lock
   Adds table lock instructions to the dump file
.PARAMETER debug
   Prints debug information for troubleshooting and debugging purposes
.PARAMETER version
   Prints the version information and exits
.PARAMETER help
   Prints this short help. Ignores all other parameters.  Also may use -?
.INPUTS
   None
.OUTPUTS
   stdout unless -file is provided.
.NOTES
  Version:        0.4.2
  Author:         Bitemo, Erik Gergely, Tres Finocchiaro
  Creation Date:  2018
  License:        Microsoft Reciprocal License (MS-RL)
.EXAMPLE
  .\GetMsSqlDump.ps1 -server SQL01 -db WideWorldImporters -table Sales.Customers -file ~\Sales.Customer.sql -overwrite -noidentity
#>

Param(
    [string]$server = "localhost",
    [string]$db = "",
    [string]$table = "",
    [string]$query = "",
    [string]$username = "",
    [string]$password = "",
    [string]$file = "",
    [string]$dateformat = "yyyy-MM-dd HH:mm:ss.FF",
    [string]$format = $null,
    [int]$buffer = 1024,
    [switch]$append = $false,
    [switch]$overwrite = $false,
    [switch]$noidentity = $false,
    [switch]$allowdots = $false,
    [switch]$pointfromtext = $false,
    [switch]$noautocommit = $false,
    [switch]$condense = $false,
    [switch]$lock = $false,
    [switch]$delete = $false,
    [switch]$debug = $false,
    [switch]$version = $false,
    [switch]$help = $false
)

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

# Halt on all exceptions
$ErrorActionPreference = "Stop"

#----------------------------------------------------------[Declarations]----------------------------------------------------------

# Thread mutex to prevent race condition with Out-File
$mtx = New-Object System.Threading.Mutex($false, "GetMsSqlDump")

# Prints $message to the console if $debug is enabled
# FIXME: Switch to Write-Verbose and $PSBoundParameters['Verbose'], first read https://stackoverflow.com/questions/44900568
function Debug($message) {
    if ($debug) {
        $message
    }
}

# FIXME: Mutex stub for non-Windows OS
if ($IsMacOS -or $IsLinux) {
    $mtx = New-Module -AsCustomObject -ScriptBlock {
        function WaitOne() {}
        function ReleaseMutex() {}
    }
}

#-----------------------------------------------------------[Functions]------------------------------------------------------------

# Formats the cell in parameter into a string, based on its type
# FIXME: Optimize for performance
function FieldToString($row, $column) {
    $thestring = ""
    if (@("System.String", "System.Boolean", "System.Char", "System.Guid", "System.Datetime") -contains $column.Datatype ) {
        $quote = "'"
    } elseif (@("string", "boolean", "char", "guid", "datetime") -contains $column.Datatype ) {
        $quote = "'"
    } else {
        $quote = ""
    }

    if ($row.IsNull($column)) {
        $thestring = 'NULL'
    } elseif (@("System.Datetime", "datetime") -contains $column.DataType) {
        $thestring = $row[$column].ToString($dateformat)
        # Prevent MySQL > 5.6.4 fractional rounding overflow
        if ($thestring -eq '9999-12-31 23:59:59.99') {
            $thestring = '9999-12-31 23:59:59.49'
        }
        $thestring = $quote + $thestring + $quote
    } else {
        $thestring = $quote + ([string] $row[$column] -replace "'", "''") + $quote
    }

    # Handle geographic data types
    if ($pointfromtext -and @("Microsoft.SqlServer.Types.SqlGeography", "sqlgeography") -contains $column.DataType) {
        $thestring = "PointFromText('" + $thestring + "')"
    }

    $thestring
}


# Creates an SqlClient connection string
function BuildConnectionString($server, $db, $username, $password) {
    $connstr = "Data Source=$server;"
    if ($db) {
        $connstr += "Initial Catalog=$db;"
    }

    if ($username) {
        $connstr += "User ID=$username;Password=$password;"
    } else {
        $connstr += "Integrated Security=SSPI;"
    }

    $connstr
}

# Appends $line to the specified $file, or to the screen if no $file is specified
function WriteLine($line, $file, $append = $true) {
    if (!$file) {
        $line
    } else {
        $mtx.WaitOne() | Out-Null
        if ($append) {
            $line | Out-File -Encoding utf8 -FilePath $file -Append
        } else {
            $line | Out-File -Encoding utf8 -FilePath $file
        }
        $mtx.ReleaseMutex() | Out-Null
    }
}

# Retrieve list of tables to be scripted
function BuildTableList($table, $connstr) {
    $table = $table -replace "\*", "%"

    # Fetch matching table(s) from schema
    $query = "
        IF ( Cast(Cast(Serverproperty('productversion') AS NVARCHAR(2)) AS FLOAT) < 9 )
            -- pre-SQL2005
            BEGIN
                SELECT o.xtype,
                    u.NAME + '.' + o.NAME oname
                FROM   sysobjects o
                    JOIN sysusers u
                        ON o.uid = u.uid
                WHERE  o.xtype = 'U'
                    AND u.NAME + '.' + o.NAME LIKE '" + $table + "'
            END
        ELSE
            BEGIN
                SELECT s.NAME + '.' + t.NAME tname
                FROM   sys.tables t
                    JOIN sys.schemas s
                        ON t.schema_id = s.schema_id
                WHERE  t.is_ms_shipped = 0
                    AND s.NAME + '.' + t.NAME LIKE '" + $table + "'
        END
    "

    $conn = New-Object System.Data.SqlClient.SqlConnection $connstr
    $conn.Open()
    $cmd = New-Object System.Data.SqlClient.SqlCommand $query, $conn
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter
    $ds = New-Object System.Data.DataSet
    $adapter.SelectCommand = $cmd
    $adapter.Fill($ds) | Out-Null
    $tables = @()
    foreach ($t in $ds.Tables) {
        foreach ($row in $t.Rows) {
            $tables += $row["tname"]
        }
    }
    $ds.Dispose()
    $cmd.Dispose()
    $adapter.Dispose()
    $conn.Close()
    $tables
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

# Get version information and exit
if ($version) {
    $output = Get-Help ($MyInvocation.MyCommand.Definition) -Full | Out-String -Stream | Select-String "Version:"
    ([string]$output).Split(":")[1].Trim()
    Exit 0
}

# Show help if insufficient parameters were provided
if (!$table -or $args[0] -eq "-?" -or ($args.Count -lt 1 -and $PSBoundParameters.Count -lt 1)) {
    Get-Help ($MyInvocation.MyCommand.Definition)
    Exit 2
}

# Avoid mutually exclusive switches
if ($append -and $overwrite) {
    Get-Help ($MyInvocation.MyCommand.Definition)
    Write-Error "You can't specify both -append and -overwrite. Remove one of them and rerun the command."
    Exit 2
}

# Avoid overwrite
if ($file -and !$overwrite -and !$append -and (Test-Path $file)) {
    Get-Help ($MyInvocation.MyCommand.Definition)
    Write-Error "File $file already exists. Please specify -overwrite if you want to replace it or -append if you want to add the dump to the end of the file."
    Exit 2
}

# Duration info for -debug flag
$start = Get-Date

# Initialize file
WriteLine "" $file $false

$connstring = BuildConnectionString $server $db $username $password
$conn = New-Object System.Data.SqlClient.SqlConnection $connstring

# Mask password from debug statements
Debug "Connection string is: $($conn.ConnectionString -replace ";Password=$password;",";Password=****;")"
$conn.Open()
Debug "Connection state is $($conn.State) (should be open)"
$cmd = New-Object System.Data.SqlClient.SqlCommand "", $conn
$adapter = New-Object System.Data.SqlClient.SqlDataAdapter
$ds = New-Object System.Data.DataSet
$adapter.SelectCommand = $cmd

Debug "Building table list..."
if ($query) {
    if (!$table) {
        $table = 'Qry'
    }
}

# If using wildcards, pull out the table list otherwise we'll just create a
# single-element array
if ($table.Contains("*")) {
    $tables = BuildTableList $table $connstring
} else {
    $tables = @($table)
}
Debug "The following table(s) will be dumped: $tables"

# Loop through the collection of tables
foreach ($obj in $tables) {
    # Construct the select query and issue the command
    # If we use a custom query, we'll use that for producing the data
    $command = "SELECT * FROM " + $obj
    if ($query) {
        $command = $query
    }

    Debug("   $command")
    $adapter.SelectCommand.CommandText = $command
    $ds = New-Object System.Data.DataSet

    # Fill the dataset
    $adapter.Fill($ds) | Out-Null

    # Read the schema (needed for identity info)
    $adapter.FillSchema($ds, "Mapped") | Out-Null

    # We expect a single table in the collection - except for custom queries
    # In case of multiple resultsets, incrementally rename them
    $resultsets = 0
    $originalobj = $obj

    # Strip dots from table names as they fail to import into MySQL
    if (!$allowdots) { $obj = $obj -replace "\.", "_" }

    foreach ($tbl in $ds.Tables) {
        # Every subsequent result set will be dumped as records in the table <table>_<resultset ordinal>
        if ($resultsets -gt 0) {
            $obj = "$($originalobj)_$($resultsets)"
        }

        WriteLine "" $file
        WriteLine "-- Table $obj  / scripted at $(Get-Date) on server $server, database $db" $file
        WriteLine "" $file

        if (!$format -and $noautocommit) {
            Write-Warning "Flag '`$noautocommit $noautocommit' was provided without specifying `$format.  Ignoring."
        }
        if (!$format -and $lock) {
            Write-Warning "Flag '`$lock $lock' was provided without specifying `$format.  Ignoring."
        }

        # Handle platform-specific statements
        $insertfooter = ""
        if ($format -eq "mysql") {
            # Handle deferred commits, improves performance
            if ($noautocommit) {
                WriteLine "SET autocommit=0;" $file
            }
            # Handle database locks for integrity
            if ($lock) {
                WriteLine "LOCK TABLES $obj WRITE;" $file
            }
        } elseif ($format -eq "mssql") {
            if ($noautocommit) {
                WriteLine "SET IMPLICIT_TRANSACTIONS ON;" $file
            }
            # Handle database locks for integrity
            if ($lock) {
                $insertfooter = " WITH (TABLOCKX)"
            }
        }

        # Handle delete flag
        if ($delete) {
            WriteLine "DELETE from $obj;" $file
        }

        # First part of the insert statements
        $insertheader = "INSERT INTO $obj ("

        # Can't remove identity column if it's part of primary key so remove
        # the primary key first
        foreach ($col in $tbl.Columns) {
            if ($col.AutoIncrement -and $noidentity) {
                Debug "Removing identity column $col"
                $tbl.PrimaryKey = $null
                $tbl.Columns.Remove($col)
                # Break to avoid changing collection mid-use; one identity
                # is allowed per table
                break
            }
        }

        $rows = $tbl.Rows.Count.ToString()
        "Writing $obj... ($rows rows)"

        # Add the column names to the insert statement skeleton
        foreach ($column in $tbl.Columns) {
            $insertheader += "$($column.ColumnName), "
            Debug "  $($column.ColumnName): $($column.DataType)"
        }
        $insertheader = $insertheader -replace ", $", ") VALUES("
        $terminator = "$insertfooter;"

        $linebuffer = New-Object System.Text.StringBuilder
        $linecount = 0
        # Start data extract, row by row
        foreach ($row in $tbl.Rows) {
            $vals = ""
            $linecount++
            foreach ($column in $tbl.Columns) {
                $vals += (FieldToString $row $column) + ", "
            }

            # Condense multiple INSERT INTO statements
            # - MSSQL limits this technique to 1000 rows at a time so we'll honor that for all engines
            # - MySQL limits this on buffer size, so in rare edge-cases 1000 may be too big
            $condensemax = 1000
            $rowheader = $insertheader
            if ($condense) {
                # Each condensed block must begin with "INSERT INTO ..."
                if ($linecount % $condensemax -eq 1) {
                    $rowheader = $insertheader
                } else {
                    $rowheader = "    ("
                }

                # Each condensed block must end with a semicolon ";"
                if ($linecount % $condensemax -eq 0 -or $linecount -eq $rows) {
                    $terminator = "$insertfooter;"
                } else {
                    $terminator = ","
                }
            }

            $vals = $rowheader + ($vals -replace ", $", ")$terminator")
            if (!$buffer) {
                WriteLine $vals $file
            } else {
                # Buffer the data to reduce number of calls to Out-File
                if ($linecount -eq 1) {
                    Debug "Writing using -buffer $buffer... ($rows remaining)..."
                }

                if ($linecount % $buffer -eq 0 -or $linecount -eq $rows) {
                    # Don't append newline, Out-File will do it automatically
                    $linebuffer.Append("$vals") | Out-Null
                    Debug "  Writing buffer at $linecount ($($rows - $linecount) remaining)"
                    WriteLine $linebuffer.toString() $file
                    $linebuffer.Clear() | Out-Null
                } else {
                    # Explicitly append newline
                    $linebuffer.AppendLine("$vals") | Out-Null
                }
            }
        }

        # Increment the resultset counter
        $resultsets++
        $linebuffer.Clear() | Out-Null
        $linecount = 0

        # Handle platform-specific statements
        if ($format -eq "mysql") {
            # Handle database locks
            if ($lock) {
                WriteLine "UNLOCK TABLES;" $file
            }
            # Handle deferred commits
            if ($noautocommit) {
                WriteLine "COMMIT;" $file
            }
        } elseif ($format -eq "mssql") {
            # Handle deferred commits
            if ($noautocommit) {
                WriteLine "COMMIT TRANSACTION;" $file
            }
            # Locks are automatically released in MSSQL
        }
    }
    # Drop the dataset
    $ds.Dispose()
}

# Final cleanup
$cmd.Dispose()
$adapter.Dispose()
$ds.Dispose()
$conn.Close()

# End duration info for -debug flag
$run = (Get-Date) - $start
Debug "Duration: $run"
