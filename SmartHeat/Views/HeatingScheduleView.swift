//
//  HeatingScheduleView.swift
//  SmartHeat
//
//  Dedicated Heating Schedules & Timetable View with Apple Liquid Glass styling.
//

import SwiftUI

struct HeatingScheduleView: View {
    @ObservedObject var scheduleManager = HeatingScheduleManager.shared
    @ObservedObject var chronoService = HardwareChronoService.shared
    @ObservedObject var viewModel: StoveViewModel
    
    @State private var selectedPlanType: Int = 0 // 0 = Platinen-Chrono (Autark), 1 = App-SmartPlan
    @State private var selectedHardwareDayId: Int = 1 // 1=Mo .. 7=So
    @State private var selectedDayId: Int = 1
    @State private var showingAddSlotSheet: Bool = false
    @State private var newSlotName: String = "Heizintervall"
    @State private var newSlotStartHour: Int = 6
    @State private var newSlotStartMin: Int = 0
    @State private var newSlotEndHour: Int = 9
    @State private var newSlotEndMin: Int = 0
    @State private var newSlotTemp: Double = 22.0
    
    init(viewModel: StoveViewModel) {
        self.viewModel = viewModel
    }
    
    private var selectedDay: DaySchedule? {
        scheduleManager.weeklySchedule.first(where: { $0.id == selectedDayId })
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                
                // Ambient warm lighting
                RadialGradient(
                    gradient: Gradient(colors: [
                        (selectedPlanType == 0 ? chronoService.chronoPlan.isGloballyEnabled : scheduleManager.isScheduleActive) ? Color.orange.opacity(0.12) : Color.blue.opacity(0.06),
                        .clear
                    ]),
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 500
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Plan Type Segmented Picker (Platinen-Chrono vs App-SmartPlan)
                        Picker("Heizplan-Art", selection: $selectedPlanType) {
                            Text("⚡ Platinen-Chrono").tag(0)
                            Text("📱 App-SmartPlan").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 2)
                        
                        if selectedPlanType == 0 {
                            // MARK: - Hardware Chrono (TiEmme EEPROM)
                            hardwareMasterCard
                            hardwareSyncActionBar
                            hardwareDaySelectorRow
                            hardwareDaySlotsCard
                        } else {
                            // MARK: - App-SmartPlan (Software Engine)
                            // 1. Master Activation & Status Card
                            masterScheduleCard
                            
                            // 2. Quick Override / Boost Card
                            quickOverrideCard
                            
                            // 3. Day of Week Segmented Selector
                            daySelectorRow
                            
                            // 4. Slots for Selected Day
                            daySlotsCard
                            
                            // 5. Presets Card
                            presetsCard
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Heizpläne")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingAddSlotSheet) {
                addSlotSheet
            }
        }
    }
    
