USE [master]
RESTORE DATABASE [WideWorldImporters] FROM 
DISK = N'C:\WideWorldImporters\WideWorldImporters-Standard.bak' WITH
MOVE N'WWI_Primary' TO N'C:\WideWorldImporters\WideWorldImporters.mdf',  
MOVE N'WWI_UserData' TO N'C:\WideWorldImporters\WideWorldImporters_UserData.ndf',  
MOVE N'WWI_Log' TO N'C:\WideWorldImporters\WideWorldImporters.ldf'
GO
