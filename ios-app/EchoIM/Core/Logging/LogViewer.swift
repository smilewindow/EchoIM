import SwiftUI

// MARK: - Level Filter

enum LevelFilter: String, CaseIterable {
    case all = "全部"
    case warningPlus = "warning+"
    case errorOnly = "error only"
}

// MARK: - LogViewer

@MainActor
struct LogViewer: View {
    @State private var selectedCategories: Set<LogCategory> = Set(LogCategory.allCases)
    @State private var levelFilter: LevelFilter = .all
    @State private var searchText: String = ""

    private var store: LogStore { LogStore.shared }

    private var filtered: [LogEntry] {
        store.entries.filter { entry in
            selectedCategories.contains(entry.category)
                && matchesLevel(entry)
                && (searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            entryList
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("清除") {
                    LogStore.shared.clear()
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索日志")
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            // Level picker
            Picker("级别", selection: $levelFilter) {
                ForEach(LevelFilter.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)

            // Category chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "全部" chip
                    let allSelected = selectedCategories.count == LogCategory.allCases.count
                    CategoryChip(
                        label: "全部",
                        isSelected: allSelected
                    ) {
                        selectedCategories = Set(LogCategory.allCases)
                    }

                    ForEach(LogCategory.allCases, id: \.self) { category in
                        CategoryChip(
                            label: category.rawValue,
                            isSelected: selectedCategories.contains(category)
                        ) {
                            toggleCategory(category)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Entry List

    private var entryList: some View {
        ScrollViewReader { proxy in
            List(filtered) { entry in
                entryRow(entry)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .onLongPressGesture {
                        UIPasteboard.general.string = clipboardText(for: entry)
                    }
            }
            .listStyle(.plain)
            .onChange(of: store.entries.last?.id) { _, _ in
                if let last = filtered.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Entry Row

    private func entryRow(_ entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Meta line: File:Line  HH:mm:ss  [category]
            Text("\(entry.file):\(entry.line)  \(timeString(entry.timestamp))  [\(entry.category.rawValue)]")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Message line: colored by level
            Text("→ \(entry.message)")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(color(for: entry.level))
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func matchesLevel(_ entry: LogEntry) -> Bool {
        switch levelFilter {
        case .all:
            return true
        case .warningPlus:
            return entry.level == .warning || entry.level == .error
        case .errorOnly:
            return entry.level == .error
        }
    }

    private func toggleCategory(_ category: LogCategory) {
        let allSelected = selectedCategories.count == LogCategory.allCases.count
        if allSelected {
            // All selected → select only this one
            selectedCategories = [category]
        } else if selectedCategories.contains(category) {
            // Deselect, but prevent empty selection
            let next = selectedCategories.subtracting([category])
            if !next.isEmpty {
                selectedCategories = next
            }
        } else {
            // Add to selection
            selectedCategories.insert(category)
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug:   return .gray
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let clipboardFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private func timeString(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func clipboardText(for entry: LogEntry) -> String {
        let time = Self.clipboardFormatter.string(from: entry.timestamp)
        return "\(entry.file):\(entry.line)  \(time)  [\(entry.category.rawValue)]  → \(entry.message)"
    }
}

// MARK: - CategoryChip

private struct CategoryChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color(uiColor: .systemGray5))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
