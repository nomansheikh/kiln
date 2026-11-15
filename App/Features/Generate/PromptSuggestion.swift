/// A starter prompt offered under a composer while its canvas is empty.
struct PromptSuggestion: Identifiable {
    let title: String
    let prompt: String

    var id: String { title }

    static let all = [
        PromptSuggestion(
            title: "Misty alpine lake",
            prompt: "A misty alpine lake at dawn, pine forest reflected in still water, soft golden light, wide landscape photograph"
        ),
        PromptSuggestion(
            title: "Watercolour cafe",
            prompt: "A cosy corner cafe on a rainy evening, warm window light, loose watercolour illustration with soft edges"
        ),
        PromptSuggestion(
            title: "Neon city at night",
            prompt: "A rain-soaked city street at night, neon signs reflected in puddles, cinematic lighting, shallow depth of field"
        ),
        PromptSuggestion(
            title: "Fox portrait",
            prompt: "A studio portrait of a red fox, detailed fur, dramatic rim lighting, dark background, 85mm lens"
        ),
    ]

    /// Starters for the Speech screen: short texts worth hearing read aloud.
    static let speech = [
        PromptSuggestion(
            title: "Tell a short story",
            prompt: "The lighthouse keeper had a habit of counting ships. Every evening at six, he climbed the forty-two steps to the lamp room, poured a cup of tea, and wrote the number in a small green notebook."
        ),
        PromptSuggestion(
            title: "Welcome a caller",
            prompt: "Thanks for calling. Our opening hours are nine to five, Monday to Friday. Leave a message after the tone and we will call you back as soon as we can."
        ),
        PromptSuggestion(
            title: "Read a weather report",
            prompt: "Good morning. Today starts bright and cold, with light winds from the north. Cloud builds through the afternoon, and there is a chance of rain by evening."
        ),
        PromptSuggestion(
            title: "Open a podcast",
            prompt: "Hello and welcome back to the show. I'm your host, and today we are talking about small tools that do one thing well."
        ),
    ]
}
