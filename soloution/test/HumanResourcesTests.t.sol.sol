// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/// @notice This is a test contract for the HumanResources contract
/// You can either run this test for a contract deployed on a local fork or for a contract deployed on Optimism
/// To use a local fork, start `anvil` using `anvil --rpc-url $RPC_URL` where `RPC_URL` should point to an Optimism RPC.
/// Deploy your contract on the local fork and set the following environment variables:
/// - HR_CONTRACT: the address of the deployed contract
/// - ETH_RPC_URL: the RPC URL of the local fork (likely http://localhost:8545)
/// To run on Optimism, you will need to set the same environment variables, but with the address of the deployed contract on Optimism
/// and ETH_RPC_URL should point to the Optimism RPC.
/// Once the environment variables are set, you can run the tests using `forge test --mp test/HumanResourcesTests.t.sol`
/// assuming that you copied the file into the `test` folder of your project.

/// @notice You may need to change these import statements depending on your project structure and where you use this test
import {Test, console, stdStorage, StdStorage} from "forge-std/Test.sol";
import {HumanResources, IHumanResources} from "../src/HumanResources.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract HumanResourcesTest is Test {
    using stdStorage for StdStorage;

    address internal constant _WETH =
        0x4200000000000000000000000000000000000006;
    address internal constant _USDC =
        0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    AggregatorV3Interface internal constant _ETH_USD_FEED =
    AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5);

    HumanResources public humanResources;

    address public hrManager = 0x4f59F96a2ee0f21708326d494742672E8211A464;
    AggregatorV3Interface public priceFeed;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public aliceSalary = 2100e18;
    uint256 public bobSalary = 700e18;
    

    uint256 public constant STANDARD_SALARY = 1000e18;


    uint256 ethPrice;

    function setUp() public {
        vm.createSelectFork(
            "https://opt-mainnet.g.alchemy.com/v2/vDf0kMWQslFTKglsajDYgwhc-1R4tuA2"
        );
        humanResources = new HumanResources(hrManager);
        priceFeed = AggregatorV3Interface(
            0x13e3Ee699D1909E989722E753853AE30b17e08c5
        );
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        uint256 feedDecimals = priceFeed.decimals();
        ethPrice = uint256(answer) * 10 ** (18 - feedDecimals);
        hrManager = humanResources.hrManager();
    }




    function test_registerEmployee() public {
        _registerEmployee(alice, aliceSalary);
        assertEq(humanResources.getActiveEmployeeCount(), 1);

        uint256 currentTime = block.timestamp;

        (
            uint256 weeklySalary,
            uint256 employedSince,
            uint256 terminatedAt
        ) = humanResources.getEmployeeInfo(alice);
        assertEq(weeklySalary, aliceSalary);
        assertEq(employedSince, currentTime);
        assertEq(terminatedAt, 0);

        skip(10 hours);

        _registerEmployee(bob, bobSalary);

        (weeklySalary, employedSince, terminatedAt) = humanResources
            .getEmployeeInfo(bob);
        assertEq(humanResources.getActiveEmployeeCount(), 2);

        assertEq(weeklySalary, bobSalary);
        assertEq(employedSince, currentTime + 10 hours);
        assertEq(terminatedAt, 0);
    }

    function test_registerEmployee_twice() public {
        _registerEmployee(alice, aliceSalary);
        vm.expectRevert(IHumanResources.EmployeeAlreadyRegistered.selector);
        _registerEmployee(alice, aliceSalary);
    }

    function test_salaryAvailable_usdc() public {
        _registerEmployee(alice, aliceSalary);
        skip(2 days);
        assertEq(
            humanResources.salaryAvailable(alice),
            ((aliceSalary / 1e12) * 2) / 7
        );

        skip(5 days);
        assertEq(humanResources.salaryAvailable(alice), aliceSalary / 1e12);
    }

    function test_salaryAvailable_eth() public {
        _registerEmployee(alice, aliceSalary);
        uint256 expectedSalary = (aliceSalary * 1e18 * 2) / ethPrice / 7;
        vm.prank(alice);
        humanResources.switchCurrency();
        skip(2 days);
        assertApproxEqRel(
            humanResources.salaryAvailable(alice),
            expectedSalary,
            0.01e18
        );
        skip(5 days);
        expectedSalary = (aliceSalary * 1e18) / ethPrice;
        assertApproxEqRel(
            humanResources.salaryAvailable(alice),
            expectedSalary,
            0.01e18
        );
    }

    function test_withdrawSalary_usdc() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);
        skip(2 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertEq(
            IERC20(_USDC).balanceOf(address(alice)),
            ((aliceSalary / 1e12) * 2) / 7
        );

        skip(5 days);
        vm.prank(alice);    
        humanResources.withdrawSalary();
        assertEq(IERC20(_USDC).balanceOf(address(alice)), aliceSalary / 1e12);
    }

    function test_withdrawSalary_eth() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);
        uint256 expectedSalary = (aliceSalary * 1e18 * 2) / ethPrice / 7;
        vm.prank(alice);
        humanResources.switchCurrency();
        skip(2 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertApproxEqRel(alice.balance, expectedSalary, 0.01e18);
        skip(5 days);
        expectedSalary = (aliceSalary * 1e18) / ethPrice;
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertApproxEqRel(alice.balance, expectedSalary, 0.01e18);
    }

    function test_reregisterEmployee() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);
        skip(2 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);
        skip(1 days);
        _registerEmployee(alice, aliceSalary * 2);
        skip(5 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 expectedSalary = ((aliceSalary * 2) / 7) +
            ((aliceSalary * 2 * 5) / 7);
        assertEq(
            IERC20(_USDC).balanceOf(address(alice)),
            expectedSalary / 1e12
        );
    }

    function test_terminated_employee_withdraw() public{
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);
        skip(2 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);
        skip(2 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 expectedSalary = ((aliceSalary*2)/7);
        assertEq(IERC20(_USDC).balanceOf(address(alice)), expectedSalary / 1e12);
    }



    function test_salary_withdrawal_on_switch() public{
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);
        skip(3 days);
        vm.prank(alice);
        humanResources.switchCurrency(); //should withdraw in usdc switch to ETH
        skip (8 days);
        vm.prank(alice);
        humanResources.switchCurrency(); //should withdraw in ETH switch to USDC
        skip(2 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 expectedETH = (aliceSalary * 1e18 * 8) / ethPrice / 7;
        uint256 expectedUSDC = ((aliceSalary*5)/7);
        assertEq(IERC20(_USDC).balanceOf(address(alice)), expectedUSDC/1e12);
        assertApproxEqRel(alice.balance, expectedETH, 0.01e18);
    }

    function test_terminated_employee_switch() public{
        _registerEmployee(alice, aliceSalary);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);
        vm.prank(alice);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        humanResources.switchCurrency();
    }



    function test_HR_not_Authorized_withdraw() public{
        vm.prank(hrManager);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        humanResources.withdrawSalary();
    }

    function test_HR_not_Authorized_switch() public{
        vm.prank(hrManager);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        humanResources.switchCurrency();
    }

    function test_Employee_not_Authorized_terminate() public{
        vm.prank(alice);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        humanResources.terminateEmployee(bob);
    }

    function test_Employee_not_Authorized_register() public{
        vm.prank(alice);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        humanResources.registerEmployee(bob, bobSalary);
    }


    // Test getActiveEmployeeCount returns correct count
    function test_activeEmployeeCountAccuracy() public {
        // Initially should be zero
        assertEq(humanResources.getActiveEmployeeCount(), 0, "Initial employee count should be zero");

        // Register employees and verify count
        _registerEmployee(alice, STANDARD_SALARY);
        assertEq(humanResources.getActiveEmployeeCount(), 1, "Employee count should be 1");

        _registerEmployee(bob, STANDARD_SALARY);
        assertEq(humanResources.getActiveEmployeeCount(), 2, "Employee count should be 2");

        // Terminate an employee and check count
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);
        assertEq(humanResources.getActiveEmployeeCount(), 1, "Employee count should decrease after termination");
    }

    // Test getEmployeeInfo returns correct details
    function test_employeeInfoReturnValues() public {
        uint256 currentTime = block.timestamp;
        
        _registerEmployee(alice, STANDARD_SALARY);

        // Verify employee info
        (
            uint256 weeklySalary,
            uint256 employedSince,
            uint256 terminatedAt
        ) = humanResources.getEmployeeInfo(alice);

        assertEq(weeklySalary, STANDARD_SALARY, "Weekly salary should match registered salary");
        assertEq(employedSince, currentTime, "Employed since timestamp should match registration time");
        assertEq(terminatedAt, 0, "Terminated at should be zero for active employee");
    }

    // Test salaryAvailable for USDC currency
    function test_salaryAvailableUSDC() public {
        _registerEmployee(alice, STANDARD_SALARY);

        // Skip some time to accumulate salary
        skip(2 days);
        uint256 expectedSalary = ((STANDARD_SALARY * 2) / 7) / 1e12;
        assertEq(
            humanResources.salaryAvailable(alice), 
            expectedSalary, 
            "Salary available should match pro-rated calculation for USDC"
        );
    }

    // Test multiple currency switches and salary availability
    function test_salaryAvailableAfterMultipleSwitches() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, STANDARD_SALARY);
        
        // Switch to ETH
        vm.prank(alice);
        humanResources.switchCurrency();
        skip(2 days);
        
        // Switch back to USDC
        vm.prank(alice);
        humanResources.switchCurrency();
        
        // Verify salary calculation remains consistent
        uint256 expectedSalary = 0;
        assertEq(
            humanResources.salaryAvailable(alice), 
            expectedSalary, 
            "Salary available should remain consistent after currency switches"
        );
    }

    // Test salary availability after employee termination
    function test_salaryAvailableAfterTermination() public {
        _registerEmployee(alice, STANDARD_SALARY);
        
        skip(2 days);
        
        // Terminate employee
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);

        skip(3 days);
        
        // Verify accumulated salary
        uint256 expectedSalary = ((STANDARD_SALARY * 2) / 7) / 1e12;
        assertEq(
            humanResources.salaryAvailable(alice), 
            expectedSalary, 
            "Salary available should reflect accumulated salary after termination"
        );
    }
    function test_prolongedSalaryAccumulation() public {
        _registerEmployee(alice, STANDARD_SALARY);
        skip(365 days);
        uint256 expectedSalary = (STANDARD_SALARY * 365) / 7;
        assertEq(
            humanResources.salaryAvailable(alice),
            expectedSalary / 1e12,
            "Prolonged salary accumulation mismatch"
        );
    }
    function test_exactWeekSalary() public {
        _registerEmployee(alice, STANDARD_SALARY);
        skip(7 days);
        uint256 expectedSalary = STANDARD_SALARY / 1e12;
        assertEq(
            humanResources.salaryAvailable(alice),
            expectedSalary,
            "Exact weekly salary mismatch"
        );
    }
    function test_multipleEmployeeSalaryAccumulation() public {
        _registerEmployee(alice, STANDARD_SALARY);
        _registerEmployee(bob, bobSalary);
        
        skip(3 days);
        
        uint256 aliceExpectedSalary = (STANDARD_SALARY * 3) / 7;
        uint256 bobExpectedSalary = (bobSalary * 3) / 7;

        assertEq(
            humanResources.salaryAvailable(alice),
            aliceExpectedSalary / 1e12,
            "Alice's salary mismatch"
        );
        assertEq(
            humanResources.salaryAvailable(bob),
            bobExpectedSalary / 1e12,
            "Bob's salary mismatch"
        );
    }

    function test_partialWithdrawals() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, STANDARD_SALARY);
        skip(3 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        
        skip(4 days);
        uint256 expectedSalary = (STANDARD_SALARY * 4) / 7;
        assertEq(
            humanResources.salaryAvailable(alice),
            expectedSalary / 1e12,
            "Salary mismatch after partial withdrawal"
        );
    }

    function test_withdrawAfterTermination() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, STANDARD_SALARY);
        skip(4 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);

        vm.prank(alice);
        humanResources.withdrawSalary();

        uint256 expectedSalary = (STANDARD_SALARY * 4) / 7;
        assertEq(
            IERC20(_USDC).balanceOf(alice),
            expectedSalary / 1e12,
            "Salary mismatch after termination"
        );
    }

    function test_reregisterWithAccruedSalary() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, STANDARD_SALARY);
        skip(3 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);

        _registerEmployee(alice, STANDARD_SALARY * 2);
        skip(4 days);

        uint256 expectedSalary = ((STANDARD_SALARY * 3) / 7) +
            ((STANDARD_SALARY * 2 * 4) / 7);

        vm.prank(alice);
        humanResources.withdrawSalary();
        assertEq(
            IERC20(_USDC).balanceOf(alice),
            expectedSalary / 1e12,
            "Salary mismatch after re-registration"
        );
    }

    function test_nonEmployeeUnauthorizedAccess() public {
        vm.prank(charlie);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        humanResources.withdrawSalary();

        vm.prank(charlie);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        humanResources.switchCurrency();
    }


    function test_insufficientFundsForWithdrawal() public {
        _registerEmployee(alice, STANDARD_SALARY);

        skip(7 days);

        vm.prank(alice);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        humanResources.withdrawSalary();
    }

    // Helper function to register an employee
    function _registerEmployee(address employeeAddress, uint256 salary) public {
        vm.prank(hrManager);
        humanResources.registerEmployee(employeeAddress, salary);
    }

    function test_doubleWithdrawalSamePeriod() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, STANDARD_SALARY);
        
        skip(3 days);
        vm.prank(alice);
        humanResources.withdrawSalary();

        // Attempt to withdraw again without any additional time passed
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertEq(
            IERC20(_USDC).balanceOf(alice),
            ((STANDARD_SALARY * 3) / 7) / 1e12,
            "Second withdrawal should not increase balance"
        );
    }


    function test_terminationBeforeWithdrawal() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, STANDARD_SALARY);

        skip(5 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);

        vm.prank(alice);
        humanResources.withdrawSalary();

        uint256 expectedSalary = (STANDARD_SALARY * 5) / 7;
        assertEq(IERC20(_USDC).balanceOf(alice), expectedSalary / 1e12, "Accrued salary mismatch after termination");
    }

    function test_immediateCurrencySwitchAfterRegistration() public {
        _registerEmployee(alice, STANDARD_SALARY);

        vm.prank(alice);
        humanResources.switchCurrency();

        assertEq(humanResources.salaryAvailable(alice), 0, "Salary should remain zero after immediate switch");
        assertEq(alice.balance, 0, "ETH balance should remain zero");
    }

    function test_reregisterAfterProlongedTime() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, STANDARD_SALARY);

        skip(7 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);

        skip(30 days); // Long gap before re-registration
        _registerEmployee(alice, STANDARD_SALARY);

        vm.prank(alice);
        humanResources.withdrawSalary();
        
        uint256 expectedSalary = STANDARD_SALARY; // New accrual only
        assertEq(IERC20(_USDC).balanceOf(alice), expectedSalary / 1e12, "Accrued salary mismatch after re-registration");
    }

    function test_terminationAndImmediateReregister() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, STANDARD_SALARY);

        skip(3 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);

        _registerEmployee(alice, STANDARD_SALARY);

        vm.prank(alice);
        humanResources.withdrawSalary();

        uint256 expectedSalary = ((STANDARD_SALARY * 3) / 7);
        assertEq(IERC20(_USDC).balanceOf(alice), expectedSalary / 1e12, "Previous accrued salary mismatch after re-registration");
    }

    function test_doubleSwap() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);
        
        skip(1 days);
        console.log("switching for the first time");
        //eth
        vm.prank(alice);
        humanResources.switchCurrency();
        console.log("switching for the second time");
        //back to usdc
        vm.prank(alice);
        humanResources.switchCurrency();
        skip(6 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertEq(IERC20(_USDC).balanceOf(address(alice)), aliceSalary / 1e12);
    }

    function test_switchBeforeTerminateAndReRegister() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);

        vm.prank(alice);
        humanResources.switchCurrency();

        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);

        skip(1 days);

        _registerEmployee(alice, aliceSalary);//usdc

        skip(2 days);//2 days salary
        vm.prank(alice);
        humanResources.withdrawSalary();//withdraw 2*USDC

        uint256 expectedSalary_usdc = (aliceSalary * 2 ) / 7;
        assertEq(IERC20(_USDC).balanceOf(address(alice)), expectedSalary_usdc / 1e12);
        vm.prank(alice);
        humanResources.switchCurrency();//withdraw0 now eth

        skip(5 days);//5 days of eth
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 expectedSalary_eth = (aliceSalary * 5 * 1e18) / ethPrice / 7;
        assertApproxEqRel(alice.balance, expectedSalary_eth, 0.01e18);   
    }


    function test_salaryAccrualAcrossReRegistration() public {
        _mintTokensFor(_USDC, address(humanResources), 50_000e6);

        // Register employee and skip time
        _registerEmployee(alice, aliceSalary);
        skip(5 days);

        // Terminate employee
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);

        // Accrue no salary during termination period
        skip(7 days);
        assertEq(humanResources.salaryAvailable(alice), (aliceSalary * 5) / 7 / 1e12, "Salary should not accrue during termination");

        // Re-register employee with new salary
        uint256 newSalary = aliceSalary * 2;
        _registerEmployee(alice, newSalary);

        // Accrue salary after re-registration
        skip(3 days);
        uint256 expectedSalary = (aliceSalary * 5) / 7 + (newSalary * 3) / 7;
        assertEq(humanResources.salaryAvailable(alice), expectedSalary / 1e12, "Salary mismatch after re-registration");
    }


    function test_salaryPrecisionWithRounding() public {
        uint256 smallSalary = 1e12; // Very small salary (1 USD per week)
        _registerEmployee(alice, smallSalary);

        skip(3 days);
        uint256 expectedSalary = (smallSalary * 3) / 7 / 1e12;
        assertEq(humanResources.salaryAvailable(alice), expectedSalary, "Small salary rounding mismatch");

        vm.prank(alice);
        humanResources.withdrawSalary();
        assertEq(IERC20(_USDC).balanceOf(alice), expectedSalary, "Small salary withdrawal mismatch");
    }

    function test_multipleTerminationsAndReRegistrations() public {
        _mintTokensFor(_USDC, address(humanResources), 100_000e6);

        // First registration
        _registerEmployee(alice, aliceSalary);
        skip(5 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);

        // Second registration
        _registerEmployee(alice, aliceSalary * 2);
        skip(3 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);

        // Third registration
        _registerEmployee(alice, aliceSalary * 3);
        skip(4 days);

        // Withdraw salary after multiple re-registrations
        vm.prank(alice);
        humanResources.withdrawSalary();

        uint256 expectedSalary = (aliceSalary * 5) / 7 + (aliceSalary * 2 * 3) / 7 + (aliceSalary * 3 * 4) / 7;
        assertEq(IERC20(_USDC).balanceOf(alice), expectedSalary / 1e12, "Salary mismatch after multiple re-registrations");
    }

    function test_multipleSalaryTiers() public {
        uint256 highSalary = 10_000e18; // 10,000 USD per week
        uint256 lowSalary = 500e18; // 500 USD per week

        _registerEmployee(alice, highSalary);
        _registerEmployee(bob, lowSalary);

        skip(3 days);

        uint256 expectedAliceSalary = (highSalary * 3) / 7 / 1e12;
        uint256 expectedBobSalary = (lowSalary * 3) / 7 / 1e12;

        assertEq(humanResources.salaryAvailable(alice), expectedAliceSalary, "High salary mismatch");
        assertEq(humanResources.salaryAvailable(bob), expectedBobSalary, "Low salary mismatch");
    }
