import SwiftUI

extension Binding where Value == Bool {
    /// A binding that is true while the optional message holds a value.
    /// Setting it to false clears the message.
    @MainActor
    init(isPresenting message: Binding<String?>) {
        self.init(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )
    }
}
