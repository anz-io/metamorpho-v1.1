// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {IMetaMorphoV1_1} from "./interfaces/IMetaMorphoV1_1.sol";
import {IMetaMorphoV1_1Factory} from "./interfaces/IMetaMorphoV1_1Factory.sol";

import {EventsLib} from "./libraries/EventsLib.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";

import {MetaMorphoV1_1} from "./MetaMorphoV1_1.sol";

import {Ownable2Step, Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {UpgradeableBeacon} from "../lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "../lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";

/// @dev newly added: interface for the initializer of MetaMorphoV1_1
interface IMetaMorphoV1_1_Initializer {
    function initialize(
        address owner,
        address morpho,
        uint256 initialTimelock,
        address asset,
        string memory name,
        string memory symbol
    ) external;
}

/// @title MetaMorphoV1_1Factory
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice This contract allows to create MetaMorphoV1_1 vaults, and to index them easily.
contract MetaMorphoV1_1Factory is IMetaMorphoV1_1Factory, Ownable2Step {
    /* IMMUTABLES */

    /// @inheritdoc IMetaMorphoV1_1Factory
    address public immutable MORPHO;

    /// @dev newly added: the address of the beacon contract for MetaMorpho
    address public immutable BEACON;

    /* STORAGE */

    /// @inheritdoc IMetaMorphoV1_1Factory
    mapping(address => bool) public isMetaMorpho;

    /// @dev newly added: whitelisted vault creators
    mapping(address => bool) public isVaultCreator;

    /* CONSTRUCTOR */

    /// @dev Initializes the contract.
    /// @param morpho The address of the Morpho contract.
    constructor(address morpho) Ownable(msg.sender) {
        if (morpho == address(0)) revert ErrorsLib.ZeroAddress();
        MetaMorphoV1_1 implementation = new MetaMorphoV1_1(
            address(0),
            address(0),
            0,
            address(0),
            "",
            "" // Zero constructor arguments
        );

        MORPHO = morpho;
        BEACON = address(new UpgradeableBeacon(address(implementation), msg.sender));
    }

    /* MODIFIERS */

    modifier onlyVaultCreator() {
        if (!isVaultCreator[msg.sender]) revert ErrorsLib.NotVaultCreator();
        _;
    }

    /* EXTERNAL */

    /// @dev newly added: set a whitelisted vault creator
    function setVaultCreator(address vaultCreator, bool isWhiteList) external onlyOwner {
        isVaultCreator[vaultCreator] = isWhiteList;
        emit EventsLib.SetVaultCreator(vaultCreator, isWhiteList);
    }

    /// @inheritdoc IMetaMorphoV1_1Factory
    function createMetaMorpho(
        address initialOwner,
        uint256 initialTimelock,
        address asset,
        string memory name,
        string memory symbol,
        bytes32 salt
    ) public onlyVaultCreator returns (IMetaMorphoV1_1 metaMorpho) {
        bytes memory data = abi.encodeWithSelector(
            IMetaMorphoV1_1_Initializer.initialize.selector, initialOwner, MORPHO, initialTimelock, asset, name, symbol
        );
        BeaconProxy proxy = new BeaconProxy{salt: salt}(BEACON, data);
        metaMorpho = IMetaMorphoV1_1(address(proxy));

        isMetaMorpho[address(metaMorpho)] = true;

        emit EventsLib.CreateMetaMorpho(
            address(metaMorpho), msg.sender, initialOwner, initialTimelock, asset, name, symbol, salt
        );
    }

    /// @dev newly added: create a MetaMorpho with config
    /// @notice The initial guardian must be finalized by calling `acceptGuardian` after the timelock.
    /// @notice The owner must call `acceptOwnership` to finalize the ownership transfer.
    function createMetaMorphoWithConfig(
        address initialOwner,
        uint256 initialTimelock,
        address asset,
        string memory name,
        string memory symbol,
        bytes32 salt,
        address initialCurator,
        uint256 initialFee,
        address initialFeeRecipient,
        address initialGuardian
    ) external onlyVaultCreator returns (IMetaMorphoV1_1 metaMorpho) {
        metaMorpho = createMetaMorpho(address(this), initialTimelock, asset, name, symbol, salt);

        metaMorpho.setCurator(initialCurator);
        metaMorpho.setFeeRecipient(initialFeeRecipient);
        if (initialFee != 0) {
            metaMorpho.setFee(initialFee);
        }
        metaMorpho.submitGuardian(initialGuardian);
        metaMorpho.transferOwnership(initialOwner);
    }
}
