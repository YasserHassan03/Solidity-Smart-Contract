// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;
// pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IHumanResources.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/ReentrancyGuard.sol";
import "./interfaces/IWETH.sol";

contract HumanResources is IHumanResources, ReentrancyGuard {
    address immutable hrManager_ad;
    IERC20 immutable usdc;
    AggregatorV3Interface immutable ethUsdPriceFeed;
    ISwapRouter immutable swapRouter;
    
    // Constants
    uint256 private constant USDC_DECIMALS = 6;
    uint256 private constant ETH_DECIMALS = 18;
    address private constant WETH = 0x4200000000000000000000000000000000000006;
    address private constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    uint24 private constant POOL_FEE = 500; // 0.05%

    struct Employee {
        uint256 weeklyUsdSalary;
        uint256 employedSince;
        uint256 terminatedAt;
        uint256 accumulatedSalary;
        uint256 lastWithdrawal;
        bool isEth;
    }

    mapping(address => Employee) private employees;
    uint256 private activeEmployeeCount;

    modifier onlyHRManager() {
        if (msg.sender != hrManager_ad) revert NotAuthorized();
        _;
    }

    modifier onlyEmployee() {
        if (employees[msg.sender].employedSince == 0) revert NotAuthorized();
        _;
    }

    modifier onlyActiveEmployee() {
        if (employees[msg.sender].employedSince == 0 || 
            employees[msg.sender].terminatedAt != 0) revert NotAuthorized();
        _;
    }

    constructor(address _hrManager) {
        hrManager_ad = _hrManager;
        usdc = IERC20(USDC);
        ethUsdPriceFeed = AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5);
        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    }

    function registerEmployee(
        address employee,
        uint256 weeklyUsdSalary
    ) external override onlyHRManager {
        if (
            employees[employee].employedSince != 0 &&
            employees[employee].terminatedAt == 0
        ) {
            revert EmployeeAlreadyRegistered();
        }
        
        // Keep accumulated salary if employee is being re-registered
        uint256 previousAccumulatedSalary = employees[employee].accumulatedSalary;
        
        employees[employee] = Employee({
            weeklyUsdSalary: weeklyUsdSalary,
            employedSince: block.timestamp,
            terminatedAt: 0,
            accumulatedSalary: previousAccumulatedSalary,
            lastWithdrawal: block.timestamp,
            isEth: false
        });
        
        activeEmployeeCount++;
        emit EmployeeRegistered(employee, weeklyUsdSalary);
    }

    function terminateEmployee(
        address employee
    ) external override onlyHRManager {
        Employee storage emp = employees[employee];
        if (emp.employedSince == 0 || emp.terminatedAt != 0) {
            revert EmployeeNotRegistered();
        }
        
        // Calculate final salary before termination
        emp.accumulatedSalary += calculatePendingSalary(employee);
        emp.terminatedAt = block.timestamp;
        emp.lastWithdrawal = block.timestamp;
        activeEmployeeCount--;
        
        emit EmployeeTerminated(employee);
    }

    function _processWithdrawal(address employee) internal nonReentrant {
        Employee storage emp = employees[employee];
        uint256 totalSalary = emp.accumulatedSalary + calculatePendingSalary(employee);
        if (totalSalary == 0) return;

        // Reset accumulated salary and update last withdrawal
        emp.accumulatedSalary = 0;
        emp.lastWithdrawal = block.timestamp;

        if (emp.isEth) {
            // Convert USDC amount to ETH equivalent
            uint256 usdcAmount = totalSalary / (10**(ETH_DECIMALS-USDC_DECIMALS));
            uint256 ethAmount = performUsdcToEthSwap(usdcAmount);
            
            // Convert WETH to ETH and send to employee
            IWETH(WETH).withdraw(ethAmount);
            (bool success,) = payable(employee).call{value: ethAmount}("");
            require(success, "ETH transfer failed");
            
            emit SalaryWithdrawn(employee, true, ethAmount);
        } else {
            // Send USDC directly
            uint256 usdcAmount = totalSalary / (10**(ETH_DECIMALS-USDC_DECIMALS));
            require(usdc.transfer(employee, usdcAmount), "USDC transfer failed");
            
            emit SalaryWithdrawn(employee, false, usdcAmount);
        }
    }

    function withdrawSalary() external override onlyEmployee {
        _processWithdrawal(msg.sender);
    }

    function switchCurrency() external override onlyActiveEmployee {
        Employee storage emp = employees[msg.sender];
        
        // Withdraw any pending salary first
        if (emp.accumulatedSalary > 0 || calculatePendingSalary(msg.sender) > 0) {
            _processWithdrawal(msg.sender);
        }
        
        emp.isEth = !emp.isEth;
        emit CurrencySwitched(msg.sender, emp.isEth);
    }

    function salaryAvailable(address employee) external view override returns (uint256) {
        Employee memory emp = employees[employee];
        if (emp.employedSince == 0) return 0;

        uint256 totalSalary = emp.accumulatedSalary + calculatePendingSalary(employee);
        
        if (emp.isEth) {
            return (totalSalary * (10**ETH_DECIMALS)) / getCurrentEthPrice();
        } else {
            return totalSalary / (10**(ETH_DECIMALS-USDC_DECIMALS));
        }
    }

    function hrManager() external view override returns (address) {
        return hrManager_ad;
    }

    function getActiveEmployeeCount() external view override returns (uint256) {
        return activeEmployeeCount;
    }

    function getEmployeeInfo(
        address employee
    ) external view override returns (
        uint256 weeklyUsdSalary,
        uint256 employedSince,
        uint256 terminatedAt
    ) {
        Employee memory emp = employees[employee];
        return (emp.weeklyUsdSalary, emp.employedSince, emp.terminatedAt);
    }

    // Helper functions
    function calculatePendingSalary(address employee) private view returns (uint256) {
        Employee memory emp = employees[employee];
        if (emp.employedSince == 0) return 0;

        uint256 endTime = emp.terminatedAt == 0 ? block.timestamp : emp.terminatedAt;
        uint256 duration = endTime - emp.lastWithdrawal;
        
        return (duration * emp.weeklyUsdSalary) / 1 weeks;
    }

    function getCurrentEthPrice() private view returns (uint256) {
        (, int256 price,,,) = ethUsdPriceFeed.latestRoundData();
        require(price > 0, "Invalid ETH price");
        return uint256(price) * (10**10); // Convert to 18 decimals
    }

    function performUsdcToEthSwap(uint256 usdcAmount) private returns (uint256) {
        // Calculate minimum ETH output based on current price
        uint256 expectedEthAmount = (usdcAmount * (10**ETH_DECIMALS)) / getCurrentEthPrice();
        uint256 minEthAmount = (expectedEthAmount * 98) / 100; // 2% slippage tolerance

        // Approve USDC spending
        TransferHelper.safeApprove(USDC, address(swapRouter), usdcAmount);

        // Perform swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: USDC,
            tokenOut: WETH,
            fee: POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: usdcAmount,
            amountOutMinimum: minEthAmount,
            sqrtPriceLimitX96: 0
        });

        return swapRouter.exactInputSingle(params);
    }

    receive() external payable {}
}