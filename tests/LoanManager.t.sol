// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Address, TestUtils } from "../modules/contract-test-utils/contracts/test.sol";
import { MockERC20 }          from "../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { LoanManagerFactory }     from "../contracts/proxy/LoanManagerFactory.sol";
import { LoanManagerInitializer } from "../contracts/proxy/LoanManagerInitializer.sol";

import {
    MockGlobals,
    MockLoan,
    MockLoanManagerMigrator,
    MockPool,
    MockPoolManager
} from "./mocks/Mocks.sol";

import { ILoanManagerStructs } from "./interfaces/ILoanManagerStructs.sol";

import { LoanManagerHarness } from "./harnesses/LoanManagerHarness.sol";

contract LoanManagerBaseTest is TestUtils {

    uint256 constant internal START = 1_664_288_489 seconds;

    address internal governor       = address(new Address());
    address internal migrationAdmin = address(new Address());
    address internal poolDelegate   = address(new Address());

    address internal implementation = address(new LoanManagerHarness());
    address internal initializer    = address(new LoanManagerInitializer());

    uint256 internal delegateManagementFeeRate = 0.05e6;
    uint256 internal platformManagementFeeRate = 0.15e6;

    MockERC20       internal fundsAsset;
    MockGlobals     internal globals;
    MockLoan        internal loan1;
    MockLoan        internal loan2;
    MockPool        internal pool;
    MockPoolManager internal poolManager;

    LoanManagerFactory internal factory;
    LoanManagerHarness internal loanManager;

    function setUp() public virtual {
        fundsAsset  = new MockERC20("FundsAsset", "FA", 18);
        globals     = new MockGlobals(governor);
        loan1       = new MockLoan();
        loan2       = new MockLoan();
        poolManager = new MockPoolManager();
        pool        = new MockPool();

        globals.setMigrationAdmin(migrationAdmin);
        globals.setPlatformManagementFeeRate(address(poolManager), platformManagementFeeRate);
        globals.setValidPoolDeployer(address(this), true);

        pool.__setAsset(address(fundsAsset));
        pool.__setManager(address(poolManager));

        poolManager.__setGlobals(address(globals));
        poolManager.setDelegateManagementFeeRate(delegateManagementFeeRate);

        vm.startPrank(governor);
        factory = new LoanManagerFactory(address(globals));
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);
        vm.stopPrank();

        bytes memory arguments = LoanManagerInitializer(initializer).encodeArguments(address(pool));
        loanManager = LoanManagerHarness(LoanManagerFactory(factory).createInstance(arguments, ""));

        vm.warp(START);
    }

    function _assertLiquidationInfo(
        ILoanManagerStructs.LiquidationInfo memory liquidationInfo,
        uint256 principal,
        uint256 interest,
        uint256 lateInterest,
        uint256 platformFees,
        address liquidator
    ) internal {
        assertEq(liquidationInfo.principal,    principal);
        assertEq(liquidationInfo.interest,     interest);
        assertEq(liquidationInfo.lateInterest, lateInterest);
        assertEq(liquidationInfo.platformFees, platformFees);
        assertEq(liquidationInfo.liquidator,   liquidator);
    }
}

contract MigrateTests is LoanManagerBaseTest {

    address internal migrator = address(new MockLoanManagerMigrator());

    function test_migrate_notFactory() external {
        vm.expectRevert("TLM:M:NOT_FACTORY");
        loanManager.migrate(migrator, "");
    }

    function test_migrate_internalFailure() external {
        vm.prank(loanManager.factory());
        vm.expectRevert("TLM:M:FAILED");
        loanManager.migrate(migrator, "");
    }

    function test_migrate_success() external {
        assertEq(loanManager.fundsAsset(), address(fundsAsset));

        vm.prank(loanManager.factory());
        loanManager.migrate(migrator, abi.encode(address(0)));

        assertEq(loanManager.fundsAsset(), address(0));
    }

}

