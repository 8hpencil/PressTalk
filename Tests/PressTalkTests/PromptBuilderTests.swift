import XCTest
@testable import PressTalk

final class PromptBuilderTests: XCTestCase {
    func testEmptyCustomPromptFallsBackToDefault() {
        XCTAssertFalse(PromptBuilder.defaultPrompt.isEmpty)
        XCTAssertEqual(PromptBuilder.build(customPrompt: "", hintWords: []), PromptBuilder.defaultPrompt)
    }

    func testWhitespaceOnlyCustomPromptFallsBackToDefault() {
        XCTAssertEqual(PromptBuilder.build(customPrompt: "  \n\t ", hintWords: []), PromptBuilder.defaultPrompt)
    }

    func testCustomPromptOverridesDefault() {
        XCTAssertEqual(PromptBuilder.build(customPrompt: " 转写为普通话 ", hintWords: []), "转写为普通话")
    }

    func testHintWordsAreAppended() {
        let prompt = PromptBuilder.build(customPrompt: "Base prompt", hintWords: ["炭滤池", "臭氧发生器"])
        XCTAssertTrue(prompt.hasPrefix("Base prompt"))
        XCTAssertTrue(prompt.contains("炭滤池"))
        XCTAssertTrue(prompt.contains("臭氧发生器"))
    }

    func testHintWordsAppendToDefaultPromptToo() {
        let prompt = PromptBuilder.build(customPrompt: "", hintWords: ["PressTalk"])
        XCTAssertTrue(prompt.hasPrefix(PromptBuilder.defaultPrompt))
        XCTAssertTrue(prompt.contains("PressTalk"))
    }
}
