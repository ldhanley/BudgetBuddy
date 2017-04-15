
declare @sql nvarchar(2000)

while(exists(select 1 from INFORMATION_SCHEMA.TABLE_CONSTRAINTS where CONSTRAINT_TYPE='FOREIGN KEY'))
begin
 SELECT TOP 1 @sql=('ALTER TABLE ' + TABLE_SCHEMA + '.[' + TABLE_NAME
 + '] DROP CONSTRAINT [' + CONSTRAINT_NAME + ']')
 FROM information_schema.table_constraints
 WHERE CONSTRAINT_TYPE = 'FOREIGN KEY'
 exec (@sql)
 PRINT @sql
end

while(exists(select 1 from INFORMATION_SCHEMA.TABLES 
             where TABLE_NAME != '__MigrationHistory' 
             AND TABLE_TYPE = 'BASE TABLE'))
begin
 SELECT TOP 1 @sql=('DROP TABLE ' + TABLE_SCHEMA + '.[' + TABLE_NAME  + ']')
 FROM INFORMATION_SCHEMA.TABLES
 WHERE TABLE_NAME != '__MigrationHistory' AND TABLE_TYPE = 'BASE TABLE' 
 exec (@sql)
 PRINT @sql
end

while(exists(select 1 from INFORMATION_SCHEMA.TABLES 
             where TABLE_SCHEMA = 'Budget'
             AND TABLE_TYPE = 'VIEW'))
begin
 SELECT TOP 1 @sql=('DROP VIEW ' + TABLE_SCHEMA + '.[' + TABLE_NAME  + ']')
 FROM INFORMATION_SCHEMA.TABLES
 WHERE TABLE_SCHEMA <> 'sys' AND TABLE_TYPE = 'VIEW'
exec (@sql)
 PRINT @sql
end

while(exists(select 1 from INFORMATION_SCHEMA.ROUTINES 
             where ROUTINE_SCHEMA = 'Budget'))
begin
 SELECT TOP 1 @sql=('DROP PROCEDURE ' + TABLE_SCHEMA + '.[' + TABLE_NAME  + ']')
 FROM INFORMATION_SCHEMA.ROUTINES
 WHERE ROUTINE_SCHEMA = 'Budget'
exec (@sql)
 PRINT @sql
end


----------------------------------------------------------------
-- Budget
----------------------------------------------------------------
IF NOT EXISTS (SELECT * FROM Sys.Schemas WHERE name = 'Budget')
BEGIN
	EXEC sp_executesql N'CREATE SCHEMA Budget';
END;

CREATE TABLE Budget.Budget (
	Budget VARCHAR(100) NOT NULL,
CONSTRAINT PK_Budget PRIMARY KEY
(
	Budget ASC
));


----------------------------------------------------------------
-- Budget Groupings and Categories
----------------------------------------------------------------

CREATE TABLE Budget.BudgetGrouping (
	Budget VARCHAR(100) NOT NULL,
	BudgetGrouping VARCHAR(100) NOT NULL,
CONSTRAINT PK_ExpenseGrouping PRIMARY KEY
(
	Budget ASC,
	BudgetGrouping ASC
));


CREATE TABLE Budget.BudgetCategory (
	Budget VARCHAR(100) NOT NULL,
	BudgetGrouping	VARCHAR(100) NOT NULL,
	BudgetCategory	VARCHAR(100) NOT NULL,
CONSTRAINT PK_BudgetCategory PRIMARY KEY
(
	Budget ASC,
	BudgetGrouping ASC,
	BudgetCategory ASC
));

----------------------------------------------------------------
-- BudgetAssessment
----------------------------------------------------------------
CREATE TABLE Budget.BudgetAssessment (
	Budget VARCHAR(100) NOT NULL REFERENCES Budget.Budget(Budget),
	BudgetAssessment DATETIMEOFFSET NOT NULL,
	BudgetAssessmentStartDate DATETIMEOFFSET NOT NULL,
	BudgetAssessmentEndDate DATETIMEOFFSET NOT NULL,
CONSTRAINT PK_BudgetAssessment PRIMARY KEY
(
	Budget ASC,
	BudgetAssessment ASC,
	BudgetAssessmentStartDate ASC,
	BudgetAssessmentEndDate ASC
));

-- CREATE PROCEDURE Budget.CreateBudgetAssessment
-- 

----------------------------------------------------------------
-- Accounts
--
-- AccountStatus can only be in Opened or Closed state
----------------------------------------------------------------
CREATE TABLE Budget.Account (
	Budget VARCHAR(100) NOT NULL REFERENCES Budget.Budget(Budget),
	Account VARCHAR(100) NOT NULL,
	AccountStatus VARCHAR(6) NOT NULL DEFAULT 'Opened' CONSTRAINT [Table Budget.Account column AccountStatus must be in (Opened, Closed)] CHECK (AccountStatus IN ('Opened', 'Closed')),
CONSTRAINT AK_Budget_Account_Status UNIQUE (
	Budget ASC,
	Account ASC,
	AccountStatus ASC
),
CONSTRAINT PK_Account PRIMARY KEY
(
	Budget ASC,
	Account ASC
));


