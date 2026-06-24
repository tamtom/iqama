//
//  widgetBundle.swift
//  widget
//
//  Created by Omar Altamimi on 21/01/2026.
//

import WidgetKit
import SwiftUI

@main
struct PrayerWidgetBundle: WidgetBundle {
    var body: some Widget {
        PrayerWidget()
        #if os(iOS)
        // Lock Screen + Dynamic Island prayer countdown (iOS only).
        PrayerLiveActivity()
        #endif
    }
}
