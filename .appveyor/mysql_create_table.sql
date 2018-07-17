CREATE DATABASE WideWorldImporters;

USE WideWorldImporters;

CREATE TABLE Sales_Customers (
	CustomerID int NOT NULL PRIMARY KEY,
	CustomerName nvarchar(100) NOT NULL,
	BillToCustomerID int NOT NULL,
	CustomerCategoryID int NOT NULL,
	BuyingGroupID int,
	PrimaryContactPersonID int NOT NULL,
	AlternateContactPersonID int,
	DeliveryMethodID int NOT NULL,
	DeliveryCityID int NOT NULL,
	PostalCityID int NOT NULL,
	CreditLimit decimal(18,2),
	AccountOpenedDate date NOT NULL,
	StandardDiscountPercentage decimal(18,3) NOT NULL,
	IsStatementSent boolean NOT NULL,
	IsOnCreditHold boolean NOT NULL,
	PaymentDays int NOT NULL,
	PhoneNumber nvarchar(20) NOT NULL,
	FaxNumber nvarchar(20) NOT NULL,
	DeliveryRun nvarchar(5),
	RunPosition nvarchar(5),
	WebsiteURL nvarchar(256) NOT NULL,
	DeliveryAddressLine1 nvarchar(60) NOT NULL,
	DeliveryAddressLine2 nvarchar(60),
	DeliveryPostalCode nvarchar(10) NOT NULL,
	DeliveryLocation geometry,
	PostalAddressLine1 nvarchar(60) NOT NULL,
	PostalAddressLine2 nvarchar(60),
	PostalPostalCode nvarchar(10) NOT NULL,
	LastEditedBy int NOT NULL,
	ValidFrom datetime NOT NULL,
	ValidTo datetime NOT NULL
);