-- Account: Opened Status State
CREATE TABLE Budget.AccountOpened (
	Budget VARCHAR(100) NOT NULL,
	Account VARCHAR(100) NOT NULL,
	AccountOpenedDate DATETIMEOFFSET NOT NULL DEFAULT GETDATE(),
	AccountStatus VARCHAR(6) NOT NULL DEFAULT 'Opened' CHECK (AccountStatus = 'Opened'),
CONSTRAINT FK_Budget_AccountOpened FOREIGN KEY (Budget, Account, AccountStatus)
	REFERENCES Budget.Account(Budget, Account, AccountStatus),
CONSTRAINT PK_Account_Opened PRIMARY KEY
(
	Budget ASC,
	Account ASC
));

-- Account: Closed Status state
CREATE TABLE Budget.AccountClosed (
	Budget VARCHAR(100) NOT NULL,
	Account VARCHAR(100) NOT NULL ,
	AccountOpenedDate DATETIMEOFFSET NOT NULL,
	AccountClosedDate DATETIMEOFFSET NOT NULL,
	AccountStatus VARCHAR(6) NOT NULL DEFAULT 'Closed' CHECK (AccountStatus = 'Closed'),
CONSTRAINT FK_Budget_AccountClosed FOREIGN KEY (Budget, Account, AccountStatus)
	REFERENCES Budget.Account(Budget, Account, AccountStatus),
CONSTRAINT PK_Account_Closed PRIMARY KEY
(
	Account ASC
));

-- Account: Deposit action
CREATE TABLE Budget.AccountDeposited (
	Budget VARCHAR(100) NOT NULL,
	Account VARCHAR(100) NOT NULL,
	AccountDepositedDate DATETIMEOFFSET NOT NULL,
	AccountDepositedAmount MONEY NOT NULL,
CONSTRAINT FK_Budget_AccountDeposited FOREIGN KEY (Budget, Account)
	REFERENCES Budget.Account(Budget, Account),
CONSTRAINT PK_Account_Deposited PRIMARY KEY
(
	Budget ASC,
	Account ASC,
	AccountDepositedDate ASC
));


-- Account: Withdrawal action
CREATE TABLE Budget.AccountWithdrawal (
	Budget VARCHAR(100) NOT NULL,
	Account VARCHAR(100) NOT NULL,
	AccountWithdrawalDate DATETIMEOFFSET NOT NULL,
	AccountWithdrawalAmount MONEY NOT NULL,
CONSTRAINT FK_Budget_AccountWithdrawal FOREIGN KEY (Budget, Account)
	REFERENCES Budget.Account(Budget, Account),
CONSTRAINT PK_Account_Withdrawal PRIMARY KEY
(
	Budget ASC,
	Account ASC,
	AccountWithdrawalDate ASC
));
GO

-- Account: Balance
CREATE TABLE Budget.AccountBalance (
	Budget VARCHAR(100) NOT NULL,
	Account VARCHAR(100) NOT NULL,
	AccountBalanceDate DATETIMEOFFSET NOT NULL DEFAULT GETDATE(),
	AccountBalanceAmount MONEY NOT NULL DEFAULT 0.00,
CONSTRAINT FK_Budget_AccountBalance FOREIGN KEY (Budget, Account)
	REFERENCES Budget.Account(Budget, Account),
CONSTRAINT PK_Account_Balance PRIMARY KEY
(
	Budget ASC,
	Account ASC,
	AccountBalanceDate ASC
));
GO

