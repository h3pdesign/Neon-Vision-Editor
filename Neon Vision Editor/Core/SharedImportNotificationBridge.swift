import Foundation

enum SharedImportNotificationBridge {
    nonisolated static let notificationName = "h3p.NeonVisionEditor.sharedImportPending"
}

@MainActor
final class SharedImportNotificationObserver {
    private var isObserving = false
    private let onPendingImport: @MainActor () -> Void

    init(onPendingImport: @escaping @MainActor () -> Void) {
        self.onPendingImport = onPendingImport
    }

    func start() {
        guard !isObserving else { return }
        isObserving = true
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let instance = Unmanaged<SharedImportNotificationObserver>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                Task { @MainActor in
                    instance.onPendingImport()
                }
            },
            SharedImportNotificationBridge.notificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    func stop() {
        guard isObserving else { return }
        isObserving = false
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(SharedImportNotificationBridge.notificationName as CFString),
            nil
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(SharedImportNotificationBridge.notificationName as CFString),
            nil
        )
    }
}
