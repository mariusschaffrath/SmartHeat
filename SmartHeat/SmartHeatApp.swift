//
//  SmartHeatApp.swift
//  SmartHeat
//
//  Created by Marius Schaffrath on 20.03.26.
//

import SwiftUI

@main
struct SmartHeatApp: App {
    @AppStorage("app_appearance_mode") private var appearanceMode: String = "dark"
    
    init() {
        // Registriere NotificationManager als UNUserNotificationCenter Delegate für Banneranzeige im Vordergrund
        _ = NotificationManager.shared
    }
    
    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "dark": return .dark
        case "light": return .light
        default: return nil // Automatisch / System
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(preferredColorScheme)
        }
    }
}
