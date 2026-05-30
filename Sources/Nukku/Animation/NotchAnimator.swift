import SwiftUI

enum NotchAnimator {
    static let expandSpring = Animation.spring(
        response: Constants.Animation.expandResponse,
        dampingFraction: Constants.Animation.expandDamping,
        blendDuration: 0
    )

    static let collapseSpring = Animation.spring(
        response: Constants.Animation.collapseResponse,
        dampingFraction: Constants.Animation.collapseDamping,
        blendDuration: 0
    )

    static let widgetSwitch = Animation.easeInOut(duration: 0.2)
    static let progressUpdate = Animation.linear(duration: 1.0)
}
