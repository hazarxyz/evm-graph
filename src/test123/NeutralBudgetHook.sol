// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestHookBase} from "./TestHookBase.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TestProjectRevenue} from "./TestProjectRevenue.sol";
import {TestPlatformRevenue} from "./TestPlatformRevenue.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";

interface INeutralLaunchTokenOwner {
    function owner() external view returns (address);
}

/// @notice Replaceable configurable project fees and optional gross-ETH swap budget. Platform fee stays 0.3%.
/// @dev This entire implementation is replaceable. Pool principal and project fee claims are separate.
/// Native-specified partial fills revert atomically instead of charging fees on unexecuted volume.
contract NeutralBudgetHook is TestHookBase {
    using SafeCast for uint256;

    address private immutable SELF = address(this);
    // Dedicated unstructured storage namespace; future versions must preserve or explicitly migrate it.
    bytes32 private constant LAUNCH_SLOT = keccak256("test.hook.initial-launch.v1");

    struct LaunchState {
        address initializer;
        address token;
        uint160 openingPrice;
        int24 tickSpacing;
        bool poolInitialized;
        address feeRecipient;
    }

    error InvalidInitialization();
    error InvalidPool();
    error PartialNativeFill();
    error NotFeeRecipient();
    error InvalidFeeClaim();

    event ProjectFeeAccrued(
        PoolId indexed poolId, address indexed sender, bool exactInput, uint256 grossEth, uint256 feeEth
    );
    event ProjectFeesClaimed(address indexed recipient, uint256 amount);

    TestProjectRevenue public immutable projectRevenue;
    TestPlatformRevenue public immutable platformRevenue;
    constructor(IPoolManager manager, TestProjectRevenue project_, TestPlatformRevenue platform_) TestHookBase(manager) {
        if (address(project_.poolManager()) != address(manager) || address(platform_.poolManager()) != address(manager)) revert InvalidInitialization();
        projectRevenue = project_; platformRevenue = platform_;
    }

    function initialize(address initializer, address token, int24 tickSpacing, uint160 openingPrice) external {
        LaunchState storage state = _launch();
        if (
            address(this) == SELF || state.initializer != address(0) || initializer == address(0)
                || token.code.length == 0 || tickSpacing <= 0 || openingPrice == 0
        ) revert InvalidInitialization();
        state.initializer = initializer;
        state.token = token;
        state.tickSpacing = tickSpacing;
        state.openingPrice = openingPrice;
        state.feeRecipient = INeutralLaunchTokenOwner(token).owner();
        if (state.feeRecipient == address(0) || state.feeRecipient != projectRevenue.active()) revert InvalidInitialization();
    }

    function beforeInitialize(address sender, PoolKey calldata key, uint160 price)
        external
        override
        onlyPoolManager
        returns (bytes4)
    {
        LaunchState storage state = _launch();
        if (
            state.initializer == address(0) || state.poolInitialized || sender != state.initializer
                || Currency.unwrap(key.currency0) != address(0) || Currency.unwrap(key.currency1) != state.token
                || key.tickSpacing != state.tickSpacing || key.fee != LPFeeLibrary.DYNAMIC_FEE_FLAG
                || address(key.hooks) != address(this) || price != state.openingPrice
        ) revert InvalidInitialization();
        state.poolInitialized = true;
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata key, uint160, int24)
        external
        override
        onlyPoolManager
        returns (bytes4)
    {
        poolManager.updateDynamicLPFee(key, 0);
        return IHooks.afterInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata data)
        external
        override
        onlyPoolManager
        virtual returns (bytes4, BeforeSwapDelta, uint24)
    {
        _requirePool(key);
        uint256 fee;
        if (_nativeSpecified(params)) {
            uint256 requested = _specifiedAmount(params);
            fee = params.amountSpecified < 0 ? _fromGross(requested) : _fromNet(requested);
            _accrue(params.amountSpecified < 0 ? requested : requested + fee, fee);
        }
        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(fee.toInt128(), 0), LPFeeLibrary.OVERRIDE_FEE_FLAG | _swapLPFee());
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) external virtual override onlyPoolManager returns (bytes4, int128) {
        _requirePool(key);
        bool exactInput = params.amountSpecified < 0;
        int128 ethDelta = delta.amount0();
        uint256 ethAmount = ethDelta < 0 ? uint256(-int256(ethDelta)) : uint256(int256(ethDelta));
        uint256 fee;
        int128 returnedFee;
        uint256 gross;
        if (_nativeSpecified(params)) {
            uint256 requested = _specifiedAmount(params);
            fee = exactInput ? _fromGross(requested) : _fromNet(requested);
            uint256 expected = exactInput ? requested - fee : requested + fee;
            if (ethAmount != expected) revert PartialNativeFill();
            gross = exactInput ? requested : expected;
        } else {
            fee = exactInput ? _fromGross(ethAmount) : _fromNet(ethAmount);
            gross = exactInput ? ethAmount : ethAmount + fee;
            _accrue(gross, fee);
            returnedFee = fee.toInt128();
        }
        _checkBudget(data,gross);
        _afterSuccessfulSwap(gross,params.zeroForOne);
        emit ProjectFeeAccrued(key.toId(), sender, exactInput, gross, fee);
        return (IHooks.afterSwap.selector, returnedFee);
    }

    function feeRecipient() external view returns (address) {
        return _launch().feeRecipient;
    }

    function projectFeeBalance() public view returns (uint256) {
        (uint256 activeAmount,) = projectRevenue.balances();
        return activeAmount;
    }

    function collectProjectFees(uint256 amount) external {
        if (msg.sender != _launch().feeRecipient) revert NotFeeRecipient();
        projectRevenue.claimActive(amount);
    }

    event FeeAllocation(uint256 grossEth, uint256 projectEth, uint256 platformEth);

    event PlatformFeeAllocation(uint256 grossEth, uint256 canonicalEth, uint256 additionalEth);

    function _accrue(uint256 gross, uint256 totalFee) internal {
        uint256 project = Math.mulDiv(gross,projectFeePips(),1_000_000);
        uint256 platform = totalFee - project;
        if (project != 0) poolManager.mint(address(projectRevenue), 0, project);
        if (platform != 0) poolManager.mint(address(platformRevenue), 0, platform);
        uint256 canonical = gross / 1000;
        platformRevenue.recordAllocation(canonical, platform - canonical);
        emit FeeAllocation(gross, project, platform);
        emit PlatformFeeAllocation(gross, canonical, platform - canonical);
    }

    bytes32 private constant CONFIG_SLOT = keccak256("neutral.hook.fee-config.v1");
    struct FeeConfig { bool configured; uint24 projectPips; }
    error InvalidProjectRate();
    error InvalidBudgetData();
    error GrossBudgetExceeded(uint256 executed,uint256 maximum);
    event ProjectRateChanged(uint24 oldRate,uint24 newRate);
    function projectFeePips() public view returns(uint24) {FeeConfig storage c=_config();return c.configured?c.projectPips:20_000;}
    function setProjectFeePips(uint24 pips) external {if(msg.sender!=_launch().feeRecipient)revert NotFeeRecipient();if(pips>50_000)revert InvalidProjectRate();uint24 old=projectFeePips();FeeConfig storage c=_config();c.configured=true;c.projectPips=pips;emit ProjectRateChanged(old,pips);}
    function _config() private pure returns(FeeConfig storage s){bytes32 slot=CONFIG_SLOT;assembly{s.slot:=slot}}
    function _fromGross(uint256 amount) private view returns(uint256){return Math.mulDiv(amount,uint256(projectFeePips())+3_000,1_000_000);}
    function _fromNet(uint256 amount) private view returns(uint256){uint256 p=uint256(projectFeePips())+3_000;return Math.mulDiv(amount,p,1_000_000-p,Math.Rounding.Ceil);}
    function _checkBudget(bytes calldata data,uint256 gross) internal pure virtual {if(data.length==0)return;if(data.length!=32)revert InvalidBudgetData();uint256 cap=abi.decode(data,(uint256));if(gross>cap)revert GrossBudgetExceeded(gross,cap);}
    function _swapLPFee() internal view virtual returns(uint24){return 0;}
    function _afterSuccessfulSwap(uint256,bool) internal virtual {}

    function _nativeSpecified(SwapParams calldata params) private pure returns (bool) {
        return (params.amountSpecified < 0) == params.zeroForOne;
    }

    function _specifiedAmount(SwapParams calldata params) private pure returns (uint256) {
        return params.amountSpecified < 0 ? uint256(-(params.amountSpecified + 1)) + 1 : uint256(params.amountSpecified);
    }

    function _requirePool(PoolKey calldata key) private view {
        LaunchState storage state = _launch();
        if (
            !state.poolInitialized || state.feeRecipient == address(0) || Currency.unwrap(key.currency0) != address(0)
                || Currency.unwrap(key.currency1) != state.token || address(key.hooks) != address(this)
                || key.tickSpacing != state.tickSpacing || key.fee != LPFeeLibrary.DYNAMIC_FEE_FLAG
        ) revert InvalidPool();
    }

    function _launch() private pure returns (LaunchState storage state) {
        bytes32 slot = LAUNCH_SLOT;
        assembly { state.slot := slot }
    }
}
