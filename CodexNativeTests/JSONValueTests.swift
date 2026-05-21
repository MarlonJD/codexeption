import XCTest

final class JSONValueTests: XCTestCase {
    func testDecodesMixedJSON() throws {
        let data = #"{"name":"codex","enabled":true,"count":2,"items":[null,"x"]}"#.data(using: .utf8)!
        let value = try JSONDecoder.codex.decode(JSONValue.self, from: data)

        XCTAssertEqual(value["name"]?.stringValue, "codex")
        XCTAssertEqual(value["enabled"]?.boolValue, true)
        XCTAssertEqual(value["count"]?.intValue, 2)
        XCTAssertEqual(value["items"]?.arrayValue?.count, 2)
    }

    func testRPCIDAcceptsStringAndInteger() throws {
        XCTAssertEqual(try JSONDecoder.codex.decode(RPCID.self, from: #"7"#.data(using: .utf8)!), .int(7))
        XCTAssertEqual(try JSONDecoder.codex.decode(RPCID.self, from: #""abc""#.data(using: .utf8)!), .string("abc"))
    }
}
