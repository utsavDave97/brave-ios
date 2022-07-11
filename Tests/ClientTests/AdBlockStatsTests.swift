//
//  AdBlockStatsTests.swift
//  
//
//  Created by Jacob on 2022-07-11.
//

import XCTest
import BraveCore
@testable import Brave

class AdBlockStatsTests: XCTestCase {
  func testGeneralRules() throws {
    let rules = """
        -advertisement-icon.
        -advertisement-management
        -advertisement.
        -advertisement/script.
        @@good-advertisement
    """
    
    let genearalEngine = AdblockEngine(rules: rules)
    AdblockEngine.setDomainResolver(AdblockEngine.defaultDomainResolver)
    let stats = AdBlockStats(generalAdblockEngine: genearalEngine)
    
    XCTAssertTrue(stats.shouldBlock(
      requestURL: URL(string: "http://example.com/-advertisement-icon.")!,
      sourceURL: URL(string: "https://example.com")!,
      resourceType: .xmlhttprequest
    ))
    
    XCTAssertFalse(stats.shouldBlock(
      requestURL: URL(string: "https://brianbondy.com")!,
      sourceURL: URL(string: "https://example.com")!,
      resourceType: .xmlhttprequest
    ))
    
    XCTAssertFalse(stats.shouldBlock(
      requestURL: URL(string: "http://example.com/good-advertisement-icon.")!,
      sourceURL: URL(string: "https://example.com")!,
      resourceType: .xmlhttprequest
    ))
  }
  
  func testRegionalRules() throws {
    let rules = """
        -advertisement-icon.
        -advertisement-management
        -advertisement.
        -advertisement/script.
        @@good-advertisement
    """
    
    let regionalEngine = AdblockEngine(rules: rules)
    AdblockEngine.setDomainResolver(AdblockEngine.defaultDomainResolver)
    let stats = AdBlockStats(regionalAdBlockEngine: regionalEngine)
    regionalEngine.
    
    XCTAssertTrue(stats.shouldBlock(
      requestURL: URL(string: "http://example.com/-advertisement-icon.")!,
      sourceURL: URL(string: "https://example.com")!,
      resourceType: .xmlhttprequest
    ))
    
    XCTAssertFalse(stats.shouldBlock(
      requestURL: URL(string: "https://brianbondy.com")!,
      sourceURL: URL(string: "https://example.com")!,
      resourceType: .xmlhttprequest
    ))
    
    XCTAssertFalse(stats.shouldBlock(
      requestURL: URL(string: "http://example.com/good-advertisement-icon.")!,
      sourceURL: URL(string: "https://example.com")!,
      resourceType: .xmlhttprequest
    ))
  }
}
