// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Starting 2% project plus 0.3% platform on the same gross ETH basis.
/// @dev Replaceable implementation policy. Aggregate rounding is resolved to the platform.
library TestFeeMath {
    uint24 internal constant TOTAL_PIPS = 23_000;
    uint24 internal constant PROJECT_PIPS = 20_000;
    uint256 internal constant DENOMINATOR = 1_000_000;
    function fromGross(uint256 gross) internal pure returns (uint256) {
        return Math.mulDiv(gross,TOTAL_PIPS,DENOMINATOR);
    }
    function fromNet(uint256 net) internal pure returns (uint256) {
        return Math.mulDiv(net,TOTAL_PIPS,DENOMINATOR-TOTAL_PIPS,Math.Rounding.Ceil);
    }
    function projectFromGross(uint256 gross) internal pure returns (uint256) {
        return gross/50;
    }
}
