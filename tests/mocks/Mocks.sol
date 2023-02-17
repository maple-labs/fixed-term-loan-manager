// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { LoanManagerStorage } from "../../contracts/proxy/LoanManagerStorage.sol";

contract MockGlobals {

    bool internal _isFactory;
    bool internal _isValidScheduledCall;

    address public governor;
    address public mapleTreasury;

    bool public protocolPaused;

    mapping(address => bool) public isPoolDeployer;

    mapping(address => uint256) public getLatestPrice;
    mapping(address => uint256) public platformManagementFeeRate;

    constructor(address governor_) {
        governor = governor_;
    }

    function isFactory(bytes32, address) external view returns (bool isFactory_) {
        isFactory_ = _isFactory;
    }

    function isValidScheduledCall(address, address, bytes32, bytes calldata) external view returns (bool isValid_) {
        isValid_ = _isValidScheduledCall;
    }

    function __setIsFactory(bool isFactory_) external {
        _isFactory = isFactory_;
    }

    function __setIsValidScheduledCall(bool isValid_) external {
        _isValidScheduledCall = isValid_;
    }

    function __setProtocolPaused(bool paused_) external {
        protocolPaused = paused_;
    }

    function setPlatformManagementFeeRate(address poolManager_, uint256 platformManagementFeeRate_) external {
        platformManagementFeeRate[poolManager_] = platformManagementFeeRate_;
    }

    function setMapleTreasury(address treasury_) external {
        mapleTreasury = treasury_;
    }

    function setValidPoolDeployer(address poolDeployer_, bool isValid_) external {
        isPoolDeployer[poolDeployer_] = isValid_;
    }

    function unscheduleCall(address, bytes32, bytes calldata) external {}

}

