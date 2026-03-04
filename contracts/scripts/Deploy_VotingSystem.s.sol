// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { VotingSystem } from "../src/VotingSystem.sol";

/// @notice Deploy script for VotingSystem with UUPS proxy
/// @dev Deploys implementation and proxy, initializes the contract
contract Deploy_VotingSystem is Script {
    /// @notice Run the deployment
    /// @return proxy Address of the deployed proxy
    /// @return impl Address of the implementation
    function run()
        external
        returns (address proxy, address impl)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        VotingSystem implementation = new VotingSystem();
        impl = address(implementation);

        console2.log("VotingSystem implementation deployed at:", impl);

        // Prepare initialization calldata
        bytes memory initData = abi.encodeCall(
            VotingSystem.initialize,
            (
                vm.envAddress("ADMIN_ADDRESS"),
                vm.envAddress("EMERGENCY_ADMIN_ADDRESS"),
                vm.envAddress("AUDITOR_ADDRESS")
            )
        );

        // Deploy proxy
        ERC1967Proxy proxyContract = new ERC1967Proxy(
            impl,
            initData
        );
        proxy = address(proxyContract);

        vm.stopBroadcast();

        console2.log("VotingSystem proxy deployed at:", proxy);
        console2.log("Deployment complete!");
        console2.log("");
        console2.log("=== Deployment Summary ===");
        console2.log("Network:", rpcUrl);
        console2.log("Admin:", vm.envAddress("ADMIN_ADDRESS"));
        console2.log("Emergency Admin:", vm.envAddress("EMERGENCY_ADMIN_ADDRESS"));
        console2.log("Auditor:", vm.envAddress("AUDITOR_ADDRESS"));
        console2.log("===========================");
    }
}
