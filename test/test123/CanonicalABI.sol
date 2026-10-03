// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @dev ABI-only definitions transcribed from pinned canonical sources; not a replacement factory or authority.
interface ITestCanonicalGraph {
    struct GraphAuthorization {bytes32 routeNamespace;bytes32 routeNonce;bytes32 topologyHash;bytes32 graphCommitment;address authorizedLauncher;uint256 totalValue;}
    struct Target {bytes32 targetIdHash;bytes32 applicantSalt;uint256 deploymentValue;uint256 initializerValue;bytes initCode;bytes initializerCalldata;}
    function deployGraph(GraphAuthorization calldata authorization,Target[] calldata targets) external payable returns(address[] memory,bytes32[] memory,bytes[] memory,bytes32);
    function computeGraphCommitment(GraphAuthorization calldata authorization,Target[] calldata targets) external view returns(bytes32,uint256);
    function effectiveTargetSalt(GraphAuthorization calldata authorization,bytes32 targetIdHash,bytes32 applicantSalt) external view returns(bytes32);
    function predictTarget(GraphAuthorization calldata authorization,Target calldata target) external view returns(address);
}
interface ITestCanonicalRouter {
    enum LaunchKindV1 {Invalid,CustomGraph,Classic}
    enum ComponentKindV1 {Other,Token,Hook}
    enum ComponentScopeV1 {Invalid,Exclusive,SharedInfrastructure}
    struct ExpectedGraphOutputV1 {uint8 targetIndex;bytes32 targetIdHash;address account;bytes32 runtimeCodeHash;}
    struct CustomGraphRouteV1 {bytes32 routeNamespace;bytes32 routeNonce;bytes32 topologyHash;bytes32 graphCommitment;ITestCanonicalGraph.Target[] targets;ExpectedGraphOutputV1[] expectedOutputs;bytes32 expectedGraphDeploymentHash;}
    struct ComponentV1 {uint8 resultIndex;address account;bytes32 runtimeCodeHash;ComponentKindV1 kind;ComponentScopeV1 scope;}
    struct StampRequestV1 {bytes32 launchId;address token;bytes32 tokenRuntimeCodeHash;PoolKey poolKey;bytes32 hookRuntimeCodeHash;ComponentV1[] components;}
    struct LaunchPermitV1 {uint256 chainId;address router;address launchWallet;LaunchKindV1 kind;bytes32 routePayloadHash;bytes32 expectedResultHash;bytes32 stampRequestHash;bytes32 nonce;uint64 validAfter;uint64 deadline;uint256 value;}
    function launchAndStampV1(LaunchPermitV1 calldata permit,StampRequestV1 calldata request,bytes calldata routePayload,bytes calldata signature) external payable returns(bytes32);
    function permitDigest(LaunchPermitV1 calldata permit) external view returns(bytes32);
    function computeStampRequestHash(StampRequestV1 calldata request) external pure returns(bytes32);
    function launchIdByToken(address token) external view returns(bytes32);
    function stampProof(address component) external view returns(bytes32,bytes32);
}
