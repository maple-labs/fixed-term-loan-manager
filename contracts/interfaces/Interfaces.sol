// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

interface IMapleGlobalsLike {

    function isPoolDeployer(address poolDeployer_) external view returns (bool isPoolDeployer_);

    function platformManagementFeeRate(address poolManager_) external view returns (uint256 platformManagementFeeRate_);

    function migrationAdmin() external view returns (address migrationAdmin_);

}

interface IMapleLoanLike {

    function acceptLender() external;

    function getNextPaymentBreakdown() external view returns (uint256 principal_, uint256 interest_, uint256 fee1_, uint256 fee2_);

    function nextPaymentDueDate() external view returns (uint256 nextPaymentDueDate_);

    function paymentInterval() external view returns (uint256 paymentInterval_);

    function principal() external view returns (uint256 principal_);

    function refinanceInterest() external view returns (uint256 refinanceInterest_);

    function setPendingLender(address pendingLender_) external;

}

interface IPoolLike {

    function asset() external view returns (address asset_);

    function manager() external view returns (address manager_);

}

interface IPoolManagerLike {

    function delegateManagementFeeRate() external view returns (uint256 delegateManagementFeeRate_);

    function globals() external view returns (address globals_);

}
