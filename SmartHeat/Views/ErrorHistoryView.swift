//
//  ErrorHistoryView.swift
//  SmartHeat
//
//  Timestamped error history list with diagnostic details and troubleshooting steps.
//

import SwiftUI

struct ErrorHistoryView: View {
    @ObservedObject var errorManager = StoveErrorLogManager.shared
    @ObservedObject var viewModel: StoveViewModel
    @State private var showingUnlockConfirmation = false
    @Environment(\.dismiss) private var dismiss
    
    init(viewModel: StoveViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            
            if errorManager.errorLog.isEmpty && !viewModel.isStoveLockedByAlarm {
                emptyStateView
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Active Alarm Card (if stove is currently locked)
                        if viewModel.isStoveLockedByAlarm {
                            activeAlarmCard
                        }
                        
                        // Header Summary Banner
                        statusSummaryBanner
                        
                        // List of Log Entries
                        ForEach(errorManager.errorLog) { entry in
                            errorCard(entry)
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle("Fehler- & Alarmhistorie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .none, action: { errorManager.resolveAll() }) {
                        Label("Alle als behoben markieren", systemImage: "checkmark.circle")
                    }
                    Button(role: .destructive, action: { errorManager.clearHistory() }) {
                        Label("Historie leeren", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Keine Fehler registriert")
                .font(.title2.bold())
            
            Text("Der Pelletofen läuft einwandfrei und ohne ungelöste Alarme.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }
    
    private var statusSummaryBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: errorManager.unresolvedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.title2)
                .foregroundColor(errorManager.unresolvedCount > 0 ? .red : .green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(errorManager.unresolvedCount > 0 ? "\(errorManager.unresolvedCount) aktive Störung(en)" : "Systemstatus Normal")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text(errorManager.unresolvedCount > 0 ? "Handlungsbedarf erforderlich" : "Alle vergangenen Meldungen sind behoben")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .liquidGlass(
            cornerRadius: 20,
            tint: errorManager.unresolvedCount > 0 ? .red : .green,
            tintOpacity: 0.08,
            specularOpacity: 0.5
        )
    }
    
    private func errorCard(_ entry: StoveErrorLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    Image(systemName: entry.severity.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(entry.severity.color)
                    
                    Text(entry.code)
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundColor(entry.severity.color)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 9)
                .background(entry.severity.color.opacity(0.14), in: Capsule())
                
                Spacer()
                
                // Timestamp
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if entry.isResolved {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                            Text("Behoben")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                    } else {
                        Text("Offen")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
            }
            
            Text(entry.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Text(entry.detail)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            
            // Troubleshooting recommendation box
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Empfohlene Lösung:")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                }
                
                Text(entry.solution)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .padding(10)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            
            if !entry.isResolved {
                Button(action: {
                    errorManager.markResolved(id: entry.id)
                }) {
                    HStack {
                        Spacer()
                        Label("Als behoben markieren", systemImage: "checkmark")
                            .font(.caption.bold())
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .background(Color.green.opacity(0.12))
                    .foregroundColor(.green)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .liquidGlass(
            cornerRadius: 22,
            tint: entry.severity.color,
            tintOpacity: entry.isResolved ? 0.03 : 0.08,
            specularOpacity: entry.isResolved ? 0.3 : 0.6
        )
    }
    
    @ViewBuilder
    private var activeAlarmCard: some View {
        let alarm = viewModel.activeHardwareAlarm
        let codeText = alarm?.codeString ?? (viewModel.stoveErrorCode > 0 ? String(format: "Er%02d", viewModel.stoveErrorCode) : "ALARM")
        let titleText = alarm?.title ?? "Ofen verriegelt (Sicherheitsabschaltung)"
        let descText = alarm?.description ?? "Die Ofenplatine hat den Betrieb aus Sicherheitsgründen gestoppt."
        let remedyText = alarm?.remedy ?? "Brennkammer kontrollieren und Störung quittieren."
        
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.red)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(codeText)
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                        
                        Text(titleText)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                    
                    Text(descText)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // Remedy box
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                    Text("Empfohlene Behebung:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                }
                
                Text(remedyText)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            
            // Unlock action button
            Button {
                showingUnlockConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isUnlocking {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "lock.open.trianglebadge.exclamationmark.fill")
                            .font(.system(size: 15, weight: .bold))
                    }
                    
                    Text(viewModel.isUnlocking ? "Wird entsperrt..." : "Störung quittieren & Ofen entsperren")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.red, Color.red.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .foregroundColor(.white)
                .shadow(color: Color.red.opacity(0.4), radius: 8, y: 3)
            }
            .disabled(viewModel.isUnlocking)
        }
        .padding(18)
        .liquidGlass(
            cornerRadius: 24,
            tint: .red,
            tintOpacity: 0.12,
            specularOpacity: 0.7
        )
        .confirmationDialog(
            "Ofen entsperren?",
            isPresented: $showingUnlockConfirmation,
            titleVisibility: .visible
        ) {
            Button("Störung quittieren & Entsperren", role: .none) {
                Task {
                    await viewModel.unlockStoveAlarm()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Bist du sicher, dass die Ursache (z. B. Pellets nachgefüllt, Brennertopf gereinigt) behoben ist?\n\nDer Alarm wird auf der Ofenplatine quittiert und die Blockierung aufgehoben. Der Ofen wird dabei NICHT gezündet.")
        }
    }
}
