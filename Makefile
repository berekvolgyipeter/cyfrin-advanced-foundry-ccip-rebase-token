-include .env

.PHONY: all test clean deploy help uninstall install snapshot format anvil 

all: clean uninstall install update build

# ---------- anvil constants ----------
PRIVATE_KEY_ANVIL_0 := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ADDRESS_ANVIL_0 := 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
PRIVATE_KEY_ANVIL_1 := 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
ADDRESS_ANVIL_1 := 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
RPC_URL_ANVIL := http://localhost:8545

# ---------- dependencies ----------
uninstall :; rm -rf dependencies/ && rm -rf soldeer.lock
install :; forge soldeer install
update:; forge soldeer update

# ---------- build ----------
build :; forge build
clean :; forge clean && rm -rf cache/

# ---------- tests ----------
TEST := forge test -vvv
TEST_UNIT := $(TEST) --match-path "test/unit/*.t.sol"

test :; $(TEST)
test-unit :; $(TEST_UNIT)
test-unit-fork-sepolia :; $(TEST_UNIT) --fork-url $(RPC_URL_SEPOLIA)
test-unit-fork-mainnet :; $(TEST_UNIT) --fork-url $(RPC_URL_MAINNET)
test-fuzz :; $(TEST) --match-path "test/fuzz/*.t.sol"
test-invariant :; $(TEST) --match-path "test/invariant/*.t.sol"
test-fork-sepolia :; $(TEST) --fork-url $(RPC_URL_SEPOLIA)
test-fork-mainnet :; $(TEST) --fork-url $(RPC_URL_MAINNET)

# ---------- coverage ----------
coverage :; forge coverage --no-match-test invariant --no-match-coverage "^(test|script)/"
coverage-lcov :; make coverage EXTRA_FLAGS="--report lcov"
coverage-txt :; make coverage EXTRA_FLAGS="--report debug > coverage.txt"

# ---------- static analysis ----------
format-check :; forge fmt --check
slither-install :; python3 -m pip install slither-analyzer
slither :; slither . --config-file slither.config.json --checklist

# ---------- etherscan ----------
check-etherscan-api:
	@response_mainnet=$$(curl -s "https://api.etherscan.io/api?module=account&action=balance&address=$(ADDRESS_DEV)&tag=latest&apikey=$(ETHERSCAN_API_KEY)"); \
	echo "Mainnet:" $$response_mainnet; \
	response_sepolia=$$(curl -s "https://api-sepolia.etherscan.io/api?module=account&action=balance&address=$(ADDRESS_DEV)&tag=latest&apikey=$(ETHERSCAN_API_KEY)"); \
	echo "Sepolia:" $$response_sepolia;

# ---------- deploy & interact ----------
NETWORK_ARGS_ANVIL := --rpc-url $(RPC_URL_ANVIL) --private-key $(PRIVATE_KEY_ANVIL_0) --broadcast
NETWORK_ARGS_SEPOLIA := --rpc-url $(RPC_URL_SEPOLIA) --account $(ACCOUNT_DEV) --sender $(ADDRESS_DEV) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1