contract SetImplementationTests is LoanManagerBaseTest {

    address internal newImplementation = address(new LoanManagerHarness());

    function test_setImplementation_notFactory() external {
        vm.expectRevert("TLM:SI:NOT_FACTORY");
        loanManager.setImplementation(newImplementation);
    }

    function test_setImplementation_success() external {
        assertEq(loanManager.implementation(), implementation);

        vm.prank(loanManager.factory());
        loanManager.setImplementation(newImplementation);

        assertEq(loanManager.implementation(), newImplementation);
    }

}

contract UpgradeTests is LoanManagerBaseTest {

    address internal newImplementation = address(new LoanManagerHarness());

    function setUp() public override {
        super.setUp();

        vm.startPrank(governor);
        factory.registerImplementation(2, newImplementation, address(0));
        factory.enableUpgradePath(1, 2, address(0));
        vm.stopPrank();
    }

    function test_upgrade_notPoolDelegate() external {
        vm.expectRevert("TLM:U:NOT_MA");
        loanManager.upgrade(2, "");
    }

    function test_upgrade_success() external {
        vm.prank(migrationAdmin);
        loanManager.upgrade(2, "");

        assertEq(loanManager.implementation(), newImplementation);
    }

}

contract LoanManagerSortingTests is LoanManagerBaseTest {

    address internal earliestLoan;
    address internal latestLoan;
    address internal medianLoan;
    address internal synchronizedLoan;

    LoanManagerHarness.PaymentInfo internal earliestPaymentInfo;
    LoanManagerHarness.PaymentInfo internal latestPaymentInfo;
    LoanManagerHarness.PaymentInfo internal medianPaymentInfo;
    LoanManagerHarness.PaymentInfo internal synchronizedPaymentInfo;

    function setUp() public override {
        super.setUp();

        earliestLoan     = address(new Address());
        medianLoan       = address(new Address());
        latestLoan       = address(new Address());
        synchronizedLoan = address(new Address());

        earliestPaymentInfo.paymentDueDate     = 10;
        medianPaymentInfo.paymentDueDate       = 20;
        synchronizedPaymentInfo.paymentDueDate = 20;
        latestPaymentInfo.paymentDueDate       = 30;
    }

    /**************************************************************************************************************************************/
    /*** Add Payment                                                                                                                    ***/
    /**************************************************************************************************************************************/

    function test_addPaymentToList_single() external {
        loanManager.addPaymentToList(earliestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),                 1);
        assertEq(loanManager.paymentWithEarliestDueDate(),     1);

        ( uint24 previous, uint24 next, uint48 paymentDueDate ) = loanManager.sortedPayments(1);

        assertEq(previous,       0);
        assertEq(next,           0);
        assertEq(paymentDueDate, earliestPaymentInfo.paymentDueDate);
    }

    function test_addPaymentToList_ascendingPair() external {
        loanManager.addPaymentToList(earliestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             1);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( uint24 previous, uint24 next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     0);

        loanManager.addPaymentToList(latestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             2);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     2);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 1);
        assertEq(next,     0);
    }

    function test_addPaymentToList_descendingPair() external {
        loanManager.addPaymentToList(latestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             1);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( uint24 previous, uint24 next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     0);

        loanManager.addPaymentToList(earliestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             2);
        assertEq(loanManager.paymentWithEarliestDueDate(), 2);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 2);
        assertEq(next,     0);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 0);
        assertEq(next,     1);
    }

    function test_addPaymentToList_synchronizedPair() external {
        loanManager.addPaymentToList(medianPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             1);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( uint24 previous, uint24 next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     0);

        loanManager.addPaymentToList(synchronizedPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             2);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     2);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 1);
        assertEq(next,     0);
    }

    function test_addPaymentToList_toHead() external {
        loanManager.addPaymentToList(medianPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             1);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( uint24 previous, uint24 next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     0);

        loanManager.addPaymentToList(latestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             2);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     2);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 1);
        assertEq(next,     0);

        loanManager.addPaymentToList(earliestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             3);
        assertEq(loanManager.paymentWithEarliestDueDate(), 3);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 3);
        assertEq(next,     2);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 1);
        assertEq(next,     0);

        ( previous, next, ) = loanManager.sortedPayments(3);

        assertEq(previous, 0);
        assertEq(next,     1);
    }

    function test_addPaymentToList_toMiddle() external {
        loanManager.addPaymentToList(earliestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             1);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( uint24 previous, uint24 next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     0);

        loanManager.addPaymentToList(latestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             2);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     2);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 1);
        assertEq(next,     0);

        loanManager.addPaymentToList(medianPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             3);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     3);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 3);
        assertEq(next,     0);

        ( previous, next, ) = loanManager.sortedPayments(3);

        assertEq(previous, 1);
        assertEq(next,     2);
    }

    function test_addPaymentToList_toTail() external {
        loanManager.addPaymentToList(earliestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             1);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( uint24 previous, uint24 next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     0);

        loanManager.addPaymentToList(medianPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             2);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     2);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 1);
        assertEq(next,     0);

        loanManager.addPaymentToList(latestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             3);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     2);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 1);
        assertEq(next,     3);

        ( previous, next, ) = loanManager.sortedPayments(3);

        assertEq(previous, 2);
        assertEq(next,     0);
    }

    /**************************************************************************************************************************************/
    /*** Remove Payment                                                                                                                 ***/
    /**************************************************************************************************************************************/

    function test_removePaymentFromList_invalidPaymentId() external {
        loanManager.addPaymentToList(earliestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             1);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( uint24 previous, uint24 next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     0);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 0);
        assertEq(next,     0);

        loanManager.removePaymentFromList(2);

        assertEq(loanManager.paymentCounter(),             1);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     0);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 0);
        assertEq(next,     0);
    }

    function test_removePaymentFromList_single() external {
        loanManager.addPaymentToList(earliestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             1);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( uint24 previous, uint24 next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     0);

        loanManager.removePaymentFromList(1);

        assertEq(loanManager.paymentCounter(),             1);
        assertEq(loanManager.paymentWithEarliestDueDate(), 0);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     0);
    }

    function test_removePaymentFromList_pair() external {
        loanManager.addPaymentToList(earliestPaymentInfo.paymentDueDate);
        loanManager.addPaymentToList(latestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             2);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( uint24 previous, uint24 next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     2);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 1);
        assertEq(next,     0);

        loanManager.removePaymentFromList(1);

        assertEq(loanManager.paymentCounter(),             2);
        assertEq(loanManager.paymentWithEarliestDueDate(), 2);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     0);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 0);
        assertEq(next,     0);
    }

    function test_removePaymentFromList_earliestDueDate() external {
        loanManager.addPaymentToList(earliestPaymentInfo.paymentDueDate);
        loanManager.addPaymentToList(medianPaymentInfo.paymentDueDate);
        loanManager.addPaymentToList(latestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             3);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( uint24 previous, uint24 next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     2);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 1);
        assertEq(next,     3);

        ( previous, next, ) = loanManager.sortedPayments(3);

        assertEq(previous, 2);
        assertEq(next,     0);

        loanManager.removePaymentFromList(1);

        assertEq(loanManager.paymentCounter(),             3);
        assertEq(loanManager.paymentWithEarliestDueDate(), 2);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     0);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 0);
        assertEq(next,     3);

        ( previous, next, ) = loanManager.sortedPayments(3);

        assertEq(previous, 2);
        assertEq(next,     0);
    }

    function test_removePaymentFromList_medianDueDate() external {
        loanManager.addPaymentToList(earliestPaymentInfo.paymentDueDate);
        loanManager.addPaymentToList(medianPaymentInfo.paymentDueDate);
        loanManager.addPaymentToList(latestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             3);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( uint24 previous, uint24 next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     2);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 1);
        assertEq(next,     3);

        ( previous, next, ) = loanManager.sortedPayments(3);

        assertEq(previous, 2);
        assertEq(next,     0);

        loanManager.removePaymentFromList(2);

        assertEq(loanManager.paymentCounter(),             3);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     3);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 0);
        assertEq(next,     0);

        ( previous, next, ) = loanManager.sortedPayments(3);

        assertEq(previous, 1);
        assertEq(next,     0);
    }

    function test_removePaymentFromList_latestDueDate() external {
        loanManager.addPaymentToList(earliestPaymentInfo.paymentDueDate);
        loanManager.addPaymentToList(medianPaymentInfo.paymentDueDate);
        loanManager.addPaymentToList(latestPaymentInfo.paymentDueDate);

        assertEq(loanManager.paymentCounter(),             3);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( uint24 previous, uint24 next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     2);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 1);
        assertEq(next,     3);

        ( previous, next, ) = loanManager.sortedPayments(3);

        assertEq(previous, 2);
        assertEq(next,     0);

        loanManager.removePaymentFromList(3);

        assertEq(loanManager.paymentCounter(),             3);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);

        ( previous, next, ) = loanManager.sortedPayments(1);

        assertEq(previous, 0);
        assertEq(next,     2);

        ( previous, next, ) = loanManager.sortedPayments(2);

        assertEq(previous, 1);
        assertEq(next,     0);

        ( previous, next, ) = loanManager.sortedPayments(3);

        assertEq(previous, 0);
        assertEq(next,     0);
    }

}