    // MARK: - Master Schedule Card
    private var masterScheduleCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: scheduleManager.isScheduleActive ? "calendar.badge.clock" : "calendar")
                        .font(.title2)
                        .foregroundColor(scheduleManager.isScheduleActive ? .orange : .secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatischer Heizplan")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text(scheduleManager.isScheduleActive ? "Aktiviert: Regelt Ofen nach Zeitplan" : "Pausiert: Manuelle Steuerung aktiv")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Toggle("", isOn: $scheduleManager.isScheduleActive)
                    .labelsHidden()
                    .tint(.orange)
            }
            
            if scheduleManager.isScheduleActive {
                Divider().opacity(0.4)
                
                HStack {
                    if let target = scheduleManager.getCurrentTargetTemperature() {
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("Aktueller Sollwert:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f °C", target))
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "moon.stars.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text(String(format: "Nacht: %.1f°C", scheduleManager.defaultNightTemp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .liquidGlass(
            cornerRadius: 22,
            tint: scheduleManager.isScheduleActive ? .orange : .clear,
            tintOpacity: 0.08,
            specularOpacity: 0.5
        )
    }
    
    // MARK: - Quick Boost Card
    private var quickOverrideCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Schnell-Steuerung", systemImage: "bolt.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
                
                Spacer()
                
                if scheduleManager.overrideUntil != nil {
                    Button("Zurücksetzen") {
                        scheduleManager.cancelOverride()
                    }
                    .font(.caption.bold())
                    .foregroundColor(.red)
                }
            }
            
            if let until = scheduleManager.overrideUntil, let temp = scheduleManager.overrideTargetTemp {
                HStack {
                    Text(String(format: "Boost aktiv: %.1f °C bis %@", temp, until.formatted(date: .omitted, time: .shortened)))
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            } else {
                HStack(spacing: 10) {
                    Button(action: {
                        scheduleManager.activateBoost(temp: 23.0, durationHours: 2.0)
                    }) {
                        HStack {
                            Image(systemName: "flame.fill")
                            Text("+2h Boost (23°C)")
                        }
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.12))
                        .foregroundColor(.orange)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        scheduleManager.activateBoost(temp: 18.5, durationHours: 4.0)
                    }) {
                        HStack {
                            Image(systemName: "moon.fill")
                            Text("Nachtmodus (18.5°C)")
                        }
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 18, tint: .orange, tintOpacity: 0.04, specularOpacity: 0.35)
    }
    
    // MARK: - Day Selector Row
    private var daySelectorRow: some View {
        HStack(spacing: 8) {
            ForEach(scheduleManager.weeklySchedule) { day in
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        selectedDayId = day.id
                    }
                }) {
                    VStack(spacing: 4) {
                        Text(day.shortName)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        
                        Circle()
                            .fill(day.slots.contains(where: { $0.isEnabled }) ? Color.orange : Color.gray.opacity(0.3))
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedDayId == day.id ?
                        Color.orange :
                        Color.white.opacity(0.06)
                    )
                    .foregroundColor(selectedDayId == day.id ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(selectedDayId == day.id ? 0.4 : 0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Day Slots Card
    private var daySlotsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDay?.name ?? "Wochentag")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("\(selectedDay?.slots.count ?? 0) aktive(s) Zeitintervall(e)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showingAddSlotSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Hinzufügen")
                    }
                    .font(.caption.bold())
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }
            
            if let day = selectedDay, !day.slots.isEmpty {
                VStack(spacing: 10) {
                    ForEach(day.slots) { slot in
                        slotRow(slot: slot, dayId: day.id)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "moon.stars")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Keine Heizintervalle für diesen Tag hinterlegt.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Der Ofen hält die Standard-Nachttemperatur von \(String(format: "%.1f", scheduleManager.defaultNightTemp))°C.")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 22, tint: .clear, tintOpacity: 0.05, specularOpacity: 0.45)
    }
    
    private func slotRow(slot: HeatingTimeSlot, dayId: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(slot.name)
                    .font(.subheadline.bold())
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(slot.timeRangeString)
                        .font(.caption.monospacedDigit())
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text(String(format: "%.1f°C", slot.targetTemp))
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.14), in: Capsule())
            
            Button(action: {
                deleteSlot(slotId: slot.id, dayId: dayId)
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.7))
                    .padding(6)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }
    
    // MARK: - Presets Card
    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vorkonfigurierte Vorlagen")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            
            HStack(spacing: 10) {
                Button(action: {
                    withAnimation(.spring()) {
                        scheduleManager.applyComfortPreset()
                    }
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Komfort", systemImage: "sparkles")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                        Text("Mo-Fr Aufheizung, Sa-So durchgehend")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    withAnimation(.spring()) {
                        scheduleManager.applyEcoPreset()
                    }
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Eco / Sparsam", systemImage: "leaf.fill")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                        Text("Nur Abends, sonst Absenkung")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 18, tint: .clear, tintOpacity: 0.05, specularOpacity: 0.3)
    }
    
    // MARK: - Add Slot Sheet
    private var addSlotSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Bezeichnung")) {
                    TextField("z.B. Morgenaufheizung", text: $newSlotName)
                }
                
                Section(header: Text("Startzeit")) {
                    Stepper("Stunde: \(String(format: "%02d", newSlotStartHour))", value: $newSlotStartHour, in: 0...23)
                    Stepper("Minute: \(String(format: "%02d", newSlotStartMin))", value: $newSlotStartMin, in: 0...55, step: 15)
                }
                
                Section(header: Text("Endzeit")) {
                    Stepper("Stunde: \(String(format: "%02d", newSlotEndHour))", value: $newSlotEndHour, in: 0...23)
                    Stepper("Minute: \(String(format: "%02d", newSlotEndMin))", value: $newSlotEndMin, in: 0...55, step: 15)
                }
                
                Section(header: Text("Zieltemperatur")) {
                    HStack {
                        Text("\(String(format: "%.1f", newSlotTemp)) °C")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Spacer()
                        Stepper("", value: $newSlotTemp, in: 16.0...26.0, step: 0.5)
                            .labelsHidden()
                    }
                }
            }
            .navigationTitle("Heizintervall anlegen")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") { showingAddSlotSheet = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Speichern") {
                        saveNewSlot()
                        showingAddSlotSheet = false
                    }
                    .bold()
                }
            }
        }
    }
    
    private func saveNewSlot() {
        guard let idx = scheduleManager.weeklySchedule.firstIndex(where: { $0.id == selectedDayId }) else { return }
        let newSlot = HeatingTimeSlot(
            name: newSlotName.isEmpty ? "Heizen" : newSlotName,
            startHour: newSlotStartHour,
            startMinute: newSlotStartMin,
            endHour: newSlotEndHour,
            endMinute: newSlotEndMin,
            targetTemp: newSlotTemp
        )
        scheduleManager.weeklySchedule[idx].slots.append(newSlot)
        scheduleManager.saveSchedule()
    }
    
    private func deleteSlot(slotId: UUID, dayId: Int) {
        guard let idx = scheduleManager.weeklySchedule.firstIndex(where: { $0.id == dayId }) else { return }
        scheduleManager.weeklySchedule[idx].slots.removeAll(where: { $0.id == slotId })
        scheduleManager.saveSchedule()
    }
    
    // MARK: - Hardware Chrono Components (TiEmme EEPROM)
    
    private var selectedHardwareDayIndex: Int {
        chronoService.chronoPlan.days.firstIndex(where: { $0.id == selectedHardwareDayId }) ?? 0
    }
    
    private var selectedHardwareDay: HardwareChronoDay {
        if chronoService.chronoPlan.days.indices.contains(selectedHardwareDayIndex) {
            return chronoService.chronoPlan.days[selectedHardwareDayIndex]
        }
        return HardwareChronoDay.defaultDays().first!
    }
    
    private var globalEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { chronoService.chronoPlan.isGloballyEnabled },
            set: { newVal in
                chronoService.chronoPlan.isGloballyEnabled = newVal
                chronoService.saveToCache()
                Task {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    _ = try? await chronoService.toggleGlobalEnable(enabled: newVal)
                }
            }
        )
    }
    
    private var modeBinding: Binding<HardwareChronoMode> {
        Binding<HardwareChronoMode>(
            get: { chronoService.chronoPlan.mode },
            set: { newMode in
                chronoService.chronoPlan.mode = newMode
                if newMode == .off {
                    chronoService.chronoPlan.isGloballyEnabled = false
                } else {
                    chronoService.chronoPlan.isGloballyEnabled = true
                }
                chronoService.saveToCache()
            }
        )
    }
    
    private func timeBinding(slotIndex: Int, isStart: Bool) -> Binding<Date> {
        Binding<Date>(
            get: {
                let dayIdx = selectedHardwareDayIndex
                guard chronoService.chronoPlan.days.indices.contains(dayIdx),
                      chronoService.chronoPlan.days[dayIdx].slots.indices.contains(slotIndex) else {
                    return Date()
                }
                let timeStr = isStart ?
                    chronoService.chronoPlan.days[dayIdx].slots[slotIndex].startTime :
                    chronoService.chronoPlan.days[dayIdx].slots[slotIndex].endTime
                
                let parts = timeStr.split(separator: ":").compactMap { Int($0) }
                let h = parts.first ?? 0
                let m = parts.count > 1 ? parts[1] : 0
                
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = h
                comps.minute = m
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let dayIdx = selectedHardwareDayIndex
                guard chronoService.chronoPlan.days.indices.contains(dayIdx),
                      chronoService.chronoPlan.days[dayIdx].slots.indices.contains(slotIndex) else {
                    return
                }
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                let str = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
                if isStart {
                    chronoService.chronoPlan.days[dayIdx].slots[slotIndex].startTime = str
                } else {
                    chronoService.chronoPlan.days[dayIdx].slots[slotIndex].endTime = str
                }
                chronoService.saveToCache()
            }
        )
    }
    
    private func slotEnabledBinding(slotIndex: Int) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                let dayIdx = selectedHardwareDayIndex
                guard chronoService.chronoPlan.days.indices.contains(dayIdx),
                      chronoService.chronoPlan.days[dayIdx].slots.indices.contains(slotIndex) else {
                    return false
                }
                return chronoService.chronoPlan.days[dayIdx].slots[slotIndex].isEnabled
            },
            set: { newVal in
                let dayIdx = selectedHardwareDayIndex
                guard chronoService.chronoPlan.days.indices.contains(dayIdx),
                      chronoService.chronoPlan.days[dayIdx].slots.indices.contains(slotIndex) else {
                    return
                }
                chronoService.chronoPlan.days[dayIdx].slots[slotIndex].isEnabled = newVal
                chronoService.saveToCache()
            }
        )
    }
    
    private var hardwareMasterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: chronoService.chronoPlan.isGloballyEnabled ? "bolt.badge.clock.fill" : "bolt.badge.clock")
                        .font(.title2)
                        .foregroundColor(chronoService.chronoPlan.isGloballyEnabled ? .orange : .secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Platinen-Chrono (Autark)")
                            .font(.headline.bold())
                        Text(chronoService.chronoPlan.isGloballyEnabled ? "Aktiv: Ofen schaltet selbstständig" : "Deaktiviert: Manuelle Ofenführung")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Toggle("", isOn: globalEnabledBinding)
                    .labelsHidden()
                    .tint(.orange)
            }
            
            Divider().opacity(0.3)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("PROGRAMM-MODUS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.0)
                    .foregroundColor(.secondary)
                
                Picker("Programm-Modus", selection: modeBinding) {
                    Text("Täglich").tag(HardwareChronoMode.daily)
                    Text("Woche").tag(HardwareChronoMode.weekly)
                    Text("Wochenende").tag(HardwareChronoMode.weekend)
                }
                .pickerStyle(.segmented)
                
                Text(modeExplanationText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            
            // Notice box
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "cpu")
                    .font(.caption.bold())
                    .foregroundColor(.orange)
                Text("Gespeichert direkt im EEPROM der TiEmme-Platine. Der Ofen zündet und stoppt auch ohne iPhone, WLAN oder Cloud zu den programmierten Zeiten.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .liquidGlass(
            cornerRadius: 22,
            tint: chronoService.chronoPlan.isGloballyEnabled ? .orange : .clear,
            tintOpacity: 0.08,
            specularOpacity: 0.5
        )
    }
    
    private var modeExplanationText: String {
        switch chronoService.chronoPlan.mode {
        case .off:
            return "Chrono ist ausgeschaltet."
        case .daily:
            return "Tagesprogramm: Jeder Tag von Mo–So hat separate individuelle Schaltzeiten."
        case .weekly:
            return "Wochenprogramm: Alle 7 Tage laufen mit demselben Zeitplan."
        case .weekend:
            return "Werktags / Wochenende: Mo–Fr für Arbeitstage, Sa–So für Wochenende."
        }
    }
    
    private var hardwareSyncActionBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Save Button
                Button {
                    Task {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        do {
                            let ok = try await chronoService.saveToStove(plan: chronoService.chronoPlan)
                            if ok {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }
                        } catch {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if chronoService.isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                        }
                        Text(chronoService.isSaving ? "Wird übertragen..." : "Auf Platine speichern")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundColor(.white)
                    .shadow(color: Color.orange.opacity(0.3), radius: 6, y: 2)
                }
                .disabled(chronoService.isSaving || chronoService.isSyncing)
                .buttonStyle(.plain)
                
                // Fetch Button
                Button {
                    Task {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        do {
                            _ = try await chronoService.fetchFromStove()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } catch {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if chronoService.isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                        Text(chronoService.isSyncing ? "Lädt..." : "Neu laden")
                    }
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundColor(.primary)
                }
                .disabled(chronoService.isSaving || chronoService.isSyncing)
                .buttonStyle(.plain)
            }
            
            // Status/Success message
            if chronoService.saveSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Erfolgreich im TiEmme-EEPROM gespeichert!")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
                .transition(.opacity)
            } else if let err = chronoService.activeError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            } else if let lastSync = chronoService.lastSyncDate {
                HStack(spacing: 4) {
                    Text("Zuletzt synchronisiert: \(lastSync.formatted(date: .omitted, time: .standard))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var hardwareDaySelectorRow: some View {
        HStack(spacing: 8) {
            ForEach(chronoService.chronoPlan.days) { day in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        selectedHardwareDayId = day.id
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(day.shortName)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        
                        Circle()
                            .fill(day.slots.contains(where: { $0.isEnabled }) ? Color.orange : Color.gray.opacity(0.3))
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedHardwareDayId == day.id ?
                        Color.orange :
                        Color.white.opacity(0.06)
                    )
                    .foregroundColor(selectedHardwareDayId == day.id ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(selectedHardwareDayId == day.id ? 0.4 : 0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var hardwareDaySlotsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedHardwareDay.name)
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("3 Platinen-Schaltfenster")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                let activeCount = selectedHardwareDay.slots.filter { $0.isEnabled }.count
                Text("\(activeCount) aktiv")
                    .font(.caption.bold())
                    .foregroundColor(activeCount > 0 ? .orange : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        activeCount > 0 ? Color.orange.opacity(0.12) : Color.white.opacity(0.05),
                        in: Capsule()
                    )
            }
            
            VStack(spacing: 10) {
                ForEach(0..<selectedHardwareDay.slots.count, id: \.self) { idx in
                    let slot = selectedHardwareDay.slots[idx]
                    hardwareSlotRow(slot: slot, slotIndex: idx)
                }
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 22, tint: .clear, tintOpacity: 0.05, specularOpacity: 0.45)
    }
    
    private func hardwareSlotRow(slot: HardwareChronoSlot, slotIndex: Int) -> some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(slot.isEnabled ? Color.orange.opacity(0.18) : Color.white.opacity(0.06))
                            .frame(width: 32, height: 32)
                        Text("\(slot.id)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(slot.isEnabled ? .orange : .secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Schaltzeit \(slot.id)")
                            .font(.subheadline.bold())
                        Text(slot.isEnabled ? "\(slot.startTime) – \(slot.endTime)" : "Inaktiv")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Toggle("", isOn: slotEnabledBinding(slotIndex: slotIndex))
                    .labelsHidden()
                    .tint(.orange)
            }
            
            if slot.isEnabled {
                Divider().opacity(0.3)
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start (Ein)")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        
                        DatePicker(
                            "",
                            selection: timeBinding(slotIndex: slotIndex, isStart: true),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Ende (Aus)")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        
                        DatePicker(
                            "",
                            selection: timeBinding(slotIndex: slotIndex, isStart: false),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(slot.isEnabled ? Color.orange.opacity(0.25) : Color.clear, lineWidth: 1)
        )
    }
}
