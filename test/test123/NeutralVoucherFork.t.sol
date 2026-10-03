// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {NeutralBudgetForkTest} from "./NeutralBudgetFork.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {NeutralVoucherHook} from "../../src/test123/NeutralVoucherHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TestProjectRevenue} from "../../src/test123/TestProjectRevenue.sol";
import {TestPlatformRevenue} from "../../src/test123/TestPlatformRevenue.sol";
import {IV4Quoter} from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
contract NeutralVoucherForkTest is NeutralBudgetForkTest {
 NeutralVoucherHook v;
 function setUp()public override{super.setUp();NeutralVoucherHook next=new NeutralVoucherHook(IPoolManager(PM),TestProjectRevenue(PROJECT),TestPlatformRevenue(PLATFORM));_activate(address(next),bytes(""));v=NeutralVoucherHook(HOOK);}
 function _fee(Vm.Log[] memory ls)internal pure returns(uint256 fee){bool found;for(uint256 i;i<ls.length;i++)if(ls[i].topics.length>0&&ls[i].topics[0]==keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)")){(,,,,,fee)=abi.decode(ls[i].data,(int128,int128,uint160,uint128,int24,uint24));found=true;}assertTrue(found);}
 function test_waiverAtomicWithBudgetAndQuoter()public{vm.expectRevert();v.queueFreeSwap();vm.prank(OWNER);v.queueFreeSwap();assertTrue(v.freeSwapQueued());vm.expectRevert();_swap(true,false,0.0001 ether,abi.encode(uint256(0.0001 ether-1)));assertTrue(v.freeSwapQueued());(uint256 quoted,)=IV4Quoter(QUOTER).quoteExactInputSingle(IV4Quoter.QuoteExactSingleParams(key,true,0.0001 ether,abi.encode(uint256(0.0001 ether))));assertGt(quoted,0);assertTrue(v.freeSwapQueued());vm.recordLogs();_swap(true,false,0.0001 ether,abi.encode(uint256(0.0001 ether)));Vm.Log[]memory logs=vm.getRecordedLogs();assertEq(_fee(logs),0);_assertFees(logs,20_000);assertFalse(v.freeSwapQueued());vm.recordLogs();_swap(false,false,uint128(oldToken/1000),"");logs=vm.getRecordedLogs();assertEq(_fee(logs),500);_assertFees(logs,20_000);}
 function test_configNamespaceSurvivesSecondReplacement()public{vm.prank(OWNER);h.setProjectFeePips(10_000);vm.prank(OWNER);v.queueFreeSwap();NeutralVoucherHook next=new NeutralVoucherHook(IPoolManager(PM),TestProjectRevenue(PROJECT),TestPlatformRevenue(PLATFORM));_activate(address(next),bytes(""));assertEq(h.projectFeePips(),10_000);assertTrue(v.freeSwapQueued());_unchangedAfterApprove();}
}
