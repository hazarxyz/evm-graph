// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @notice Permanent ERC-20 address; the agent owns the separate standard ProxyAdmin.
/// @dev No feature selectors, supply invariant or metadata restriction is enforced by this shell.
contract TestTokenProxy is TransparentUpgradeableProxy {
    constructor(address implementation, address agent, bytes memory initialization)
        TransparentUpgradeableProxy(implementation, agent, initialization)
    {}
    /// @dev The canonical factory initializes the entire graph in the same transaction.
    /// Never deploy this shell as an isolated uninitialized live proxy.
    function _unsafeAllowUninitialized() internal pure override returns (bool) { return true; }
}