contract MockLoan {

    address public borrower;
    address public collateralAsset;
    address public fundsAsset;

    bool public isImpaired;

    uint256 public collateral;
    uint256 public delegateServiceFee;
    uint256 public nextPaymentInterest;
    uint256 public nextPaymentDueDate;
    uint256 public nextPaymentLateInterest;
    uint256 public nextPaymentPrincipal;
    uint256 public originalNextPaymentDueDate;
    uint256 public paymentInterval;
    uint256 public platformServiceFee;
    uint256 public unimpairedPaymentDueDate;
    uint256 public principal;
    uint256 public principalRequested;
    uint256 public refinanceInterest;

    // Refinance Variables
    uint256 public refinanceNextPaymentInterest;
    uint256 public refinanceNextPaymentDueDate;
    uint256 public refinanceNextPaymentPrincipal;
    uint256 public refinancePaymentInterval;
    uint256 public refinancePrincipal;
    uint256 public refinancePrincipalRequested;

    mapping(address => uint256) public unaccountedAmounts;

    constructor(address collateralAsset_, address fundsAsset_) {
        collateralAsset = collateralAsset_;
        fundsAsset      = fundsAsset_;
    }

    function acceptNewTerms(address, uint256, bytes[] calldata) external returns (bytes32 refinanceCommitment_) {
        nextPaymentInterest  = refinanceNextPaymentInterest;
        nextPaymentDueDate   = refinanceNextPaymentDueDate;
        nextPaymentPrincipal = refinanceNextPaymentPrincipal;
        paymentInterval      = refinancePaymentInterval;
        principal            = refinancePrincipal;
        principalRequested   = refinancePrincipalRequested;

        refinanceNextPaymentInterest  = 0;
        refinanceNextPaymentDueDate   = 0;
        refinanceNextPaymentPrincipal = 0;
        refinancePaymentInterval      = 0;
        refinancePrincipal            = 0;
        refinancePrincipalRequested   = 0;

        refinanceCommitment_ = 0; // Mock return
    }

    function fundLoan() external returns (uint256 fundsLent_) {
        // Do nothing
    }

    function getNextPaymentDetailedBreakdown() external view returns (
        uint256 principal_,
        uint256[3] memory interest_,
        uint256[2] memory fees_
    ) {
        principal_ = nextPaymentPrincipal;

        interest_[0] = nextPaymentInterest;
        interest_[1] = nextPaymentLateInterest;
        interest_[2] = refinanceInterest;

        fees_[0] = delegateServiceFee;
        fees_[1] = platformServiceFee;
    }

    function repossess(address destination_) external returns (uint256 collateralRepossessed_, uint256 fundsAssetRepossessed_) {
        collateralRepossessed_ = collateral;
        fundsAssetRepossessed_ = 0;
        MockERC20(collateralAsset).transfer(destination_, collateral);
    }

    function removeLoanImpairment() external {
        nextPaymentDueDate = unimpairedPaymentDueDate;
        delete unimpairedPaymentDueDate;

        isImpaired = false;
    }

    function setPendingLender(address lender_) external {
        // Do nothing
    }

    function acceptLender() external {
        // Do nothing
    }

    function impairLoan() external {
        unimpairedPaymentDueDate = nextPaymentDueDate;
        nextPaymentDueDate       = block.timestamp;
        isImpaired               = true;
    }

    function __setCollateral(uint256 collateral_) external {
        collateral = collateral_;
    }

      function __setCollateralAsset(address collateralAsset_) external {
        collateralAsset = collateralAsset_;
    }

    function __setNextPaymentDueDate(uint256 nextPaymentDueDate_) external {
        nextPaymentDueDate = nextPaymentDueDate_;
    }

    function __setNextPaymentInterest(uint256 nextPaymentInterest_) external {
        nextPaymentInterest = nextPaymentInterest_;
    }

    function __setNextPaymentLateInterest(uint256 nextPaymentLateInterest_) external {
        nextPaymentLateInterest = nextPaymentLateInterest_;
    }

    function __setNextPaymentPrincipal(uint256 nextPaymentPrincipal_) external {
        nextPaymentPrincipal = nextPaymentPrincipal_;
    }

    function __setOriginalNextPaymentDueDate(uint256 originalNextPaymentDueDate_) external {
        originalNextPaymentDueDate = originalNextPaymentDueDate_;
    }

    function __setPlatformServiceFee(uint256 platformServiceFee_) external {
        platformServiceFee = platformServiceFee_;
    }

    function __setPrincipal(uint256 principal_) external {
        principal = principal_;
    }

    function __setPrincipalRequested(uint256 principalRequested_) external {
        principalRequested = principalRequested_;
    }

    function __setRefinanceInterest(uint256 refinanceInterest_) external {
        refinanceInterest = refinanceInterest_;
    }

    function __setRefinancePrincipal(uint256 principal_) external {
        refinancePrincipal = principal_;
    }

    function __setRefinanceNextPaymentInterest(uint256 nextPaymentInterest_) external {
        refinanceNextPaymentInterest = nextPaymentInterest_;
    }

    function __setRefinanceNextPaymentDueDate(uint256 nextPaymentDueDate_) external {
        refinanceNextPaymentDueDate = nextPaymentDueDate_;
    }

}

contract MockLoanManagerMigrator is LoanManagerStorage {

    fallback() external {
        fundsAsset = abi.decode(msg.data, (address));
    }

}

contract MockPool {

    address public asset;
    address public manager;

    function __setAsset(address asset_) external {
        asset = asset_;
    }

    function __setManager(address manager_) external {
        manager = manager_;
    }

}

contract MockPoolManager {

    address _factory;

    address public poolDelegate;

    uint256 public delegateManagementFeeRate;

    function factory() external view returns (address factory_) {
        factory_ = _factory;
    }

    function hasSufficientCover() external pure returns (bool hasSufficientCover_) {
        hasSufficientCover_ = true;
    }

    function setDelegateManagementFeeRate(uint256 delegateManagementFeeRate_) external {
        delegateManagementFeeRate = delegateManagementFeeRate_;
    }

    function __setFactory(address factory_) external {
        _factory = factory_;
    }

    function __setPoolDelegate(address poolDelegate_) external {
        poolDelegate = poolDelegate_;
    }

}

contract MockLiquidator {

    uint256 public collateralRemaining;

    fallback() external {
        // Do nothing.
    }

}

contract MockLiquidatorFactory {

    function createInstance(bytes calldata, bytes32) external returns (address instance_) {
        instance_ = address(new MockLiquidator());
    }

}

contract MockFactory {

    bool _isInstance;

    function isInstance(address) external view returns (bool isInstance_) {
        isInstance_ = _isInstance;
    }

    function __setIsInstance(bool isInstance_) external {
        _isInstance = isInstance_;
    }
    
}
