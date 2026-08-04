using System.Diagnostics;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace SpeechX.Core;

/// <summary>
/// Calls Groq/OpenRouter OpenAI-compatible chat completions to post-process a transcript,
/// and lists available models. Port of the macOS LlmService.
/// </summary>
public sealed class LlmService
{
    private static readonly HttpClient ModelsHttp = new();

    /// <summary>Per-request timeout for chat completions (some OpenRouter models take 30s+).</summary>
    public TimeSpan RequestTimeout { get; set; } = TimeSpan.FromSeconds(90);

    /// <summary>Delay before the single retry on 429/5xx / network blips.</summary>
    public TimeSpan RetryDelay { get; set; } = TimeSpan.FromMilliseconds(250);

    public async Task<IReadOnlyList<LlmModel>> FetchModelsAsync(LlmProvider provider, string apiKey)
    {
        if (string.IsNullOrEmpty(apiKey)) throw ApiException.MissingKey();

        using var request = new HttpRequestMessage(HttpMethod.Get, provider.ModelsUrl());
        request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {apiKey}");

        var (data, status) = await PerformAsync(ModelsHttp, request).ConfigureAwait(false);
        if (status < 200 || status >= 300)
            throw ApiException.Http(status, data);

        LlmModelsResponse? root;
        try { root = JsonSerializer.Deserialize<LlmModelsResponse>(data); }
        catch { throw ApiException.Decoding(); }
        if (root == null) throw ApiException.Decoding();

        return (root.Data ?? new())
            .Select(m => new LlmModel(m.Id, m.Name ?? m.Id))
            .OrderBy(m => m.DisplayName.ToLowerInvariant(), StringComparer.Ordinal)
            .ToList();
    }

    public async Task<string> ProcessTextAsync(
        string text, LlmProcessingOptions options, LlmProvider provider, string apiKey, string model)
    {
        var systemPrompt = BuildSystemPrompt(options);
        if (systemPrompt == null) return text;
        if (string.IsNullOrEmpty(apiKey)) throw ApiException.MissingKey();
        if (string.IsNullOrEmpty(model)) throw ApiException.MissingModel();

        var body = new
        {
            model,
            messages = new[]
            {
                new { role = "system", content = systemPrompt },
                new { role = "user", content = text },
            },
            temperature = 0,
        };

        string json;
        try { json = JsonSerializer.Serialize(body); }
        catch { throw ApiException.Encoding(); }

        // A fresh client per call so we can apply the long per-request timeout.
        using var client = new HttpClient { Timeout = RequestTimeout };
        return await SendChatCompletionAsync(client, provider, apiKey, json, allowRetry: true).ConfigureAwait(false);
    }

