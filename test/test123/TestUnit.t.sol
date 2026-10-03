// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {TestFeeMath} from "../../src/test123/TestFeeMath.sol";
import {TestProjectRevenue} from "../../src/test123/TestProjectRevenue.sol";
import {TestPlatformRevenue} from "../../src/test123/TestPlatformRevenue.sol";
import {TestToken} from "../../src/test123/TestToken.sol";
import {TestTokenProxy} from "../../src/test123/TestTokenProxy.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";

/// @dev Unit-only claim ledger double. Real settlement is tested against Mainnet PoolManager in TestGraphFork.
contract TestUnitManager {
    mapping(address=>uint256) public claims;
    bool private locked=true;
    function credit(address recipient) external payable {claims[recipient]+=msg.value;}
    function balanceOf(address who,uint256 id) external view returns(uint256){require(id==0);return claims[who];}
    function unlock(bytes calldata data) external returns(bytes memory result){require(locked,"reentrant");locked=false;result=IUnlockCallback(msg.sender).unlockCallback(data);locked=true;}
    function burn(address from,uint256 id,uint256 amount) external {require(!locked&&from==msg.sender&&id==0);claims[from]-=amount;}
    function take(Currency currency,address to,uint256 amount) external {require(!locked&&Currency.unwrap(currency)==address(0));(bool ok,)=to.call{value:amount}("");require(ok,"payout rejected");}
}
contract TestRejectEther {receive() external payable {revert("reject");}}
contract TestUnit is Test {
    TestUnitManager m;
    address constant ACTIVE=address(0xA123);
    address constant TREASURY=address(0xB123);
    address constant PLATFORM=address(0xC123);
    address constant HOOK=address(0xD123);
    function setUp() public {m=new TestUnitManager();vm.deal(address(this),1 ether);vm.etch(HOOK,hex"00");}
    function testFuzz_grossFeePartition(uint128 raw) public pure {
        uint256 gross=uint256(raw);uint256 fee=TestFeeMath.fromGross(gross);
        assertEq(fee,gross*23/1000);assertLe(fee,gross);
        uint256 project=TestFeeMath.projectFromGross(gross);uint256 canonical=gross/1000;
        assertGe(fee,project+canonical);
        uint256 extra=fee-project-canonical;
        assertGe(extra,gross*2/1000);assertLe(extra,gross*2/1000+2);
    }
    function testFuzz_netGrossUpMinimality(uint128 raw) public pure {
        uint256 net=uint256(raw);uint256 fee=TestFeeMath.fromNet(net);uint256 gross=net+fee;
        assertGe(fee*1000,gross*23);
        if(fee>0)assertLt((fee-1)*977,net*23);
        assertEq(fee,(gross*23+999)/1000);
        uint256 project=gross/50;uint256 canonical=gross/1000;
        assertGe(fee,project+canonical);assertLe(fee-project-canonical,gross*2/1000+3);
    }
    function test_projectCumulativeRoundingAndIndependentClaims() public {
        TestProjectRevenue v=new TestProjectRevenue(IPoolManager(address(m)),ACTIVE,TREASURY);
        m.credit{value:1}(address(v));v.claimActive(1);
        m.credit{value:1}(address(v));(uint256 a,uint256 t)=v.balances();assertEq(a,0);assertEq(t,1);v.claimTreasury(1);
        m.credit{value:3}(address(v));(a,t)=v.balances();assertEq(a,2);assertEq(t,1);
        v.claimActive(2);v.claimTreasury(1);assertEq(ACTIVE.balance,3);assertEq(TREASURY.balance,2);assertEq(m.claims(address(v)),0);
        vm.expectRevert(TestProjectRevenue.InvalidClaim.selector);v.claimTreasury(1);
        vm.expectRevert(TestProjectRevenue.NotPoolManager.selector);v.unlockCallback(abi.encode(address(this),1));
    }
    function test_rejectingTreasuryCannotBlockActivePayout() public {
        TestRejectEther rejects=new TestRejectEther();TestProjectRevenue v=new TestProjectRevenue(IPoolManager(address(m)),ACTIVE,address(rejects));
        m.credit{value:10}(address(v));vm.expectRevert();v.claimTreasury(5);v.claimActive(5);
        (uint256 a,uint256 t)=v.balances();assertEq(a,0);assertEq(t,5);assertEq(ACTIVE.balance,5);
    }
    function _platform() internal returns(TestPlatformRevenue v){v=new TestPlatformRevenue(IPoolManager(address(m)),PLATFORM,address(this));v.initialize(HOOK);}
    function test_platformSeparateClaimsAndUnsolicitedCredit() public {
        TestPlatformRevenue v=_platform();m.credit{value:1}(address(v)); // ERC-6909 unsolicited credit must not brick swaps.
        m.credit{value:30}(address(v));vm.prank(HOOK);v.recordAllocation(10,20);
        assertEq(v.canonicalPlatformBalance(),10);assertEq(v.additionalPlatformBalance(),20);assertEq(v.unassignedBalance(),1);
        v.claimCanonical(4);v.claimAdditional(20);v.claimCanonical(6);v.claimUnassigned(1);
        assertEq(PLATFORM.balance,31);assertEq(v.balance(),0);
        vm.expectRevert(TestPlatformRevenue.InvalidClaim.selector);v.claimCanonical(1);
        vm.expectRevert(TestPlatformRevenue.NotHook.selector);v.recordAllocation(0,0);
        vm.expectRevert(TestPlatformRevenue.InvalidConfiguration.selector);v.initialize(HOOK);
        vm.expectRevert(TestPlatformRevenue.NotPoolManager.selector);v.unlockCallback(abi.encode(uint8(0),1));
    }
    function test_platformOverallocationRejectedAndPriorCreditsUnchanged() public {
        TestPlatformRevenue v=_platform();m.credit{value:30}(address(v));vm.prank(HOOK);v.recordAllocation(10,20);
        vm.expectRevert(TestPlatformRevenue.InvalidConfiguration.selector);vm.prank(HOOK);v.recordAllocation(1,0);
        assertEq(v.canonicalPlatformBalance(),10);assertEq(v.additionalPlatformBalance(),20);
    }
    function testFuzz_projectClaimsConserve(uint64 raw1,uint64 raw2) public {
        uint256 x=bound(raw1,0,1e12);uint256 y=bound(raw2,0,1e12);TestProjectRevenue v=new TestProjectRevenue(IPoolManager(address(m)),ACTIVE,TREASURY);
        m.credit{value:x}(address(v));(uint256 a,)=v.balances();if(a>0)v.claimActive(a);
        m.credit{value:y}(address(v));(uint256 a2,uint256 t)=v.balances();if(a2>0)v.claimActive(a2);if(t>0)v.claimTreasury(t);
        assertEq(ACTIVE.balance+TREASURY.balance,x+y);assertEq(TREASURY.balance,(x+y)/2);assertEq(v.poolManager().balanceOf(address(v),0),0);
    }
    function test_tokenInitializationMetadataAndTransferAccounting() public {
        TestToken impl=new TestToken();vm.expectRevert();impl.initialize("123","123",address(this),address(this),"data:application/json,{}");
        TestToken token=TestToken(address(new TestTokenProxy(address(impl),address(this),abi.encodeCall(TestToken.initialize,("123","123",address(this),address(this),"data:application/json,{}")))));
        assertEq(token.name(),"123");assertEq(token.symbol(),"123");assertEq(token.decimals(),18);assertEq(token.totalSupply(),1e27);
        token.transfer(ACTIVE,100);token.updateMetadata("456","456","data:application/json,{}");assertEq(token.balanceOf(ACTIVE),100);assertEq(token.totalSupply(),1e27);assertEq(token.owner(),address(this));assertEq(token.name(),"456");
        vm.expectRevert();vm.prank(ACTIVE);token.updateMetadata("789","789","");
        vm.expectRevert();token.initialize("123","123",address(this),address(this),"");
    }
    receive() external payable{}
}
