// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { LoanManager }            from "../contracts/LoanManager.sol";
import { LoanManagerFactory }     from "../contracts/proxy/LoanManagerFactory.sol";
import { LoanManagerInitializer } from "../contracts/proxy/LoanManagerInitializer.sol";

import { MockFactory, MockGlobals, MockPoolManager } from "./mocks/Mocks.sol";

contract CreateInstanceTests is Test {

    address internal governor;
    address internal implementation;
    address internal initializer;

    address asset        = makeAddr("asset");
    address pool         = makeAddr("pool");
    address poolDeployer = makeAddr("poolDeployer");

    MockGlobals     internal globals;
    MockPoolManager internal poolManager;
    MockFactory     internal poolManagerFactory;

    LoanManagerFactory internal factory;

    function setUp() public virtual {
        governor       = makeAddr("governor");
        implementation = address(new LoanManager());
        initializer    = address(new LoanManagerInitializer());

        globals            = new MockGlobals(governor);
        poolManager        = new MockPoolManager();
        poolManagerFactory = new MockFactory();

        vm.startPrank(governor);
        factory = new LoanManagerFactory(address(globals));
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);
        vm.stopPrank();

        globals.setValidPoolDeployer(poolDeployer, true);

        poolManager.__setAsset(asset);
        poolManager.__setPool(pool);
    }

    function test_createInstance_notPoolDeployer() external {
        vm.expectRevert();
        LoanManager(factory.createInstance(abi.encode(address(poolManager)), "SALT"));
    }

    function test_createInstance_invalidPoolManagerFactory() external {
        vm.prank(address(poolManager));
        vm.expectRevert("LMF:CI:INVALID_FACTORY");
        LoanManager(factory.createInstance(abi.encode(address(poolManager)), "SALT"));
    }

    function test_createInstance_notPoolManager() external {
        globals.__setIsFactory(true);
        poolManager.__setFactory(address(poolManagerFactory));

        vm.prank(address(poolManager));
        vm.expectRevert("LMF:CI:NOT_PM");
        LoanManager(factory.createInstance(abi.encode(address(poolManager)), "SALT"));
    }

    function testFail_createInstance_notPool() external {
        factory.createInstance(abi.encode(address(1)), "SALT");
    }

    function testFail_createInstance_collision() external {
        factory.createInstance(abi.encode(address(poolManager)), "SALT");
        factory.createInstance(abi.encode(address(poolManager)), "SALT");
    }

    function test_createInstance_success_asPoolDeployer() external {
        vm.prank(poolDeployer);
        LoanManager loanManager_ = LoanManager(factory.createInstance(abi.encode(address(poolManager)), "SALT"));

        assertEq(loanManager_.pool(),        pool);
        assertEq(loanManager_.fundsAsset(),  asset);
        assertEq(loanManager_.poolManager(), address(poolManager));
    }

    function test_createInstance_asPoolManager() external {
        globals.__setIsFactory(true);
        poolManager.__setFactory(address(poolManagerFactory));
        poolManagerFactory.__setIsInstance(true);

        vm.prank(address(poolManager));
        LoanManager loanManager_ = LoanManager(factory.createInstance(abi.encode(address(poolManager)), "SALT"));

        assertEq(loanManager_.pool(),        pool);
        assertEq(loanManager_.fundsAsset(),  asset);
        assertEq(loanManager_.poolManager(), address(poolManager));
    }

}