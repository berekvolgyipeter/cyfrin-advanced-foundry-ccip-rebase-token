#!/bin/bash

# ACCOUNT, RPC_URL_ZKSYNC_SEPOLIA and RPC_URL_SEPOLIA must be defined in .env
source .env

# Define constants 
AMOUNT=100000

ZKSYNC_REGISTRY_MODULE_OWNER_CUSTOM="0x3139687Ee9938422F57933C3CDB3E21EE43c4d0F"
ZKSYNC_TOKEN_ADMIN_REGISTRY="0xc7777f12258014866c677Bdb679D0b007405b7DF"
ZKSYNC_ROUTER="0xA1fdA8aa9A8C4b945C45aD30647b01f07D7A0B16"
ZKSYNC_RNM_PROXY_ADDRESS="0x3DA20FD3D8a8f8c1f1A5fD03648147143608C467"
ZKSYNC_SEPOLIA_CHAIN_SELECTOR="6898391096552792247"
ZKSYNC_LINK_ADDRESS="0x23A1aFD896c8c8876AF46aDc38521f4432658d1e"

SEPOLIA_TOKEN_ADMIN_REGISTRY="0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82"
SEPOLIA_ROUTER="0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59"
SEPOLIA_RNM_PROXY_ADDRESS="0xba3f6251de62dED61Ff98590cB2fDf6871FbB991"
SEPOLIA_CHAIN_SELECTOR="16015286601757825753"
SEPOLIA_LINK_ADDRESS="0x779877A7B0D9E8603169DdbD7836e478b4624789"

NETWORK_ARGS_ZKSYNC="--rpc-url ${RPC_URL_ZKSYNC_SEPOLIA} --account ${ACCOUNT}"
NETWORK_ARGS_SEPOLIA="--rpc-url ${RPC_URL_SEPOLIA} --account ${ACCOUNT}"

foundryup-zksync
forge build --zksync

# =================================================================================================
# 1. On ZkSync Sepolia!
# =================================================================================================

# Compile and deploy the Rebase Token contract
echo -e "\nCompiling and deploying the Rebase Token contract on ZKsync..."
ZKSYNC_REBASE_TOKEN_ADDRESS=$(forge create src/RebaseToken.sol:RebaseToken ${NETWORK_ARGS_ZKSYNC} --legacy --zksync | awk '/Deployed to:/ {print $3}')
echo "ZKsync rebase token address: $ZKSYNC_REBASE_TOKEN_ADDRESS"

# Compile and deploy the pool contract
echo -e "\nCompiling and deploying the pool contract on ZKsync..."
ZKSYNC_POOL_ADDRESS=$(forge create src/RebaseTokenPool.sol:RebaseTokenPool ${NETWORK_ARGS_ZKSYNC} --legacy --zksync --constructor-args ${ZKSYNC_REBASE_TOKEN_ADDRESS} [] ${ZKSYNC_RNM_PROXY_ADDRESS} ${ZKSYNC_ROUTER} | awk '/Deployed to:/ {print $3}')
echo "Pool address: $ZKSYNC_POOL_ADDRESS"

# Set the permissions for the pool contract
echo -e "\nSetting the permissions for the pool contract on ZKsync..."
cast send ${ZKSYNC_REBASE_TOKEN_ADDRESS} ${NETWORK_ARGS_ZKSYNC} "grantMintAndBurnRole(address)" ${ZKSYNC_POOL_ADDRESS}
echo "Pool permissions set"

# Set the CCIP roles and permissions
echo -e "\nSetting the CCIP roles and permissions on ZKsync..."
cast send ${ZKSYNC_REGISTRY_MODULE_OWNER_CUSTOM} "registerAdminViaOwner(address)" ${ZKSYNC_REBASE_TOKEN_ADDRESS} ${NETWORK_ARGS_ZKSYNC}
cast send ${ZKSYNC_TOKEN_ADMIN_REGISTRY} "acceptAdminRole(address)" ${ZKSYNC_REBASE_TOKEN_ADDRESS} ${NETWORK_ARGS_ZKSYNC}
cast send ${ZKSYNC_TOKEN_ADMIN_REGISTRY} "setPool(address,address)" ${ZKSYNC_REBASE_TOKEN_ADDRESS} ${ZKSYNC_POOL_ADDRESS} ${NETWORK_ARGS_ZKSYNC}
echo "CCIP roles and permissions set"

# =================================================================================================
# 2. On Sepolia!
# =================================================================================================

echo -e "\nRunning the script to deploy the contracts on Sepolia..."
output=$(forge script ./script/Deployer.s.sol:TokenAndPoolDeployer ${NETWORK_ARGS_SEPOLIA} --broadcast)
echo "Contracts deployed on Sepolia"

# Extract the addresses from the output
SEPOLIA_REBASE_TOKEN_ADDRESS=$(echo "$output" | grep 'token: contract RebaseToken' | awk '{print $4}')
SEPOLIA_POOL_ADDRESS=$(echo "$output" | grep 'pool: contract RebaseTokenPool' | awk '{print $4}')

