import MailKit

// MEExtension is UI-actor isolated in the SDK, but MailKit creates and calls the principal object
// on an XPC queue, so main-actor inference would trap at runtime.
nonisolated final class MailExtension: NSObject, MEExtension {
    func handlerForMessageActions() -> MEMessageActionHandler {
        MessageActionHandler.shared
    }
}
