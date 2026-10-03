// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {NeutralBudgetHook} from "../../src/test123/NeutralBudgetHook.sol";
import {TestProjectRevenue} from "../../src/test123/TestProjectRevenue.sol";
import {TestPlatformRevenue} from "../../src/test123/TestPlatformRevenue.sol";
import {TestToken} from "../../src/test123/TestToken.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {IV4Quoter} from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
interface INeutralNFT {function ownerOf(uint256)external view returns(address);}
interface INeutralUR {function execute(bytes calldata,bytes[] calldata,uint256)external payable;}
contract NeutralBudgetForkTest is Test {
 using PoolIdLibrary for PoolKey; using StateLibrary for IPoolManager;
 address constant OWNER=0xBb145cA83272c3806D4dDc75cA1D5514789cF1C5;
 address constant TOKEN=0x92C7D78306ae671D2D03118bD316e452399bd20F;
 address constant HOOK=0xE2D9a7D916e7D7aD85d486989C50BB55Ca6efFFF;
 address constant ADMIN=0x2CD47fD54D3a4221Dc6D3c9309552349a9dCAf89;
 address constant TA=0x78aD0275f1B0dD7a0CA1590434faa4F44D758626;
 address constant PM=0x000000000004444c5dc75cB358380D2e3dE08A90;
 address constant PROJECT=0xb6Beb82aE8df48F20CE884F7C8CB2c22b609d9a2;
 address constant PLATFORM=0xC3FdDCef8d96ed0f648245a96c44162FB77bf014;
 address constant UR=0x23617e59A5925b2A4Bf75d73ff6711cD0b29De85;
 address constant PERMIT2=0x000000000022D473030F116dDEE9F6B43aC78BA3;
 address constant POSM=0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
 address constant QUOTER=0x52F0E24D1c21C8A0cB1e5a5dD6198556BD9E1203;
 NeutralBudgetHook h; PoolKey key; uint256 oldActive;uint256 oldTreasury; uint256 oldPlatform;uint128 oldL; uint256 oldToken;uint256 oldAllowance;
 function setUp()public virtual {
   uint256 b=vm.envUint("ETHEREUM_FORK_BLOCK");vm.createSelectFork(vm.envString("ETHEREUM_RPC_URL"),b);assertEq(block.chainid,1);assertEq(block.number,b);assertGe(b,26113909);
   key=PoolKey(Currency.wrap(address(0)),Currency.wrap(TOKEN),0x800000,1,IHooks(HOOK));assertEq(PoolId.unwrap(key.toId()),0x8bf0a6b33185fb91e0ae6652cfb90d30fd066d5f58a979f38e90d4d143402334);
   (oldActive,oldTreasury)=TestProjectRevenue(PROJECT).balances();oldPlatform=TestPlatformRevenue(PLATFORM).balance();oldL=IPositionManager(POSM).getPositionLiquidity(431284);oldToken=TestToken(TOKEN).balanceOf(OWNER);oldAllowance=TestToken(TOKEN).allowance(OWNER,PERMIT2);
   NeutralBudgetHook next=new NeutralBudgetHook(IPoolManager(PM),TestProjectRevenue(PROJECT),TestPlatformRevenue(PLATFORM));_activate(address(next),bytes(""));h=NeutralBudgetHook(HOOK);
   _unchanged();vm.deal(OWNER,1 ether);vm.startPrank(OWNER);TestToken(TOKEN).approve(PERMIT2,oldToken);IAllowanceTransfer(PERMIT2).approve(TOKEN,UR,uint160(oldToken),uint48(block.timestamp+1 hours));vm.stopPrank();
 }
 function _activate(address n,bytes memory data)internal {vm.prank(OWNER);ProxyAdmin(ADMIN).upgradeAndCall(ITransparentUpgradeableProxy(HOOK),n,data);assertEq(address(uint160(uint256(vm.load(HOOK,0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)))),n);}
 function _unchanged() internal view {
   (uint256 a,uint256 t)=TestProjectRevenue(PROJECT).balances();assertEq(a,oldActive);assertEq(t,oldTreasury);assertEq(TestPlatformRevenue(PLATFORM).balance(),oldPlatform);assertEq(TestToken(TOKEN).balanceOf(OWNER),oldToken);assertEq(TestToken(TOKEN).allowance(OWNER,PERMIT2),oldAllowance);
   assertEq(ProxyAdmin(ADMIN).owner(),OWNER);assertEq(ProxyAdmin(TA).owner(),OWNER);assertEq(INeutralNFT(POSM).ownerOf(431284),OWNER);assertEq(IPositionManager(POSM).getPositionLiquidity(431284),oldL);assertEq(h.feeRecipient(),OWNER);assertEq(TestProjectRevenue(PROJECT).treasury(),0xd50d558AbFDaC2e64B2F9A9959E9B361d792f2Da);assertFalse(IPoolManager(PM).isOperator(PROJECT,HOOK));assertEq(IPoolManager(PM).allowance(PROJECT,HOOK,0),0);
 }
 function _swap(bool buy,bool exactOut,uint128 amount,bytes memory data) internal {
  bytes[] memory p=new bytes[](3);uint128 bound=exactOut?(buy?uint128(0.001 ether):uint128(oldToken/100)):1;
  p[0]=exactOut?abi.encode(IV4Router.ExactOutputSingleParams(key,buy,amount,bound,0,data)):abi.encode(IV4Router.ExactInputSingleParams(key,buy,amount,bound,0,data));
  p[1]=abi.encode(buy?key.currency0:key.currency1,uint256(exactOut?bound:amount));p[2]=abi.encode(buy?key.currency1:key.currency0,uint256(exactOut?amount:bound));
  bytes[] memory input=new bytes[](2);input[0]=abi.encode(abi.encodePacked(uint8(exactOut?8:6),uint8(12),uint8(15)),p);input[1]=abi.encode(address(0),OWNER,uint256(0));
  vm.prank(OWNER);INeutralUR(UR).execute{value:buy?(exactOut?uint256(bound):uint256(amount)):0}(hex"1004",input,block.timestamp);
 }
 function _assertFees(Vm.Log[] memory ls,uint24 rate) internal pure {
 uint256 n;for(uint256 i;i<ls.length;i++){if(ls[i].topics.length>0&&ls[i].topics[0]==keccak256("FeeAllocation(uint256,uint256,uint256)")){(uint256 g,uint256 p,uint256 f)=abi.decode(ls[i].data,(uint256,uint256,uint256));assertEq(p,g*rate/1_000_000);assertGe(f,g*3000/1_000_000);assertLe(f,g*3000/1_000_000+2);n++;}}
 assertEq(n,1);
 }
 function test_exactActivationStorageClaimsAndAuthority()public {_unchangedAfterApprove();assertEq(h.projectFeePips(),20_000);vm.expectRevert(NeutralBudgetHook.NotFeeRecipient.selector);h.setProjectFeePips(0);vm.expectRevert(NeutralBudgetHook.InvalidProjectRate.selector);vm.prank(OWNER);h.setProjectFeePips(50_001);}
 function _unchangedAfterApprove()internal view {assertEq(IPositionManager(POSM).getPositionLiquidity(431284),oldL);(uint256 a,uint256 t)=TestProjectRevenue(PROJECT).balances();assertEq(a,oldActive);assertEq(t,oldTreasury);}
 function test_budgetAcceptanceAndAtomicRollback()public {vm.recordLogs();_swap(true,false,0.0001 ether,abi.encode(uint256(0.0001 ether)));_assertFees(vm.getRecordedLogs(),20_000);uint256 old=TestToken(TOKEN).balanceOf(OWNER);(uint256 a,uint256 t)=TestProjectRevenue(PROJECT).balances();vm.expectRevert();_swap(true,false,0.0001 ether,abi.encode(uint256(0.0001 ether-1)));assertEq(TestToken(TOKEN).balanceOf(OWNER),old);(uint256 aa,uint256 tt)=TestProjectRevenue(PROJECT).balances();assertEq(aa,a);assertEq(tt,t);assertEq(IPositionManager(POSM).getPositionLiquidity(431284),oldL);}
 function test_badBudgetDataRollsBack()public {vm.expectRevert();_swap(true,false,0.0001 ether,hex"12");_unchangedAfterApprove();}
 function test_feeRaiseLowerFourModesAndQuoter()public {for(uint256 i;i<3;i++){uint24 rate=i==0?30_000:i==1?10_000:0;vm.prank(OWNER);h.setProjectFeePips(rate);vm.recordLogs();_swap(true,false,0.0001 ether,"");_assertFees(vm.getRecordedLogs(),rate);vm.recordLogs();_swap(false,false,uint128(oldToken/1000),"");_assertFees(vm.getRecordedLogs(),rate);vm.recordLogs();_swap(true,true,1 ether,abi.encode(uint256(0.001 ether)));_assertFees(vm.getRecordedLogs(),rate);vm.recordLogs();_swap(false,true,0.000001 ether,abi.encode(uint256(0.001 ether)));_assertFees(vm.getRecordedLogs(),rate);(uint256 q,)=IV4Quoter(QUOTER).quoteExactInputSingle(IV4Quoter.QuoteExactSingleParams(key,true,0.0001 ether,abi.encode(uint256(0.0001 ether))));assertGt(q,0);}assertEq(IPositionManager(POSM).getPositionLiquidity(431284),oldL);}
 function testFuzz_roundingBudgetAndSplit(uint24 p,uint128 raw)public {p=uint24(bound(p,0,50_000));uint128 amount=uint128(bound(raw,1e9,1e14));vm.prank(OWNER);h.setProjectFeePips(p);vm.recordLogs();_swap(true,false,amount,abi.encode(uint256(amount)));_assertFees(vm.getRecordedLogs(),p);(uint256 a,uint256 t)=TestProjectRevenue(PROJECT).balances();assertEq(a+t,IPoolManager(PM).balanceOf(PROJECT,0));assertGe(a,oldActive);assertGe(t,oldTreasury);}
 function test_oldClaimsRemainClaimableWithoutTreasuryOrLPChange()public {uint256 tEth=0xd50d558AbFDaC2e64B2F9A9959E9B361d792f2Da.balance;uint256 oldEth=OWNER.balance;vm.prank(OWNER);h.collectProjectFees(oldActive);assertEq(OWNER.balance,oldEth+oldActive);(,uint256 t)=TestProjectRevenue(PROJECT).balances();assertEq(t,oldTreasury);assertEq(0xd50d558AbFDaC2e64B2F9A9959E9B361d792f2Da.balance,tEth);assertEq(IPositionManager(POSM).getPositionLiquidity(431284),oldL);}
}