CREATE VIEW Budget.BudgetAssessmentAccount AS
SELECT a.Budget, b.Account, a.BudgetAssessment, a.BudgetAssessmentStartDate, a.BudgetAssessmentEndDate,
	(SELECT SUM(AccountBalanceAmount)
		FROM Budget.AccountBalance
		WHERE Budget = b.Budget AND Account = b.Account 
			AND AccountBalanceDate = (SELECT MIN(AccountBalanceDate) FROM Budget.AccountBalance 
				WHERE Budget = b.Budget AND Account = b.Account AND AccountBalanceDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate)) AS AccountBalanceStartAmount,
	(SELECT SUM(AccountBalanceAmount)
		FROM Budget.AccountBalance
		WHERE Budget = b.Budget AND Account = b.Account 
			AND AccountBalanceDate = (SELECT MAX(AccountBalanceDate) FROM Budget.AccountBalance 
				WHERE Budget = b.Budget AND Account = b.Account AND AccountBalanceDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate)) AccountBalanceEndAmount, 
	(SELECT SUM(AccountDepositedAmount)
		FROM Budget.AccountDeposited
		WHERE Budget = b.Budget AND Account = b.Account AND AccountDepositedDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS Deposited,
	(SELECT SUM(AccountWithdrawalAmount)
		FROM Budget.AccountWithdrawal
		WHERE Budget = b.Budget AND Account = b.Account AND AccountWithdrawalDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS Withdrawn
FROM Budget.BudgetAssessment a
	LEFT JOIN Budget.Account b ON b.Budget = a.Budget -- ALso check to see if account is closed?
GO


CREATE PROCEDURE Budget.AccountOpen
	@Budget VARCHAR(100),
	@Account VARCHAR(100),
	@AccountBalanceAmount MONEY = 0
AS
BEGIN
	SET NOCOUNT ON

	INSERT INTO Budget.Account(Budget, Account)
	VALUES (@Budget, @Account);

	INSERT INTO Budget.AccountOpened(Budget, Account)
	VALUES (@Budget, @Account);

	INSERT INTO Budget.AccountBalance(Budget, Account, AccountBalanceAmount)
	VALUES (@Budget, @Account, @AccountBalanceAmount);
END;


----------------------------------------------------------------
-- Income
----------------------------------------------------------------
CREATE TABLE Budget.Income (
	Budget VARCHAR(100) NOT NULL REFERENCES Budget.Budget(Budget),
	Income VARCHAR(100) NOT NULL,
	IncomeSchedule VARCHAR(20) CONSTRAINT [Table Budget.Income column IncomeSchedule must be in (SalaryBiWeekly, HourlyBiWeekly)] CHECK (IncomeSchedule IN ('SalaryBiWeekly', 'HourlyBiWeekly')),
CONSTRAINT AK_Budget_Income_Schedule UNIQUE (
	Budget ASC,
	Income ASC,
	IncomeSchedule ASC
),
CONSTRAINT PK_Income PRIMARY KEY
(
	Budget ASC,
	Income ASC
));

-- Estimated: Future Income assumption
CREATE TABLE Budget.IncomeSalaryBiWeekly (
	Budget VARCHAR(100) NOT NULL,
	Income VARCHAR(100) NOT NULL,
	IncomeSalaryBiWeeklyFirstPayDate DATE NOT NULL,
	IncomeSalaryBiWeeklyFinalPayDate DATE NOT NULL,
	IncomeSalaryBiWeeklyAmount MONEY NOT NULL,
	IncomeSchedule VARCHAR(20) CONSTRAINT [Table Budget.Income column IncomeSchedule must be SalaryBiWeekly] CHECK (IncomeSchedule = 'SalaryBiWeekly'),
CONSTRAINT FK_Budget_IncomeSalaryBiWeekly FOREIGN KEY (Budget, Income, IncomeSchedule)
	REFERENCES Budget.Income(Budget, Income, IncomeSchedule),
CONSTRAINT PK_IncomeSalaryBiWeekly PRIMARY KEY
(
	Budget ASC,
	Income ASC,
	IncomeSalaryBiWeeklyFirstPayDate ASC
));

CREATE TABLE Budget.IncomeHourly (
	Budget VARCHAR(100) NOT NULL,
	Income VARCHAR(100) NOT NULL,
	IncomeHourlyPerHourAmount MONEY NOT NULL,
	IncomeSchedule VARCHAR(20) CONSTRAINT [Table Budget.Income column IncomeSchedule must be HourlyBiWeekly] CHECK (IncomeSchedule = 'HourlyBiWeekly'),
CONSTRAINT FK_Budget_IncomeHourly FOREIGN KEY (Budget, Income, IncomeSchedule)
	REFERENCES Budget.Income(Budget, Income, IncomeSchedule),
CONSTRAINT PK_IncomeHourly PRIMARY KEY
(
	Budget ASC,
	Income ASC,
	IncomeHourlyPerHourAmount ASC
));

CREATE TABLE Budget.IncomeHourlyEstimatedHours (
	Budget VARCHAR(100) NOT NULL,
	Income VARCHAR(100) NOT NULL,
	IncomeHourlyPerHourAmount MONEY NOT NULL,
	IncomeHourlyEstimatedHoursPayDate DATE NOT NULL,
CONSTRAINT FK_IncomeHourlyEstimatedHours_IncomeHourly FOREIGN KEY (Budget, Income, IncomeHourlyPerHourAmount)
	REFERENCES Budget.IncomeHourly(Budget, Income, IncomeHourlyPerHourAmount),
CONSTRAINT PK_IncomeHourlyEstimatedHours PRIMARY KEY
(
	Budget ASC,
	Income ASC,
	IncomeHourlyPerHourAmount ASC,
	IncomeHourlyEstimatedHoursPayDate ASC
));

-- Actuals: Pay statement amounts (money deposited into account)
CREATE TABLE Budget.IncomeActual (
	Budget VARCHAR(100) NOT NULL,
	Income VARCHAR(100) NOT NULL,
	IncomeActualDate DATE NOT NULL,
	IncomeActualAmount MONEY NOT NULL,
CONSTRAINT FK_Budget_IncomeActual FOREIGN KEY (Budget, Income)
	REFERENCES Budget.Income(Budget, Income),
CONSTRAINT PK_IncomeActual PRIMARY KEY
(
	Budget ASC,
	Income ASC,
	IncomeActualDate ASC
));


GO

CREATE VIEW Budget.BudgetAssessmentIncome AS
SELECT a.Budget, b.Income, a.BudgetAssessment, a.BudgetAssessmentStartDate, a.BudgetAssessmentEndDate,
	--(SELECT SUM(AccountDepositedAmount)
	--	FROM Budget.IncomeHourly
	--	WHERE Budget = b.Budget AND Account = b.Account AND AccountDepositedDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate)
	--+ (SELECT SUM(AccountDepositedAmount)
	--	FROM Budget.AccountDeposited
	--	WHERE Budget = b.Budget AND Account = b.Account AND AccountDepositedDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate)
	--+ (SELECT SUM(AccountDepositedAmount)
	--	FROM Budget.AccountDeposited
	--	WHERE Budget = b.Budget AND Account = b.Account AND AccountDepositedDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate)
	0 AS IncomeEstimatedAmount,

	(SELECT SUM(IncomeActualAmount)
		FROM Budget.IncomeActual
		WHERE Budget = b.Budget AND Income = b.Income AND IncomeActualDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS IncomeActualAmount
FROM Budget.BudgetAssessment a
	LEFT JOIN Budget.Income b ON b.Budget = a.Budget -- ALso check to see if account is closed?
GO


----------------------------------------------------------------
-- Assets
----------------------------------------------------------------
CREATE TABLE Budget.Asset (
	Budget VARCHAR(100) NOT NULL,
	Asset VARCHAR(100) NOT NULL,
	AssetPurchaseDate DATE NOT NULL,
	AssetPrice MONEY NOT NULL,
CONSTRAINT PK_Asset PRIMARY KEY
(
	Budget ASC,
	Asset ASC
));

-- Estimated Sale Amount
CREATE TABLE Budget.AssetEstimateSaleValue (
	Budget VARCHAR(100) NOT NULL,
	Asset VARCHAR(100) NOT NULL,
	AssetEstimatedSaleValueDate DATE NOT NULL,
	AssetEstimatedSaleAmount MONEY NOT NULL,
CONSTRAINT FK_Budget_AssetEstimateSaleValue FOREIGN KEY (Budget, Asset)
	REFERENCES Budget.Asset(Budget, Asset),
CONSTRAINT PK_AssetEstimateSaleValue PRIMARY KEY
(
	Budget ASC,
	Asset ASC,
	AssetEstimatedSaleValueDate ASC
));

GO

-- Controls
CREATE VIEW Budget.BudgetAssessmentAsset AS
SELECT a.Budget, b.Asset, a.BudgetAssessment, a.BudgetAssessmentStartDate, a.BudgetAssessmentEndDate,
	(SELECT MIN(AssetEstimatedSaleAmount)
		FROM Budget.AssetEstimateSaleValue
		WHERE Budget = b.Budget AND Asset = b.Asset AND AssetEstimatedSaleValueDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS AssetEstimatedValueAmount
FROM Budget.BudgetAssessment a
	LEFT JOIN Budget.Asset b ON b.Budget = a.Budget -- ALso check to see if account is closed?
GO


----------------------------------------------------------------
-- Debts
----------------------------------------------------------------

CREATE TABLE Budget.Debt (
	Budget VARCHAR(100) NOT NULL,
	Debt VARCHAR(100) NOT NULL,
	DebtCompounding VARCHAR(10) CONSTRAINT [Table Budget.Debt column DebtCompounding must be in (Daily, Monthly)] CHECK (DebtCompounding IN ('Daily', 'Monthly')),
CONSTRAINT AK_Budget_Debt_Compounding UNIQUE (
	Budget ASC,
	Debt ASC,
	DebtCompounding ASC
),
CONSTRAINT PK_Debt PRIMARY KEY
(
	Budget ASC,
	Debt ASC
));

CREATE TABLE Budget.DebtDailyCompounding (
	Budget VARCHAR(100) NOT NULL,
	Debt VARCHAR(100) NOT NULL,
	AnnualInterestRate DECIMAL(6, 4) NOT NULL,
	DebtCompounding VARCHAR(10) CONSTRAINT [Table Budget.DebtDailyCompounding column DebtCompounding must be Daily)] CHECK (DebtCompounding = 'Daily'),
CONSTRAINT FK_Budget_DebtDailyCompounding FOREIGN KEY (Budget, Debt, DebtCompounding)
	REFERENCES Budget.Debt(Budget, Debt, DebtCompounding),
CONSTRAINT PK_DebtDailyCompounding PRIMARY KEY
(
	Budget ASC,
	Debt ASC
));

CREATE TABLE Budget.DebtMonthlyCompounding (
	Budget VARCHAR(100) NOT NULL,
	Debt VARCHAR(100) NOT NULL,
	AnnualInterestRate DECIMAL(6, 4) NOT NULL,
	DebtCompounding VARCHAR(10) CONSTRAINT [Table Budget.DebtMonthlyCompounding column DebtCompounding must be Monthly] CHECK (DebtCompounding = 'Monthly'),
CONSTRAINT FK_Budget_DebtMonthlyCompounding FOREIGN KEY (Budget, Debt, DebtCompounding)
	REFERENCES Budget.Debt(Budget, Debt, DebtCompounding),
CONSTRAINT PK_DebtMonthlyCompounding PRIMARY KEY
(
	Budget ASC,
	Debt ASC
));

CREATE TABLE Budget.DebtPrincipal (
	Budget VARCHAR(100) NOT NULL,
	Debt VARCHAR(100) NOT NULL,
	PrincipalDate DATE NOT NULL,
	PrincipalAmount MONEY NOT NULL,
CONSTRAINT FK_Budget_DebtPrincipal FOREIGN KEY (Budget, Debt)
	REFERENCES Budget.Debt(Budget, Debt),
CONSTRAINT PK_DebtPrincipal PRIMARY KEY
(
	Budget ASC,
	Debt ASC,
	PrincipalDate ASC
));

CREATE TABLE Budget.DebtAsset (
	Budget VARCHAR(100) NOT NULL,
	Debt VARCHAR(100) NOT NULL,
	Asset VARCHAR(100) NOT NULL,
CONSTRAINT FK_Budget_DebtAsset FOREIGN KEY (Budget, Debt)
	REFERENCES Budget.Debt(Budget, Debt),
CONSTRAINT FK_Budget_DebtAsset_Asset FOREIGN KEY (Budget, Asset)
	REFERENCES Budget.Asset(Budget, Asset),
CONSTRAINT PK_DebtAsset PRIMARY KEY
(
	Budget ASC,
	Debt ASC
));


GO

-- Controls
CREATE VIEW Budget.BudgetAssessmentDebt AS
SELECT a.Budget, b.Debt, a.BudgetAssessment, a.BudgetAssessmentStartDate, a.BudgetAssessmentEndDate,
	--0.00 AS PrincipalAmount
	(SELECT MIN(PrincipalAmount)
			FROM Budget.DebtPrincipal
			WHERE Budget = b.Budget AND Debt = b.Debt AND PrincipalDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS DebtPrincipalAmount
FROM Budget.BudgetAssessment a
	LEFT JOIN Budget.Debt b ON b.Budget = a.Budget -- ALso check to see if account is closed?
GO

-- CREATE PROCEDURE GeneratedEstimatedPayments(Budget, Debt, FromIncome)


----------------------------------------------------------------
-- Expenses
----------------------------------------------------------------

CREATE TABLE Budget.Expense (
	Budget VARCHAR(100) NOT NULL,
	BudgetGrouping	VARCHAR(100) NOT NULL,
	BudgetCategory	VARCHAR(100) NOT NULL,
	Expense VARCHAR(100) NOT NULL,
CONSTRAINT FK_Budget_Expense_Grouping_Category FOREIGN KEY (Budget, BudgetGrouping, BudgetCategory)
	REFERENCES Budget.BudgetCategory(Budget, BudgetGrouping, BudgetCategory),
CONSTRAINT PK_Expense PRIMARY KEY
(
	Budget ASC,
	BudgetGrouping ASC,
	BudgetCategory ASC,
	Expense ASC
));

CREATE TABLE Budget.ExpenseEstimates (
	Budget VARCHAR(100) NOT NULL,
	BudgetGrouping	VARCHAR(100) NOT NULL,
	BudgetCategory	VARCHAR(100) NOT NULL,
	Expense VARCHAR(100) NOT NULL,
	ExpenseEstimateDate DATETIMEOFFSET NOT NULL,
	ExpenseEstimateAmount MONEY NOT NULL,
CONSTRAINT FK_Budget_ExpenseEstimates FOREIGN KEY (Budget, BudgetGrouping, BudgetCategory, Expense)
	REFERENCES Budget.Expense(Budget, BudgetGrouping, BudgetCategory, Expense),
CONSTRAINT PK_ExpenseEstimates PRIMARY KEY
(
	Budget ASC,
	BudgetGrouping ASC,
	BudgetCategory ASC,
	Expense ASC,
	ExpenseEstimateDate ASC
));

CREATE TABLE Budget.ExpenseActuals (
	Budget VARCHAR(100) NOT NULL,
	BudgetGrouping	VARCHAR(100) NOT NULL,
	BudgetCategory	VARCHAR(100) NOT NULL,
	Expense VARCHAR(100) NOT NULL,
	ExpenseActualDate DATETIMEOFFSET NOT NULL,
	--ExpenseActualPaidFromAccount VARCHAR(100) NOT NULL,
	ExpenseActualAmount MONEY NOT NULL,
CONSTRAINT FK_Budget_ExpenseActuals FOREIGN KEY (Budget, BudgetGrouping, BudgetCategory, Expense)
	REFERENCES Budget.Expense(Budget, BudgetGrouping, BudgetCategory, Expense),
CONSTRAINT PK_ExpenseActuals PRIMARY KEY
(
	Budget ASC,
	BudgetGrouping ASC,
	BudgetCategory ASC,
	Expense ASC,
	ExpenseActualDate ASC
));

CREATE TABLE Budget.ExpenseIncome (
	Budget VARCHAR(100) NOT NULL,
	BudgetGrouping	VARCHAR(100) NOT NULL,
	BudgetCategory	VARCHAR(100) NOT NULL,
	Expense VARCHAR(100) NOT NULL,
	Income VARCHAR(100) NOT NULL,
CONSTRAINT FK_Budget_ExpenseIncome FOREIGN KEY (Budget, BudgetGrouping, BudgetCategory, Expense)
	REFERENCES Budget.Expense(Budget, BudgetGrouping, BudgetCategory, Expense),
CONSTRAINT FK_Budget_ExpenseIncome_Income FOREIGN KEY (Budget, Income)
	REFERENCES Budget.Income(Budget, Income),
CONSTRAINT PK_ExpenseIncome PRIMARY KEY
(
	Budget ASC,
	BudgetGrouping ASC,
	BudgetCategory ASC,
	Expense ASC,
	Income ASC
));

GO

-- Controls
CREATE VIEW Budget.BudgetAssessmentExpense AS
SELECT a.Budget, b.Expense, a.BudgetAssessment, a.BudgetAssessmentStartDate, a.BudgetAssessmentEndDate,
	(SELECT MIN(ExpenseEstimateAmount)
		FROM Budget.ExpenseEstimates
		WHERE Budget = b.Budget AND Expense = b.Expense AND ExpenseEstimateDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS ExpenseEstimatedAmount,
	(SELECT MIN(ExpenseActualAmount)
		FROM Budget.ExpenseActuals
		WHERE Budget = b.Budget AND Expense = b.Expense AND ExpenseActualDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS ExpenseActualAmount
FROM Budget.BudgetAssessment a
	LEFT JOIN Budget.Expense b ON b.Budget = a.Budget -- ALso check to see if account is closed?
GO



----------------------------------------------------------------
-- TEST
----------------------------------------------------------------
CREATE VIEW Budget.BudgetAssessmentTotals AS
SELECT
	Budget, BudgetAssessment, BudgetAssessmentStartDate, BudgetAssessmentEndDate,
	AccountBalanceStartAmount, AccountBalanceEndAmount,
	IncomeEstimatedAmount, IncomeActualAmount,
	AccountDeposited, AccountWithdrawn,
	AssetEstimatedValueAmount,
	DebtPrincipalAmount,
	ExpenseEstimatedAmount, ExpenseActualAmount,
	(AccountBalanceEndAmount - AccountBalanceStartAmount)
	+ IncomeActualAmount
	+ AssetEstimatedValueAmount
	- DebtPrincipalAmount
	- ExpenseActualAmount AS BalanceChangeAmount
FROM (
	SELECT a.Budget, a.BudgetAssessment, a.BudgetAssessmentStartDate, a.BudgetAssessmentEndDate,
		0 AS AccountBalanceStartAmount,
		200.0 AccountBalanceEndAmount, 
		(SELECT SUM(AccountDepositedAmount)
			FROM Budget.AccountDeposited
			WHERE Budget = a.Budget AND AccountDepositedDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS AccountDeposited,
		(SELECT SUM(AccountWithdrawalAmount)
			FROM Budget.AccountWithdrawal
			WHERE Budget = a.Budget AND AccountWithdrawalDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS AccountWithdrawn,
		0 AS IncomeEstimatedAmount,
		(SELECT SUM(IncomeActualAmount)
			FROM Budget.IncomeActual
			WHERE Budget = a.Budget AND IncomeActualDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS IncomeActualAmount,
		(SELECT SUM(AssetEstimatedSaleAmount)
			FROM Budget.AssetEstimateSaleValue
			WHERE Budget = a.Budget AND AssetEstimatedSaleValueDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS AssetEstimatedValueAmount,
		(SELECT SUM(PrincipalAmount)
				FROM Budget.DebtPrincipal
				WHERE Budget = a.Budget AND PrincipalDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS DebtPrincipalAmount,
		(SELECT SUM(ExpenseEstimateAmount)
			FROM Budget.ExpenseEstimates
			WHERE Budget = a.Budget AND ExpenseEstimateDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS ExpenseEstimatedAmount,
		(SELECT SUM(ExpenseActualAmount)
			FROM Budget.ExpenseActuals
			WHERE Budget = a.Budget AND ExpenseActualDate BETWEEN a.BudgetAssessmentStartDate AND a.BudgetAssessmentEndDate) AS ExpenseActualAmount
	FROM Budget.BudgetAssessment a
) z
GO




----------------------------------------------------------------
-- TEST
----------------------------------------------------------------

INSERT INTO Budget.Budget VALUES('My Personal Budget');

INSERT INTO Budget.BudgetGrouping VALUES('My Personal Budget', '1 - Income');
INSERT INTO Budget.BudgetGrouping VALUES('My Personal Budget', '2 - Recurring Fixed');
INSERT INTO Budget.BudgetGrouping VALUES('My Personal Budget', '3 - Expense - Recurring Variable');
INSERT INTO Budget.BudgetGrouping VALUES('My Personal Budget', '4 - Expense - Non-Recurring Variable');
INSERT INTO Budget.BudgetGrouping VALUES('My Personal Budget', '5 - Mom/Teresa');
INSERT INTO Budget.BudgetGrouping VALUES('My Personal Budget', '6 - Credit Card Payment Out');

INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '1 - Income', 'Child Support');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '1 - Income', 'Deposit');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '1 - Income', 'Other');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '1 - Income', 'Payroll');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '1 - Income', 'Transfer');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '2 - Expense - Fixed', 'Auto - Fee');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '2 - Expense - Fixed', 'Auto - Gas');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '2 - Expense - Fixed', 'Auto - Insurance');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '2 - Expense - Fixed', 'Auto - Loan');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '2 - Expense - Fixed', 'Auto - Tolls');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '2 - Expense - Fixed', 'Gym - LA FITNESS');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '2 - Expense - Fixed', 'Gym - YMCA');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '2 - Expense - Fixed', 'House Rent');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '2 - Expense - Fixed', 'Lifelock');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '2 - Expense - Fixed', 'Utilities');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Auto - Gas');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Auto - Maintenance');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Azure');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Bank Fee');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Books');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Credt Card Payment');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Dining Out  - Family');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Dining Out  - Pensacola');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Dining Out  - Social');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Dining Out  - Travel');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Dining Out - Personal');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Entertainment');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Entertainment - Event');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Entertainment - Hotel');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Entertainment - Movie');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Entertainment - Sporting Goods');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Entertainment - Travel');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Gift');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Groceries');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Household');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Interest Charged');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Kids');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Medical');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Pet');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Phone');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'School Lunch');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Scouts');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Taxes');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Training');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '3 - Expense - Recurring Variable', 'Transfer to Savings');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '4 - Expense - Non-Recurring Variable', 'Cash Withdrawal');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '4 - Expense - Non-Recurring Variable', 'Other');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '4 - Expense - Non-Recurring Variable', 'Pet Medical');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '5 - Mom/Teresa', 'Mom - Accident');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '5 - Mom/Teresa', 'Mom - Death Certificate');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '5 - Mom/Teresa', 'Mom - House Sale');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '5 - Mom/Teresa', 'Other');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '5 - Mom/Teresa', 'Sister Apartment');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '5 - Mom/Teresa', 'Sister Electric');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '5 - Mom/Teresa', 'Transfer');
INSERT INTO Budget.BudgetCategory VALUES('My Personal Budget', '6 - Credit Card Payment Out', 'Credt Card Payment');

