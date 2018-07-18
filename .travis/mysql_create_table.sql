CREATE DATABASE Northwinds;

USE Northwinds;

CREATE TABLE Orders (
	OrderID	int NOT NULL PRIMARY KEY,
	CustomerID varchar(5) NOT NULL,
	EmployeeID int NOT NULL,
	OrderDate datetime NOT NULL,
	RequiredDate datetime,
	ShippedDate datetime,
	ShipVia int NOT NULL,
	Freight	double default 0 NOT NULL,
	ShipName nvarchar(40) NOT NULL,
	ShipAddress nvarchar(60)	NOT NULL,
	ShipCity nvarchar(15)	NOT NULL,
	ShipRegion nvarchar(15),
	ShipPostalCode nvarchar(10),
	ShipCountry nvarchar(15)	NOT NULL
);
