import Foundation
import XCTest

final class JSONLineFramerTests: XCTestCase {
    func testFramesChunkedNewlineDelimitedMessages() {
        var framer = JSONLineFramer()

        XCTAssertTrue(framer.append(Data(#"{"id":"#.utf8)).isEmpty)
        let first = framer.append(Data((#"1}"# + "\n" + #"{"id":2}"# + "\n").utf8))

        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(String(data: first[0], encoding: .utf8), #"{"id":1}"#)
        XCTAssertEqual(String(data: first[1], encoding: .utf8), #"{"id":2}"#)
        XCTAssertNil(framer.flush())
    }

    func testKeepsTrailingPartialLine() {
        var framer = JSONLineFramer()

        let lines = framer.append(Data(#"{"id":1}"#.utf8))
        XCTAssertTrue(lines.isEmpty)
        XCTAssertEqual(String(data: framer.flush()!, encoding: .utf8), #"{"id":1}"#)
    }
}