INSERT INTO Budget.BudgetAssessment VALUES('My Personal Budget', '2017-02-20', '2017-01-01', '2018-01-01');

INSERT INTO Budget.Account VALUES('My Personal Budget', 'BOA Checking', 'Opened');
INSERT INTO Budget.Account VALUES('My Personal Budget', 'BOA Savings', 'Opened');

INSERT INTO Budget.AccountOpened VALUES('My Personal Budget', 'BOA Checking', '1996-09-01', 'Opened');
INSERT INTO Budget.AccountOpened VALUES('My Personal Budget', 'BOA Savings', '1998-01-01', 'Opened');

INSERT INTO Budget.AccountDeposited VALUES('My Personal Budget', 'BOA Checking', '2017-01-02', 500.00);
INSERT INTO Budget.AccountDeposited VALUES('My Personal Budget', 'BOA Checking', '2017-01-16', 500.00);

INSERT INTO Budget.AccountDeposited VALUES('My Personal Budget', 'BOA Savings', '2017-01-07', 300.00);

INSERT INTO Budget.AccountWithdrawal VALUES('My Personal Budget', 'BOA Checking', '2017-01-05', 100.00);
INSERT INTO Budget.AccountWithdrawal VALUES('My Personal Budget', 'BOA Checking', '2017-01-09', 200.00);
INSERT INTO Budget.AccountWithdrawal VALUES('My Personal Budget', 'BOA Checking', '2017-01-19', 200.00);
INSERT INTO Budget.AccountWithdrawal VALUES('My Personal Budget', 'BOA Checking', '2017-01-21', 300.00);