    /// <summary>
    /// Pure prompt assembly. Deterministic given options; returns null when no steps are enabled.
    /// </summary>
    public static string? BuildSystemPrompt(LlmProcessingOptions options)
    {
        if (!options.HasAnyStep) return null;

        // --- Custom vocabulary block (focus-words injected for phonetic correction) ---
        var dictText = options.UserDictionary?.Trim() ?? "";
        var vocabBlock = dictText.Length == 0 ? "(none)" : dictText;

        // --- Base SpeechX text-refinement prompt ---
        var prompt = @"You are the text-refinement layer of SpeechX, a real-time voice dictation system. You receive raw, unpunctuated speech-to-text transcripts and must convert them into clean, publication-ready text that reflects the speaker's TRUE FINAL INTENT — not a literal transcription.

## CORE PRINCIPLE
You are a cleanup layer, not an editor. You remove noise (filler, stutters, abandoned retractions) and fix mechanics (grammar, punctuation, casing). You do NOT summarize, shorten, or remove any clause that carries actual content or meaning — even if that content sounds informal, rambling, or wordy. When in doubt, KEEP the words and just clean their grammar. Deleting content is a worse failure than leaving in a slightly awkward phrase.

## RULES

### 1. Self-Correction & Retraction (delete ONLY the abandoned fragment, nothing else)
When the speaker corrects themselves, keep only the final corrected version. Discard ONLY the specific abandoned word/clause and its retraction cue word — do not touch or shorten anything else in the sentence.
- Input: ""My name is Sai, sorry, Arun."" → Output: ""My name is Arun.""
- Input: ""Email John — actually, cc Sarah too."" → Output: ""Email John, cc Sarah too."" (note: ""too"" stays — it was never retracted)
- Input: ""I think we should launch Friday. Scratch that, let's do Monday."" → Output: ""Let's launch Monday."" (note: ""launch"" stays — only ""Friday"" was retracted, not the verb)
- Input: ""Can you send the report to... hmm... just send it to the whole team."" → Output: ""Can you send the report to the whole team?"" (note: preserve the original question form — ""hmm"" is filler, not a retraction of the question itself)
Retraction cue words: ""actually,"" ""wait,"" ""no,"" ""sorry,"" ""I mean,"" ""scratch that,"" ""let me rephrase,"" ""or rather."" Strip ONLY the cue word and the specific abandoned word/phrase it points to — never a whole clause unless the whole clause was actually abandoned. When resolving a retraction that swaps one value for another (not a full deletion), keep a natural connecting word if the original phrasing had one — for example, keep 'instead' if the speaker's correction implies a replacement. Example: 'Text John instead of Sam' → 'Text John instead of Sam' stays as-is if 'Sam' was never retracted; but 'Send it to Sam, actually John' → 'Send it to John' remains correct without 'instead' since none was spoken.

### 2. Disfluency Removal (filler words only — never framing clauses)
Remove ONLY: ""um,"" ""uh,"" ""like"" (filler use), ""you know"" (filler use), stutters (""I I I think"" → ""I think""), and immediate word repetition used as stalling (""the the meeting"" → ""the meeting"").
Do NOT remove clauses that carry meaning, even if wordy or informal — e.g. ""so basically what I'm trying to say is X"" is NOT filler; ""so basically"" can be trimmed but ""what I'm trying to say is"" plus X should generally stay intact unless it is pure stalling with zero content. If unsure whether something is filler or content, treat it as content and keep it.

### 3. Grammar, Punctuation, Casing
Apply full sentence casing, punctuation, and grammar correction as if professionally typed. Fix run-ons into properly punctuated sentences.

### 4. Register Preservation (critical — do not upgrade tone)
Match the speaker's exact register. This is not optional polish — output must sound like the same person who spoke it.
- Keep contractions: ""we're,"" ""I'm,"" ""let's,"" ""gonna,"" ""wanna""
- Keep casual openers/closers exactly as spoken: ""yo,"" ""hey,"" ""thanks,"" ""cool,"" ""no worries"" — never upgrade ""yo"" to nothing, or ""thanks"" to ""thank you""
- Keep questions as questions. If the speaker asked ""can you send me X?"", the output must remain a question — do not flatten it into a command like ""send me X.""
- Keep casual word choices: ""that file"" stays ""that file,"" do not swap to ""the file"" unless grammatically required
- Example: Input: ""yo can you like send me that file when you get a chance"" → Output: ""Yo, can you send me that file when you get a chance?"" (only ""like"" removed — everything else, including tone and question form, stays)

### 5. Numbers, Names, Technical Terms
Render clearly spoken digit sequences as numerals unless context implies they should stay spelled out (e.g. ""I have three cats"" stays ""three,"" ""there are two options"" stays ""two"").
Preserve proper nouns, brand names, and technical terms EXACTLY as given in the CUSTOM VOCABULARY list — correct phonetic misrecognitions using that list as ground truth. If a term is NOT in the list, do your best with standard capitalization conventions for known tech terms (e.g. product names typically capitalize each meaningful syllable) rather than leaving a garbled phonetic guess — but never invent a spelling you're not reasonably confident about; when uncertain, keep the closest phonetic transcription.

### 6. Repetition vs. Lists
When the same word is repeated back-to-back as stalling, collapse to one: ""the the meeting"" → ""the meeting.""
When multiple distinct items are listed with repeated nouns, format as a clean list: ""milk milk eggs bread bread"" → ""milk, eggs, and bread."" Always include the Oxford comma + ""and"" before the last list item.

### 7. Long-Form Coherence
For extended dictation, preserve every clause and every named entity mentioned. Never drop the opening framing sentence (e.g. ""So the way X works is...""). Never drop a product name, technical term, or verb even in a long sentence — re-read your output against the input before finalizing and confirm every content word survived.

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
{{RAW_TEXT}}";

        // --- Append optional processing steps (code-mix, translation) ---
        var extras = new List<string>();
        if (options.CodeMix is { } mixType)
            extras.Add($"The input is in {mixType}. Transliterate any non-Roman script (such as Devanagari, Tamil, etc.) to Roman script. Keep English words as-is. Do not translate — preserve the original meaning in mixed form.");
        if (options.TargetLanguage is { } lang)
            extras.Add($"After refinement, translate the entire text to {lang}. Every word in the final output must be in {lang}.");
        if (extras.Count > 0)
            prompt += "\n\n## ADDITIONAL INSTRUCTIONS\n" + string.Join("\n", extras);

        // --- Prepend user's custom instructions if provided ---
        var trimmedCustom = options.CustomPrompt?.Trim() ?? "";
        if (trimmedCustom.Length > 0)
            prompt = trimmedCustom + "\n\n" + prompt;

        prompt = prompt.Replace("{{USER_DICTIONARY}}", vocabBlock);
        return prompt;
    }

