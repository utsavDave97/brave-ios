// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import BraveCore
import OrderedCollections

extension BraveWallet.TransactionInfo {
  var isSwap: Bool {
    switch txType {
    case .ethSwap, .solanaSwap:
      return true
    default:
      return false
    }
  }
  var isEIP1559Transaction: Bool {
    if coin == .eth {
      guard let ethTxData1559 = txDataUnion.ethTxData1559 else { return false }
      return !ethTxData1559.maxPriorityFeePerGas.isEmpty && !ethTxData1559.maxFeePerGas.isEmpty
    } else if coin == .fil {
      guard let filTxData = txDataUnion.filTxData else { return false }
      return !filTxData.gasPremium.isEmpty && !filTxData.gasFeeCap.isEmpty
    }
    return false
  }
  var ethTxToAddress: String {
    // Eth transaction are all coming as `ethTxData1559`
    // Comment below out for future proper eth transaction separation (EIP1559 and non-EIP1559)
    /*if isEIP1559Transaction {
     return txDataUnion.ethTxData1559?.baseData.to ?? ""
     } else {
     return txDataUnion.ethTxData?.to ?? ""
     }*/
    txDataUnion.ethTxData1559?.baseData.to ?? ""
  }
  var ethTxValue: String {
    // Eth transaction are all coming as `ethTxData1559`
    // Comment below out for future proper eth transaction separation (EIP1559 and non-EIP1559)
    /*if isEIP1559Transaction {
     return txDataUnion.ethTxData1559?.baseData.value ?? ""
     } else {
     return txDataUnion.ethTxData?.value ?? ""
     }*/
    txDataUnion.ethTxData1559?.baseData.value ?? ""
  }
  
  var ethTxGasLimit: String {
    // Eth transaction are all coming as `ethTxData1559`
    // Comment below out for future proper eth transaction separation (EIP1559 and non-EIP1559)
    /*if isEIP1559Transaction {
     return txDataUnion.ethTxData1559?.baseData.gasLimit ?? ""
     } else {
     return txDataUnion.ethTxData?.gasLimit ?? ""
     }*/
    txDataUnion.ethTxData1559?.baseData.gasLimit ?? ""
  }
  
  var ethTxGasPrice: String {
    // Eth transaction are all coming as `ethTxData1559`
    // Comment below out for future proper eth transaction separation (EIP1559 and non-EIP1559)
    /*if isEIP1559Transaction {
     return txDataUnion.ethTxData1559?.baseData.gasPrice ?? ""
     } else {
     return txDataUnion.ethTxData?.gasPrice ?? ""
     }*/
    txDataUnion.ethTxData1559?.baseData.gasPrice ?? ""
  }
  
  var ethTxData: [NSNumber] {
    // Eth transaction are all coming as `ethTxData1559`
    // Comment below out for future proper eth transaction separation (EIP1559 and non-EIP1559)
    /*if isEIP1559Transaction {
     return txDataUnion.ethTxData1559?.baseData.data ?? .init()
     } else {
     return txDataUnion.ethTxData?.data ?? .init()
     }*/
    txDataUnion.ethTxData1559?.baseData.data ?? .init()
  }
  
  var ethTxNonce: String {
    // Eth transaction are all coming as `ethTxData1559`
    // Comment below out for future proper eth transaction separation (EIP1559 and non-EIP1559)
    /*if isEIP1559Transaction {
     return txDataUnion.ethTxData1559?.baseData.nonce ?? .init()
     } else {
     return txDataUnion.ethTxData?.nonce ?? .init()
     }*/
    txDataUnion.ethTxData1559?.baseData.nonce ?? ""
  }
}

extension BraveWallet.OriginInfo {
  /// If the current OriginInfo matches the Brave Wallet origin
  var isBraveWalletOrigin: Bool {
    originSpec == WalletConstants.braveWalletOriginSpec
  }
}

extension BraveWallet.AccountId {
  /// Two `AccountIds` equal iff their `unique_key` fields equal. Use this to
  /// check AccountIds for equality or to store as string keys. Persist with
  /// caution as format may change.
  /// https://github.com/brave/brave-core/pull/18767
  open override func isEqual(_ object: Any?) -> Bool {
    guard let object = object as? BraveWallet.AccountId else { return false }
    return self.uniqueKey == object.uniqueKey
  }
}

extension BraveWallet.CoinType {
  public var keyringIds: [BraveWallet.KeyringId] {
    switch self {
    case .eth:
      return [.default]
    case .sol:
      return [.solana]
    case .fil:
      return [.filecoin, .filecoinTestnet]
    case .btc:
      return [.bitcoin84, .bitcoin84Testnet]
    @unknown default:
      return [.default]
    }
  }
  
