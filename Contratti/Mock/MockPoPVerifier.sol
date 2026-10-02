// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoPVerifier} from "../Interfacce/IPoPVerifier.sol";

contract MockPoPVerifier is IPoPVerifier {
    bool public shouldPass = true;

    function setShouldPass(bool _pass) external {
        shouldPass = _pass;
    }

    function verifyProof(
        address /* signal */,
        bytes32 /* nullifierHash */,
        bytes calldata /* proof */
    ) external view override returns (bool) {
        return shouldPass;
    }
}
