import Foundation
import HealthKit
import UserNotifications
import WatchKit

/// The rest timer on the wrist: a tap on the wrist when it is over, also with the screen off (a
/// local notification at the end, since the app may not be running then).
@MainActor
final class RestTimer: ObservableObject {
    @Published private(set) var end: Date?
    @Published private(set) var length: Int = 90
    private var tick: Task<Void, Never>?
    private let id = "rest"

    var running: Bool { end != nil }

    func remaining(at now: Date = Date()) -> Int {
        guard let end else { return length }
        return max(0, Int(ceil(end.timeIntervalSince(now))))
    }

    func start(seconds: Int) {
        length = max(5, seconds)
        let end = Date().addingTimeInterval(TimeInterval(length))
        self.end = end
        WKInterfaceDevice.current().play(.start)
        schedule(at: end)
        tick?.cancel()
        tick = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, end.timeIntervalSinceNow)) * 1_000_000_000)
            guard !Task.isCancelled, let self, self.end == end else { return }
            self.end = nil
            WKInterfaceDevice.current().play(.notification)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [self.id])
        }
    }

    func add(_ seconds: Int) {
        guard let end else { length = max(5, length + seconds); return }
        start(seconds: max(5, Int(end.timeIntervalSinceNow) + seconds))
    }

    func stop() {
        tick?.cancel()
        end = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    func preset(_ seconds: Int) { if !running { length = max(5, seconds) } }

    private func schedule(at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Rest is over")
            content.body = String(localized: "Next set.")
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
            center.add(UNNotificationRequest(identifier: "rest", content: content, trigger: trigger))
        }
    }
}

/// A strength workout recorded on the watch: the live heart rate and active energy while it runs,
/// saved to Apple Health when it ends. While it runs the app keeps running with the screen off,
/// so the rest timer's tap arrives on time too.
@MainActor
final class HeartSession: NSObject, ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var bpm: Double?
    @Published private(set) var kcal: Double = 0
    @Published private(set) var start: Date?
    @Published private(set) var error: String?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// With `-demo`: numbers to show, nothing recorded.
    func showDemo() {
        running = true
        bpm = 128
        kcal = 214
        start = Date().addingTimeInterval(-1500)
    }

    func begin() async {
        error = nil
        guard HKHealthStore.isHealthDataAvailable() else {
            error = String(localized: "Apple Health is not available on this watch.")
            return
        }
        let heart = HKQuantityType(.heartRate), energy = HKQuantityType(.activeEnergyBurned)
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType(), energy], read: [heart, energy])
            let config = HKWorkoutConfiguration()
            config.activityType = .traditionalStrengthTraining
            config.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            start = now
            bpm = nil
            kcal = 0
            running = true
        } catch {
            self.error = error.localizedDescription
            session = nil
            builder = nil
        }
    }

    func end() async {
        guard let session, let builder else { running = false; return }
        session.end()
        do {
            try await builder.endCollection(at: Date())
            _ = try await builder.finishWorkout()
        } catch {
            self.error = error.localizedDescription
        }
        self.session = nil
        self.builder = nil
        running = false
    }

    fileprivate func collected(bpm: Double?, kcal: Double?) {
        if let bpm { self.bpm = bpm }
        if let kcal { self.kcal = kcal }
    }

    fileprivate func failed(_ e: Error) { error = e.localizedDescription }
}

extension HeartSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.failed(error) }
    }
}

extension HeartSession: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        let bpm = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: perMinute)
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        Task { @MainActor in self.collected(bpm: bpm, kcal: kcal) }
    }
}
