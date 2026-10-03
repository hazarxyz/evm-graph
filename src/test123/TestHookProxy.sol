// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";


/// @notice Concrete canonical-manager callback dispatch with standard unrestricted implementation upgrades.
/// @dev Each fixed hook selector authenticates PoolManager, then delegates its original calldata.
///      Other selectors retain the standard transparent proxy path; no implementation feature menu.
contract TestHookProxy is TransparentUpgradeableProxy, IHooks {
    address private immutable CANONICAL_MANAGER;
    error MissingHookPermissions();
    error NotCanonicalManager();
    constructor(address implementation,address agent,bytes memory initialization,address manager)
        TransparentUpgradeableProxy(implementation,agent,initialization)
    {
        if(uint160(address(this)) & Hooks.ALL_HOOK_MASK != Hooks.ALL_HOOK_MASK) revert MissingHookPermissions();
        require(manager.code.length != 0,"missing manager");
        CANONICAL_MANAGER = manager;
    }
    modifier onlyCanonicalManager() {
        if(msg.sender != CANONICAL_MANAGER) revert NotCanonicalManager();
        _;
    }
    function beforeInitialize(address, PoolKey calldata, uint160) external override onlyCanonicalManager returns (bytes4) { _fallback(); }
    function afterInitialize(address, PoolKey calldata, uint160, int24)
        external
        override
        onlyCanonicalManager
        returns (bytes4)
    { _fallback(); }
    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        override
        onlyCanonicalManager
        returns (bytes4)
    { _fallback(); }
    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override onlyCanonicalManager returns (bytes4, BalanceDelta) { _fallback(); }
    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        override
        onlyCanonicalManager
        returns (bytes4)
    { _fallback(); }
    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override onlyCanonicalManager returns (bytes4, BalanceDelta) { _fallback(); }
    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        override
        onlyCanonicalManager
        returns (bytes4, BeforeSwapDelta, uint24)
    { _fallback(); }
    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        onlyCanonicalManager
        returns (bytes4, int128)
    { _fallback(); }
    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        override
        onlyCanonicalManager
        returns (bytes4)
    { _fallback(); }
    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        override
        onlyCanonicalManager
        returns (bytes4)
    { _fallback(); }
    /// @dev The canonical factory initializes the entire graph in the same transaction.
    /// Never deploy this shell as an isolated uninitialized live proxy.
    function _unsafeAllowUninitialized() internal pure override returns (bool) { return true; }
}