echo -e "\nSepolia rebase token address: $SEPOLIA_REBASE_TOKEN_ADDRESS"
echo "Sepolia pool address: $SEPOLIA_POOL_ADDRESS"

# Set the permissions and CCIP roles on Sepolia
echo -e "\nSetting the permissions and the CCIP roles on Sepolia..."
$(forge script ./script/Deployer.s.sol:SetPermissions ${NETWORK_ARGS_SEPOLIA} --broadcast --sig "run(address,address)" ${SEPOLIA_REBASE_TOKEN_ADDRESS} ${SEPOLIA_POOL_ADDRESS})
echo "Permissions and CCIP roles set"

# Deploy the vault 
echo -e "\nDeploying the vault on Sepolia..."
VAULT_ADDRESS=$(forge script ./script/Deployer.s.sol:VaultDeployer ${NETWORK_ARGS_SEPOLIA} --broadcast --sig "run(address)" ${SEPOLIA_REBASE_TOKEN_ADDRESS} | grep 'vault: contract Vault' | awk '{print $NF}')
echo "Vault address: $VAULT_ADDRESS"

# Configure the pool on Sepolia
echo -e "\nConfiguring the pool on Sepolia..."
# uint64 remoteChainSelector,
#         address remotePoolAddress, /
#         address remoteTokenAddress, /
#         bool outboundRateLimiterIsEnabled, false 
#         uint128 outboundRateLimiterCapacity, 0
#         uint128 outboundRateLimiterRate, 0
#         bool inboundRateLimiterIsEnabled, false 
#         uint128 inboundRateLimiterCapacity, 0 
#         uint128 inboundRateLimiterRate 0 
CONFIG_POOL_SIG="run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)"
CONFIG_POOL_ARGS="${SEPOLIA_POOL_ADDRESS} ${ZKSYNC_SEPOLIA_CHAIN_SELECTOR} ${ZKSYNC_POOL_ADDRESS} ${ZKSYNC_REBASE_TOKEN_ADDRESS} false 0 0 false 0 0"
forge script ./script/ConfigurePool.s.sol:ConfigurePoolScript ${NETWORK_ARGS_SEPOLIA} --broadcast --sig ${CONFIG_POOL_SIG} ${CONFIG_POOL_ARGS}

# Deposit funds to the vault
echo -e "\nDepositing funds to the vault on Sepolia..."
cast send ${VAULT_ADDRESS} --value ${AMOUNT} ${NETWORK_ARGS_SEPOLIA} "deposit()"

# Wait a beat for some interest to accrue

# Configure the pool on ZKsync
echo -e "\nConfiguring the pool on ZKsync..."
APPLY_CHAIN_UPDATES_SIG="applyChainUpdates((uint64,bool,bytes,bytes,(bool,uint128,uint128),(bool,uint128,uint128))[])"
APPLY_CHAIN_UPDATES_ARGS="[(${SEPOLIA_CHAIN_SELECTOR},true,$(cast abi-encode "f(address)" ${SEPOLIA_POOL_ADDRESS}),$(cast abi-encode "f(address)" ${SEPOLIA_REBASE_TOKEN_ADDRESS}),(false,0,0),(false,0,0))]"
cast send ${ZKSYNC_POOL_ADDRESS} ${NETWORK_ARGS_ZKSYNC} ${APPLY_CHAIN_UPDATES_SIG} ${APPLY_CHAIN_UPDATES_ARGS}

# Bridge the funds using the script to zksync 
echo -e "\nGetting Sepolia balance before bridging to ZKsync..."
SEPOLIA_BALANCE_BEFORE=$(cast balance $(cast wallet address --account ${ACCOUNT}) --erc20 ${SEPOLIA_REBASE_TOKEN_ADDRESS} --rpc-url ${RPC_URL_SEPOLIA})
echo "Sepolia balance before bridging: $SEPOLIA_BALANCE_BEFORE"

echo -e "\nBridging the funds using the script to ZKsync..."
BRIDGE_SCRIPT_SIG="run(address,uint64,address,uint256,address,address)"
BRIDGE_SCRIPT_ARGS="$(cast wallet address --account ${ACCOUNT}) ${ZKSYNC_SEPOLIA_CHAIN_SELECTOR} ${SEPOLIA_REBASE_TOKEN_ADDRESS} ${AMOUNT} ${SEPOLIA_LINK_ADDRESS} ${SEPOLIA_ROUTER}"
forge script ./script/BridgeTokens.s.sol:BridgeTokensScript ${NETWORK_ARGS_SEPOLIA} --broadcast --sig ${BRIDGE_SCRIPT_SIG} ${BRIDGE_SCRIPT_ARGS}
echo "Funds bridged to ZKsync"

SEPOLIA_BALANCE_AFTER=$(cast balance $(cast wallet address --account ${ACCOUNT}) --erc20 ${SEPOLIA_REBASE_TOKEN_ADDRESS} --rpc-url ${RPC_URL_SEPOLIA})
echo "Sepolia balance after bridging: $SEPOLIA_BALANCE_AFTER"
