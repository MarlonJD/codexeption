import XCTest

final class CodexProtocolTests: XCTestCase {
    func testTurnStartPayloadUsesCodexUserInputShape() throws {
        let params = TurnStartParams(
            threadId: "thread-1",
            input: [.text("Merhaba"), .localImage(path: "/tmp/image.png")],
            cwd: "/tmp/project",
            approvalPolicy: "on-request",
            model: "gpt-5.4",
            effort: "medium"
        )

        let value = try JSONValue.encoded(params)

        XCTAssertEqual(value["threadId"]?.stringValue, "thread-1")
        XCTAssertEqual(value["input"]?.arrayValue?.first?["type"]?.stringValue, "text")
        XCTAssertEqual(value["input"]?.arrayValue?.first?["text_elements"]?.arrayValue?.count, 0)
        XCTAssertEqual(value["input"]?.arrayValue?.last?["type"]?.stringValue, "localImage")
        XCTAssertEqual(value["input"]?.arrayValue?.last?["path"]?.stringValue, "/tmp/image.png")
    }

    func testUnknownNotificationDecodesWithoutTypedSchema() throws {
        let data = #"{"method":"future/event","params":{"answer":42}}"#.data(using: .utf8)!
        let message = try JSONDecoder.codex.decode(JSONRPCIncomingMessage.self, from: data)

        XCTAssertEqual(message.method, "future/event")
        XCTAssertEqual(message.params?["answer"]?.intValue, 42)
    }

    func testApprovalRequestMapsCommandRequest() {
        let envelope = ServerRequestEnvelope(
            id: .int(9),
            method: "item/commandExecution/requestApproval",
            params: .object([
                "threadId": .string("t1"),
                "turnId": .string("turn1"),
                "itemId": .string("item1"),
                "command": .string("swift test"),
                "cwd": .string("/tmp/project")
            ])
        )

        let approval = ApprovalRequest.from(envelope)

        XCTAssertEqual(approval.id, "9")
        XCTAssertEqual(approval.kind, .commandExecution)
        XCTAssertEqual(approval.title, "swift test")
        XCTAssertEqual(approval.cwd, "/tmp/project")
    }
}
