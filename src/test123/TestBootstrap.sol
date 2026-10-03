// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestToken} from "./TestToken.sol";
import {TestTokenProxy} from "./TestTokenProxy.sol";
import {TestHookProxy} from "./TestHookProxy.sol";
import {TestInitialHook} from "./TestInitialHook.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Pool} from "@uniswap/v4-core/src/libraries/Pool.sol";

interface ITestUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

interface IPositionPermit2 {
    function permit2() external view returns (address);
}

/// @notice Atomic graph bootstrap using direct token and hook outputs, with no seeded ETH.
/// @dev Owner supplies a reviewed opening price/range and mined hook salt. Not independently audited.
contract TestBootstrap {
    address public immutable agent;
    IPoolManager public immutable manager;
    IPositionManager public immutable positionManager;
    IAllowanceTransfer public immutable permit2;
    ITestUniversalRouter public immutable router;
    address public immutable graphFactory;
    address public originalTokenAdmin;
    address public originalHookAdmin;

    bool public launched;
    TestToken public token;
    TestHookProxy public hook;
    uint256 public positionId;
    uint256 public launchRoundingDust;

    struct Parameters {
        int24 lowerTick;
        int24 openingTick;
        uint128 minInitialBuyOut;
        uint256 deadline;
    }

    error InvalidConfiguration();
    error NotAgent();
    error AlreadyLaunched();
    error LaunchPostconditionFailed();
    event Launched(address indexed token, address indexed hook, PoolId indexed poolId, uint256 positionId);

    constructor(
        address agent_,
        IPoolManager manager_,
        IPositionManager positionManager_,
        IAllowanceTransfer permit2_,
        ITestUniversalRouter router_,
        address factory_
    ) {
        if (
            agent_ == address(0) || factory_.code.length == 0 || address(manager_).code.length == 0 || address(positionManager_).code.length == 0
                || address(permit2_).code.length == 0 || address(router_).code.length == 0
                || address(positionManager_.poolManager()) != address(manager_)
                || IPositionPermit2(address(positionManager_)).permit2() != address(permit2_)
                || address(IV4Router(address(router_)).poolManager()) != address(manager_)
        ) revert InvalidConfiguration();
        agent = agent_;
        manager = manager_;
        positionManager = positionManager_;
        permit2 = permit2_;
        router = router_;
        graphFactory = factory_;
    }

    /// @notice Called only by the canonical graph factory, after all graph outputs exist.
    function initialize(address token_, address hook_, Parameters calldata p) external payable returns (PoolKey memory key) {
        if (msg.sender != graphFactory) revert NotAgent();
        if (launched) revert AlreadyLaunched();
        if (p.lowerTick < TickMath.MIN_TICK || p.openingTick >= TickMath.MAX_TICK || p.lowerTick >= p.openingTick
            || p.deadline < block.timestamp || msg.value > type(uint128).max || (msg.value > 0 && p.minInitialBuyOut == 0)) revert InvalidConfiguration();
        token = TestToken(token_);
        hook = TestHookProxy(payable(hook_));
        if (token.owner() != agent || token.balanceOf(address(this)) != token.INITIAL_SUPPLY() || uint160(hook_) & 0x3fff != 0x3fff) revert InvalidConfiguration();
        originalTokenAdmin = _adminAddress(token_);
        originalHookAdmin = _adminAddress(hook_);
        if (ProxyAdmin(originalTokenAdmin).owner() != agent || ProxyAdmin(originalHookAdmin).owner() != agent) revert InvalidConfiguration();
        launched = true;
        key = PoolKey(Currency.wrap(address(0)),Currency.wrap(token_),LPFeeLibrary.DYNAMIC_FEE_FLAG,1,IHooks(hook_));
        if (manager.initialize(key, TickMath.getSqrtPriceAtTick(p.openingTick)) != p.openingTick) revert LaunchPostconditionFailed();
        _mintPosition(key,p);
        launchRoundingDust = token.balanceOf(address(this));
        if (msg.value > 0) _initialBuy(key,uint128(msg.value),p.minInitialBuyOut,p.deadline);
        uint256 bought = token.balanceOf(address(this)) - launchRoundingDust;
        if (bought != 0 && !token.transfer(agent,bought)) revert LaunchPostconditionFailed();
        emit Launched(token_,hook_,key.toId(),positionId);
    }

    function _adminAddress(address proxy) private pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694",proxy,hex"01")))));
    }

    function _mintPosition(PoolKey memory key, Parameters calldata p) private {
        uint160 lower = TickMath.getSqrtPriceAtTick(p.lowerTick);
        uint160 upper = TickMath.getSqrtPriceAtTick(p.openingTick);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(lower, upper, token.totalSupply());
        if (liquidity <= 2 || liquidity - 2 > Pool.tickSpacingToMaxLiquidityPerTick(1)) revert InvalidConfiguration();
        // Leave two liquidity units of headroom for the opposite-direction rounding used during minting.
        liquidity -= 2;
        uint256 amount = SqrtPriceMath.getAmount1Delta(lower, upper, liquidity, true);
        if (amount > type(uint128).max || amount > token.totalSupply()) revert InvalidConfiguration();
        if (!token.approve(address(permit2), amount)) revert LaunchPostconditionFailed();
        permit2.approve(address(token), address(positionManager), uint160(amount), uint48(block.timestamp));
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.CLOSE_CURRENCY), uint8(Actions.CLOSE_CURRENCY)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            key, p.lowerTick, p.openingTick, uint256(liquidity), uint128(0), uint128(amount), agent, bytes("")
        );
        params[1] = abi.encode(key.currency0);
        params[2] = abi.encode(key.currency1);
        positionId = positionManager.nextTokenId();
        positionManager.modifyLiquidities(abi.encode(actions, params), p.deadline);
        if (
            IERC721(address(positionManager)).ownerOf(positionId) != agent
                || positionManager.getPositionLiquidity(positionId) != liquidity
        ) revert LaunchPostconditionFailed();
        permit2.approve(address(token), address(positionManager), 0, 0);
        if (!token.approve(address(permit2), 0)) revert LaunchPostconditionFailed();
    }

    function _initialBuy(PoolKey memory key, uint128 amountIn, uint128 minOut, uint256 deadline) private {
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(IV4Router.ExactInputSingleParams(key, true, amountIn, minOut, 0, bytes("")));
        params[1] = abi.encode(key.currency0, uint256(amountIn));
        params[2] = abi.encode(key.currency1, uint256(minOut));
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(actions, params);
        inputs[1] = abi.encode(address(0), agent, uint256(0));
        // Universal Router 2.1.2: V4_SWAP, then SWEEP any unspent native input back to the agent.
        uint256 beforeTokens = token.balanceOf(address(this));
        router.execute{value: amountIn}(hex"1004", inputs, deadline);
        if (token.balanceOf(address(this)) < beforeTokens + minOut) revert LaunchPostconditionFailed();
    }
}
