#!/usr/bin/env swift
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

setlinebuf(stdout)

let questions: [(Int, String)] = [
    (1,   "How do I change my dictation shortcut?"),
    (2,   "What's the difference between toggle recording and push to talk?"),
    (3,   "Why does my hotkey sometimes produce a weird character like ≤?"),
    (5,   "Which AI provider should I use for cleanup?"),
    (10,  "Can I record for two hours straight?"),
    (101, "Okay so umm I've been using Jot for a bit and I want to — I'm not sure how this works exactly but basically what I want to do is I want to change the shortcut for starting dictation because ⌥Space actually conflicts with something on my Mac and I need it to be something else, so like, what's the procedure, where in the app do I go to do that?"),
    (102, "Hey so I've been trying to figure out the right way to use Jot and there are these two modes right, toggle and push-to-talk or whatever, and I'm getting a bit confused about when to use each one — like what actually is the difference between them, how do they behave, what's the intended use case for each, can you walk me through it?"),
    (103, "So this is weird, I don't know if this is a bug or what, but sometimes when I hit my hotkey — I mean the one I set up for dictation — it doesn't actually start recording. Instead, like, a weird character shows up in whatever I'm typing in, I think it's been ≤ and also ÷ sometimes. Do you know what's going on? How do I fix this?"),
    (105, "Hey so I'm trying to set up the cleanup feature — I guess it's the LLM post-processing step — and there are a bunch of provider options. I see Apple Intelligence is there, also OpenAI, Anthropic, Gemini, and Ollama. I care about privacy and I don't really want to pay anything. Which one should I pick? Like what would you actually recommend for my situation?"),
    (110, "So I was thinking about using Jot for a much longer session — like, I have this lecture that's about two hours long and I want to record and transcribe the whole thing end-to-end without stopping. Is that something Jot can actually handle? Like is there a hard limit I should be aware of? What happens if I go really long, does quality degrade or does it just stop working or what?"),
]

if #available(macOS 26.4, *) {
    let sem = DispatchSemaphore(value: 0)
    Task {
        for (id, q) in questions {
            let t = (try? await SystemLanguageModel.default.tokenCount(for: q)) ?? -1
            print("q\(id)  \(t) tokens   \(q.prefix(80))")
        }
        sem.signal()
    }
    sem.wait()
}
