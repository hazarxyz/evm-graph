// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {NeutralBudgetHook} from "./NeutralBudgetHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TestProjectRevenue} from "./TestProjectRevenue.sol";
import {TestPlatformRevenue} from "./TestPlatformRevenue.sol";
/// @notice Keeps configurable project fees and optional gross budgets, adding a public one-swap LP fee waiver.
/// Anyone can consume the queued waiver. The normal liquidity-provider fee is0.05%; project and platform fees remain separate.
contract NeutralVoucherHook is NeutralBudgetHook {
 bytes32 private constant VOUCHER_SLOT=keccak256("neutral.hook.public-waiver.v1");
 struct Voucher {bool queued;}
 event FreeSwapQueued();
 event FreeSwapConsumed(uint256 grossEth,bool buy);
 constructor(IPoolManager manager,TestProjectRevenue project_,TestPlatformRevenue platform_) NeutralBudgetHook(manager,project_,platform_) {}
 function queueFreeSwap()external {if(msg.sender!=projectRevenue.active())revert NotFeeRecipient();_voucher().queued=true;emit FreeSwapQueued();}
 function freeSwapQueued()external view returns(bool){return _voucher().queued;}
 function _swapLPFee()internal view override returns(uint24){return _voucher().queued?0:500;}
 function _afterSuccessfulSwap(uint256 gross,bool buy)internal virtual override {Voucher storage v=_voucher();if(v.queued){v.queued=false;emit FreeSwapConsumed(gross,buy);}}
 function _voucher()private pure returns(Voucher storage s){bytes32 slot=VOUCHER_SLOT;assembly{s.slot:=slot}}
}
