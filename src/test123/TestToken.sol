// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

/// @notice Launch implementation. Supply, decimals and transfer behavior are initial choices;
/// the agent-owned external ProxyAdmin may install newly written implementations later.
contract TestToken is ERC20Upgradeable, Ownable2StepUpgradeable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 ether;

    // Storage layout retained explicitly across neutral upgrades.
    struct Metadata {
        string name;
        string symbol;
        string uri;
    }
    bytes32 private constant METADATA_SLOT = 0xaf7f7287c9c163f7ebe81ce19f70fbce273b445ed7fb836babcf15904daab400;
    event MetadataUpdated(string name, string symbol, string tokenURI);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address initialHolder,
        address metadataAuthority,
        string memory uri
    ) external initializer {
        require(initialHolder != address(0), "zero holder");
        __ERC20_init(name_, symbol_);
        __Ownable_init(metadataAuthority);
        __Ownable2Step_init();
        _setMetadata(name_, symbol_, uri);
        _mint(initialHolder, INITIAL_SUPPLY);
    }

    function metadata() internal pure returns (Metadata storage m) {
        bytes32 slot = METADATA_SLOT;
        assembly { m.slot := slot }
    }

    function name() public view override returns (string memory) {
        return metadata().name;
    }

    function symbol() public view override returns (string memory) {
        return metadata().symbol;
    }

    function tokenURI() external view returns (string memory) {
        return metadata().uri;
    }

    function updateMetadata(string calldata name_, string calldata symbol_, string calldata uri) external onlyOwner {
        _setMetadata(name_, symbol_, uri);
    }

    function _setMetadata(string memory name_, string memory symbol_, string memory uri) internal {
        require(bytes(name_).length > 0 && bytes(name_).length <= 128, "invalid name");
        require(bytes(symbol_).length > 0 && bytes(symbol_).length <= 32, "invalid symbol");
        require(bytes(uri).length <= 2048, "invalid uri");
        Metadata storage m = metadata();
        m.name = name_;
        m.symbol = symbol_;
        m.uri = uri;
        emit MetadataUpdated(name_, symbol_, uri);
    }
}
