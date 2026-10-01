//
//  AppInfo.swift
//  Eyes Out
//
//  Naming, versioning and the safety text. The display name lives here as a
//  single constant so the app can be renamed without touching anything else.
//

import Foundation

enum AppInfo {

    /// Shown throughout the UI. Change this one line to rename the app; the
    /// Xcode target name and bundle identifier are independent of it.
    static let displayName = "Eyes Out"

    static var versionString: String {
        let bundle = Bundle.main.infoDictionary
        let version = bundle?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = bundle?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Safety text
    //
    // The wording is deliberately about SCOPE rather than blanket exclusion.
    // Under the Consumer Rights Act 2015 and UCTA 1977 a term purporting to
    // exclude liability for death or personal injury caused by negligence is
    // void, so "we are not liable for anything" buys nothing. What does help is
    // describing accurately and prominently what the app can and cannot see, so
    // that not showing an invisible aircraft is the product working as
    // described rather than failing.

    static let oneLineDisclaimer =
        "Supplement to lookout — not all aircraft are visible to this app."

    static let primaryWarning = """
    This app is an aid to lookout. It is not a collision avoidance system, not \
    an anti-collision system, and not a navigation system.

    It shows only aircraft that your connected receiver reports to it. Many \
    aircraft cannot be seen by it at all. You must continue to maintain a full \
    visual lookout at all times and comply with the Rules of the Air.

    A blank or green screen does NOT mean the airspace around you is empty.
    """

    static let whatItCannotSee = [
        "Aircraft with no ADS-B Out — most of the UK GA fleet transmits Mode S only, which this app cannot receive.",
        "Aircraft with no electronic conspicuity at all — many gliders, microlights, balloons, paragliders and vintage aircraft.",
        "Gliders and others using FLARM, unless your receiver is FLARM-equipped, configured and licensed.",
        "Drones, military aircraft operating without conspicuity, and anything with its transponder switched off.",
        "Any aircraft while your receiver has no power, no GPS fix, or a poor aerial position in the cockpit.",
        "Aircraft outside the range, altitude band or target limits configured in this app.",
    ]

    static let howToUse = [
        "Mount the phone where you can see it in peripheral vision without it obstructing your view outside.",
        "Green means nothing is within the display range. It does not mean clear.",
        "Amber means traffic is inside the caution ring. Look for it visually.",
        "Red and flashing means traffic is close, or is converging on a collision bearing.",
        "An arrow points towards the aircraft; its tail grows towards the centre as the aircraft gets closer.",
        "A pulsing ring means an aircraft at that distance whose direction is not known — look all round.",
        "CBDR means constant bearing, decreasing range: the aircraft is on a collision course and will not appear to move in your windscreen.",
    ]

    // MARK: - iPad windowing
    //
    // Worth spelling out in the app: iPadOS 26 folded Split View and Slide Over
    // into the windowing system, so a pilot left in Full Screen Apps mode simply
    // cannot put two apps on screen and will reasonably conclude this app is
    // broken rather than that a system setting needs changing.

    static let iPadWindowingSteps = [
        "Open Settings › Multitasking & Gestures and choose Windowed Apps.",
        "Open your navigation app and leave it full screen.",
        "Open \(displayName), then drag inward from any corner to shrink it into a window.",
        "Drag it to a corner clear of your map controls. It stays where you put it.",
    ]

    static let iPadWindowingNote = """
    In Full Screen Apps mode iPadOS shows one app at a time and nothing else: \
    Split View and Slide Over no longer exist separately, having been folded \
    into the windowing system. Windowed Apps or Stage Manager is therefore \
    required to see \(displayName) and your navigation app together.

    Turning it on changes nothing else. Apps still open full screen; you only \
    see a difference when you deliberately shrink one.
    """

    static let iPadWindowingFooter = """
    In a small window the controls are hidden to leave room for the display. \
    Widen the window to change the traffic source or reach diagnostics.
    """

    static let relationshipToOtherApps = """
    \(displayName) is a supplement to your navigation software, not a \
    substitute for it. It does not show maps, airspace, terrain, NOTAMs or \
    routing, and it must not be used for navigation.

    Continue to use SkyDemon, ForeFlight or your usual electronic flight bag \
    for navigation and airspace awareness. \(displayName) is designed to sit \
    alongside them, showing one thing — nearby traffic — in a form you can read \
    in a glance.

    Both can receive from the same SkyEcho at the same time; they do not conflict.
    """
}