contract QueueNextPaymentTests is LoanManagerBaseTest {

    uint256 internal principalRequested = 1_000_000e18;
    uint256 internal paymentInterest    = 1e18;
    uint256 internal paymentPrincipal   = 0;

    MockLoan internal loan;

    function setUp() public override {
        super.setUp();

        loan = new MockLoan();

        // Set next payment information for loanManager to use.
        loan.__setPrincipalRequested(principalRequested);  // Simulate funding
        loan.__setNextPaymentInterest(paymentInterest);
        loan.__setNextPaymentPrincipal(paymentPrincipal);
        loan.__setNextPaymentDueDate(block.timestamp + 100);
    }

    function test_queueNextPayment_fees() external {
        uint256 platformManagementFeeRate_ = 75_0000;
        uint256 delegateManagementFeeRate_ = 50_0000;

        globals.setPlatformManagementFeeRate(address(poolManager), platformManagementFeeRate_);
        poolManager.setDelegateManagementFeeRate(delegateManagementFeeRate_);

        loanManager.__queueNextPayment(address(loan), block.timestamp, block.timestamp + 30 days);

        uint256 paymentId = loanManager.paymentIdOf(address(loan));
        ILoanManagerStructs.PaymentInfo memory paymentInfo = ILoanManagerStructs(address(loanManager)).payments(paymentId);

        assertEq(paymentInfo.platformManagementFeeRate, 75_0000);
        assertEq(paymentInfo.delegateManagementFeeRate, 25_0000);  // Gets reduced to 0.25 so sum is less than 100%
    }

    function testFuzz_queueNextPayment_fees(uint256 platformManagementFeeRate_, uint256 delegateManagementFeeRate_) external {
        platformManagementFeeRate_ = constrictToRange(platformManagementFeeRate_, 0, 100_0000);
        delegateManagementFeeRate_ = constrictToRange(delegateManagementFeeRate_, 0, 100_0000);

        globals.setPlatformManagementFeeRate(address(poolManager), platformManagementFeeRate_);
        poolManager.setDelegateManagementFeeRate(delegateManagementFeeRate_);

        loanManager.__queueNextPayment(address(loan), block.timestamp, block.timestamp + 30 days);

        uint256 paymentId = loanManager.paymentIdOf(address(loan));
        ILoanManagerStructs.PaymentInfo memory paymentInfo = ILoanManagerStructs(address(loanManager)).payments(paymentId);

        assertEq(paymentInfo.platformManagementFeeRate, platformManagementFeeRate_);

        assertTrue(paymentInfo.platformManagementFeeRate + paymentInfo.delegateManagementFeeRate <= 100_0000);
    }

}

