import SwiftUI

enum NotchAnimator {
    // Shape expand: slightly elastic, feels alive
    static let expand = Animation.spring(
        response: Constants.Animation.expandResponse,
        dampingFraction: Constants.Animation.expandDamping
    )

    // Shape collapse: quick, decisive
    static let collapse = Animation.spring(
        response: Constants.Animation.collapseResponse,
        dampingFraction: Constants.Animation.collapseDamping
    )

    // Content fade timings
    static let contentReveal = Animation.easeOut(duration: 0.20)   // fade-in on expand
    static let contentHide   = Animation.easeIn(duration: 0.10)    // fade-out on collapse

    // Widget tab switch
    static let widgetSwitch  = Animation.easeInOut(duration: 0.20)

    // Media progress bar
    static let progressUpdate = Animation.linear(duration: 1.0)
}
