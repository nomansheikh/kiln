/// A starter prompt offered under the composer while the canvas is empty.
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
}
