// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";

import {IERC20} from "@ccip/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";
import {Vault} from "src/Vault.sol";

contract TokenAndPoolDeployer is Script {
    function deployRebaseToken() public returns (RebaseToken token) {
        vm.startBroadcast();
        token = new RebaseToken();
        vm.stopBroadcast();
    }

    function deployRebaseTokenPool(RebaseToken token) public returns (RebaseTokenPool pool) {
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startBroadcast();

        pool = new RebaseTokenPool(
            IERC20(address(token)), new address[](0), networkDetails.rmnProxyAddress, networkDetails.routerAddress
        );

        vm.stopBroadcast();
    }

    function run() public returns (RebaseToken token, RebaseTokenPool pool) {
        token = deployRebaseToken();
        pool = deployRebaseTokenPool(token);
    }
}

contract SetPermissions is Script {
    function grantRole(address token, address pool) public {
        vm.startBroadcast();
        IRebaseToken(token).grantMintAndBurnRole(pool);
        vm.stopBroadcast();
    }

    function setAdmin(address token, address pool) public {
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startBroadcast();

        RegistryModuleOwnerCustom(networkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(token);
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).acceptAdminRole(token);
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).setPool(token, pool);

        vm.stopBroadcast();
    }

    function run(address token, address pool) public {
        grantRole(token, pool);
        setAdmin(token, pool);
    }
}

contract VaultDeployer is Script {
    function run(address token) public returns (Vault vault) {
        vm.startBroadcast();

        vault = new Vault(IRebaseToken(token));
        IRebaseToken(token).grantMintAndBurnRole(address(vault));

        vm.stopBroadcast();
    }
}
