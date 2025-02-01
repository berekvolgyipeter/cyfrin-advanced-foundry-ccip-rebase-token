// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console, Test} from "forge-std/Test.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {TokenPool} from "@ccip/ccip/pools/TokenPool.sol";
import {RegistryModuleOwnerCustom} from "@ccip/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "@ccip/ccip/libraries/RateLimiter.sol";
import {IERC20} from "@ccip/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRouterClient} from "@ccip/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/ccip/libraries/Client.sol";

import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";
import {Vault} from "src/Vault.sol";

contract CrossChainTest is Test {
    uint256 public constant SEND_VALUE = 1e5;
    uint256 public constant VAULT_REWARDS_AMOUNT = 1e18;
    address public owner = makeAddr("owner");
    address alice = makeAddr("alice");
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    RebaseToken arbSepoliaToken;
    RebaseToken sepoliaToken;

    RebaseTokenPool arbSepoliaPool;
    RebaseTokenPool sepoliaPool;

    TokenAdminRegistry tokenAdminRegistrySepolia;
    TokenAdminRegistry tokenAdminRegistryArbSepolia;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    RegistryModuleOwnerCustom registryModuleOwnerCustomSepolia;
    RegistryModuleOwnerCustom registryModuleOwnerCustomArbSepolia;

    Vault vault;

    /// @notice See official chainlink guide to setup the environment:
    /// https://docs.chain.link/ccip/tutorials/cross-chain-tokens/register-from-eoa-burn-mint-foundry
    function setUp() public {
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        // make the address persistent across chains
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 1. Setup the Sepolia and Arbitrum Sepolia forks
        sepoliaFork = vm.createFork("sepolia");
        arbSepoliaFork = vm.createFork("arb-sepolia");

        // 2. Deploy and configure on the source chain: Sepolia
        deployAndConfigureSepolia();

        // 3. Deploy and configure on the destination chain: Arbitrum Sepolia
        deployAndConfigureArbSepolia();

        // 4. Configure the token pools
        configureTokenPool(
            sepoliaFork, sepoliaPool, arbSepoliaPool, IRebaseToken(address(arbSepoliaToken)), arbSepoliaNetworkDetails
        );
        configureTokenPool(
            arbSepoliaFork, arbSepoliaPool, sepoliaPool, IRebaseToken(address(sepoliaToken)), sepoliaNetworkDetails
        );
    }

    function deployAndConfigureSepolia() internal {
        vm.selectFork(sepoliaFork);
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);

        // 1. Deploy the token
        sepoliaToken = new RebaseToken();
        console.log("Sepolia rebase token address: %s", address(sepoliaToken));

        // 2. Deploy the token pool
        address[] memory allowlist = new address[](0); // all addresses are allowed to interact with the pool
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            allowlist,
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        // deploy the vault and add rewards (only on Sepolia, because it's the original source chain in the test)
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        vm.deal(address(vault), VAULT_REWARDS_AMOUNT);

        // 3. Claim Mint and Burn roles
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        sepoliaToken.grantMintAndBurnRole(address(vault));

        // 4. Claim admin role
        registryModuleOwnerCustomSepolia =
            RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomSepolia.registerAdminViaOwner(address(sepoliaToken));

        // 4. Accept admin role
        tokenAdminRegistrySepolia = TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistrySepolia.acceptAdminRole(address(sepoliaToken));

        // 5. Link token to pool in the token admin registry
        tokenAdminRegistrySepolia.setPool(address(sepoliaToken), address(sepoliaPool));

        vm.stopPrank();
    }

    function deployAndConfigureArbSepolia() internal {
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);

        // 1. Deploy the token
        arbSepoliaToken = new RebaseToken();
        console.log("Arbitrum Sepolia rebase token address: %s", address(arbSepoliaToken));

        // 2. Deploy the token pool
        address[] memory allowlist = new address[](0); // all addresses are allowed to interact with the pool
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            allowlist,
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        // 3. Claim Mint and Burn role
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));

        // 4. Claim admin role
        registryModuleOwnerCustomArbSepolia =
            RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomArbSepolia.registerAdminViaOwner(address(arbSepoliaToken));

        // 4. Accept admin role
        tokenAdminRegistryArbSepolia = TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistryArbSepolia.acceptAdminRole(address(arbSepoliaToken));

        // 5. Link token to pool in the token admin registry
        tokenAdminRegistryArbSepolia.setPool(address(arbSepoliaToken), address(arbSepoliaPool));

        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 fork,
        TokenPool localPool,
        TokenPool remotePool,
        IRebaseToken remoteToken,
        Register.NetworkDetails memory remoteNetworkDetails
    )
        public
    {
        vm.selectFork(fork);
        vm.startPrank(owner);

        // 6. Configure the token pool
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(address(remotePool)),
            remoteTokenAddress: abi.encode(address(remoteToken)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        localPool.applyChainUpdates(chains);

        vm.stopPrank();
    }

    // -------------------- TEST HELPER FUNCTIONS -------------------- //

    /// @notice See official chainlink guide to transfer tokens cross-chain:
    /// https://docs.chain.link/ccip/tutorials/transfer-tokens-from-contract
    function bridgeTokens(
        uint256 amount,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    )
        public
    {
        // ----------------------------------------------------- //
        // -------------------- LOCAL CHAIN -------------------- //
        // ----------------------------------------------------- //
        vm.selectFork(localFork);

        // Create the message to send tokens cross-chain
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amount});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(alice),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: "",
            feeToken: localNetworkDetails.linkAddress
        });

        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);

        // Approve the router to spend fee on users behalf
        vm.prank(alice);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);

        // Give the user fee amount of LINK
        ccipLocalSimulatorFork.requestLinkFromFaucet(alice, fee);

        // Approve the router to burn tokens on users behalf
        vm.prank(alice);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amount);

        uint256 sourceBalanceBeforeBridge = IERC20(address(localToken)).balanceOf(alice);

        // Send the message
        vm.prank(alice);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);

        // Check balance after bridge
        assertEq(sourceBalanceBeforeBridge - amount, IERC20(address(localToken)).balanceOf(alice));

        uint256 localUserInterestRate = localToken.getUserInterestRate(alice);

        // ------------------------------------------------------ //
        // -------------------- REMOTE CHAIN -------------------- //
        // ------------------------------------------------------ //
        vm.selectFork(remoteFork);
        // Pretend it takes 15 minutes to bridge the tokens
        vm.warp(block.timestamp + 15 minutes);

        uint256 destBalanceBeforeBridge = IERC20(address(remoteToken)).balanceOf(alice);

        // Send the message cross-chain
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        // Check balance after bridge
        assertEq(destBalanceBeforeBridge + amount, IERC20(address(remoteToken)).balanceOf(alice));

        // Check interest rate after bridge
        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(alice);
        assertEq(localUserInterestRate, remoteUserInterestRate);
    }

    function bridgeAndBridgeBackTokens(uint256 amount) public {
        vm.selectFork(sepoliaFork);
        vm.deal(alice, SEND_VALUE);

        // Deposit to the vault and receive tokens
        vm.prank(alice);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        assertEq(IRebaseToken(address(sepoliaToken)).balanceOf(alice), SEND_VALUE);

        // bridge tokens to the destination chain
        bridgeTokens(
            amount,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );

        // bridge back tokens to the source chain after 1 hour
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 1 hours);

        uint256 destBalance = IRebaseToken(address(arbSepoliaToken)).balanceOf(alice);
        uint256 destPrincipalBalance = IRebaseToken(address(arbSepoliaToken)).principalBalanceOf(alice);
        assertEq(destPrincipalBalance, amount);
        assertGt(destBalance, amount); // interest rate has been accumulated during the 1 hour

        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );
    }

    // -------------------- TEST FUNCTIONS -------------------- //

    function testBridgeAndBridgeBackTokens() public {
        bridgeAndBridgeBackTokens(SEND_VALUE / 2);
    }

    function testBridgeAndBridgeBackAllTokens() public {
        bridgeAndBridgeBackTokens(SEND_VALUE);
    }
}
