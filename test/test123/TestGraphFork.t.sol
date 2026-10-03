// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ITestCanonicalGraph as G,ITestCanonicalRouter as R} from "./CanonicalABI.sol";
import {TestProjectRevenue} from "../../src/test123/TestProjectRevenue.sol";
import {TestPlatformRevenue} from "../../src/test123/TestPlatformRevenue.sol";
import {TestToken} from "../../src/test123/TestToken.sol";
import {TestTokenProxy} from "../../src/test123/TestTokenProxy.sol";
import {TestInitialHook} from "../../src/test123/TestInitialHook.sol";
import {TestHookBase} from "../../src/test123/TestHookBase.sol";
import {TestHookProxy} from "../../src/test123/TestHookProxy.sol";
import {TestBootstrap,ITestUniversalRouter} from "../../src/test123/TestBootstrap.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SwapParams,ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta,toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta,toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {IV4Quoter} from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

contract TestReplacementProbe is TestHookBase {
    bytes32 public stored;
    address public seenManager;
    address public seenSender;
    address public seenSelf;
    bytes public seenData;
    error ProbeRevert(bytes);
    constructor(IPoolManager m) TestHookBase(m) {}
    function writeIndependentSelector(bytes32 x) external {stored=x;}
    function beforeSwap(address sender,PoolKey calldata,SwapParams calldata,bytes calldata data) external override onlyPoolManager returns(bytes4,BeforeSwapDelta,uint24) {
        if(data.length == 1) revert ProbeRevert(data);
        seenManager=msg.sender;seenSender=sender;seenSelf=address(this);seenData=data;
        return(IHooks.beforeSwap.selector,toBeforeSwapDelta(3,4),0x400000);
    }
    function afterAddLiquidity(address,PoolKey calldata,ModifyLiquidityParams calldata,BalanceDelta,BalanceDelta,bytes calldata) external override onlyPoolManager returns(bytes4,BalanceDelta) {
        return(IHooks.afterAddLiquidity.selector,toBalanceDelta(5,6));
    }
}