// commented to run with limited public RPC
    // function test_largeNumberOfEmployees() public {
    //     _mintTokensFor(_USDC, address(humanResources), 100_000e8);
    //     uint256 numEmployees = 100;
    //     for (uint256 i = 0; i < numEmployees; i++) {
    //         address employee = makeAddr(string(abi.encodePacked("employee", i)));
    //         _registerEmployee(employee, STANDARD_SALARY);
    //     }

    //     assertEq(humanResources.getActiveEmployeeCount(), numEmployees, "Employee count mismatch");

    //     skip(7 days);

    //     for (uint256 i = 0; i < numEmployees; i++) {
    //         address employee = makeAddr(string(abi.encodePacked("employee", i)));
    //         vm.prank(employee);
    //         humanResources.withdrawSalary();
    //     }
    // }

    function test_partialWithdrawalBeforeSwitch() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);

        // Skip 3 days and partially withdraw salary
        skip(3 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 partialUSDC = (aliceSalary * 3) / 7 / 1e12;
        assertEq(IERC20(_USDC).balanceOf(alice), partialUSDC, "Partial USDC withdrawal mismatch");

        // Skip 2 more days and switch to ETH
        skip(2 days);
        uint256 remainingUSDC = (aliceSalary * 2) / 7 / 1e12;
        vm.prank(alice);
        humanResources.switchCurrency();
        assertEq(IERC20(_USDC).balanceOf(alice), partialUSDC + remainingUSDC, "Remaining USDC mismatch after switch");

        assertEq(humanResources.salaryAvailable(alice), 0, "Salary should reset after switch");
    }

    function test_terminationAfterCurrencySwitch() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);

        // Skip 4 days and switch to ETH
        skip(4 days);
        vm.prank(alice);
        humanResources.switchCurrency();

        // Skip 3 days and terminate the employee
        skip(3 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);

        // Verify salary withdrawable in ETH
        uint256 totalETH = (aliceSalary * 1e18 * 3) / ethPrice / 7;
        uint256 totalUSDC = (aliceSalary * 4) / 7 / 1e12;
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertApproxEqRel(alice.balance, totalETH, 0.01e18, "Total ETH mismatch after termination");
        assertEq(IERC20(_USDC).balanceOf(alice), totalUSDC, "USDC withdrawal mismatch");
    }

    function test_reRegistrationResetsCurrency() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);

        // Switch to ETH
        vm.prank(alice);
        humanResources.switchCurrency();

        // Skip 4 days and terminate
        skip(4 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);

        // Re-register with a new salary
        _registerEmployee(alice, aliceSalary * 2);

        // Verify currency reset
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 expectedUSDC = (aliceSalary * 4) / 7 / 1e12;
        assertEq(IERC20(_USDC).balanceOf(alice), expectedUSDC, "Mismatch in USDC withdrawal after re-registration");
    }


    function test_staggeredEmployeeTermination() public {
        _mintTokensFor(_USDC, address(humanResources), 50_000e6);
        _registerEmployee(alice, aliceSalary);
        _registerEmployee(bob, bobSalary);

        // Alice switches to ETH after 3 days
        skip(3 days);
        vm.prank(alice);
        humanResources.switchCurrency();

        // Bob is terminated after 5 days
        skip(2 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(bob);

        // Verify balances
        uint256 expectedAliceUSDC = (aliceSalary * 3) / 7 / 1e12;
        uint256 expectedAliceETH = (aliceSalary * 1e18 * 2) / ethPrice / 7;
        uint256 expectedBobUSDC = (bobSalary * 5) / 7 / 1e12;

        vm.prank(alice);
        humanResources.withdrawSalary();
        assertApproxEqRel(alice.balance, expectedAliceETH, 0.01e18, "Alice's ETH mismatch");
        assertEq(IERC20(_USDC).balanceOf(alice), expectedAliceUSDC, "Alice's USDC mismatch");
        vm.prank(bob);
        humanResources.withdrawSalary();
        assertEq(IERC20(_USDC).balanceOf(bob), expectedBobUSDC, "Bob's USDC mismatch");
    }

        function test_withdrawalAndMultipleCurrencySwitches() public {
        _mintTokensFor(_USDC, address(humanResources), 50_000e6);
        _registerEmployee(alice, aliceSalary);

        // Skip 8 days and switch to ETH
        skip(8 days);
        vm.prank(alice);
        humanResources.switchCurrency();

        uint256 expectedUSDC = (aliceSalary * 8) / 7 / 1e12;
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertEq(IERC20(_USDC).balanceOf(alice), expectedUSDC, "Mismatch in USDC withdrawal");


        // Skip 3 more days and switch back to USDC
        skip(3 days);
        vm.prank(alice);
        humanResources.switchCurrency();

        // Withdrawal in ETH
        uint256 expectedETH = (aliceSalary * 1e18 * 3) / ethPrice / 7;
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertApproxEqRel(alice.balance, expectedETH, 0.01e18, "Mismatch in first ETH withdrawal");
    }

    function test_salaryResetsOnReRegistration() public {
        _mintTokensFor(_USDC, address(humanResources), 50_000e6);
        _registerEmployee(alice, aliceSalary);

        // Skip 4 days and withdraw partially
        skip(4 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 partialUSDC = (aliceSalary * 4) / 7 / 1e12;
        assertEq(IERC20(_USDC).balanceOf(alice), partialUSDC, "Partial withdrawal mismatch");

        // Terminate and re-register with new salary
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);
        _registerEmployee(alice, aliceSalary * 2);

        // Skip 2 days and withdraw
        skip(2 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 expectedUSDC = partialUSDC + (aliceSalary * 2 * 2) / 7 / 1e12;
        assertEq(IERC20(_USDC).balanceOf(alice), expectedUSDC, "Mismatch in salary after re-registration");
    }
// commented to run with limited public RPC
    // function test_largeNumberOfEmployeesSimultaneousActions() public {
    //     _mintTokensFor(_USDC, address(humanResources), 50_000e8);
    //     uint256 numEmployees = 50;
    //     address[] memory employees = new address[](numEmployees);

    //     // Register multiple employees
    //     for (uint256 i = 0; i < numEmployees; i++) {
    //         employees[i] = makeAddr(string(abi.encodePacked("employee", i)));
    //         _registerEmployee(employees[i], aliceSalary);
    //     }

    //     // Skip 5 days
    //     skip(5 days);

    //     // All employees withdraw salary
    //     for (uint256 i = 0; i < numEmployees; i++) {
    //         vm.prank(employees[i]);
    //         humanResources.withdrawSalary();
    //     }

    //     // Validate each employee's balance
    //     uint256 expectedUSDC = (aliceSalary * 5) / 7 / 1e12;
    //     for (uint256 i = 0; i < numEmployees; i++) {
    //         assertEq(IERC20(_USDC).balanceOf(employees[i]), expectedUSDC, string(abi.encodePacked("Mismatch for employee ", i)));
    //     }
    // }

    function test_multipleEmployeesStaggeredOperations() public {
        _mintTokensFor(_USDC, address(humanResources), 100_000e6);
        _registerEmployee(alice, aliceSalary);
        _registerEmployee(bob, bobSalary);

        // Alice switches currency after 3 days
        skip(3 days);
        vm.prank(alice);
        humanResources.switchCurrency();
        uint256 expectedAliceUSDC = (aliceSalary * 3) / 7 / 1e12;
        // Bob withdraws after 5 days
        skip(2 days);
        vm.prank(bob);
        humanResources.withdrawSalary();

        // Alice switches back to USDC after another 4 days
        skip(4 days);
        vm.prank(alice);
        humanResources.switchCurrency();

        // Validate balances
        uint256 expectedAliceETH = (aliceSalary * 1e18 * 6) / ethPrice / 7;
        uint256 expectedBobUSDC = (bobSalary * 5) / 7 / 1e12;

        assertApproxEqRel(alice.balance, expectedAliceETH, 0.01e18, "Mismatch in Alice's ETH withdrawal");
        assertEq(IERC20(_USDC).balanceOf(bob), expectedBobUSDC, "Mismatch in Bob's USDC withdrawal");
        assertEq(IERC20(_USDC).balanceOf(alice), expectedAliceUSDC, "Mismatch in Alice's USDC after switch");
    }
    function _mintTokensFor(
        address token_,
        address account_,
        uint256 amount_
    ) internal {
        stdstore
            .target(token_)
            .sig(IERC20(token_).balanceOf.selector)
            .with_key(account_)
            .checked_write(amount_);
    }
}