contract UintCastingTests is LoanManagerBaseTest {

    function test_castUint24() external {
        vm.expectRevert("TLM:UINT24_CAST_OOB");
        loanManager.castUint24(2 ** 24);

        uint256 castedValue = loanManager.castUint24(2 ** 24 - 1);

        assertEq(castedValue, 2 ** 24 - 1);
    }

    function test_castUint48() external {
        vm.expectRevert("TLM:UINT48_CAST_OOB");
        loanManager.castUint48(2 ** 48);

        uint256 castedValue = loanManager.castUint48(2 ** 48 - 1);

        assertEq(castedValue, 2 ** 48 - 1);
    }

    function test_castUint112() external {
        vm.expectRevert("TLM:UINT112_CAST_OOB");
        loanManager.castUint112(2 ** 112);

        uint256 castedValue = loanManager.castUint112(2 ** 112 - 1);

        assertEq(castedValue, 2 ** 112 - 1);
    }

    function test_castUint128() external {
        vm.expectRevert("TLM:UINT128_CAST_OOB");
        loanManager.castUint128(2 ** 128);

        uint256 castedValue = loanManager.castUint128(2 ** 128 - 1);

        assertEq(castedValue, 2 ** 128 - 1);
    }
}

contract SetterTests is LoanManagerBaseTest {

    function setUp() public override {
        super.setUp();

        loanManager.__setDomainStart(START);
        loanManager.__setDomainEnd(START + 1_000_000);
        loanManager.__setIssuanceRate(0.1e30);
        loanManager.__setPrincipalOut(1_000_000e6);
        loanManager.__setAccountedInterest(10_000e6);
    }

    function test_getAccruedInterest() external {
        // At the start accrued interest is zero.
        assertEq(loanManager.getAccruedInterest(), 0);

        vm.warp(START + 1_000);
        assertEq(loanManager.getAccruedInterest(), 100);

        vm.warp(START + 22_222);
        assertEq(loanManager.getAccruedInterest(), 2222);

        vm.warp(START + 888_888);
        assertEq(loanManager.getAccruedInterest(), 88888);

        vm.warp(START + 1_000_000);
        assertEq(loanManager.getAccruedInterest(), 100_000);

        vm.warp(START + 1_000_000 + 1);
        assertEq(loanManager.getAccruedInterest(), 100_000);

        vm.warp(START + 2_000_000);
        assertEq(loanManager.getAccruedInterest(), 100_000);
    }

    function test_getAssetsUnderManagement() external {
        // At the start there's only principal out and accounted interest
        assertEq(loanManager.assetsUnderManagement(), 1_000_000e6 + 10_000e6);

         vm.warp(START + 1_000);
        assertEq(loanManager.assetsUnderManagement(), 1_000_000e6 + 10_000e6 + 100);

        vm.warp(START + 22_222);
        assertEq(loanManager.assetsUnderManagement(), 1_000_000e6 + 10_000e6 + 2222);

        vm.warp(START + 888_888);
        assertEq(loanManager.assetsUnderManagement(), 1_000_000e6 + 10_000e6 + 88888);

        vm.warp(START + 1_000_000);
        assertEq(loanManager.assetsUnderManagement(), 1_000_000e6 + 10_000e6 + 100_000);

        vm.warp(START + 1_000_000 + 1);
        assertEq(loanManager.assetsUnderManagement(), 1_000_000e6 + 10_000e6 + 100_000);

        vm.warp(START + 2_000_000);
        assertEq(loanManager.assetsUnderManagement(), 1_000_000e6 + 10_000e6 + 100_000);
    }

}

