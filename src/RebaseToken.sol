// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interest in
 * rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate that is the global interest rate at the time of depositing.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    mapping(address => uint256) private s_userInterestRate; // user's interest rate per second
    mapping(address => uint256) private s_userLastUpdatedTimestamp;
    uint256 private s_interestRate = 5 * PRECISION_FACTOR / 1e8;

    event InterestRateSet(uint256 newInterestRate);

    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);

    constructor() Ownable(msg.sender) ERC20("RebaseToken", "RBT") {}

    function grantMintAndBurnRole(address _address) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _address);
    }

    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @dev returns the principal balance of the user - i.e. the last updated stored balance,
     * which does not consider the perpetually accruing interest that has not yet been minted.
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mints new tokens for a given address.
     * Called when a user either deposits or bridges tokens to this chain.
     * @notice This function also mints any accrued interest since the last time the user's balance was updated.
     * @dev The interest rate of the user is either the contract interest rate if the user is
     * depositing or the user's interest rate from the source token if the user is bridging.
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) public onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burns tokens from a given address.
     * @notice This function also mints any accrued interest since the last time the user's balance was updated.
     */
    function burn(address _from, uint256 _amount) public onlyRole(MINT_AND_BURN_ROLE) {
        _amount = _mitigateDust(_from, _amount);
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Calculates the balance of the user, which is the
     * principal balance + interest generated by the principal balance.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // The amount of tokens user had last time their interest was minted to them.
        uint256 principalBalance = super.balanceOf(_user);
        if (principalBalance == 0) {
            return 0;
        }
        // shares * current accumulated interest for user since their interest was last minted to them.
        return (principalBalance * _calculateAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }

    /**
     * @dev transfers tokens from the sender to the recipient.
     * @notice This function also mints any accrued interest for both sender and receiver since the last times their
     * respective balances were updated.
     */
    function transfer(address _to, uint256 _amount) public override returns (bool) {
        _amount = _mitigateDust(msg.sender, _amount);
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_to);
        _setReceipientInterestRate(msg.sender, _to);
        return super.transfer(_to, _amount);
    }

    /**
     * @dev transfers tokens from a specified address to the recipient.
     * @notice This function also mints any accrued interest for both sender and receiver since the last times their
     * respective balances were updated.
     */
    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        _amount = _mitigateDust(_from, _amount);
        _mintAccruedInterest(_from);
        _mintAccruedInterest(_to);
        _setReceipientInterestRate(_from, _to);
        return super.transferFrom(_from, _to, _amount);
    }

    /**
     * @dev returns the full balance of the user if the amount is the maximum of uint256.
     */
    function _mitigateDust(address _user, uint256 _amount) private view returns (uint256) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_user);
        }
        return _amount;
    }

    /**
     * @dev Sets the recipient's interest rate only if they have not yet got one (or they tranferred/burned all their
     * tokens). Otherwise senders could force recipients to have lower interest.
     */
    function _setReceipientInterestRate(address _from, address _to) private {
        if (balanceOf(_to) == 0) {
            s_userInterestRate[_to] = s_userInterestRate[_from];
        }
    }

    /**
     * @dev returns the interest accrued since the last update of the user's balance
     * - i.e. since the last time the interest accrued was minted to the user.
     */
    function _calculateAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        uint256 timeDifference = block.timestamp - s_userLastUpdatedTimestamp[_user];
        // represents the linear growth over time = 1 + (interest rate * time)
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeDifference);
    }

    /**
     * @dev accumulates the accrued interest of the user to the principal balance.
     * This function mints the users accrued interest since they last transferred or bridged tokens.
     */
    function _mintAccruedInterest(address _user) internal {
        // The amount of tokens user had last time their interest was minted to them.
        uint256 principalBalance = super.balanceOf(_user);

        // Calculate the accrued interest since the last accumulation
        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncrease = currentBalance - principalBalance;

        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
    }

    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
