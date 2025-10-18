//
//  SprinklerScheduleViews.swift
//  MeltixSwift
//

import SwiftUI

// MARK: – Models

struct Schedule: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var enabled: Bool
    var rainGuard: Bool
    var slots: [ScheduleSlot]
    
    static func new() -> Schedule {
        .init(id: "temp-\(UUID().uuidString)",
              name: "", enabled: true, rainGuard: false, slots: [])
    }
    var isTemp: Bool { id.hasPrefix("temp-") }
}

struct ScheduleSlot: Identifiable, Codable, Equatable {
    var id: String
    var days: [Int]          // NEW: Support multiple days
    var time: String
    var duration: Int
    var zones: [Int]

    static func new() -> ScheduleSlot {
        .init(id: "temp-\(UUID().uuidString)",
              days: [0], time: "06:00", duration: 10, zones: [1])
    }
    var isTemp: Bool { id.hasPrefix("temp-") }
}

// MARK: – Service

@MainActor
enum ScheduleAPI {
    private struct Dto: Codable {
        var id: String?
        var deviceId: String?
        var name: String
        var enabled: Bool
        var rainGuard: Bool
        var slots: [SlotDto]
    }
    private struct SlotDto: Codable {
        var id: String?
        var days: [Int]    // ← NEW
        var start: String
        var durationMin: Int
        var zones: [Int]
    }

    static func list(deviceId: String) async throws -> [Schedule] {
        let res: [Dto] = try await request("/schedule", method: "GET", query: ["deviceId": deviceId])
        return res.map(toModel)
    }
    static func create(_ s: Schedule, deviceId: String) async throws {
        try await requestVoid("/schedule", method: "POST", body: toDto(s, deviceId: deviceId))
    }
    static func update(_ s: Schedule) async throws {
        try await requestVoid("/schedule/\(s.id)", method: "PUT", body: toDto(s, deviceId: nil))
    }
    static func delete(_ s: Schedule) async throws {
        try await requestVoid("/schedule/\(s.id)", method: "DELETE")
    }

    private static func toDto(_ s: Schedule, deviceId: String?) -> Dto {
        .init(id: s.isTemp ? nil : s.id,
              deviceId: deviceId,
              name: s.name, enabled: s.enabled, rainGuard: s.rainGuard,
              slots: s.slots.map {
                  .init(id: $0.isTemp ? nil : $0.id,
                        days: $0.days, start: $0.time,
                        durationMin: $0.duration, zones: $0.zones)
              })
    }
    private static func toModel(_ d: Dto) -> Schedule {
        .init(id: d.id ?? "temp-\(UUID())",
              name: d.name, enabled: d.enabled, rainGuard: d.rainGuard,
              slots: d.slots.map {
                  .init(id: $0.id ?? "temp-\(UUID())",
                        days: $0.days, time: $0.start,
                        duration: $0.durationMin, zones: $0.zones)
              })
    }

    private static func request<T: Decodable>(
        _ path: String, method: String,
        query: [String:String]? = nil, body: Encodable? = nil) async throws -> T {

        var urlStr = AuthManager.shared.baseURL + path
        if let q = query {
            urlStr += "?" + q.map { "\($0)=\($1)" }.joined(separator: "&")
        }
        guard let url = URL(string: urlStr),
              let tok = AuthManager.shared.token else { throw URLError(.badURL) }

        var req = URLRequest(url: url); req.httpMethod = method
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = try JSONEncoder().encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode ?? 500 < 400 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private static func requestVoid(
        _ path: String, method: String, body: Encodable? = nil) async throws {
        struct Empty: Decodable {}
        _ = try await request(path, method: method, body: body) as Empty
    }
}

// MARK: – Schedule List View

struct ScheduleListView: View {
    let device: Device
    @State private var list: [Schedule] = []
    @State private var loading = true
    @State private var err: String?
    @State private var edit: Schedule?
    @State private var showToast = false
    @State private var toastMsg = ""

