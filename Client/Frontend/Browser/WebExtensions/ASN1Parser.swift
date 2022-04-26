// Copyright 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation

protocol ASN1Node {
}

struct ASN1 {
  struct Sequence: ASN1Node {
    let values: [ASN1Node]
  }

  struct ObjectIdentifier: ASN1Node {
    let data: Data
  }

  struct OctetString: ASN1Node {
    let data: Data
  }

  struct BitString: ASN1Node {
    let data: Data
  }

  struct Integer: ASN1Node {
    let data: Data
  }

  struct Null: ASN1Node {
  }
}

struct ASN1Parser {
//  enum ASN1Node {
//    case sequence(values: [ASN1Node])
//    case objectIdentifier(data: Data)
//    case octetString(data: Data)
//    case bitString(data: Data)
//    case integer(data: Data)
//    case null
//  }
  
  func parse(data: Data) throws -> ASN1Node {
    return try parseNode(reader: Reader(data: data))
  }
  
  private func parseNode(reader: Reader) throws -> ASN1Node {
    let tagId = try reader.read(count: 1)[0]
    
    switch tagId {
      // Sequence
      case 0x30:
        let length = try reader.readLength()
        let data = try reader.read(count: length)
        return ASN1.Sequence(values: try parseSequence(data: data))
    
      // Object Identifier
      case 0x06:
        let length = try reader.readLength()
        let data = try reader.read(count: length)
        return ASN1.ObjectIdentifier(data: data)
      
      // Octet String
      case 0x04:
        let length = try reader.readLength()
        let data = try reader.read(count: length)
        return ASN1.OctetString(data: data)
      
      // Bit String
      case 0x03:
        let length = try reader.readLength()
        _ = try reader.read(count: 1) // BitString has `0x00` reserved after `Length`
        let data = try reader.read(count: length - 1)
        return ASN1.BitString(data: data)
      
      // Integer
      case 0x02:
        let length = try reader.readLength()
        let data = try reader.read(count: length)
        return ASN1.Integer(data: data)
      
      // Null
      case 0x05:
        _ = try reader.read(count: 1)
        return ASN1.Null()
      
      default:
        throw Reader.ReaderError.unknownType
    }
  }
  
  private func parseSequence(data: Data) throws -> [ASN1Node] {
    let reader = Reader(data: data)
    var values = [ASN1Node]()
    while reader.hasMoreContent {
      let node = try parseNode(reader: reader)
      values.append(node)
    }
    return values
  }
  
  private class Reader {
    private let data: Data
    private var offset: Int
    var hasMoreContent: Bool {
      data.count > offset
    }
    
    enum ReaderError: String, Error {
      case insufficientData
      case unknownType
    }
    
    init(data: Data) {
      self.data = data
      self.offset = 0
    }
    
    func read(count: Int) throws -> Data {
      if count == 0 {
        return Data()
      }
      
      if count + offset > data.count {
        throw ReaderError.insufficientData
      }
      
      defer { offset += count }
      return data.subdata(in: offset..<offset + count)
    }
    
    // Read Length of the Tag-Length-Value
    // See: docs.microsoft.com/en-us/windows/win32/seccertenroll/about-encoded-length-and-value-bytes
    func readLength() throws -> Int {
      let length = try Int(read(count: 1)[0])
      if length & 0x80 == 0 {
        // Current byte = length
        return length
      }
      
      // Next bytes = length
      let data = try read(count: length & 0x7F)
      var actualLength = 0
      for byte in data {
        actualLength = (actualLength << 8) | Int(byte)
      }
      return Int(actualLength)
    }
  }
}
