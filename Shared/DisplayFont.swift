//
//  DisplayFont.swift
//  Shared between Eyes Out (iOS) and the watch app
//
//  One face for everything on the traffic display, so the phone and the watch
//  read the same way.
//
//  SF Pro at heavy weight, standard width, with the letters tracked apart.
//
//  Not SF Rounded: soft terminals look friendly, which is the wrong register
//  for something whose job is to tell a pilot an aircraft is about to cross
//  their nose. Not condensed either, which was the first attempt — condensed
//  black is sharp but dense, and the strokes crowd into each other when read
//  from the corner of the eye. Weight plus air between the letters is how
//  cockpit annunciators are set, and it survives a glance far better.
//
//  Kept in one place because display type is the sort of thing that gets
//  revisited, and sixteen scattered font literals do not revise well.
//

import SwiftUI

extension Font {

    /// The headline state word: CLEAR, CAUTION, CLOSE TRAFFIC.
    /// Pair with `.tracking(Font.annunciatorTracking(size))`.
    static func annunciator(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .default).width(.standard)
    }

    /// Letter spacing to go with it, scaled so it looks the same at any size.
    static func annunciatorTracking(_ size: CGFloat) -> CGFloat {
        size * 0.042
    }

    /// Supporting text — ranges, heights, source badges.
    static func annunciatorDetail(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default).width(.standard)
    }

    /// Figures drawn beside the arrows. Untracked: digits are read as a group
    /// rather than scanned letter by letter, and spacing them out would make
    /// "+04" read as three separate things.
    static func trafficLabel(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default).width(.standard)
    }
}
