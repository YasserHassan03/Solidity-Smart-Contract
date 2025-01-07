# HumanResources Smart Contract Documentation

## Core Features

- Salary management in USD-denominated amounts
- Support for both USDC and ETH salary payments
- Automatic currency conversion using Uniswap V3
- Real-time ETH/USD price feed integration via Chainlink
- Protection against reentrancy attacks

## Interface Implementation

### Employee Management Functions

#### `registerEmployee(address employee, uint256 weeklyUsdSalary)`
- Registers a new employee or re-registers a terminated employee
- Only callable by HR manager
- Maintains accumulated salary for re-registered employees
- Initializes employee with USDC as default payment currency
- Emits `EmployeeRegistered` event

#### `terminateEmployee(address employee)`
- Terminates an active employee's contract
- Only callable by HR manager
- Calculates and stores final salary before termination
- Updates employee count and termination timestamp
- Emits `EmployeeTerminated` event

### Salary Operations

#### `withdrawSalary()`
- Allows employees to withdraw their accumulated salary
- Supports both USDC and ETH withdrawals
- Automatically converts USDC to ETH if employee has selected ETH payments
- Protected against reentrancy attacks
- Emits `SalaryWithdrawn` event

#### `switchCurrency()`
- Toggles between USDC and ETH as payment currency
- Only available for active employees
- Automatically processes any pending salary before switching
- Emits `CurrencySwitched` event

### View Functions

#### `salaryAvailable(address employee)`
- Returns the total available salary for withdrawal
- Includes both accumulated and pending salary
- Converts amount to appropriate currency (USDC or ETH)
- Returns 0 for non-employees

#### `hrManager()`
- Returns the address of the HR manager

#### `getActiveEmployeeCount()`
- Returns the current number of active employees

#### `getEmployeeInfo(address employee)`
- Returns employee's weekly salary, employment start date, and termination date
- Accessible for both active and terminated employees

## Security Features

- Reentrancy protection on withdrawal functions
- Role-based access control using modifiers
- Slippage protection for Uniswap swaps
- Safe transfer helpers for token operations
- Immutable contract addresses
- Precise decimal handling for both USDC (6) and ETH (18)

## Events

The contract emits the following events:
- `EmployeeRegistered(address employee, uint256 weeklyUsdSalary)`
- `EmployeeTerminated(address employee)`
- `SalaryWithdrawn(address employee, bool isEth, uint256 amount)`
- `CurrencySwitched(address employee, bool isEth)`