INSERT INTO Budget.AccountWithdrawal VALUES('My Personal Budget', 'BOA Savings', '2017-01-07', 100.00);

-- SalaryBiWeekly, HourlyBiWeekly
INSERT INTO Budget.Income VALUES('My Personal Budget', 'Current salaried job', 'SalaryBiWeekly');

INSERT INTO Budget.IncomeSalaryBiWeekly VALUES('My Personal Budget', 'Current salaried job', '2017-01-13', '2017-01-27', 1200.00, 'SalaryBiWeekly');

INSERT INTO Budget.IncomeActual VALUES('My Personal Budget', 'Current salaried job', '2017-01-13', 1150.00);
INSERT INTO Budget.IncomeActual VALUES('My Personal Budget', 'Current salaried job', '2017-01-27', 1200.00);

INSERT INTO Budget.Asset VALUES('My Personal Budget', '40 inch LED TV', '2016-07-01', 400.00);
INSERT INTO Budget.Asset VALUES('My Personal Budget', 'Car', '2015-08-18', 22000.00);

INSERT INTO Budget.AssetEstimateSaleValue VALUES('My Personal Budget', '40 inch LED TV', '2017-01-01', 200.00);
INSERT INTO Budget.AssetEstimateSaleValue VALUES('My Personal Budget', 'Car', '2017-01-01', 15000.00);