  var localizedTitle: String {
    switch self {
    case .eth:
      return Strings.Wallet.coinTypeEthereum
    case .sol:
      return Strings.Wallet.coinTypeSolana
    case .fil:
      return Strings.Wallet.coinTypeFilecoin
    case .btc:
      fallthrough
    @unknown default:
      return Strings.Wallet.coinTypeUnknown
    }
  }
  
  var localizedDescription: String {
    switch self {
    case .eth:
      return Strings.Wallet.coinTypeEthereumDescription
    case .sol:
      return Strings.Wallet.coinTypeSolanaDescription
    case .fil:
      return Strings.Wallet.coinTypeFilecoinDescription
    case .btc:
      fallthrough
    @unknown default:
      return Strings.Wallet.coinTypeUnknown
    }
  }
  
  var iconName: String {
    switch self {
    case .eth:
      return "eth-asset-icon"
    case .sol:
      return "sol-asset-icon"
    case .fil:
      return "filecoin-asset-icon"
    case .btc:
      fallthrough
    @unknown default:
      return ""
    }
  }
  
  var defaultAccountName: String {
    switch self {
    case .eth:
      return Strings.Wallet.defaultEthAccountName
    case .sol:
      return Strings.Wallet.defaultSolAccountName
    case .fil:
      return Strings.Wallet.defaultFilAccountName
    case .btc:
      fallthrough
    @unknown default:
      return ""
    }
  }
  
  var defaultSecondaryAccountName: String {
    switch self {
    case .eth:
      return Strings.Wallet.defaultSecondaryEthAccountName
    case .sol:
      return Strings.Wallet.defaultSecondarySolAccountName
    case .fil:
      return Strings.Wallet.defaultSecondaryFilAccountName
    case .btc:
      fallthrough
    @unknown default:
      return ""
    }
  }
  
  /// Sort order used when sorting by coin types
  var sortOrder: Int {
    switch self {
    case .eth:
      return 1
    case .sol:
      return 2
    case .fil:
      return 3
    case .btc:
      fallthrough
    @unknown default:
      return 10
    }
  }
}

extension BraveWallet.TransactionInfo {
  var coin: BraveWallet.CoinType {
    if txDataUnion.solanaTxData != nil {
      return .sol
    } else if txDataUnion.filTxData != nil {
      return .fil
    } else {
      return .eth
    }
  }
}

extension BraveWallet.NetworkInfo {
  func isNativeAsset(_ token: BraveWallet.BlockchainToken) -> Bool {
    return nativeToken.contractAddress.caseInsensitiveCompare(token.contractAddress) == .orderedSame
    && nativeToken.symbol.caseInsensitiveCompare(token.symbol) == .orderedSame
    && symbol.caseInsensitiveCompare(token.symbol) == .orderedSame
    && nativeToken.decimals == token.decimals
    && coin == token.coin
  }
  
  /// The group id that this network should generate for any token
  /// that belongs to this network.
  /// - Warning: This format must to updated if
  /// `BraveWallet.BlockchainToken.walletUserAssetGroupId` format is
  ///  changed under `Data`
  var walletUserAssetGroupId: String {
    "\(coin.rawValue).\(chainId)"
  }
  
  /// Generate the link for a submitted transaction with given transaction hash and coin type. 
  func txBlockExplorerLink(txHash: String, for coin: BraveWallet.CoinType) -> URL? {
    if coin != .fil,
       let baseURL = blockExplorerUrls.first.map(URL.init(string:)) {
      return baseURL?.appendingPathComponent("tx/\(txHash)")
    } else if var urlComps = blockExplorerUrls.first.map(URLComponents.init(string:)) {
      urlComps?.queryItems = [URLQueryItem(name: "cid", value: txHash)]
      return urlComps?.url
    }
    return nil
  }
}

extension BraveWallet.BlockchainToken {
  /// The id to fetch price and price history.
  var assetRatioId: String {
    if !coingeckoId.isEmpty {
      return coingeckoId
    }
    
    if chainId != BraveWallet.MainnetChainId || contractAddress.isEmpty {
      return symbol
    }
    
    return contractAddress
  }
  
  /// The id to map with the return balance from RPCService
  var assetBalanceId: String {
    contractAddress + symbol + chainId + tokenId
  }
  
  var isAuroraSupportedToken: Bool {
    let isSupportedContractAddress = WalletConstants.supportedAuroraBridgeTokensContractAddresses
      .contains(where: { $0.caseInsensitiveCompare(contractAddress) == .orderedSame })
    return (contractAddress.isEmpty || isSupportedContractAddress) && chainId == BraveWallet.MainnetChainId
  }
  
  var nftTokenTitle: String {
    if isErc721, let tokenId = Int(tokenId.removingHexPrefix, radix: 16) {
      return "\(name) #\(tokenId)"
    } else {
      return name
    }
  }
}

