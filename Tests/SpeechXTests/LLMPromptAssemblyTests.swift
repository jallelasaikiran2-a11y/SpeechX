import XCTest
@testable import SpeechX

final class LLMPromptAssemblyTests: XCTestCase {
    func testReturnsNilWhenNoStepsEnabled() {
        let options = LLMProcessingOptions(
            codeMix: nil,
            fixSpelling: false,
            fixGrammar: false,
            targetLanguage: nil
        )
        XCTAssertNil(LLMService.buildSystemPrompt(for: options))
    }

    func testSpellingOnlyProducesBasePrompt() {
        let options = LLMProcessingOptions(
            codeMix: nil,
            fixSpelling: true,
            fixGrammar: false,
            targetLanguage: nil
        )
        let prompt = LLMService.buildSystemPrompt(for: options)
        XCTAssertNotNil(prompt)
        // The base SpeechX prompt is always present when any step is enabled
        XCTAssertTrue(prompt!.contains("You are the text-refinement layer of SpeechX"))
        XCTAssertTrue(prompt!.contains("Self-Correction & Retraction"))
        XCTAssertTrue(prompt!.contains("Disfluency Removal"))
        XCTAssertTrue(prompt!.contains("CUSTOM VOCABULARY"))
        XCTAssertTrue(prompt!.contains("Return only the refined transcript text"))
        // No additional instructions appended for spelling-only
        XCTAssertFalse(prompt!.contains("ADDITIONAL INSTRUCTIONS"))
    }

    func testCodeMixAppendsAdditionalInstruction() {
        let options = LLMProcessingOptions(
            codeMix: "Hinglish",
            fixSpelling: true,
            fixGrammar: false,
            targetLanguage: nil
        )
        let prompt = LLMService.buildSystemPrompt(for: options)
        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt!.contains("ADDITIONAL INSTRUCTIONS"))
        XCTAssertTrue(prompt!.contains("Hinglish"))
        XCTAssertTrue(prompt!.contains("Transliterate any non-Roman script"))
    }

    func testTranslationAppendsAdditionalInstruction() {
        let options = LLMProcessingOptions(
            codeMix: nil,
            fixSpelling: false,
            fixGrammar: false,
            targetLanguage: "Spanish"
        )
        let prompt = LLMService.buildSystemPrompt(for: options)
        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt!.contains("ADDITIONAL INSTRUCTIONS"))
        XCTAssertTrue(prompt!.contains("translate the entire text to Spanish"))
    }

    func testCodeMixAndTranslationBothAppended() {
        let options = LLMProcessingOptions(
            codeMix: "Tanglish",
            fixSpelling: true,
            fixGrammar: true,
            targetLanguage: "English"
        )
        let prompt = LLMService.buildSystemPrompt(for: options)!
        // Both extras present in order
        let codeMixIdx = prompt.range(of: "Tanglish")!.lowerBound
        let translateIdx = prompt.range(of: "translate the entire text to English")!.lowerBound
        XCTAssertLessThan(codeMixIdx, translateIdx)
    }

    func testUserDictionaryInjectsIntoPrompt() {
        let options = LLMProcessingOptions(
            codeMix: nil,
            fixSpelling: true,
            fixGrammar: false,
            targetLanguage: nil,
            userDictionary: "SpeechX\nSai Kiran\nDeepgram"
        )
        let prompt = LLMService.buildSystemPrompt(for: options)!
        XCTAssertTrue(prompt.contains("SpeechX"))
        XCTAssertTrue(prompt.contains("Sai Kiran"))
        XCTAssertTrue(prompt.contains("Deepgram"))
    }

    func testEmptyDictionaryShowsNone() {
        let options = LLMProcessingOptions(
            codeMix: nil,
            fixSpelling: true,
            fixGrammar: false,
            targetLanguage: nil,
            userDictionary: nil
        )
        let prompt = LLMService.buildSystemPrompt(for: options)!
        XCTAssertTrue(prompt.contains("(none)"))
    }

    func testCustomPromptIsPrepended() {
        let custom = "Always respond in bullet points."
        let options = LLMProcessingOptions(
            codeMix: nil,
            fixSpelling: true,
            fixGrammar: false,
            targetLanguage: nil,
            customPrompt: custom
        )
        let prompt = LLMService.buildSystemPrompt(for: options)!
        // Custom instructions come before the base SpeechX prompt
        let customIdx = prompt.range(of: "bullet points")!.lowerBound
        let baseIdx = prompt.range(of: "text-refinement layer of SpeechX")!.lowerBound
        XCTAssertLessThan(customIdx, baseIdx)
    }

    func testStripReasoningRemovesThinkBlock() {
        let input = "<think>let me think about this</think>Hi, kyā kar rahe ho?"
        XCTAssertEqual(LLMService.stripReasoning(input), "Hi, kyā kar rahe ho?")
    }

    func testStripReasoningRemovesMultilineThinkingBlock() {
        let input = """
        <thinking>
        Step 1: parse
        Step 2: respond
        </thinking>
        Final answer.
        """
        XCTAssertEqual(LLMService.stripReasoning(input), "Final answer.")
    }

    func testStripReasoningRemovesReasoningBlock() {
        let input = "<reasoning>internal</reasoning>\n\nOutput text"
        XCTAssertEqual(LLMService.stripReasoning(input), "Output text")
    }

    func testStripReasoningIsCaseInsensitive() {
        let input = "<Think>x</THINK>y"
        XCTAssertEqual(LLMService.stripReasoning(input), "y")
    }

    func testStripReasoningHandlesUnclosedOpener() {
        let input = "<think>only opening tag, no close, final answer here"
        XCTAssertEqual(LLMService.stripReasoning(input), "only opening tag, no close, final answer here".replacingOccurrences(of: "<think>", with: ""))
    }

    func testStripReasoningLeavesCleanTextUntouched() {
        let input = "Hello world."
        XCTAssertEqual(LLMService.stripReasoning(input), "Hello world.")
    }

    func testStripReasoningHandlesMultipleBlocks() {
        let input = "<think>a</think>middle<think>b</think>end"
        XCTAssertEqual(LLMService.stripReasoning(input), "middleend")
    }

    func testHasAnyStepIgnoresDictionary() {
        // A dictionary-only config has no LLM step (the dictionary is applied in code instead).
        let options = LLMProcessingOptions(
            codeMix: nil, fixSpelling: false, fixGrammar: false, targetLanguage: nil, customPrompt: nil)
        XCTAssertFalse(options.hasAnyStep)
    }

    func testHasAnyStepReflectsAnyEnabledOption() {
        XCTAssertFalse(LLMProcessingOptions(codeMix: nil, fixSpelling: false, fixGrammar: false, targetLanguage: nil).hasAnyStep)
        XCTAssertTrue(LLMProcessingOptions(codeMix: "Hinglish", fixSpelling: false, fixGrammar: false, targetLanguage: nil).hasAnyStep)
        XCTAssertTrue(LLMProcessingOptions(codeMix: nil, fixSpelling: true, fixGrammar: false, targetLanguage: nil).hasAnyStep)
        XCTAssertTrue(LLMProcessingOptions(codeMix: nil, fixSpelling: false, fixGrammar: true, targetLanguage: nil).hasAnyStep)
        XCTAssertTrue(LLMProcessingOptions(codeMix: nil, fixSpelling: false, fixGrammar: false, targetLanguage: "French").hasAnyStep)
    }
}