INSERT INTO Budget.Debt VALUES('My Personal Budget', 'Car', 'Monthly');

INSERT INTO Budget.DebtMonthlyCompounding VALUES('My Personal Budget', 'Car', 2.49, 'Monthly');

INSERT INTO Budget.DebtPrincipal VALUES('My Personal Budget', 'Car', '2017-01-01', 16250.00);

INSERT INTO Budget.DebtAsset VALUES('My Personal Budget', 'Car', 'Car');

INSERT INTO Budget.Expense VALUES('My Personal Budget', '2 - Expense - Fixed', 'House Rent', 'House Rent');

INSERT INTO Budget.ExpenseEstimates VALUES('My Personal Budget', '2 - Expense - Fixed', 'House Rent', 'House Rent', '2017-01-01', 1200.00);

INSERT INTO Budget.ExpenseActuals VALUES('My Personal Budget', '2 - Expense - Fixed', 'House Rent', 'House Rent', '2017-01-01', 1250.00);


-- Test Queries

SELECT * FROM Budget.BudgetAssessmentTotals
GO

CREATE VIEW Budget.BudgetAssessmentItems AS
SELECT Budget, 'Account' AS BudgetType, Account AS BudgetItem, Deposited - Withdrawn AS CreditAmount, 0 AS DebitAmount FROM Budget.BudgetAssessmentAccount
UNION ALL
SELECT Budget, 'Asset' AS BudgetType, Asset AS BudgetItem, AssetEstimatedValueAmount AS CreditAmount, 0 AS DebitAmount FROM Budget.BudgetAssessmentAsset
UNION ALL
SELECT Budget, 'Income' AS BudgetType, Income AS BudgetItem, IncomeActualAmount AS CreditAmount, 0 AS DebitAmount FROM Budget.BudgetAssessmentIncome
UNION ALL
SELECT Budget, 'Debt' AS BudgetType, Debt AS BudgetItem, 0 AS CreditAmount, DebtPrincipalAmount AS DebitAmount FROM Budget.BudgetAssessmentDebt
UNION ALL
SELECT Budget, 'Expense' AS BudgetType, Expense AS BudgetItem, 0 AS CreditAmount, ExpenseActualAmount AS DebitAmount FROM Budget.BudgetAssessmentExpense
GO