/// @dev Mechanics ONLY: fork funding and one exact authority response are mocked. No live permit is produced.
contract TestGraphFork is Test {
    using StateLibrary for IPoolManager;
    address constant AGENT=0xBb145cA83272c3806D4dDc75cA1D5514789cF1C5;
    address constant TREASURY=0xd50d558AbFDaC2e64B2F9A9959E9B361d792f2Da;
    address constant PLATFORM=0x4957f49620AFf3Adbbe8195a4f633E49cc93376c;
    address constant FACTORY=0xB012e4A8F2c5FC4E8E4faCA9D5Ad6FfF13FBA887;
    address constant STAMP=0x8622DD5bAb44185f2A458ac90384Ac99248f8d56;
    address constant AUTHORITY=0x755509eA6e3F5Ec1aA2E797bb68f1B87DD8b886b;
    address constant MANAGER=0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant POSM=0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address constant PERMIT2=0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant SWAP_ROUTER=0x23617e59A5925b2A4Bf75d73ff6711cD0b29De85;
    address constant QUOTER=0x52F0E24D1c21C8A0cB1e5a5dD6198556BD9E1203;
    bytes32 constant ADMIN_SLOT=0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    uint256 constant BUY=0.01875 ether; // Mechanical estimate only, not a fresh USD quote.
    int24 constant OPEN=198060;
    G internal factory=G(FACTORY);
    R internal stamp=R(STAMP);
    R.StampRequestV1 internal request;
    R.LaunchPermitV1 internal permit;
    bytes internal routePayload;
    address[] internal outputs;
    PoolKey internal key;
    bytes32 internal digest;
    bytes constant MOCK_SIGNATURE="fork-mechanics-only";

    function setUp() public {
        vm.createSelectFork(vm.envString("ETHEREUM_RPC_URL"),vm.envUint("ETHEREUM_FORK_BLOCK"));
        assertEq(block.chainid,1);
        assertEq(FACTORY.codehash,0xd23692fae59331592048e71a96d4963e170ee56e449683dc9f7fa3f9470018b8);
        assertEq(AUTHORITY.codehash,0xd7d408ebcd99b2b70be43e20253d6d92a8ea8fab29bd3be7f55b10032331fb4c);
        assertEq(MANAGER.codehash,0x785f1014552b7ce7d5fb7d0c970ca60edee94fd00425d7ca21609acac7ce1293);
        assertEq(STAMP.codehash,0x40e27ecf201761d5eb66bc4f2d5c6124831ef078d7baf458ca5f41b1a8108546);
        vm.deal(AGENT,2 ether); // Synthetic test-only funding.
        _prepare();
    }
    function _target(string memory id,bytes memory init) internal pure returns(G.Target memory) {
        return G.Target(keccak256(bytes(id)),bytes32(0),0,0,init,"");
    }
    function _predict(G.GraphAuthorization memory auth,G.Target memory target) internal view returns(address) {
        return factory.predictTarget(auth,target);
    }
    function _prepare() internal {
        G.GraphAuthorization memory auth=G.GraphAuthorization(keccak256("test123-neutral"),keccak256("2026-10-03-candidate-v1"),keccak256("7-direct-outputs-2-standard-child-admins"),bytes32(uint256(1)),STAMP,BUY);
        G.Target[] memory t=_build(auth);
        (auth.graphCommitment,)=factory.computeGraphCommitment(auth,t);
        key=PoolKey(Currency.wrap(address(0)),Currency.wrap(_predict(auth,t[4])),0x800000,1,IHooks(_predict(auth,t[5])));
        uint256 snap=vm.snapshotState();
        vm.deal(STAMP,BUY);
        vm.prank(STAMP);
        (address[] memory observed,bytes32[] memory hashes,,bytes32 graphHash)=factory.deployGraph{value:BUY}(auth,t);
        Witness memory w=_witness(auth,t,observed,hashes,graphHash);
        assertTrue(vm.revertToState(snap));
        outputs=observed;
        routePayload=abi.encode(R.CustomGraphRouteV1(auth.routeNamespace,auth.routeNonce,auth.topologyHash,auth.graphCommitment,t,w.expected,graphHash));
        request.launchId=keccak256("test123-launch-candidate"); request.token=observed[4]; request.tokenRuntimeCodeHash=hashes[4]; request.poolKey=key; request.hookRuntimeCodeHash=hashes[5];
        for(uint256 i;i<w.components.length;i++) request.components.push(w.components[i]);
        permit=R.LaunchPermitV1(1,STAMP,AGENT,R.LaunchKindV1.CustomGraph,keccak256(routePayload),w.resultHash,stamp.computeStampRequestHash(request),auth.routeNonce,uint64(block.timestamp),uint64(block.timestamp+1 hours),BUY);
        digest=stamp.permitDigest(permit);
    }
    struct Witness {R.ExpectedGraphOutputV1[] expected; R.ComponentV1[] components; bytes32 resultHash;}
    function _witness(G.GraphAuthorization memory auth,G.Target[] memory t,address[] memory observed,bytes32[] memory hashes,bytes32 graphHash) internal view returns(Witness memory w) {
        w.expected=new R.ExpectedGraphOutputV1[](7);
        w.components=new R.ComponentV1[](7);
        bytes32[] memory outputHashes=new bytes32[](7);
        for(uint8 i;i<7;i++){
            assertEq(observed[i],_predict(auth,t[i]));
            assertLe(t[i].initCode.length,49152);
            assertLe(observed[i].code.length,24576);
            w.expected[i]=R.ExpectedGraphOutputV1(i,t[i].targetIdHash,observed[i],hashes[i]);
            w.components[i]=R.ComponentV1(i,observed[i],hashes[i],i==4?R.ComponentKindV1.Token:(i==5?R.ComponentKindV1.Hook:R.ComponentKindV1.Other),R.ComponentScopeV1.Exclusive);
            outputHashes[i]=keccak256(abi.encode(keccak256("ProgrammableExpectedGraphOutputV1(uint8 targetIndex,bytes32 targetIdHash,address account,bytes32 runtimeCodeHash)"),i,t[i].targetIdHash,observed[i],hashes[i]));
        }
        // Router stamp hashing requires strictly increasing component addresses.
        // Preserve graph output order and each component's original resultIndex.
        for(uint256 i=1;i<w.components.length;i++) {
            R.ComponentV1 memory item=w.components[i];uint256 j=i;
            while(j>0&&uint160(w.components[j-1].account)>uint160(item.account)) {
                w.components[j]=w.components[j-1];j--;
            }
            w.components[j]=item;
        }
        w.resultHash=keccak256(abi.encode(keccak256("ProgrammableExpectedGraphResultV1(bytes32 expectedOutputsHash,bytes32 graphDeploymentHash)"),keccak256(abi.encodePacked(outputHashes)),graphHash));
    }
    function _build(G.GraphAuthorization memory auth) internal returns(G.Target[] memory t) {
        t=new G.Target[](7);
        t[0]=_target("project-revenue",abi.encodePacked(type(TestProjectRevenue).creationCode,abi.encode(MANAGER,AGENT,TREASURY)));
        t[1]=_target("platform-revenue",abi.encodePacked(type(TestPlatformRevenue).creationCode,abi.encode(MANAGER,PLATFORM,FACTORY)));
        t[2]=_target("token-implementation",type(TestToken).creationCode);
        t[6]=_target("bootstrap",abi.encodePacked(type(TestBootstrap).creationCode,abi.encode(AGENT,MANAGER,POSM,PERMIT2,SWAP_ROUTER,FACTORY)));
        address boot=_predict(auth,t[6]);
        t[3]=_target("hook-implementation",abi.encodePacked(type(TestInitialHook).creationCode,abi.encode(MANAGER,_predict(auth,t[0]),_predict(auth,t[1]))));
        t[4]=_target("token-proxy",abi.encodePacked(type(TestTokenProxy).creationCode,abi.encode(_predict(auth,t[2]),AGENT,bytes(""))));
        address token=_predict(auth,t[4]);
        t[5]=_target("hook-proxy",abi.encodePacked(type(TestHookProxy).creationCode,abi.encode(_predict(auth,t[3]),AGENT,bytes(""),MANAGER)));
        t[5].applicantSalt=_mine(auth,t[5]);
        address hook=_predict(auth,t[5]);
        t[1].initializerCalldata=abi.encodeCall(TestPlatformRevenue.initialize,(hook));
        string memory uri='data:application/json;utf8,{"name":"123","symbol":"123","description":"Neutral hook test.","interop":{"erc1046":true},"image":"https://picsum.photos/id/960/512/512.jpg","external_url":"https://programmable.market/","website":"https://programmable.market/","twitter":"https://x.com/ProgrammableHQ"}';
        t[4].initializerCalldata=abi.encodeCall(TestToken.initialize,("123","123",boot,AGENT,uri));
        t[5].initializerCalldata=abi.encodeCall(TestInitialHook.initialize,(boot,token,int24(1),TickMath.getSqrtPriceAtTick(OPEN)));
        t[6].initializerCalldata=abi.encodeCall(TestBootstrap.initialize,(token,hook,TestBootstrap.Parameters(-160100,OPEN,1,block.timestamp+1 hours)));
        t[6].initializerValue=BUY;
    }
    function _mine(G.GraphAuthorization memory auth,G.Target memory target) internal view returns(bytes32) {
        bytes32 saltType=keccak256("ProgrammableCreate2GraphTargetSaltV1(uint256 chainId,address factory,bytes32 routeNamespace,bytes32 routeNonce,bytes32 targetIdHash,bytes32 applicantSalt,address authorizedLauncher)");
        bytes32 codeHash=keccak256(target.initCode);
        bytes memory saltPreimage=abi.encode(saltType,block.chainid,FACTORY,auth.routeNamespace,auth.routeNonce,target.targetIdHash,bytes32(0),STAMP);
        bytes memory create2Preimage=abi.encodePacked(hex"ff",FACTORY,bytes32(0),codeHash);
        for(uint256 i;i<1_000_000;i++) {
            bytes32 effective;
            address predicted;
            assembly ("memory-safe") {
                mstore(add(saltPreimage,0xe0),i)
                effective := keccak256(add(saltPreimage,0x20),mload(saltPreimage))
                mstore(add(create2Preimage,0x35),effective)
                predicted := and(keccak256(add(create2Preimage,0x20),mload(create2Preimage)),0xffffffffffffffffffffffffffffffffffffffff)
            }
            if(uint160(predicted)&0x3fff==0x3fff){assertEq(factory.effectiveTargetSalt(auth,target.targetIdHash,bytes32(i)),effective);return bytes32(i);}
        }
        revert("mine exhausted");
    }
    function _launchMocked() internal returns(bytes32 result) {
        // Only this exact candidate digest+test signature is mocked; never serialize this signature as an authority permit.
        vm.mockCall(AUTHORITY,abi.encodeWithSelector(IERC1271.isValidSignature.selector,digest,MOCK_SIGNATURE),abi.encode(bytes4(0x1626ba7e)));
        vm.prank(AGENT);
        result=stamp.launchAndStampV1{value:BUY}(permit,request,routePayload,MOCK_SIGNATURE);
    }
    function token() internal view returns(TestToken) {return TestToken(outputs[4]);}
    function boot() internal view returns(TestBootstrap) {return TestBootstrap(outputs[6]);}
    function project() internal view returns(TestProjectRevenue) {return TestProjectRevenue(outputs[0]);}
    function platform() internal view returns(TestPlatformRevenue) {return TestPlatformRevenue(outputs[1]);}
    function test_canonicalRouterLaunch_MOCK_AUTHORITY_ONLY() public {
        (uint160 beforePrice,,,)=IPoolManager(MANAGER).getSlot0(key.toId());assertEq(beforePrice,0);
        uint256 gasBefore=gasleft();bytes32 result=_launchMocked();
        emit log_named_uint("canonical Router execution gas, excludes test preparation",gasBefore-gasleft());
        assertTrue(result!=bytes32(0));assertEq(stamp.launchIdByToken(outputs[4]),request.launchId);
        assertEq(token().name(),"123");assertEq(token().symbol(),"123");assertEq(token().decimals(),18);
        assertEq(token().owner(),AGENT);assertEq(token().totalSupply(),1_000_000_000 ether);
        assertEq(uint160(outputs[5])&0x3fff,0x3fff);
        assertGt(token().balanceOf(AGENT),0);assertEq(token().balanceOf(outputs[6]),boot().launchRoundingDust());
        assertEq(token().allowance(outputs[6],PERMIT2),0);
        assertEq(ProxyAdmin(boot().originalTokenAdmin()).owner(),AGENT);
        assertEq(ProxyAdmin(boot().originalHookAdmin()).owner(),AGENT);
        assertEq(boot().originalTokenAdmin(),address(uint160(uint256(vm.load(outputs[4],ADMIN_SLOT)))));
        assertEq(boot().originalHookAdmin(),address(uint160(uint256(vm.load(outputs[5],ADMIN_SLOT)))));
        assertEq(IERC721(POSM).ownerOf(boot().positionId()),AGENT);
        assertGt(IPositionManager(POSM).getPositionLiquidity(boot().positionId()),0);
        (,,,uint24 lpFee)=IPoolManager(MANAGER).getSlot0(key.toId());assertEq(lpFee,0);
        (uint256 a,uint256 t)=project().balances();assertEq(a,BUY/100);assertEq(t,BUY/100);assertEq(platform().balance(),BUY*3/1000);assertEq(platform().canonicalPlatformBalance(),BUY/1000);assertEq(platform().additionalPlatformBalance(),BUY*2/1000);
        assertEq(IPoolManager(MANAGER).balanceOf(outputs[5],0),0);
        assertLt(routePayload.length,524288);
    }
    function test_missingRealAuthorityPermitRejectsAndLeavesAllOutputsAbsent() public {
        vm.expectRevert(bytes4(keccak256("InvalidPermitSignature()")));vm.prank(AGENT);stamp.launchAndStampV1{value:BUY}(permit,request,routePayload,MOCK_SIGNATURE);
        for(uint256 i;i<7;i++)assertEq(outputs[i].code.length,0);
        (uint160 price,,,)=IPoolManager(MANAGER).getSlot0(key.toId());assertEq(price,0);
    }
    function test_badInitialPurchaseRevertsEntireCanonicalFactoryGraph() public {
        R.CustomGraphRouteV1 memory r=abi.decode(routePayload,(R.CustomGraphRouteV1));
        r.targets[6].initializerCalldata=abi.encodeCall(TestBootstrap.initialize,(outputs[4],outputs[5],TestBootstrap.Parameters(-160100,OPEN,type(uint128).max,block.timestamp+1 hours)));
        G.GraphAuthorization memory a=G.GraphAuthorization(r.routeNamespace,r.routeNonce,r.topologyHash,r.graphCommitment,STAMP,BUY);
        (a.graphCommitment,)=factory.computeGraphCommitment(a,r.targets);
        vm.deal(STAMP,BUY);vm.expectRevert();vm.prank(STAMP);factory.deployGraph{value:BUY}(a,r.targets);
        for(uint256 i;i<7;i++)assertEq(outputs[i].code.length,0);
        (uint160 price,,,)=IPoolManager(MANAGER).getSlot0(key.toId());assertEq(price,0);
    }
    function _approveRouter() internal {
        vm.startPrank(AGENT);token().approve(PERMIT2,type(uint256).max);
        IAllowanceTransfer(PERMIT2).approve(outputs[4],SWAP_ROUTER,type(uint160).max,uint48(block.timestamp+1 days));vm.stopPrank();
    }
    function _swap(bool buy,bool exactOut,uint128 amount,uint128 bound,uint256 value) internal {
        bytes[] memory p=new bytes[](3);
        p[0]=exactOut?abi.encode(IV4Router.ExactOutputSingleParams(key,buy,amount,bound,0,bytes(""))):abi.encode(IV4Router.ExactInputSingleParams(key,buy,amount,bound,0,bytes("")));
        p[1]=abi.encode(buy?key.currency0:key.currency1,uint256(exactOut?bound:amount));
        p[2]=abi.encode(buy?key.currency1:key.currency0,uint256(exactOut?amount:bound));
        bytes[] memory input=new bytes[](2);
        input[0]=abi.encode(abi.encodePacked(uint8(exactOut?Actions.SWAP_EXACT_OUT_SINGLE:Actions.SWAP_EXACT_IN_SINGLE),uint8(Actions.SETTLE_ALL),uint8(Actions.TAKE_ALL)),p);
        input[1]=abi.encode(address(0),AGENT,uint256(0));
        vm.recordLogs();
        vm.prank(AGENT);ITestUniversalRouter(SWAP_ROUTER).execute{value:value}(hex"1004",input,block.timestamp);
        _assertAllocations(vm.getRecordedLogs());
    }
    function _exactOutput(bool buy,uint128 amount) internal {
        (uint256 quoted,)=IV4Quoter(QUOTER).quoteExactOutputSingle(IV4Quoter.QuoteExactSingleParams(key,buy,amount,""));
        uint256 oldOut=buy?token().balanceOf(AGENT):AGENT.balance;
        uint256 oldIn=buy?AGENT.balance:token().balanceOf(AGENT);
        _swap(buy,true,amount,uint128(quoted),buy?quoted:0);
        assertEq((buy?token().balanceOf(AGENT):AGENT.balance)-oldOut,amount);
        assertEq(oldIn-(buy?AGENT.balance:token().balanceOf(AGENT)),quoted);
    }
    function _assertAllocations(Vm.Log[] memory logs) internal pure {
        uint256 count;
        for(uint256 i;i<logs.length;i++)if(logs[i].topics.length>0&&logs[i].topics[0]==keccak256("FeeAllocation(uint256,uint256,uint256)")){
            (uint256 gross,uint256 p,uint256 f)=abi.decode(logs[i].data,(uint256,uint256,uint256));
            assertEq(p,gross/50);assertGe(p+f,gross*23000/1000000);assertLe(p+f,(gross*23000+999999)/1000000);assertGe(f,gross*3000/1000000);assertLe(f,gross*3000/1000000+2);count++;
        }
        assertEq(count,1);
        uint256 platformCount;
        for(uint256 i;i<logs.length;i++)if(logs[i].topics.length>0&&logs[i].topics[0]==keccak256("PlatformFeeAllocation(uint256,uint256,uint256)")){
            (uint256 gross,uint256 canonical,uint256 additional)=abi.decode(logs[i].data,(uint256,uint256,uint256));
            assertEq(canonical,gross/1000);
            assertGe(additional,gross*2000/1000000);
            assertLe(additional,gross*2000/1000000+3);
            platformCount++;
        }
        assertEq(platformCount,1);
    }
    function test_officialRouterAllFourModesClaimsAndSlippage() public {
        _launchMocked();_approveRouter();
        _swap(true,false,0.001 ether,1,0.001 ether);
        _swap(false,false,10 ether,1,0);
        _exactOutput(true,1 ether);_exactOutput(false,0.00001 ether);
        (uint256 a,uint256 t)=project().balances();assertApproxEqAbs(a,t,1);assertEq(a+t,IPoolManager(MANAGER).balanceOf(outputs[0],0));
        uint256 platformClaim=platform().balance();uint256 aBefore=AGENT.balance;uint256 tBefore=TREASURY.balance;uint256 fBefore=PLATFORM.balance;
        (uint160 priceBefore,,,)=IPoolManager(MANAGER).getSlot0(key.toId());uint128 liquidity=IPositionManager(POSM).getPositionLiquidity(boot().positionId());
        vm.prank(address(0xBAD));project().claimActive(a);assertEq(AGENT.balance,aBefore+a);assertEq(TREASURY.balance,tBefore);
        project().claimTreasury(t);platform().claimCanonical(platform().canonicalPlatformBalance());platform().claimAdditional(platform().additionalPlatformBalance());
        assertEq(TREASURY.balance,tBefore+t);assertEq(PLATFORM.balance,fBefore+platformClaim);
        assertEq(IPoolManager(MANAGER).balanceOf(outputs[0],0),0);assertEq(platform().balance(),0);
        (uint160 priceAfter,,,)=IPoolManager(MANAGER).getSlot0(key.toId());assertEq(priceAfter,priceBefore);
        assertEq(IPositionManager(POSM).getPositionLiquidity(boot().positionId()),liquidity);
        uint256 oldTokens=token().balanceOf(AGENT);vm.expectRevert();_swap(true,false,0.001 ether,type(uint128).max,0.001 ether);assertEq(token().balanceOf(AGENT),oldTokens);
    }
    function test_facadeConcreteDispatchArbitraryUpgradeAndTreasuryIsolation() public {
        _launchMocked();(uint256 a,uint256 t)=project().balances();uint256 p=platform().balance();
        TestReplacementProbe next=new TestReplacementProbe(IPoolManager(MANAGER));
        address originalHookAdmin=boot().originalHookAdmin();
        vm.prank(AGENT);ProxyAdmin(originalHookAdmin).upgradeAndCall(ITransparentUpgradeableProxy(outputs[5]),address(next),abi.encodeCall(TestReplacementProbe.writeIndependentSelector,(bytes32(uint256(77)))));
        TestReplacementProbe proxy=TestReplacementProbe(outputs[5]);assertEq(proxy.stored(),bytes32(uint256(77)));
        bytes memory data=new bytes(169);data[0]=0x12;data[168]=0x34;
        vm.prank(MANAGER);(bytes4 s,BeforeSwapDelta d,uint24 f)=proxy.beforeSwap(AGENT,key,SwapParams(true,-int256(1),TickMath.MIN_SQRT_PRICE+1),data);
        assertEq(s,IHooks.beforeSwap.selector);assertEq(BeforeSwapDelta.unwrap(d),BeforeSwapDelta.unwrap(toBeforeSwapDelta(3,4)));assertEq(f,0x400000);
        assertEq(proxy.seenManager(),MANAGER);assertEq(proxy.seenSender(),AGENT);assertEq(proxy.seenSelf(),outputs[5]);assertEq(proxy.seenData(),data);
        vm.expectRevert(TestHookProxy.NotCanonicalManager.selector);proxy.beforeSwap(AGENT,key,SwapParams(true,-int256(1),TickMath.MIN_SQRT_PRICE+1),data);
        vm.expectRevert(abi.encodeWithSelector(TestReplacementProbe.ProbeRevert.selector,hex"01"));vm.prank(MANAGER);proxy.beforeSwap(AGENT,key,SwapParams(true,-int256(1),TickMath.MIN_SQRT_PRICE+1),hex"01");
        BalanceDelta bd;vm.prank(MANAGER);(s,bd)=proxy.afterAddLiquidity(AGENT,key,ModifyLiquidityParams(-1,1,1,bytes32(0)),toBalanceDelta(0,0),toBalanceDelta(0,0),data);
        assertEq(s,IHooks.afterAddLiquidity.selector);assertEq(BalanceDelta.unwrap(bd),BalanceDelta.unwrap(toBalanceDelta(5,6)));
        (uint256 aa,uint256 tt)=project().balances();assertEq(aa,a);assertEq(tt,t);assertEq(platform().balance(),p);
        assertFalse(IPoolManager(MANAGER).isOperator(outputs[0],outputs[5]));assertEq(IPoolManager(MANAGER).allowance(outputs[0],outputs[5],0),0);
        project().claimActive(a);(,tt)=project().balances();assertEq(tt,t);project().claimTreasury(t);platform().claimCanonical(platform().canonicalPlatformBalance());platform().claimAdditional(platform().additionalPlatformBalance());
    }
}