    var body: some View {
        ZStack {
            Color.jetBlack.ignoresSafeArea()
            VStack(spacing: 0) {
                // ─────── HEADER (matches SprinklerDetailView) ───────
                VStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 36))
                        .foregroundColor(.gold)
                    Text("Sprinkler Controller")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text(device.id)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                Divider().background(Color.gold.opacity(0.4))

                // ─────── Add (+) Button ───────
                HStack {
                    Spacer()
                    Button {
                        if list.count >= 3 {
                            toastMsg = "Max 3 schedules"
                            withAnimation { showToast = true }
                        } else {
                            edit = Schedule.new()
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.gold)
                    }
                    .padding(.trailing, 18)
                    .padding(.top, -46)
                }
                .frame(maxHeight: 0) // doesn't take vertical space

                // ─────── Main Content ───────
                if loading {
                    ProgressView().tint(.gold)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if list.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 42))
                            .foregroundColor(.darkGold)
                        Text("No schedules yet")
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(list, id: \.id) { s in
                                scheduleCard(s)
                            }
                        }
                        .padding(.vertical, 18)
                        .padding(.horizontal, 16)
                    }
                }
            }
            // ─────── Toast ───────
            if showToast {
                VStack {
                    Spacer()
                    Text(toastMsg)
                        .font(.callout.bold())
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(Color.gold)
                        .foregroundColor(.black)
                        .cornerRadius(14)
                        .shadow(radius: 8)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { showToast = false }
                            }
                        }
                    Spacer().frame(height: 38)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .onAppear { Task { await refresh() } }
        .sheet(item: $edit) { s in
            ScheduleEditor(device: device, sched: s) { await refresh() }
        }
        .alert("Error", isPresented: .constant(err != nil)) {
            Button("OK", role: .cancel) { err = nil }
        } message: { Text(err ?? "") }
    }

    // Card for each schedule
    private func scheduleCard(_ s: Schedule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(s.name)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { s.enabled },
                    set: { val in Task { await toggle(s, val) } }
                ))
                .labelsHidden()
                .tint(.gold)
                Button {
                    Task { await del(s) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .padding(.leading, 4)
                }
            }
            .padding(.bottom, 2)
            ForEach(s.slots) { slot in
                HStack {
                    Text("\(formatDays(slot.days)), \(slot.time)")
                        .font(.caption)
                        .foregroundColor(.gold)
                    Spacer()
                    Text("\(slot.duration)m")
                        .font(.caption)
                        .foregroundColor(.gold)
                }
            }
        }
        .padding(14)
        .background(Color.charcoalGray)
        .cornerRadius(14)
        .onTapGesture { edit = s }
        .shadow(radius: 3)
    }

    // API
    private func refresh() async {
        loading = true
        do {
            // Sort by createdAt, or fallback to name or id for stable order
            var loaded = try await ScheduleAPI.list(deviceId: device.id)
            loaded.sort { $0.name < $1.name } // or by createdAt if available
            list = loaded
        }
        catch { err = "Fetch failed" }
        loading = false
    }
    private func del(_ s: Schedule) async {
        do { try await ScheduleAPI.delete(s); await refresh() }
        catch { err = "Delete failed" }
    }
    private func toggle(_ s: Schedule, _ val: Bool) async {
        var x = s; x.enabled = val
        do { try await ScheduleAPI.update(x); await refresh() }
        catch { err = "Update failed" }
    }
    private func formatDays(_ days: [Int]) -> String {
        days.sorted().map { Calendar.current.shortWeekdaySymbols[$0 % 7].prefix(3) }.joined(separator: ", ")
    }
}

// MARK: – Schedule Editor

struct ScheduleEditor: View {
    let device: Device
    @State var sched: Schedule
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var slotEdit = ScheduleSlot.new()
    @State private var slotIdx: Int? = nil
    @State private var showSlot = false

    @State private var toast: String?

    var body: some View {
        ZStack {
            // Tap-to-dismiss background
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    hideKeyboard()
                }

            // Actual content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .padding(.trailing, 4)
                    }
                    .foregroundColor(.gold)

