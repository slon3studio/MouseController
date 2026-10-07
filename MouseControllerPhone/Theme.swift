import SwiftUI
import UIKit

enum Theme {
    static let background = Color(red: 0.043, green: 0.047, blue: 0.063)
    static let surface = Color(red: 0.106, green: 0.114, blue: 0.133)
    static let pad = Color(red: 0.082, green: 0.090, blue: 0.110)
    static let stroke = Color.white.opacity(0.08)
    static let accent = Color(red: 0.216, green: 0.541, blue: 0.867)
    static let success = Color(red: 0.388, green: 0.600, blue: 0.133)
    static let warning = Color(red: 0.937, green: 0.624, blue: 0.153)
    static let secondaryText = Color.white.opacity(0.55)
    static let mutedText = Color.white.opacity(0.32)

    static let accentUIColor = UIColor(red: 0.216, green: 0.541, blue: 0.867, alpha: 1)
}

enum Haptics {

    // Same key as the toggle in MousePadView's settings sheet.
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func click() { if isEnabled { light.impactOccurred() } }
    static func doubleClick() { if isEnabled { medium.impactOccurred() } }
    static func rightClick() { if isEnabled { rigid.impactOccurred() } }
    static func dragStart() { if isEnabled { medium.impactOccurred(intensity: 1) } }
    static func gesture() { if isEnabled { rigid.impactOccurred(intensity: 0.7) } }
    static func selection() { if isEnabled { selectionGenerator.selectionChanged() } }
}
