// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Pool} from "@ccip/ccip/libraries/Pool.sol";
import {TokenPool} from "@ccip/ccip/pools/TokenPool.sol";
import {IERC20} from "@ccip/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";

contract RebaseTokenPool is TokenPool {
    constructor(
        IERC20 token,
        address[] memory allowlist, // addresses authorized to initiate cross-chain operations (0 = everyone)
        address rmnProxy, // Risk Management Network proxy address
        address router // CCIP router address
    )
        TokenPool(token, allowlist, rmnProxy, router)
    {}

    /// @notice burns the tokens on the source chain
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        // required by CCIP
        _validateLockOrBurn(lockOrBurnIn);

        // Burn the tokens on the source chain.
        // CCIP first sends the tokens to the pool contract,
        // and we have to approve the pool contract to burn the tokens.
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        // Encode a function call to pass the caller's info to the destination pool and update it.
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);
        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    /// @notice Mints the tokens on the destination chain
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        // required by CCIP
        _validateReleaseOrMint(releaseOrMintIn);

        // Mint rebasing tokens to the receiver on the destination chain.
        (uint256 userInterestRate) = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        IRebaseToken(address(i_token)).mint(releaseOrMintIn.receiver, releaseOrMintIn.amount, userInterestRate);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
    }
}