    private async Task<string> SendChatCompletionAsync(
        HttpClient client, LlmProvider provider, string apiKey, string json, bool allowRetry)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, provider.ChatCompletionsUrl());
        request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {apiKey}");
        request.Content = new StringContent(json, Encoding.UTF8, "application/json");
        if (provider == LlmProvider.OpenRouter)
        {
            request.Headers.TryAddWithoutValidation("HTTP-Referer", "https://github.com/Vocallabsai/speechx");
            request.Headers.TryAddWithoutValidation("X-Title", "SpeechX");
        }

        int status;
        string data;
        try
        {
            (data, status) = await PerformAsync(client, request).ConfigureAwait(false);
        }
        catch (ApiException e) when (allowRetry && e.ErrorKind == ApiException.Kind.Network)
        {
            await Task.Delay(RetryDelay).ConfigureAwait(false);
            return await SendChatCompletionAsync(client, provider, apiKey, json, allowRetry: false).ConfigureAwait(false);
        }

        if (status < 200 || status >= 300)
        {
            Debug.WriteLine($"[llm] {provider.DisplayName()} /chat/completions HTTP {status}: {data}");
            if (allowRetry && (status == 429 || (status >= 500 && status < 600)))
            {
                await Task.Delay(RetryDelay).ConfigureAwait(false);
                return await SendChatCompletionAsync(client, provider, apiKey, json, allowRetry: false).ConfigureAwait(false);
            }
            throw ApiException.Http(status, data);
        }

        LlmChatResponse? root;
        try { root = JsonSerializer.Deserialize<LlmChatResponse>(data); }
        catch { throw ApiException.Decoding(); }
        var result = root?.Choices is { Count: > 0 } ch ? ch[0].Message?.Content : null;
        if (string.IsNullOrEmpty(result))
            throw ApiException.Decoding();

        return StripReasoning(result!);
    }

    /// <summary>
    /// Strip reasoning/thinking blocks some models emit inline. Handles &lt;think&gt;, &lt;thinking&gt;,
    /// and &lt;reasoning&gt; tags (case-insensitive). For an unbalanced opener, keep only text after
    /// the last opening tag.
    /// </summary>
    public static string StripReasoning(string text)
    {
        string[] tags = { "think", "thinking", "reasoning" };
        var output = text;
        foreach (var tag in tags)
        {
            var pattern = $"<\\s*{tag}\\s*>[\\s\\S]*?<\\s*/\\s*{tag}\\s*>";
            output = Regex.Replace(output, pattern, "", RegexOptions.IgnoreCase);

            var openPattern = $"<\\s*{tag}\\s*>";
            var matches = Regex.Matches(output, openPattern, RegexOptions.IgnoreCase);
            if (matches.Count > 0)
            {
                var last = matches[^1];
                output = output[(last.Index + last.Length)..];
            }
        }
        return output.Trim();
    }

    private static async Task<(string body, int status)> PerformAsync(HttpClient client, HttpRequestMessage request)
    {
        try
        {
            var response = await client.SendAsync(request).ConfigureAwait(false);
            var body = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
            return (body, (int)response.StatusCode);
        }
        catch (Exception e)
        {
            throw ApiException.Network(e.Message);
        }
    }

    // MARK: - Response DTOs

    private sealed class LlmModelsResponse
    {
        [JsonPropertyName("data")] public List<LlmModelEntry>? Data { get; set; }
    }

    private sealed class LlmModelEntry
    {
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("name")] public string? Name { get; set; }
    }

    private sealed class LlmChatResponse
    {
        [JsonPropertyName("choices")] public List<LlmChoice>? Choices { get; set; }
    }

    private sealed class LlmChoice
    {
        [JsonPropertyName("message")] public LlmMessage? Message { get; set; }
    }

    private sealed class LlmMessage
    {
        [JsonPropertyName("content")] public string? Content { get; set; }
    }
}