                    Text(sched.isTemp ? "New Schedule" : "Edit Schedule")
                        .font(.title2).bold().foregroundColor(.gold)
                    Spacer()
                }
                .padding()
                .background(Color.charcoalGray)
                .shadow(radius: 6)

                ScrollView {
                    VStack(spacing: 18) {
                        // Name & Toggles Card
                        VStack(spacing: 16) {
                            TextField("Schedule Name", text: $sched.name)
                                .padding()
                                .background(Color.jetBlack.opacity(0.9))
                                .cornerRadius(10)
                                .foregroundColor(.white)
                                .font(.headline)

                            HStack(spacing: 24) {
                                Toggle("Enabled", isOn: $sched.enabled)
                                    .toggleStyle(SwitchToggleStyle(tint: .gold))
                                    .foregroundColor(.gold)
                                Toggle("Rain Guard", isOn: $sched.rainGuard)
                                    .toggleStyle(SwitchToggleStyle(tint: .gold))
                                    .foregroundColor(.gold)
                            }
                        }
                        .padding()
                        .background(Color.charcoalGray)
                        .cornerRadius(16)
                        .shadow(radius: 4)

                        // Slots List Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Slots")
                                    .font(.headline)
                                    .foregroundColor(.gold)
                                Spacer()
                                Button(action: {
                                    slotIdx = nil; slotEdit = ScheduleSlot.new(); showSlot = true
                                }) {
                                    Label("Add", systemImage: "plus.circle.fill")
                                        .foregroundColor(.gold)
                                }
                            }

                            if sched.slots.isEmpty {
                                Text("No slots added yet.")
                                    .foregroundColor(.gray)
                                    .padding(.top, 6)
                            } else {
                                ForEach(Array(sched.slots.enumerated()), id: \.1.id) { i, sl in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(formatDays(sl.days)), \(sl.time)")
                                                .foregroundColor(.white)
                                            Text("Duration: \(sl.duration)m, Zones: \(sl.zones.map(String.init).joined(separator: ", "))")
                                                .font(.caption)
                                                .foregroundColor(.gold)
                                        }
                                        Spacer()
                                        Button(action: {
                                            slotIdx = i
                                            slotEdit = sl
                                            showSlot = true
                                        }) {
                                            Image(systemName: "pencil")
                                                .foregroundColor(.gold)
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.jetBlack.opacity(0.6))
                                    .cornerRadius(10)
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            sched.slots.remove(at: i)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color.charcoalGray)
                        .cornerRadius(16)
                        .shadow(radius: 4)
                    }
                    .padding()
                }

                // Save Button
                VStack {
                    if busy {
                        ProgressView().tint(.gold)
                    } else {
                        Button(action: {
                            let trimmed = sched.name.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty {
                                showToast("Name is required.")
                                return
                            }
                            if sched.slots.isEmpty {
                                showToast("At least one slot required.")
                                return
                            }
                            Task { await store() }
                        }) {
                            Text("Save")
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color.gold)
                                .foregroundColor(.black)
                                .font(.title3.bold())
                                .cornerRadius(14)
                                .shadow(radius: 4)
                        }
                    }
                }
                .padding([.horizontal, .bottom])
            }
            .background(Color.jetBlack.ignoresSafeArea())
            .sheet(isPresented: $showSlot) {
                SlotEditor(slot: $slotEdit, onDone: {
                    if let idx = slotIdx { sched.slots[idx] = slotEdit }
                    else { sched.slots.append(slotEdit) }
                })
            }

            // Toast overlay
            if let toast = toast {
                VStack {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.gold)
                        .foregroundColor(.black)
                        .cornerRadius(14)
                        .shadow(radius: 6)
                        .padding(.top, 18)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                    Spacer()
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { self.toast = nil }
                    }
                }
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
    }

    private func store() async {
        busy = true
        do {
            if sched.isTemp {
                try await ScheduleAPI.create(sched, deviceId: device.id)
            } else {
                try await ScheduleAPI.update(sched)
            }
            await onDone()
            dismiss()
        } catch {
            showToast("Network error—try again.")
        }
        busy = false
    }

    private func formatDays(_ days: [Int]) -> String {
        days.sorted().map { Calendar.current.shortWeekdaySymbols[$0 % 7].prefix(3) }.joined(separator: ", ")
    }
}


// MARK: – Slot Editor

struct SlotEditor: View {
    @Binding var slot: ScheduleSlot
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    private let days = Calendar.current.shortWeekdaySymbols // ["Sun", "Mon", ...]
    private let hours = Array(0...23)
    private let minutes = stride(from: 0, to: 60, by: 5).map { $0 }
    @State private var tempHour: Int = 6
    @State private var tempMinute: Int = 0

    private func updateTempTime() {
        let comps = slot.time.split(separator: ":").map { Int($0) ?? 0 }
        tempHour = comps.first ?? 6
        tempMinute = comps.count > 1 ? comps[1] : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Spacer()
                Text("Schedule Slot")
                    .font(.title.bold())
                    .foregroundColor(.gold)
                Spacer()
            }

