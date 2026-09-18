//
//  NotificationManager.swift
//  SmartHeat
//
//  Local Push Notification manager for pellet hopper alerts, stove alarms,
//  and ignition status changes.
//

import Foundation
import UserNotifications
import SwiftUI
import Combine

@MainActor
public class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationManager()
    
    // MARK: - AppStorage / Settings Keys
    private let lowPelletEnabledKey = "smartheat_notif_low_pellet"
    private let stoveErrorsEnabledKey = "smartheat_notif_stove_errors"
    private let ignitionFinishedEnabledKey = "smartheat_notif_ignition_finished"
    private let lowPelletThresholdKey = "smartheat_notif_low_pellet_threshold"
    
    @Published public var isAuthorized: Bool = false
    
    @Published public var lowPelletNotifications: Bool {
        didSet { UserDefaults.standard.set(lowPelletNotifications, forKey: lowPelletEnabledKey) }
    }
    @Published public var stoveErrorNotifications: Bool {
        didSet { UserDefaults.standard.set(stoveErrorNotifications, forKey: stoveErrorsEnabledKey) }
    }
    @Published public var ignitionFinishedNotifications: Bool {
        didSet { UserDefaults.standard.set(ignitionFinishedNotifications, forKey: ignitionFinishedEnabledKey) }
    }
    @Published public var lowPelletThresholdKg: Double {
        didSet { UserDefaults.standard.set(lowPelletThresholdKg, forKey: lowPelletThresholdKey) }
    }
    
    private var lastLowPelletAlertDate: Date = .distantPast
    private var lastErrorAlertCode: String = ""
    private var wasIgniting: Bool = false
    
    public override init() {
        self.lowPelletNotifications = UserDefaults.standard.object(forKey: lowPelletEnabledKey) as? Bool ?? true
        self.stoveErrorNotifications = UserDefaults.standard.object(forKey: stoveErrorsEnabledKey) as? Bool ?? true
        self.ignitionFinishedNotifications = UserDefaults.standard.object(forKey: ignitionFinishedEnabledKey) as? Bool ?? true
        self.lowPelletThresholdKg = UserDefaults.standard.object(forKey: lowPelletThresholdKey) as? Double ?? 4.0
        
        super.init()
        
        // Registriere Delegate, damit Benachrichtigungsbanner auch bei geöffneter App angezeigt werden!
        UNUserNotificationCenter.current().delegate = self
        checkAuthorization()
    }
    
    // MARK: - UNUserNotificationCenterDelegate (Foreground Presentation)
    /// Stellt sicher, dass Benachrichtigungen auch im Vordergrund als Banner und mit Ton erscheinen
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }
    
    public func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }
    }
    
    public func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        if settings.authorizationStatus == .denied {
            self.isAuthorized = false
            return false
        }
        
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            self.isAuthorized = true
            return true
        }
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            self.isAuthorized = granted
            return granted
        } catch {
            print("Notification permission error: \(error.localizedDescription)")
            self.isAuthorized = false
            return false
        }
    }
    
    // MARK: - Notification Dispatchers
    
    public func checkPelletLevel(currentKg: Double, remainingHours: Double) {
        guard lowPelletNotifications, isAuthorized else { return }
        guard currentKg <= lowPelletThresholdKg else { return }
        
        let now = Date()
        // Alert at most once every 3 hours for low pellets
        guard now.timeIntervalSince(lastLowPelletAlertDate) > 10800 else { return }
        lastLowPelletAlertDate = now
        
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Pellet-Vorrat fast erschöpft"
        content.body = String(format: "Nur noch %.1f kg Pellets im Tank (ca. %.1f Std. Restlaufzeit). Bitte bald nachfüllen!", currentKg, remainingHours)
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "smartheat.low_pellets.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    public func checkStoveError(errorCode: String, errorTitle: String, solution: String) {
        guard stoveErrorNotifications, isAuthorized else { return }
        guard !errorCode.isEmpty, errorCode != lastErrorAlertCode else { return }
        lastErrorAlertCode = errorCode
        
        let content = UNMutableNotificationContent()
        content.title = "🚨 Ofen-Störung: \(errorTitle)"
        content.body = "\(errorCode): \(solution)"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "smartheat.alarm.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    public func checkIgnitionStatus(operationalStateTitle: String, isNowHeating: Bool) {
        guard ignitionFinishedNotifications, isAuthorized else { return }
        
        if !wasIgniting && operationalStateTitle.contains("Zündung") {
            wasIgniting = true
        } else if wasIgniting && isNowHeating {
            wasIgniting = false
            
            let content = UNMutableNotificationContent()
            content.title = "🔥 Pelletofen ist betriebsbereit"
            content.body = "Die Zündphase wurde erfolgreich beendet. Der Ofen heizt jetzt stabil."
            content.sound = .default
            
            let request = UNNotificationRequest(identifier: "smartheat.ignition_done.\(UUID().uuidString)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    public func sendTestNotification(completion: ((Bool) -> Void)? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "🔥 SmartHeat Test-Mitteilung"
        content.body = "Mitteilungen sind aktiv! Du erhältst Benachrichtigungen bei Störungen und niedrigem Pelletstand."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "smartheat.test.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Test notification error: \(error.localizedDescription)")
                    completion?(false)
                } else {
                    print("Test notification successfully registered")
                    completion?(true)
                }
            }
        }
    }
}
