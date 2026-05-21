import XCTest

final class CodexProtocolTests: XCTestCase {
    func testTurnStartPayloadUsesCodexUserInputShape() throws {
        let params = TurnStartParams(
            threadId: "thread-1",
            input: [.text("Merhaba"), .localImage(path: "/tmp/image.png")],
            cwd: "/tmp/project",
            approvalPolicy: "on-request",
            approvalsReviewer: "auto_review",
            sandboxPolicy: nil,
            model: "gpt-5.4",
            effort: "medium"
        )

        let value = try JSONValue.encoded(params)

        XCTAssertEqual(value["threadId"]?.stringValue, "thread-1")
        XCTAssertEqual(value["input"]?.arrayValue?.first?["type"]?.stringValue, "text")
        XCTAssertEqual(value["input"]?.arrayValue?.first?["text_elements"]?.arrayValue?.count, 0)
        XCTAssertEqual(value["input"]?.arrayValue?.last?["type"]?.stringValue, "localImage")
        XCTAssertEqual(value["input"]?.arrayValue?.last?["path"]?.stringValue, "/tmp/image.png")
        XCTAssertEqual(value["approvalPolicy"]?.stringValue, "on-request")
        XCTAssertEqual(value["approvalsReviewer"]?.stringValue, "auto_review")
    }

    func testModelListDecodesReasoningEffortObjects() throws {
        let data = """
        {
          "data": [
            {
              "id": "gpt-5.5",
              "model": "gpt-5.5",
              "displayName": "GPT-5.5",
              "description": "",
              "hidden": false,
              "supportedReasoningEfforts": [
                {"reasoningEffort": "low"},
                {"reasoningEffort": "medium"},
                {"reasoningEffort": "high"}
              ],
              "defaultReasoningEffort": "medium",
              "isDefault": true
            }
          ],
          "nextCursor": null
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.codex.decode(ModelListResponseDTO.self, from: data)

        XCTAssertEqual(response.data.first?.supportedReasoningEfforts, ["low", "medium", "high"])
        XCTAssertEqual(response.data.first?.defaultReasoningEffort, "medium")
    }

    func testUnknownNotificationDecodesWithoutTypedSchema() throws {
        let data = #"{"method":"future/event","params":{"answer":42}}"#.data(using: .utf8)!
        let message = try JSONDecoder.codex.decode(JSONRPCIncomingMessage.self, from: data)

        XCTAssertEqual(message.method, "future/event")
        XCTAssertEqual(message.params?["answer"]?.intValue, 42)
    }

    func testInitializedNotificationEncodesWithoutRequestID() throws {
        let data = try JSONEncoder.codex.encode(JSONRPCOutgoingNotification(method: "initialized"))
        let value = try JSONDecoder.codex.decode(JSONValue.self, from: data)

        XCTAssertEqual(value["method"]?.stringValue, "initialized")
        XCTAssertNil(value["id"])
    }

    func testAuthStatusMapsSignedInMethod() throws {
        let data = #"{"authMethod":"chatgpt","authToken":null,"requiresOpenaiAuth":true}"#.data(using: .utf8)!
        let response = try JSONDecoder.codex.decode(GetAuthStatusResponseDTO.self, from: data)

        XCTAssertEqual(response.status, .signedIn(method: "chatgpt"))
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

    func testDiffSnapshotBuildsLiveChangeSummary() {
        let diff = """
        diff --git a/CodexNative/Services/CodexClient.swift b/CodexNative/Services/CodexClient.swift
        index 1111111..2222222 100644
        --- a/CodexNative/Services/CodexClient.swift
        +++ b/CodexNative/Services/CodexClient.swift
        @@ -1,2 +1,3 @@
         import Foundation
        +import SwiftUI
        -let old = true
        +let new = true
        diff --git a/CodexNative/Views/LiveView.swift b/CodexNative/Views/LiveView.swift
        new file mode 100644
        --- /dev/null
        +++ b/CodexNative/Views/LiveView.swift
        @@ -0,0 +1,2 @@
        +struct LiveView {}
        +let value = 1
        """

        let summary = DiffSnapshot(threadID: "t1", turnID: "turn1", unifiedDiff: diff).changeSummary

        XCTAssertEqual(summary.fileCount, 2)
        XCTAssertEqual(summary.additions, 4)
        XCTAssertEqual(summary.deletions, 1)
        XCTAssertEqual(summary.files[0].displayName, "CodexClient.swift")
        XCTAssertEqual(summary.files[0].state, .modified)
        XCTAssertEqual(summary.files[1].displayName, "LiveView.swift")
        XCTAssertEqual(summary.files[1].state, .created)
    }
}
