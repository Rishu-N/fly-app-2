import Foundation
import PlannerCore
import WidgetKit

/// Writes the small JSON the widgets read, and reloads timelines only when the *rendered*
/// content changed. The fingerprint is a stable FNV-1a hash persisted in the App Group, so a
/// fresh process (launch, Lock Screen intent) doesn't burn a reload from WidgetKit's budget.
@MainActor
final class WidgetSnapshotWriter {
    static let widgetKind = "DayflightNow"
    private static let hashKey = "widget.snapshot.hash"
    private var pending: Task<Void, Never>?

    func scheduleWrite(after delay: Duration = .seconds(1), _ make: @escaping @MainActor () -> WidgetSnapshot) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.write(make())
        }
    }

    func cancelScheduledWrite() {
        pending?.cancel()
        pending = nil
    }

    /// Awaitable: returns after the file is on disk.
    func write(_ snapshot: WidgetSnapshot) async {
        var stripped = snapshot
        stripped.generatedAt = Date(timeIntervalSince1970: 0)
        stripped.tasks = snapshot.tasks.map { task in
            var t = task
            t.notes = ""
            t.checklist = []
            t.updatedAt = t.createdAt
            return t
        }
        guard let data = try? stripped.encoded() else { return }
        let hash = Int64(bitPattern: StableHash.fnv1a64(data))
        guard AppGroup.defaults.object(forKey: Self.hashKey) as? Int64 != hash else { return }
        let url = AppGroup.widgetSnapshotURL
        let ok = await Task.detached(priority: .utility) { () -> Bool in
            (try? data.write(to: url, options: [.atomic])) != nil
        }.value
        guard ok else { return }
        AppGroup.defaults.set(hash, forKey: Self.hashKey)
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
    }
}
