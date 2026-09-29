import SwiftUI
import AppKit

// MARK: - Export CSV (in-popover range picker)

enum ExportPreset: String, CaseIterable, Identifiable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case allTime = "All Time"
    case custom = "Custom"

    var id: String { rawValue }
}

struct ExportRangeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: UIState

    @State private var preset: ExportPreset = .thisMonth
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var applyingPreset = false

    var body: some View {
        VStack(alignment: .leading, spacing: HT.Space.m) {
            NavHeader(backTitle: "Back", onBack: { ui.pop() }) {
                Text("Export CSV")
            }

            Text("Includes sessions whose start falls in the range (local timezone), inclusive.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            presetRow

            VStack(spacing: HT.Space.s) {
                dateRow(title: "Start", date: $startDate)
                dateRow(title: "End", date: $endDate)
            }
            .padding(HT.Space.s)
            .background(HT.cardShape.fill(.quaternary))
            .onChange(of: startDate) { _ in markCustomIfNeeded() }
            .onChange(of: endDate) { _ in markCustomIfNeeded() }

            HStack {
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if startDay > endDay {
                    Text("Start is after end")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            HStack {
                Button("Cancel") { ui.pop() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    store.exportCSV(range: currentRange)
                } label: {
                    Label("Export CSV…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .capsuleButton()
                .disabled(startDay > endDay)
                .keyboardShortcut(.defaultAction)
            }
            .font(.callout)
            .padding(.horizontal, HT.Space.xs)
        }
        .onAppear { applyPreset(.thisMonth) }
    }

    private var startDay: Date { Calendar.current.startOfDay(for: startDate) }
    private var endDay: Date { Calendar.current.startOfDay(for: endDate) }

    private var presetRow: some View {
        VStack(alignment: .leading, spacing: HT.Space.xs) {
            Text("Range")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: HT.Space.xs)],
                      alignment: .leading, spacing: HT.Space.xs) {
                ForEach(ExportPreset.allCases) { p in
                    Button {
                        applyPreset(p)
                    } label: {
                        Text(p.rawValue)
                            .font(.caption.weight(preset == p ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.bordered)
                    .tint(preset == p ? Color.accentColor : nil)
                    .capsuleButton()
                }
            }
        }
    }

    private func dateRow(title: String, date: Binding<Date>) -> some View {
        HStack {
            Text(title)
                .frame(width: 44, alignment: .leading)
            DatePicker("", selection: date, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
            Spacer(minLength: 0)
        }
    }

    private var currentRange: Store.ExportRange {
        Store.ExportRange(start: startDate, end: endDate)
    }

    private var countLabel: String {
        let n = store.sessionCount(in: currentRange)
        return n == 1 ? "1 session" : "\(n) sessions"
    }

    private func markCustomIfNeeded() {
        guard !applyingPreset else { return }
        if preset != .custom { preset = .custom }
    }

    private func applyPreset(_ p: ExportPreset) {
        applyingPreset = true
        preset = p
        let cal = Calendar.current
        switch p {
        case .today:
            startDate = store.startOfToday
            endDate = store.now
        case .thisWeek:
            startDate = store.startOfWeek
            endDate = store.now
        case .thisMonth:
            startDate = store.startOfMonth
            endDate = store.now
        case .allTime:
            let r = store.allTimeExportRange
            startDate = cal.startOfDay(for: r.start)
            endDate = r.end
        case .custom:
            break
        }
        // Defer so onChange from the assignments above still sees applyingPreset == true.
        DispatchQueue.main.async { applyingPreset = false }
    }
}
