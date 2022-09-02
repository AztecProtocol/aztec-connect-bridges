// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

///@notice This cheat codes interface is named _CheatCodes so you can use the CheatCodes interface in other testing files without errors
interface _CheatCodes {
    function ffi(string[] calldata) external returns (bytes memory);
}

contract VyperDeployer {
    address constant HEVM_ADDRESS =
        address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

    string internal PATH = "src/bridges/";

    /// @notice Initializes cheat codes in order to use ffi to compile Vyper contracts
    _CheatCodes cheatCodes = _CheatCodes(HEVM_ADDRESS);

    ///@notice Compiles a Vyper contract and returns the address that the contract was deployeod to
    ///@notice If deployment fails, an error will be thrown
    ///@param fileName - The file name of the Vyper contract. For example, the file name for "SimpleStore.vy" is "SimpleStore"
    ///@return deployedAddress - The address that the contract was deployed to

    function deployContract(string memory fileName) public returns (address) {
        ///@notice create a list of strings with the commands necessary to compile Vyper contracts
        string[] memory cmds = new string[](2);
        cmds[0] = "vyper";
        cmds[1] = string(abi.encodePacked(PATH, fileName, ".vy"));

        ///@notice compile the Vyper contract and return the bytecode
        bytes memory bytecode = cheatCodes.ffi(cmds);

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        ///@notice check that the deployment was successful
        require(
            deployedAddress != address(0),
            "VyperDeployer could not deploy contract"
        );

        ///@notice return the address that the contract was deployed to
        return deployedAddress;
    }

    ///@notice Compiles a Vyper contract with constructor arguments and returns the address that the contract was deployeod to
    ///@notice If deployment fails, an error will be thrown
    ///@param fileName - The file name of the Vyper contract. For example, the file name for "SimpleStore.vy" is "SimpleStore"
    ///@return deployedAddress - The address that the contract was deployed to
    function deployContract(string memory fileName, bytes calldata args)
        public
        returns (address)
    {
        ///@notice create a list of strings with the commands necessary to compile Vyper contracts
        string[] memory cmds = new string[](2);
        cmds[0] = "vyper";
        cmds[1] = string(abi.encodePacked(PATH, fileName, ".vy"));

        ///@notice compile the Vyper contract and return the bytecode
        bytes memory _bytecode = cheatCodes.ffi(cmds);

        //add args to the deployment bytecode
        bytes memory bytecode = abi.encodePacked(_bytecode, args);

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        ///@notice check that the deployment was successful
        require(
            deployedAddress != address(0),
            "VyperDeployer could not deploy contract"
        );

        ///@notice return the address that the contract was deployed to
        return deployedAddress;
    }
}
