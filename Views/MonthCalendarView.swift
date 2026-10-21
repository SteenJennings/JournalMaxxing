import SwiftUI

/// Compact month calendar for the Today screen: dots mark days that have
/// entries; tapping a day makes it the working day (compose / backfill /
/// browse that date). Month navigation is internal; selection is a binding
/// owned by TodayView, which reacts to changes.
struct MonthCalendarView: View {
    @Binding var selectedDate: Date
    var entryDays: Set<Date>
    @State private var monthAnchor: Date = MonthCalendarView.firstOfMonth(Date())

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    static func firstOfMonth(_ date: Date) -> Date {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: c) ?? Calendar.current.startOfDay(for: date)
    }

    private var cells: [Date?] {
        let first = MonthCalendarView.firstOfMonth(monthAnchor)
        guard let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let lead = (cal.component(.weekday, from: first) - 1 + 7) % 7 // Sunday-first grid
        var out: [Date?] = Array(repeating: nil, count: lead)
        for d in range {
            out.append(cal.date(byAdding: .day, value: d - 1, to: first))
        }
        return out
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(monthAnchor.formatted(.dateTime.month(.wide).year()))
                    .font(Theme.display(15)).foregroundStyle(Theme.ink)
                Spacer()
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain).foregroundStyle(Theme.ink)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(weekdaySymbols.indices, id: \.self) { i in
                    Text(weekdaySymbols[i]).font(.caption2).foregroundStyle(.secondary)
                        .frame(height: 14)
                }
                ForEach(cells.indices, id: \.self) { i in
                    if let day = cells[i] {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
        .journalCard(padding: 10)
    }

    private func dayCell(_ day: Date) -> some View {
        let start = cal.startOfDay(for: day)
        let isSelected = cal.isDate(start, inSameDayAs: selectedDate)
        let isToday = cal.isDateInToday(start)
        let hasEntry = entryDays.contains(start)
        return Button { selectedDate = start } label: {
            ZStack {
                if isSelected {
                    Circle().fill(Theme.accent)
                } else if isToday {
                    Circle().stroke(Theme.accent, lineWidth: 1.5)
                }
                VStack(spacing: 1) {
                    Text("\(cal.component(.day, from: day))")
                        .font(.system(size: 13, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isSelected ? .white : Theme.ink)
                    Circle()
                        .fill(isSelected ? .white : Theme.accent)
                        .frame(width: 4, height: 4)
                        .opacity(hasEntry ? 1 : 0)
                }
            }
            .frame(height: 34)
        }
        .buttonStyle(.plain)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = next
        }
    }
}
