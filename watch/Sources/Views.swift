import SwiftUI

extension Color {
    /// openGym's green.
    static let og = Color(red: 0.19, green: 0.82, blue: 0.35)
}

@main
struct OpenGymWatchApp: App {
    @StateObject private var store = Store()
    @StateObject private var rest = RestTimer()
    @StateObject private var heart = HeartSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(rest)
                .environmentObject(heart)
                .tint(Color.og)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var heart: HeartSession
    @Environment(\.scenePhase) private var phase
    // `-tab 2` on the command line opens on that page (the screenshots).
    @State private var tab = UserDefaults.standard.integer(forKey: "tab")

    var body: some View {
        Group {
            if store.paired {
                TabView(selection: $tab) {
                    WorkoutView().tag(0)
                    RestView().tag(1)
                    HeartView().tag(2)
                    SettingsView().tag(3)
                }
                .tabViewStyle(.verticalPage)
            } else {
                PairView()
            }
        }
        .onAppear { if store.demo { heart.showDemo() } }
        .onChange(of: phase) { _, now in
            if now == .active { store.startPolling() } else { store.stopPolling() }
        }
        .task { store.startPolling() }
    }
}

// MARK: - The workout in progress

struct WorkoutView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let a = store.summary?.active {
                    ActiveWorkout(active: a, unit: store.summary?.unit ?? "kg")
                } else if store.summary != nil {
                    Text("No workout running").font(.headline)
                    Text("Start one on the phone or in the browser: it shows up here.").font(.footnote).foregroundStyle(.secondary)
                    if let last = store.summary?.last {
                        Divider()
                        Text("Last workout").font(.caption).foregroundStyle(.secondary)
                        Text(last.name.isEmpty ? last.d : last.name).font(.body.bold())
                        Text("\(last.d) · \(last.sets) sets").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let w = store.summary?.weight {
                        Divider()
                        Text("Body weight").font(.caption).foregroundStyle(.secondary)
                        Text("\(Fmt.num(w.w)) \(store.summary?.unit ?? "kg")").font(.title3.bold())
                    }
                } else if let e = store.error {
                    Text(e).font(.footnote).foregroundStyle(.orange)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Workout")
    }
}

struct ActiveWorkout: View {
    let active: WatchSummary.Active
    let unit: String

    private var done: Int { active.entries.reduce(0) { $0 + $1.sets.filter(\.done).count } }
    private var total: Int { active.entries.reduce(0) { $0 + $1.sets.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(active.name.isEmpty ? String(localized: "Workout") : active.name).font(.headline).lineLimit(1)
                Spacer()
                if let start = active.start {
                    Text(Date(timeIntervalSince1970: start / 1000), style: .timer).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        .fixedSize().layoutPriority(1)
                }
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
            Text("\(done) of \(total) sets").font(.caption2).foregroundStyle(.secondary)
            if active.entries.indices.contains(active.current) {
                let e = active.entries[active.current]
                Text(e.name).font(.title3.bold()).lineLimit(3).padding(.top, 4)
                ForEach(Array(e.sets.enumerated()), id: \.offset) { i, s in
                    HStack {
                        Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 16, alignment: .leading)
                        Text(Fmt.set(s, unit: unit)).font(.body.monospacedDigit())
                        Spacer()
                        Image(systemName: s.done ? "checkmark.circle.fill" : "circle").foregroundStyle(s.done ? Color.og : .secondary)
                    }
                    .opacity(s.done ? 0.6 : 1)
                }
                let next = active.entries.dropFirst(active.current + 1).first
                if let next {
                    Text("Next: \(next.name)").font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                }
            } else {
                Label("All sets done", systemImage: "checkmark.seal.fill").foregroundStyle(Color.og).padding(.top, 4)
            }
        }
    }
}

// MARK: - Rest timer

struct RestView: View {
    @EnvironmentObject var rest: RestTimer
    @EnvironmentObject var store: Store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = rest.remaining(at: ctx.date)
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: rest.running ? CGFloat(left) / CGFloat(max(rest.length, 1)) : 1)
                        .stroke(Color.og, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(Fmt.clock(left)).font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                }
                .frame(maxWidth: 120, maxHeight: 120)
                HStack {
                    Button("−15") { rest.running ? rest.add(-15) : rest.preset(rest.length - 15) }
                    if rest.running {
                        Button { rest.stop() } label: { Image(systemName: "stop.fill") }.tint(.red)
                    } else {
                        Button { rest.start(seconds: rest.length) } label: { Image(systemName: "play.fill") }
                    }
                    Button("+15") { rest.running ? rest.add(15) : rest.preset(rest.length + 15) }
                }
                .font(.footnote)
            }
        }
        .navigationTitle("Rest")
        .onAppear { if !rest.running { rest.preset(Int(store.summary?.restSec ?? 90)) } }
    }
}

// MARK: - Heart rate

struct HeartView: View {
    @EnvironmentObject var heart: HeartSession

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "heart.fill").foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: heart.running)
                Text(heart.bpm.map { Fmt.num($0, decimals: 0) } ?? "--").font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                Text("bpm").font(.footnote).foregroundStyle(.secondary)
            }
            if heart.running, let start = heart.start {
                HStack {
                    Text(start, style: .timer).monospacedDigit()
                    Text("·")
                    Text("\(Fmt.num(heart.kcal, decimals: 0)) kcal")
                }
                .font(.footnote).foregroundStyle(.secondary)
                Button(role: .destructive) { Task { await heart.end() } } label: { Label("End workout", systemImage: "stop.fill") }
                    .tint(.red)
            } else {
                Text("Records the workout in Apple Health and shows your heart rate live.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { Task { await heart.begin() } } label: { Label("Start workout", systemImage: "play.fill") }
            }
            if let e = heart.error { Text(e).font(.caption2).foregroundStyle(.orange) }
        }
        .navigationTitle("Heart")
    }
}

// MARK: - Settings and pairing

struct SettingsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connected to").font(.caption).foregroundStyle(.secondary)
                Text(store.demo ? "demo" : (URL(string: store.server)?.host ?? store.server)).font(.footnote).lineLimit(2)
                if let name = store.userName { Text(name).font(.headline) }
                if let when = store.updated {
                    Text("Updated \(when, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
                }
                if let e = store.error { Text(e).font(.caption2).foregroundStyle(.orange) }
                Button("Refresh") { Task { await store.refresh() } }
                Button("Disconnect", role: .destructive) { store.unpair() }.tint(.red)
                Text("openGym \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

struct PairView: View {
    @EnvironmentObject var store: Store
    @State private var server = UserDefaults.standard.string(forKey: "server") ?? ""
    @State private var code = ""
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pair with openGym").font(.headline)
                Text("In openGym on the phone or in the browser: Settings → Account → Pair the mobile app. Type the code shown there.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Server address", text: $server)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button {
                    busy = true
                    Task { _ = await store.pair(server: server, code: code); busy = false }
                } label: {
                    if busy { ProgressView() } else { Text("Pair") }
                }
                .disabled(busy || server.isEmpty || code.count < 4)
                if let e = store.error { Text(e).font(.caption2).foregroundStyle(.orange) }
            }
        }
    }
}
