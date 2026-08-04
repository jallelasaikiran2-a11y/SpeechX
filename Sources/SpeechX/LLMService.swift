import Foundation
import os.log

private let llmLogger = Logger(subsystem: "com.speechx.app", category: "llm")

enum LLMProvider: String, CaseIterable, Identifiable {
    case groq        = "groq"
    case openRouter  = "open_router"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq:       return "Groq"
        case .openRouter: return "OpenRouter"
        }
    }

    var baseURL: URL {
        switch self {
        case .groq:       return URL(staticString: "https://api.groq.com/openai/v1")
        case .openRouter: return URL(staticString: "https://openrouter.ai/api/v1")
        }
    }

    var modelsURL: URL          { baseURL.appendingPathComponent("models") }
    var chatCompletionsURL: URL { baseURL.appendingPathComponent("chat/completions") }

    var signupURL: URL {
        switch self {
        case .groq:       return URL(staticString: "https://console.groq.com/keys")
        case .openRouter: return URL(staticString: "https://openrouter.ai/keys")
        }
    }

    var keychainKey: String {
        switch self {
        case .groq:       return "groq_api_key"
        case .openRouter: return "openrouter_api_key"
        }
    }
}

struct LLMModel: Identifiable, Hashable {
    let id: String
    let displayName: String
}

struct LLMProcessingOptions {
    var codeMix: String?          // nil = disabled; value = mixType e.g. "Hinglish"
    var fixSpelling: Bool
    var fixGrammar: Bool
    var targetLanguage: String?   // nil = disabled; value = e.g. "French"
    var customPrompt: String?     // nil/empty = disabled; user-supplied bias prepended to system prompt
    var userDictionary: String?   // nil/empty = no custom vocabulary; value = focus-words entries for the prompt

    // Note: the focus-words dictionary is ALSO applied deterministically in code
    // (see FocusWordsDictionary) after LLM processing — the LLM gets the vocabulary
    // as a hint for phonetic correction, while the code-side pass is the authoritative
    // spelling/expansion override.

    var hasAnyStep: Bool {
        if codeMix != nil || fixSpelling || fixGrammar || targetLanguage != nil { return true }
        let trimmedCustom = customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmedCustom.isEmpty
    }
}

class LLMService {
    /// Per-request timeout for chat completions. Default URLSession is 60s, but some
    /// OpenRouter models (Anthropic Sonnet, large Gemini) routinely take 30+ seconds —
    /// 90s leaves headroom without hanging the UI forever.
    var requestTimeout: TimeInterval = 90

    /// Delay before the single retry on 429/5xx / network blips.
    var retryDelay: TimeInterval = 0.25

