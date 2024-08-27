// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IKatanaV2Factory } from "./interfaces/IKatanaV2Factory.sol";
import { IKatanaV2Pair } from "@katana/v3-contracts/periphery/interfaces/IKatanaV2Pair.sol";
import { IKatanaGovernance } from "@katana/v3-contracts/external/interfaces/IKatanaGovernance.sol";

contract KatanaGovernance is OwnableUpgradeable, IKatanaV2Factory, IKatanaGovernance {
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @inheritdoc IKatanaGovernance
  address public immutable getV3Factory;
  /// @inheritdoc IKatanaGovernance
  address public immutable getPositionManager;

  /// @dev The address of the V3 migrator contract.
  /// This is used to skip authorization checks for the migrator.
  address public immutable v3Migrator;

  /// @dev Revert error when the length of the array is invalid.
  error InvalidLength();
  /// @dev Revert error when the caller is not authorized.
  error Unauthorized();

  /// @dev Gap for upgradeability.
  uint256[50] private __gap;

  /// @dev Indicates the token is unauthorized for trade.
  uint40 private constant UNAUTHORIZED = 0;
  /// @dev Indicates the token is publicly allowed for trade.
  uint40 private constant AUTHORIZED = type(uint40).max;

  /// @dev The factory contract.
  IKatanaV2Factory private _factory;
  /// @dev The mapping of token to permission.
  mapping(address token => Permission) private _permission;
  /// @dev The unique set of tokens.
  EnumerableSet.AddressSet private _tokens;
  /// @dev The router address
  address private _router;

  /// @dev Only use this modifier for boolean-returned methods
  modifier skipIfRouterOrAllowedAllOrOwner(address account) {
    _skipIfRouterOrMigratorOrAllowedAllOrOwner(account);
    _;
  }

  constructor(address nonfungiblePositionManager, address v3Factory, address migrator) {
    getV3Factory = v3Factory;
    getPositionManager = nonfungiblePositionManager;
    v3Migrator = migrator;
    _disableInitializers();
  }

  function initialize(address admin, address factory) external initializer {
    _setFactory(factory);
    __Ownable_init_unchained(admin);

    IKatanaV2Pair pair;
    uint40 until = AUTHORIZED;
    bool[] memory statusesPlaceHolder;
    address[] memory allowedPlaceHolder;
    uint256 length = IKatanaV2Factory(factory).allPairsLength();

    for (uint256 i; i < length; ++i) {
      pair = IKatanaV2Pair(IKatanaV2Factory(factory).allPairs(i));
      _setPermission(pair.token0(), until, allowedPlaceHolder, statusesPlaceHolder);
      _setPermission(pair.token1(), until, allowedPlaceHolder, statusesPlaceHolder);
    }
  }

  function initializeV2(address router) external reinitializer(2) {
    _router = router;
  }

  /// @inheritdoc IKatanaGovernance
  function setRouter(address router) external onlyOwner {
    _router = router;
  }

  /// @inheritdoc IKatanaGovernance
  function v3FactoryMulticall(bytes[] calldata data) external onlyOwner returns (bytes[] memory results) {
    results = new bytes[](data.length);
    address factory = getV3Factory;

    for (uint256 i; i < data.length; ++i) {
      results[i] = Address.functionCall(factory, data[i]);
    }
  }

  /**
   * @inheritdoc IKatanaV2Factory
   */
  function createPair(address tokenA, address tokenB) external returns (address pair) {
    address sender = _msgSender();
    address[] memory tokens = new address[](2);
    tokens[0] = tokenA;
    tokens[1] = tokenB;
    if (!this.isAuthorized(tokens, sender)) revert Unauthorized();

    pair = _factory.createPair(tokenA, tokenB);
  }

  /**
   * @inheritdoc IKatanaGovernance
   */
  function createPairAndSetPermission(
    address tokenA,
    address tokenB,
    uint40 whitelistUntil,
    address[] calldata alloweds,
    bool[] calldata statuses
  ) external onlyOwner returns (address pair) {
    pair = _factory.createPair(tokenA, tokenB);
    _setPermission(tokenA, whitelistUntil, alloweds, statuses);
    _setPermission(tokenB, whitelistUntil, alloweds, statuses);
  }

  /**
   * @inheritdoc IKatanaGovernance
   */
  function setPermission(address token, uint40 whitelistUntil, address[] calldata alloweds, bool[] calldata statuses)
    external
    onlyOwner
  {
    _setPermission(token, whitelistUntil, alloweds, statuses);
  }

  /**
   * @inheritdoc IKatanaV2Factory
   */
  function setPairImplementation(address impl) external onlyOwner {
    _factory.setPairImplementation(impl);
  }

  /**
   * @inheritdoc IKatanaV2Factory
   */
  function setAllowedAll(bool shouldAllow) external onlyOwner {
    _factory.setAllowedAll(shouldAllow);
  }

  /**
   * @inheritdoc IKatanaGovernance
   */
  function setFactory(address factory) external onlyOwner {
    _setFactory(factory);
  }

  /**
   * @inheritdoc IKatanaV2Factory
   */
  function setTreasury(address newTreasury) external onlyOwner {
    _factory.setTreasury(newTreasury);
  }

  /**
   * @inheritdoc IKatanaV2Factory
   */
  function getPair(address tokenA, address tokenB) external view returns (address pair) {
    return _factory.getPair(tokenA, tokenB);
  }

  /**
   * @inheritdoc IKatanaV2Factory
   */
  function allPairs(uint256 index) external view returns (address pair) {
    return _factory.allPairs(index);
  }

  /**
   * @inheritdoc IKatanaV2Factory
   */
  function allPairsLength() external view returns (uint256) {
    return _factory.allPairsLength();
  }

  /**
   * @inheritdoc IKatanaV2Factory
   */
  function treasury() external view returns (address) {
    return _factory.treasury();
  }

  /**
   * @inheritdoc IKatanaV2Factory
   */
  function pairImplementation() external view returns (address) {
    return _factory.pairImplementation();
  }

  /**
   * @inheritdoc IKatanaV2Factory
   */
  function INIT_CODE_PAIR_HASH() external view returns (bytes32) {
    return _factory.INIT_CODE_PAIR_HASH();
  }

  /**
   * @inheritdoc IKatanaGovernance
   */
  function getRouter() external view returns (address) {
    return _router;
  }

  /**
   * @inheritdoc IKatanaGovernance
   */
  function getFactory() external view returns (address) {
    return address(_factory);
  }

  /**
   * @inheritdoc IKatanaGovernance
   */
  function isAuthorized(address token, address account)
    external
    view
    skipIfRouterOrAllowedAllOrOwner(account)
    returns (bool authorized)
  {
    authorized = _isAuthorized(_permission[token], account);
  }

  /**
   * @inheritdoc IKatanaGovernance
   */
  function isAuthorized(address[] calldata tokens, address account)
    external
    view
    skipIfRouterOrAllowedAllOrOwner(account)
    returns (bool authorized)
  {
    uint256 length = tokens.length;

    for (uint256 i; i < length; ++i) {
      if (!_isAuthorized(_permission[tokens[i]], account)) return false;
    }

    return true;
  }

  /**
   * @inheritdoc IKatanaGovernance
   */
  function getWhitelistUntil(address token) external view returns (uint40) {
    return _permission[token].whitelistUntil;
  }

  /**
   * @inheritdoc IKatanaGovernance
   */
  function getWhitelistedTokensFor(address account)
    external
    view
    returns (address[] memory tokens, uint40[] memory whitelistUntils)
  {
    unchecked {
      uint256 length = _tokens.length();
      tokens = new address[](length);
      whitelistUntils = new uint40[](length);
      uint256 count;
      address token;
      uint40 whitelistUntil;
      Permission storage $;

      for (uint256 i; i < length; ++i) {
        token = _tokens.at(i);
        $ = _permission[token];
        whitelistUntil = $.whitelistUntil;

        if (block.timestamp < whitelistUntil && $.allowed[account]) {
          tokens[count] = token;
          whitelistUntils[count] = whitelistUntil;
          ++count;
        }
      }

      assembly {
        mstore(tokens, count)
        mstore(whitelistUntils, count)
      }
    }
  }

  /**
   * @inheritdoc IKatanaGovernance
   */
  function getManyTokensWhitelistInfo()
    external
    view
    returns (address[] memory tokens, uint40[] memory whitelistedUntils)
  {
    tokens = _tokens.values();
    uint256 length = tokens.length;
    whitelistedUntils = new uint40[](length);

    for (uint256 i; i < length; ++i) {
      whitelistedUntils[i] = _permission[tokens[i]].whitelistUntil;
    }
  }

  /**
   * @inheritdoc IKatanaV2Factory
   */
  function allowedAll() public view returns (bool) {
    return _factory.allowedAll();
  }

  /**
   * @dev Sets the address of the factory contract.
   * Can only be called by the contract owner.
   */
  function _setFactory(address factory) private {
    _factory = IKatanaV2Factory(factory);

    emit FactoryUpdated(_msgSender(), factory);
  }

  /**
   * @dev Sets the permission for a token.
   * @param token The address of the token.
   * @param whitelistUntil The end of the whitelist duration in seconds.
   * @param alloweds The array of addresses to be allowed in whitelist duration.
   * @param statuses The corresponding array of statuses (whether allowed or not).
   */
  function _setPermission(address token, uint40 whitelistUntil, address[] memory alloweds, bool[] memory statuses)
    private
  {
    uint256 length = alloweds.length;
    if (length != statuses.length) revert InvalidLength();

    Permission storage $ = _permission[token];
    $.whitelistUntil = whitelistUntil;
    _tokens.add(token);

    for (uint256 i; i < length; ++i) {
      $.allowed[alloweds[i]] = statuses[i];
    }

    emit PermissionUpdated(_msgSender(), token, whitelistUntil, alloweds, statuses);
  }

  /**
   * @dev Checks if an account is authorized.
   * @param account The address of the account to check authorization for.
   * @return A boolean indicating whether the account is authorized or not.
   */
  function _isAuthorized(Permission storage $, address account) private view returns (bool) {
    uint256 expiry = $.whitelistUntil;
    if (expiry == UNAUTHORIZED) return false;
    if (expiry == AUTHORIZED || block.timestamp > expiry) return true;

    return $.allowed[account];
  }

  /**
   * @dev Skips the function if the caller is allowed all or the owner.
   * WARNING: This function can return and exit current context and skip the function.
   */
  function _skipIfRouterOrMigratorOrAllowedAllOrOwner(address account) internal view {
    if (account == _router || account == v3Migrator || allowedAll() || account == owner()) {
      assembly ("memory-safe") {
        mstore(0x0, true)
        return(0x0, 32)
      }
    }
  }
}