contract AddTests is LoanManagerBaseTest {

    function test_add_notMigrationAdmin() external {
        vm.expectRevert("TLM:A:NOT_MA");
        loanManager.add(address(loan1));
    }

    function test_add_noPayment() external {
        vm.prank(address(migrationAdmin));
        vm.expectRevert("TLM:A:INVALID_LOAN");
        loanManager.add(address(loan1));
    }

    function test_add_latePayment() external {
        // Set up for success case
        loan1.__setPaymentInterval(30 days);
        loan1.__setPrincipal(1_000_000e18);
        loan1.__setNextPaymentInterest(50_000e18);
        loan1.__setRefinanceInterest(0);

        loan1.__setNextPaymentDueDate(block.timestamp);

        vm.prank(address(migrationAdmin));
        vm.expectRevert("TLM:A:INVALID_LOAN");
        loanManager.add(address(loan1));

        loan1.__setNextPaymentDueDate(block.timestamp + 1);

        vm.prank(address(migrationAdmin));
        loanManager.add(address(loan1));
    }

    function test_add_multipleLoans_a() external {
        {
            (
                uint256 previous_,
                uint256 next_,
                uint256 sortedPaymentDueDate_
            ) = loanManager.sortedPayments(1);

            assertEq(previous_,             0);
            assertEq(next_,                 0);
            assertEq(sortedPaymentDueDate_, 0);

            (
                uint256 platformManagementFeeRate_,
                uint256 delegateManagementFeeRate_,
                uint256 startDate_,
                uint256 paymentDueDate_,
                uint256 incomingNetInterest_,
                uint256 refinanceInterest_,
                uint256 issuanceRate_
            ) = loanManager.payments(1);

            assertEq(delegateManagementFeeRate_, 0);
            assertEq(incomingNetInterest_,       0);
            assertEq(issuanceRate_,              0);
            assertEq(paymentDueDate_,            0);
            assertEq(platformManagementFeeRate_, 0);
            assertEq(refinanceInterest_,         0);
            assertEq(startDate_,                 0);
        }

        assertEq(loanManager.accountedInterest(),          0);
        assertEq(loanManager.assetsUnderManagement(),      0);
        assertEq(loanManager.domainEnd(),                  0);
        assertEq(loanManager.domainStart(),                0);
        assertEq(loanManager.getAccruedInterest(),         0);
        assertEq(loanManager.issuanceRate(),               0);
        assertEq(loanManager.paymentCounter(),             0);
        assertEq(loanManager.paymentWithEarliestDueDate(), 0);
        assertEq(loanManager.principalOut(),               0);
        assertEq(loanManager.unrealizedLosses(),           0);

        /**********************************************************************************************************************************/
        /*** Add the first loan                                                                                                         ***/
        /**********************************************************************************************************************************/

        loan1.__setNextPaymentDueDate(START + 20 days);
        loan1.__setPaymentInterval(30 days);
        loan1.__setPrincipal(1_000_000e18);
        loan1.__setNextPaymentInterest(50_000e18);
        loan1.__setRefinanceInterest(0);

        vm.prank(address(migrationAdmin));
        loanManager.add(address(loan1));

        {
            (
                uint256 previous_,
                uint256 next_,
                uint256 sortedPaymentDueDate_
            ) = loanManager.sortedPayments(1);

            assertEq(previous_,             0);
            assertEq(next_,                 0);
            assertEq(sortedPaymentDueDate_, START + 20 days);

            (
                uint256 platformManagementFeeRate_,
                uint256 delegateManagementFeeRate_,
                uint256 startDate_,
                uint256 paymentDueDate_,
                uint256 incomingNetInterest_,
                uint256 refinanceInterest_,
                uint256 issuanceRate_
            ) = loanManager.payments(1);

            assertEq(delegateManagementFeeRate_, 0.05e6);
            assertEq(incomingNetInterest_,       50_000e18 * 4 / 5 - 1);  // Rounding error due to issuance rate calculation.
            assertEq(issuanceRate_,              uint256(40_000e18) * 1e30 / 30 days);
            assertEq(paymentDueDate_,            START + 20 days);
            assertEq(platformManagementFeeRate_, 0.15e6);
            assertEq(refinanceInterest_,         0);
            assertEq(startDate_,                 START - 10 days);
        }

        uint256 issuanceRate      = uint256(40_000e18) * 1e30 / 30 days;
        uint256 accountedInterest = issuanceRate * 10 days / 1e30;

        assertEq(loanManager.accountedInterest(),          accountedInterest);
        assertEq(loanManager.assetsUnderManagement(),      1_000_000e18 + accountedInterest);
        assertEq(loanManager.domainEnd(),                  START + 20 days);
        assertEq(loanManager.domainStart(),                START);
        assertEq(loanManager.getAccruedInterest(),         0);
        assertEq(loanManager.issuanceRate(),               issuanceRate);
        assertEq(loanManager.paymentCounter(),             1);
        assertEq(loanManager.paymentWithEarliestDueDate(), 1);
        assertEq(loanManager.principalOut(),               1_000_000e18);
        assertEq(loanManager.unrealizedLosses(),           0);

        /**********************************************************************************************************************************/
        /*** Add the second loan                                                                                                        ***/
        /**********************************************************************************************************************************/

        loan2.__setNextPaymentDueDate(START + 10 days);
        loan2.__setPaymentInterval(30 days);
        loan2.__setPrincipal(2_500_000e18);
        loan2.__setNextPaymentInterest(100_000e18);
        loan2.__setRefinanceInterest(0);

        vm.prank(address(migrationAdmin));
        loanManager.add(address(loan2));

        {
            (
                uint256 previous_,
                uint256 next_,
                uint256 sortedPaymentDueDate_
            ) = loanManager.sortedPayments(1);

            assertEq(previous_,             2);
            assertEq(next_,                 0);
            assertEq(sortedPaymentDueDate_, START + 20 days);

            (
                uint256 platformManagementFeeRate_,
                uint256 delegateManagementFeeRate_,
                uint256 startDate_,
                uint256 paymentDueDate_,
                uint256 incomingNetInterest_,
                uint256 refinanceInterest_,
                uint256 issuanceRate_
            ) = loanManager.payments(1);

            assertEq(delegateManagementFeeRate_, 0.05e6);
            assertEq(incomingNetInterest_,       50_000e18 * 4 / 5 - 1);  // Rounding error due to issuance rate calculation.
            assertEq(issuanceRate_,              uint256(40_000e18) * 1e30 / 30 days);
            assertEq(paymentDueDate_,            START + 20 days);
            assertEq(platformManagementFeeRate_, 0.15e6);
            assertEq(refinanceInterest_,         0);
            assertEq(startDate_,                 START - 10 days);
        }

        {
            (
                uint256 previous_,
                uint256 next_,
                uint256 sortedPaymentDueDate_
            ) = loanManager.sortedPayments(2);

            assertEq(previous_,             0);
            assertEq(next_,                 1);
            assertEq(sortedPaymentDueDate_, START + 10 days);

            (
                uint256 platformManagementFeeRate_,
                uint256 delegateManagementFeeRate_,
                uint256 startDate_,
                uint256 paymentDueDate_,
                uint256 incomingNetInterest_,
                uint256 refinanceInterest_,
                uint256 issuanceRate_
            ) = loanManager.payments(2);

            assertEq(delegateManagementFeeRate_, 0.05e6);
            assertEq(incomingNetInterest_,       100_000e18 * 4 / 5 - 1);  // Rounding error due to issuance rate calculation.
            assertEq(issuanceRate_,              uint256(80_000e18) * 1e30 / 30 days);
            assertEq(paymentDueDate_,            START + 10 days);
            assertEq(platformManagementFeeRate_, 0.15e6);
            assertEq(refinanceInterest_,         0);
            assertEq(startDate_,                 START - 20 days);
        }

        uint256 issuanceRate1 = uint256(40_000e18) * 1e30 / 30 days;
        uint256 issuanceRate2 = uint256(80_000e18) * 1e30 / 30 days;

        uint256 totalPrincipalOut      = 1_000_000e18 + 2_500_000e18;
        uint256 totalIssuanceRate      = issuanceRate1 + issuanceRate2;
        uint256 totalAccountedInterest = issuanceRate1 * 10 days / 1e30 + issuanceRate2 * 20 days / 1e30;

        assertEq(loanManager.accountedInterest(),          totalAccountedInterest);
        assertEq(loanManager.assetsUnderManagement(),      totalPrincipalOut + totalAccountedInterest);
        assertEq(loanManager.domainEnd(),                  START + 10 days);
        assertEq(loanManager.domainStart(),                START);
        assertEq(loanManager.getAccruedInterest(),         0);
        assertEq(loanManager.issuanceRate(),               totalIssuanceRate);
        assertEq(loanManager.paymentCounter(),             2);
        assertEq(loanManager.paymentWithEarliestDueDate(), 2);
        assertEq(loanManager.principalOut(),               totalPrincipalOut);
        assertEq(loanManager.unrealizedLosses(),           0);
    }

}