    func fetchModels(provider: LLMProvider, apiKey: String) async throws -> [LLMModel] {
        guard !apiKey.isEmpty else { throw APIError.missingKey }

        var request = URLRequest(url: provider.modelsURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(httpStatus) else {
            let body = String(data: data, encoding: .utf8)
            llmLogger.error("\(provider.displayName) /models HTTP \(httpStatus): \(body ?? "<binary>")")
            throw APIError.http(status: httpStatus, body: body)
        }
        guard let root = try? JSONDecoder().decode(LLMModelsResponse.self, from: data) else {
            let body = String(data: data, encoding: .utf8)
            llmLogger.error("\(provider.displayName) /models decode failed: \(body ?? "<binary>")")
            throw APIError.decoding
        }
        let models = (root.data ?? [])
            .map { LLMModel(id: $0.id, displayName: $0.name ?? $0.id) }
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        llmLogger.info("\(provider.displayName) /models returned \(models.count) entries")
        return models
    }

    func processText(
        _ text: String,
        options: LLMProcessingOptions,
        provider: LLMProvider,
        apiKey: String,
        model: String
    ) async throws -> String {
        guard let systemPrompt = Self.buildSystemPrompt(for: options) else { return text }
        guard !apiKey.isEmpty else { throw APIError.missingKey }
        guard !model.isEmpty else { throw APIError.missingModel }

        var request = URLRequest(url: provider.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout
        if provider == .openRouter {
            request.setValue("https://github.com/Vocallabsai/speechx", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("SpeechX", forHTTPHeaderField: "X-Title")
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": text]
            ],
            "temperature": 0
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            llmLogger.error("Failed to encode chat completion request body")
            throw APIError.encoding
        }
        request.httpBody = httpBody

        return try await sendChatCompletion(request: request, provider: provider, allowRetry: true)
    }

    /// Pure prompt assembly. Extracted as `static` so it's deterministic given options
    /// and unit-testable without spinning up a real network. Returns `nil` when no
    /// processing steps are enabled (caller short-circuits to passthrough).
    static func buildSystemPrompt(for options: LLMProcessingOptions) -> String? {
        guard options.hasAnyStep else { return nil }

        // --- Custom vocabulary block (focus-words injected for phonetic correction) ---
        let dictText = options.userDictionary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let vocabBlock = dictText.isEmpty ? "(none)" : dictText

        // --- Base SpeechX text-refinement prompt ---
        var prompt = """
        You are the text-refinement layer of SpeechX, a real-time voice dictation system. You receive raw, unpunctuated speech-to-text transcripts and must convert them into clean, publication-ready text that reflects the speaker's TRUE FINAL INTENT — not a literal transcription.

        ## CORE PRINCIPLE
        You are a cleanup layer, not an editor. You remove noise (filler, stutters, abandoned retractions) and fix mechanics (grammar, punctuation, casing). You do NOT summarize, shorten, or remove any clause that carries actual content or meaning — even if that content sounds informal, rambling, or wordy. When in doubt, KEEP the words and just clean their grammar. Deleting content is a worse failure than leaving in a slightly awkward phrase.

        ## RULES

        ### 1. Self-Correction & Retraction (delete ONLY the abandoned fragment, nothing else)
        When the speaker corrects themselves, keep only the final corrected version. Discard ONLY the specific abandoned word/clause and its retraction cue word — do not touch or shorten anything else in the sentence.
        - Input: "My name is Sai, sorry, Arun." → Output: "My name is Arun."
        - Input: "Email John — actually, cc Sarah too." → Output: "Email John, cc Sarah too." (note: "too" stays — it was never retracted)
        - Input: "I think we should launch Friday. Scratch that, let's do Monday." → Output: "Let's launch Monday." (note: "launch" stays — only "Friday" was retracted, not the verb)
        - Input: "Can you send the report to... hmm... just send it to the whole team." → Output: "Can you send the report to the whole team?" (note: preserve the original question form — "hmm" is filler, not a retraction of the question itself)
        Retraction cue words: "actually," "wait," "no," "sorry," "I mean," "scratch that," "let me rephrase," "or rather." Strip ONLY the cue word and the specific abandoned word/phrase it points to — never a whole clause unless the whole clause was actually abandoned. When resolving a retraction that swaps one value for another (not a full deletion), keep a natural connecting word if the original phrasing had one — for example, keep 'instead' if the speaker's correction implies a replacement. Example: 'Text John instead of Sam' → 'Text John instead of Sam' stays as-is if 'Sam' was never retracted; but 'Send it to Sam, actually John' → 'Send it to John' remains correct without 'instead' since none was spoken.

        ### 2. Disfluency Removal (filler words only — never framing clauses)
        Remove ONLY: "um," "uh," "like" (filler use), "you know" (filler use), stutters ("I I I think" → "I think"), and immediate word repetition used as stalling ("the the meeting" → "the meeting").
        Do NOT remove clauses that carry meaning, even if wordy or informal — e.g. "so basically what I'm trying to say is X" is NOT filler; "so basically" can be trimmed but "what I'm trying to say is" plus X should generally stay intact unless it is pure stalling with zero content. If unsure whether something is filler or content, treat it as content and keep it.

        ### 3. Grammar, Punctuation, Casing
        Apply full sentence casing, punctuation, and grammar correction as if professionally typed. Fix run-ons into properly punctuated sentences.

        ### 4. Register Preservation (critical — do not upgrade tone)
        Match the speaker's exact register. This is not optional polish — output must sound like the same person who spoke it.
        - Keep contractions: "we're," "I'm," "let's," "gonna," "wanna"
        - Keep casual openers/closers exactly as spoken: "yo," "hey," "thanks," "cool," "no worries" — never upgrade "yo" to nothing, or "thanks" to "thank you"
        - Keep questions as questions. If the speaker asked "can you send me X?", the output must remain a question — do not flatten it into a command like "send me X."
        - Keep casual word choices: "that file" stays "that file," do not swap to "the file" unless grammatically required
        - Example: Input: "yo can you like send me that file when you get a chance" → Output: "Yo, can you send me that file when you get a chance?" (only "like" removed — everything else, including tone and question form, stays)

        ### 5. Numbers, Names, Technical Terms
        Render clearly spoken digit sequences as numerals unless context implies they should stay spelled out (e.g. "I have three cats" stays "three," "there are two options" stays "two").
        Preserve proper nouns, brand names, and technical terms EXACTLY as given in the CUSTOM VOCABULARY list — correct phonetic misrecognitions using that list as ground truth. If a term is NOT in the list, do your best with standard capitalization conventions for known tech terms (e.g. product names typically capitalize each meaningful syllable) rather than leaving a garbled phonetic guess — but never invent a spelling you're not reasonably confident about; when uncertain, keep the closest phonetic transcription.

        ### 6. Repetition vs. Lists
        When the same word is repeated back-to-back as stalling, collapse to one: "the the meeting" → "the meeting."
        When multiple distinct items are listed with repeated nouns, format as a clean list: "milk milk eggs bread bread" → "milk, eggs, and bread." Always include the Oxford comma + "and" before the last list item.

        ### 7. Long-Form Coherence
        For extended dictation, preserve every clause and every named entity mentioned. Never drop the opening framing sentence (e.g. "So the way X works is..."). Never drop a product name, technical term, or verb even in a long sentence — re-read your output against the input before finalizing and confirm every content word survived.

        ### 8. Absolute Guardrails (self-check before output)
        Before returning your answer, verify:
        - Did I delete any word that carried actual meaning (not filler, not a retracted fragment)? If yes, put it back.
        - Did I change a question into a statement, or a casual phrase into a formal one? If yes, revert it.
        - Did I use every word from the CUSTOM VOCABULARY list correctly wherever it phonetically appears in the input?
        - Is my output roughly the same length as the input, minus only true filler/retracted words? If it's noticeably shorter, I have likely over-trimmed — re-check.

        ## CUSTOM VOCABULARY (correct any phonetic misrecognition to these exact forms)
        {{USER_DICTIONARY}}

        ## OUTPUT FORMAT
        Return only the refined transcript text. No quotes, no labels, no explanation, no markdown.

        ## RAW TRANSCRIPT
        {{RAW_TEXT}}
        """

        // --- Append optional processing steps (code-mix, translation) ---
        var extras: [String] = []
        if let mixType = options.codeMix {
            extras.append("The input is in \(mixType). Transliterate any non-Roman script (such as Devanagari, Tamil, etc.) to Roman script. Keep English words as-is. Do not translate — preserve the original meaning in mixed form.")
        }
        if let lang = options.targetLanguage {
            extras.append("After refinement, translate the entire text to \(lang). Every word in the final output must be in \(lang).")
        }
        if !extras.isEmpty {
            prompt += "\n\n## ADDITIONAL INSTRUCTIONS\n" + extras.joined(separator: "\n")
        }

        // --- Prepend user's custom instructions if provided ---
        let trimmedCustom = options.customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedCustom.isEmpty {
            prompt = trimmedCustom + "\n\n" + prompt
        }

        prompt = prompt.replacingOccurrences(of: "{{USER_DICTIONARY}}", with: vocabBlock)
        return prompt
    }

    // MARK: - Internal helpers

    private func sendChatCompletion(
        request: URLRequest,
        provider: LLMProvider,
        allowRetry: Bool
    ) async throws -> String {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await performRequest(request)
        } catch let error as APIError {
            if allowRetry, case .network = error {
                llmLogger.info("Retrying \(provider.displayName) /chat/completions after network error")
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                return try await sendChatCompletion(request: request, provider: provider, allowRetry: false)
            }
            throw error
        }

        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(httpStatus) {
            let bodyStr = String(data: data, encoding: .utf8)
            llmLogger.error("\(provider.displayName) /chat/completions HTTP \(httpStatus): \(bodyStr ?? "<binary>")")
            if allowRetry && (httpStatus == 429 || (500..<600).contains(httpStatus)) {
                llmLogger.info("Retrying \(provider.displayName) /chat/completions after HTTP \(httpStatus)")
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                return try await sendChatCompletion(request: request, provider: provider, allowRetry: false)
            }
            throw APIError.http(status: httpStatus, body: bodyStr)
        }

        guard let root = try? JSONDecoder().decode(LLMChatResponse.self, from: data),
              let result = root.choices?.first?.message?.content,
              !result.isEmpty else {
            let bodyStr = String(data: data, encoding: .utf8)
            llmLogger.error("\(provider.displayName) /chat/completions decode failed: \(bodyStr ?? "<binary>")")
            throw APIError.decoding
        }
        return Self.stripReasoning(result)
    }

    /// Strip reasoning/thinking blocks that some models (DeepSeek R1, Qwen QwQ, etc.) emit
    /// inline in the assistant content. Handles `<think>...</think>`, `<thinking>...</thinking>`,
    /// and `<reasoning>...</reasoning>` tags. Case-insensitive, multiline. If an opening tag
    /// has no closing tag (streamed cut-off), drop everything up to the last seen opener.
    static func stripReasoning(_ text: String) -> String {
        let tags = ["think", "thinking", "reasoning"]
        var output = text
        for tag in tags {
            let pattern = "<\\s*\(tag)\\s*>[\\s\\S]*?<\\s*/\\s*\(tag)\\s*>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(output.startIndex..., in: output)
                output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "")
            }
            // Unbalanced opener: keep only text after the last opening tag.
            let openPattern = "<\\s*\(tag)\\s*>"
            if let openRegex = try? NSRegularExpression(pattern: openPattern, options: [.caseInsensitive]) {
                let range = NSRange(output.startIndex..., in: output)
                if let last = openRegex.matches(in: output, options: [], range: range).last,
                   let swiftRange = Range(last.range, in: output) {
                    output = String(output[swiftRange.upperBound...])
                }
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }
}

// MARK: - Response Models

private struct LLMModelsResponse: Codable {
    let data: [LLMModelEntry]?
}

private struct LLMModelEntry: Codable {
    let id: String
    let name: String?
}

private struct LLMChatResponse: Codable {
    let choices: [LLMChoice]?
}

private struct LLMChoice: Codable {
    let message: LLMMessage?
}

private struct LLMMessage: Codable {
    let content: String?
}
