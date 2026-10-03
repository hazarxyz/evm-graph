// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @notice Keeps earned ETH claims outside replaceable hook code and splits them equally.
/// @dev No owner, upgrades, allowance or arbitrary destination. Future hook code
/// may route new revenue elsewhere, but cannot spend claims already held here.
contract TestProjectRevenue {
    IPoolManager public immutable poolManager;
    address public immutable active;
    address public immutable treasury;
    uint256 private activeCredit;
    uint256 private treasuryCredit;
    uint256 private allocated;

    error InvalidConfiguration();
    error InvalidClaim();
    error NotPoolManager();
    event RevenueClaimed(address indexed recipient,uint256 amount);

    constructor(IPoolManager manager,address active_,address treasury_) {
        if(address(manager).code.length==0||active_==address(0)||treasury_==address(0)||active_==treasury_)revert InvalidConfiguration();
        poolManager=manager;active=active_;treasury=treasury_;
    }

    function balances() public view returns(uint256 activeAmount,uint256 treasuryAmount) {
        uint256 pending=poolManager.balanceOf(address(this),0)-activeCredit-treasuryCredit;
        uint256 toTreasury=(allocated+pending)/2-allocated/2;
        return(activeCredit+pending-toTreasury,treasuryCredit+toTreasury);
    }

    // Either payout can be triggered by anyone, always to its fixed beneficiary.
    // A recipient that rejects ETH cannot prevent the other beneficiary claiming.
    function claimActive(uint256 amount) external { _claim(true,amount); }
    function claimTreasury(uint256 amount) external { _claim(false,amount); }

    function _claim(bool toActive,uint256 amount) private {
        (uint256 a,uint256 t)=balances();
        allocated+=poolManager.balanceOf(address(this),0)-activeCredit-treasuryCredit;
        activeCredit=a;treasuryCredit=t;
        if(amount==0||amount>(toActive?a:t))revert InvalidClaim();
        if(toActive)activeCredit-=amount;else treasuryCredit-=amount;
        poolManager.unlock(abi.encode(toActive?active:treasury,amount));
    }

    function unlockCallback(bytes calldata data) external returns(bytes memory) {
        if(msg.sender!=address(poolManager))revert NotPoolManager();
        (address recipient,uint256 amount)=abi.decode(data,(address,uint256));
        if(recipient!=active&&recipient!=treasury)revert InvalidClaim();
        poolManager.burn(address(this),0,amount);
        poolManager.take(Currency.wrap(address(0)),recipient,amount);
        emit RevenueClaimed(recipient,amount);
        return "";
    }
}