extension BraveWallet.OnRampProvider {
  var name: String {
    switch self {
    case .ramp:
      return Strings.Wallet.rampNetworkProviderName
    case .sardine:
      return Strings.Wallet.sardineProviderName
    case .transak:
      return Strings.Wallet.transakProviderName
    case .stripe:
      // Product names not localized
      return String.localizedStringWithFormat(Strings.Wallet.stripeNetworkProviderName, "Link", "Stripe")
    case .coinbase:
      return "Coinbase Pay"
    default:
      return ""
    }
  }
  
  var shortName: String {
    switch self {
    case .ramp:
      return Strings.Wallet.rampNetworkProviderShortName
    case .sardine:
      return Strings.Wallet.sardineProviderShortName
    case .transak:
      return Strings.Wallet.transakProviderShortName
    case .stripe:
      // Product name is not localized
      return "Link"
    case .coinbase:
      return "Coinbase Pay"
    default:
      return ""
    }
  }
  
  var localizedDescription: String {
    switch self {
    case .ramp:
      return Strings.Wallet.rampNetworkProviderDescription
    case .sardine:
      return Strings.Wallet.sardineProviderDescription
    case .transak:
      return Strings.Wallet.transakProviderDescription
    case .stripe:
      return Strings.Wallet.stripeNetworkProviderDescription
    case .coinbase:
      return Strings.Wallet.coinbaseNetworkProviderDescription
    default:
      return ""
    }
  }
  
  var iconName: String {
    switch self {
    case .ramp:
      return "ramp-network-icon"
    case .sardine:
      return "sardine-icon"
    case .transak:
      return "transak-icon"
    case .stripe:
      return "link-by-stripe-icon"
    case .coinbase:
      return "coinbase-icon"
    default:
      return ""
    }
  }
  
  /// Supported local region identifiers / codes for the `OnRampProvider`. Will return nil if all locale region identifiers / codes are supported.
  private var supportedLocaleRegionIdentifiers: [String]? {
    switch self {
    case .stripe:
      return ["us"]
    default:
      return nil
    }
  }
  
  /// All supported `OnRampProvider`s for users Locale.
  static var allSupportedOnRampProviders: OrderedSet<BraveWallet.OnRampProvider> {
    .init(WalletConstants.supportedOnRampProviders.filter { onRampProvider in
      if let supportedLocaleRegionIdentifiers = onRampProvider.supportedLocaleRegionIdentifiers {
        // Check if `Locale` contains any of the `supportedLocaleRegionIdentifiers`
        return supportedLocaleRegionIdentifiers.contains(where: { code in
          Locale.current.safeRegionCode?.caseInsensitiveCompare(code) == .orderedSame
        })
      }
      // all locale codes/identifiers are supported for this `OnRampProvider`
      return true
    })
  }
}

extension Locale {
  /// The region identifier (iOS 16+) or region code for the `Locale`.
  var safeRegionCode: String? {
    if #available(iOS 16, *) {
      return Locale.current.region?.identifier ?? Locale.current.regionCode
    } else {
      return Locale.current.regionCode
    }
  }
}

extension BraveWallet.CoinMarket {
  static func abbreviateToBillion(input: Double) -> Double {
    input / 1000000000
  }
}

extension BraveWallet.KeyringId {
  static func keyringId(for coin: BraveWallet.CoinType, on chainId: String) -> BraveWallet.KeyringId {
    switch coin {
    case .eth:
      return .default
    case .sol:
      return .solana
    case .fil:
      return chainId == BraveWallet.FilecoinMainnet ? .filecoin : .filecoinTestnet
    case.btc:
      return chainId == BraveWallet.BitcoinMainnet ? .bitcoin84 : .bitcoin84Testnet
    @unknown default:
      return .default
    }
  }
}

extension BraveWallet.BraveSwapFeeParams {
  convenience init(chainId: String, swapParams: BraveWallet.SwapParams) {
    self.init(
      chainId: chainId,
      inputToken: swapParams.sellToken,
      outputToken: swapParams.buyToken,
      taker: swapParams.takerAddress
    )
  }
}

public extension String {
  /// Returns true if the string ends with a supported ENS extension.
  var endsWithSupportedENSExtension: Bool {
    WalletConstants.supportedENSExtensions.contains(where: hasSuffix)
  }
  
  /// Returns true if the string ends with a supported SNS extension.
  var endsWithSupportedSNSExtension: Bool {
    WalletConstants.supportedSNSExtensions.contains(where: hasSuffix)
  }
  
  /// Returns true if the string ends with a supported UD extension.
  var endsWithSupportedUDExtension: Bool {
    WalletConstants.supportedUDExtensions.contains(where: hasSuffix)
  }
  
  /// Returns true if `Self` is a valid account name
  var isValidAccountName: Bool {
    self.count <= 30
  }
}

public extension URL {
  /// Returns true if url's scheme is supported to be resolved using IPFS public gateway
  var isIPFSScheme: Bool {
    guard let scheme = self.scheme?.lowercased() else { return false }
    return WalletConstants.supportedIPFSSchemes.contains(scheme)
  }
}
