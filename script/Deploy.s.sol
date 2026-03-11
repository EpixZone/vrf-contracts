// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VRFCoinFlip} from "../src/VRFCoinFlip.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        VRFCoinFlip game = new VRFCoinFlip();
        console.log("VRFCoinFlip deployed at:", address(game));

        vm.stopBroadcast();
    }
}
