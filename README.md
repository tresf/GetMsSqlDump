# GetMsSqlDump [![Travis-CI](https://travis-ci.org/tresf/GetMsSqlDump.svg?branch=master)](https://travis-ci.org/tresf/GetMsSqlDump) [![AppVeyor](https://ci.appveyor.com/api/projects/status/ldh5em2kj2j1ftl4?svg=true)](https://ci.appveyor.com/project/tresf/getmssqldump)
A mysqldump-like tool for Microsoft SQL Server by Bitemo, Erik Gergely, Tres Finocchiaro

[Click here to download.](https://github.com/tresf/GetMsSqlDump/archive/master.zip)

## Quick Reference

```ps1
.\GetMsSqlDump.ps1 [-server servername] [-db dbname]
   -table tablename [-query "customquery"] [-username username -password password]
   [-file filename] [-dateformat dateformat]
   [-append] [-noidentity] [-debug] [-help] [-?]
```

## Description

This is a tool which enables you to dump the content of one or more tables into a text file in the form of INSERT INTO statements, allowing you to archive/transfer/review/modify the data in an easy and convenient way.


## Parameters

All parameters **must** be prefixed with a single hyphen.  e.g. `-server sql1`.

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `server` |	Name of database server to connect, port other than 1433 should be added with a comma (e.g. SQL01,1435). At the moment, protocols cannot be specified | `localhost` |
| `db` | Name of the database to connect to. If missing, the user's default database will be used | N/A |
| `table` | Name of table(s) to dump. You can use the `*` (asterisk) as wildcard which will be translated into the `%` wildcard during pattern matching. Note that the schema (or owner in pre-SQL 2005 versions) is part of the name. Wildcards work with pre-SQL 2005 versions now. If you want to dump all the tables, just type a `*`. If you use a custom query, tablename will be the name of the new pseudo-table the insert commands will target. | N/A |
| `query` | An arbitrary SQL query which returns one or more result set(s). In case of multiple result sets the first result set will get the name specified by the `–table` parameter, the subsequent ones will get the specified name suffixed by an underscore and the 0-based ordinal of the result set. That is, if you specified tbl as the table name and you have 3 result sets, they’ll be called tbl, `tbl_1` and `tbl_2`. If you don’t specify a tablename, the built-in default is Qry. If you don’t specify column names for computed columns, they’ll get the name column`<ordinal>` name where `<ordinal>` shows the ordinal of the column among the unnamed columns. | N/A |
| `username` |	SQL login name if SQL authentication is used. If no value given, Windows integrated authentication will be used and the password parameter will be ignored. | N/A |
| `password` | Password of the SQL login specified in the username parameter. If no username was specified, this parameter will be ignored. | N/A |
| `file` |		Destination of the dump file. If omitted, dump will be redirected to stdout. If the file already exists, either the [`append` or the `overwrite` switch](#switches) should be specified. Submitting both switches results in script abortion to avoid ambiguous situations and unintentional data loss. | N/A |
| `dateformat` | Format of datetime fields in tables. For all the options please refer to the MSDN “Custom DateTime Format Strings" on the web. For basic tutorial, go down to the dateformat options section. | `yyyy-MM-dd HH:mm:ss.FF`|

### Switches
Switches are Boolean parameters without arguments, if they present, their value will be true.

All switched **must** be prefixed with a single hyphen.  e.g. `-append -overwrite -debug`.

| Switch | Description |
|--------|-------------|
| `append` |	Dump will be appended to the file specified by file parameter. |
| `overwrite` | Dump will overwrite the file specified by file parameter. |
| `noidentity` | Identity values won't be dumped. This way you can add the rows to a table with the same identity column specification. If no identity column exists in the table, the switch will be ignored. |
| `allowdots` | Disable the replacement of dots `.` in a table name with underscores `_`. |
| `pointfromtext` | Use PointFromText attempts to convert `SqlGeography` `POINT(x y)` values using `PointFromText('POINT(x y)')` WKT (well-known-text) conversion |
| `debug` |	Prints way more characters to your screen than you'd like to. If something didn’t work in the way you expected, or you want to submit a bug, run your statement with the debug switch. |
| `version` |	Prints the version information and exits. |
| `help` or `?` |	Prints this short help. Ignores all other parameters. |

## Examples

### Example 1

Dump the content of the **table** `Person.Address` (omitting the identity column) from the **db** `AdventureWorks` on **server** `SQL01` and will write it into the **file** `C:\Documents\Address.sql`. If the file already exists, it will be **overwritten** and all of its content will be lost.

```ps1
.\GetMsSqlDump.ps1 -server SQL01 -db AdventureWorks –table Person.Address –file C:\Documents\Address.sql –overwrite –noidentity
```

* #### Shorthand
   * Same thing as [Example 1](#example_1), but a uses a shorthand techique. In PowerShell, you must specify just enough characters from the parameter name to make it unambiguous for the shell. You can even omit the parameter names if you specified all the parameters in the expected order.
   ```ps1
   .\GetMsSqlDump.ps1 -s SQL01 -d AdventureWorks -t Person.Address -f C:\Documents\Address.sql -o -n
   ```

### Example 2
Dump all the **tables** under the `Person` schema in SQL 2005 and above.
**Warning:** Inconsistent behavior.  Dumps the **tables** owned by the `Person` user in SQL 2000 and below.

```ps1
GetMsSqlDump.ps1 -server SQL01 -db AdventureWorks –table Person.* –file C:\Documents\PersonSchema.sql –overwrite –noidentity
```

### Example 3
Run the specified query and save its result as an dump file like above but as `INSERT` commands into the `CustomTable` table.

```ps1
GetMsSqlDump.ps1 -server SQL01 -db AdventureWorks –table CustomTable –query “select top 100 contactID, FirstName, MiddleName, LastName from Person.Contact” –file C:\Documents\PersonSchema.sql –overwrite –noidentity
```

## Additional information

### Default parameters
All the parameter defaults can be set at the very beginning of the script.

### Dateformat options
The dateformat string can be built from strings specifying the formatting of individual dateparts. The string **is case sensitive**, for example `m` is for minute and `M` is for Month.

| Unit | Code | Description | Format | Notes |
|------|------|-------------|--------|-------|
| Year | `y`  | Year | `y\|yy\|yyy\|yyyy` | |
| Month | `M` | Month as number or name, depending | `M\|MM\|MMM\|MMMM` | `MMM`	is abbreviated month name. `MMMM` is full month name |
| Day | `d` | Day | `d\|dd\|ddd\|dddd` | `dd` is 01-31. `ddd` is day name abbreviated. `dddd` is full day name |
| Hour | `h` | Hour | `h\|hh` | `hh` is 01-12 |
| Hour | `H` | Hour in 24-hour format | `H\|HH` | `H` is 0-23. `HH` is 00-23 |
| AM/PM | `t` | AM or PM | `t\|tt` | `t` is A or P.  `tt` is AM or PM |
| Minute | `m` | Minute | `m\|mm` | `m` is 0-59.  `mm` is `00-59` |
| Second | `s` | Second |  `s\|ss` | `s` is 0-59.  `ss` is `00-59` |
| Fragment | `f` | Fragment seconds **with** trailing zeros | `f\|ff\|fff\|ffff` |
| Fragment | `F` | Fragment seconds **without** trailing zeros | `F\|FF\|FFF\|FFFF` |
| Timezone | `z` | Timezone information | `z\|zz\|zzz` | `z` and `zz` are hours only. `zzz` is hours:minutes. |
