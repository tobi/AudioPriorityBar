import Foundation

/// Represents an action that can be triggered by clicking the menu bar icon
enum ClickAction: String, Codable, CaseIterable {
    case toggle = "Toggle Mode"
    case menu = "Show Menu"
    case noAction = "No Action"

    var displayName: String { self.rawValue }
}

/// Configuration for click actions on the menu bar icon
struct ClickActionsConfig: Codable {
    var leftClick: ClickAction
    var rightClick: ClickAction
    var longLeftClick: ClickAction
    var longRightClick: ClickAction

    /// Default configuration: left and right click show menu, long presses do nothing
    static var `default`: ClickActionsConfig {
        ClickActionsConfig(
            leftClick: .menu,
            rightClick: .menu,
            longLeftClick: .noAction,
            longRightClick: .noAction
        )
    }

    /// Validates that at least one action is set to show menu
    var isValid: Bool {
        leftClick == .menu || rightClick == .menu ||
        longLeftClick == .menu || longRightClick == .menu
    }
}