SELECT * FROM Budget.BudgetAssessmentItems

SELECT Budget, SUM(CreditAmount) AS CreditAmount, SUM(DebitAmount) AS DebitAmount, SUM(CreditAmount) - SUM(DebitAmount) AS Balance
FROM (
	SELECT Budget, 'Account' AS BudgetType, Account AS BudgetItem, Deposited - Withdrawn AS CreditAmount, 0 AS DebitAmount FROM Budget.BudgetAssessmentAccount
	UNION ALL
	SELECT Budget, 'Asset' AS BudgetType, Asset AS BudgetItem, AssetEstimatedValueAmount AS CreditAmount, 0 AS DebitAmount FROM Budget.BudgetAssessmentAsset
	UNION ALL
	SELECT Budget, 'Income' AS BudgetType, Income AS BudgetItem, IncomeActualAmount AS CreditAmount, 0 AS DebitAmount FROM Budget.BudgetAssessmentIncome
	UNION ALL
	SELECT Budget, 'Debt' AS BudgetType, Debt AS BudgetItem, 0 AS CreditAmount, DebtPrincipalAmount AS DebitAmount FROM Budget.BudgetAssessmentDebt
	UNION ALL
	SELECT Budget, 'Expense' AS BudgetType, Expense AS BudgetItem, 0 AS CreditAmount, ExpenseActualAmount AS DebitAmount FROM Budget.BudgetAssessmentExpense
) z
GROUP BY Budget