            // Multi-day
            VStack(alignment: .leading, spacing: 8) {
                Text("Days")
                    .font(.headline)
                    .foregroundColor(.gold)
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { i in
                        let isSelected = slot.days.contains(i)
                        Button(action: {
                            if isSelected {
                                slot.days.removeAll { $0 == i }
                            } else {
                                slot.days.append(i)
                                slot.days.sort() // optional, keeps order
                            }
                        }) {
                            Text(days[i].prefix(3))
                                .font(.callout.weight(.semibold))
                                .foregroundColor(isSelected ? .black : .white)
                                .frame(width: 36, height: 32)
                                .background(isSelected ? Color.gold : Color.charcoalGray.opacity(0.7))
                                .cornerRadius(8)
                                .shadow(radius: isSelected ? 2 : 0)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            // Start Time Picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Start Time")
                    .font(.headline)
                    .foregroundColor(.gold)
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Picker("Hour", selection: $tempHour) {
                            ForEach(hours, id: \.self) { h in
                                Text(String(format: "%02d", h))
                                    .font(.system(.title3, design: .monospaced))
                                    .foregroundColor(.white)
                                    .tag(h)
                            }
                        }
                        .frame(width: 60, height: 100)
                        .clipped()
                        .pickerStyle(.wheel)
                        .background(Color.charcoalGray.opacity(0.9))
                        .cornerRadius(10)

                        Text(":")
                            .font(.title)
                            .foregroundColor(.gold)

                        Picker("Minute", selection: $tempMinute) {
                            ForEach(minutes, id: \.self) { m in
                                Text(String(format: "%02d", m))
                                    .font(.system(.title3, design: .monospaced))
                                    .foregroundColor(.white)
                                    .tag(m)
                            }
                        }
                        .frame(width: 60, height: 100)
                        .clipped()
                        .pickerStyle(.wheel)
                        .background(Color.charcoalGray.opacity(0.9))
                        .cornerRadius(10)
                    }
                    Spacer()
                }
                .onChange(of: tempHour) { _ in updateTime() }
                .onChange(of: tempMinute) { _ in updateTime() }
                .onAppear { updateTempTime() }
            }

            // Duration
            HStack {
                Text("Duration")
                    .font(.headline)
                    .foregroundColor(.gold)
                Spacer()
                HStack(spacing: 2) {
                    Button(action: {
                        if slot.duration > 5 { slot.duration -= 5 }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(slot.duration > 5 ? .gold : .gray)
                    }.disabled(slot.duration <= 5)
                    Text("\(slot.duration) min")
                        .font(.system(.body, design: .monospaced)).frame(width: 58)
                        .foregroundColor(.white)
                    Button(action: {
                        if slot.duration < 120 { slot.duration += 5 }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(slot.duration < 120 ? .gold : .gray)
                    }.disabled(slot.duration >= 120)
                }
            }

            // Zones
            VStack(alignment: .leading, spacing: 6) {
                Text("Zones")
                    .font(.headline)
                    .foregroundColor(.gold)
                HStack(spacing: 16) {
                    ForEach(1...4, id: \.self) { z in
                        Button(action: {
                            if slot.zones.contains(z) {
                                slot.zones.removeAll { $0 == z }
                            } else {
                                slot.zones.append(z)
                            }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: slot.zones.contains(z) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(slot.zones.contains(z) ? .gold : .gray)
                                Text("Z\(z)")
                                    .foregroundColor(.white)
                            }
                            .padding(.vertical, 7)
                            .padding(.horizontal, 8)
                            .background(Color.charcoalGray.opacity(0.8))
                            .cornerRadius(8)
                        }
                    }
                }
            }

            // Done Button
            HStack {
                Spacer()
                Button("Done") {
                    onDone()
                    dismiss()
                }
                .font(.headline)
                .padding(.vertical, 10)
                .padding(.horizontal, 60)
                .background(Color.gold)
                .foregroundColor(.black)
                .cornerRadius(12)
                Spacer()
            }
        }
        .padding(22)
        .background(Color.charcoalGray)
        .cornerRadius(18)
        .padding()
        .navigationBarHidden(true)
    }

    private func updateTime() {
        slot.time = String(format: "%02d:%02d", tempHour, tempMinute)
    }
}

// Hide Keyboard Helper
