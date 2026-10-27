import Capacitor
import UIKit
import UserNotifications
import WebKit

/**
 * The app's own bridge view controller (Main.storyboard). Since Capacitor 6 the bridge only loads
 * the plugins that come from npm packages (packageClassList in capacitor.config.json); plugins
 * that live in the app itself are registered here, or the page finds none of them.
 */
class MainViewController: CAPBridgeViewController {
    /// The downloaded animation packs, read through Background Assets (AnimationPacksPlugin.swift).
    private let packFiles = AnimationPackSchemeHandler()

    override open func webViewConfiguration(for instanceConfiguration: InstanceConfiguration) -> WKWebViewConfiguration {
        let config = super.webViewConfiguration(for: instanceConfiguration)
        config.setURLSchemeHandler(packFiles, forURLScheme: AnimationPackSchemeHandler.scheme)
        return config
    }

    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(PrintPlugin())
        bridge?.registerPluginInstance(RestAlertPlugin())
        bridge?.registerPluginInstance(DeviceAuthPlugin())
        bridge?.registerPluginInstance(AnimationPacksPlugin())
        bridge?.registerPluginInstance(NudgeCheckPlugin())
        bridge?.registerPluginInstance(GymReminderPlugin())
        bridge?.registerPluginInstance(WatchBridgePlugin())
        bridge?.registerPluginInstance(AppleHealthPlugin())
        bridge?.registerPluginInstance(WidgetBridgePlugin())
        bridge?.registerPluginInstance(LiveActivityPlugin())
        bridge?.registerPluginInstance(AppIconPlugin())
        // Reading Apple Health into the health area (lib/health/apple-health.js), beside
        // AppleHealthPlugin, which writes workouts and weigh-ins to it.
        bridge?.registerPluginInstance(HealthKitPlugin())
        // The Music app's player for the workout's music bar (lib/music/apple-music.js).
        bridge?.registerPluginInstance(MusicPlayerPlugin())
        WidgetPreview.runIfAsked()
        // After loadView has finished: the view is the web view only once it has.
        if ProcessInfo.processInfo.arguments.contains(MainViewController.pendingProbeArgument) {
            DispatchQueue.main.async { [weak self] in self?.showPendingProbe() }
        }
    }

    /**
     * The iPhone Duo closed writes the time and the battery in a block at the top of its right
     * column, and that block grows while the screen records or a call goes on (the island taller).
     * The page cannot see it (no safe-area inset says how tall it is), so its height goes to the
     * page as --status-block, and the tab bar's icons in that column start below it
     * (index.css body.tabbar-status). 0 where the status bar is no block on the right.
     */
    private var statusWatch: Timer?
    private var statusBlock: CGFloat = -1

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reportStatusBlock()
        // iOS posts nothing when the status bar changes size now: a look a second, a property read.
        statusWatch?.invalidate()
        statusWatch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.reportStatusBlock() }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        reportStatusBlock()
    }

    private func reportStatusBlock() {
        guard let web = webView, let frame = view.window?.windowScene?.statusBarManager?.statusBarFrame else { return }
        let bounds = view.window?.bounds ?? view.bounds
        let onRight = frame.width > 0 && frame.minX >= bounds.width / 2 && frame.height < bounds.height
        let h = onRight ? frame.maxY.rounded(.up) : 0
        guard h != statusBlock else { return }
        statusBlock = h
        web.evaluateJavaScript("document.documentElement.style.setProperty('--status-block','\(Int(h))px')")
    }

    /**
     * For the UI tests only (ios/App/AppUITests): launched with this argument, the app shows the
     * ids of the local notifications iOS holds for it, as a tiny label a test can read. A UI test
     * runs in its own process and cannot ask UNUserNotificationCenter about another app, and this
     * is what iOS really has pending, not what the page meant to schedule. Never shown otherwise:
     * nothing but XCUIApplication.launchArguments passes the argument.
     */
    static let pendingProbeArgument = "-OpenGymUITestPending"

    private func showPendingProbe() {
        // On the window, not inside the web view: what a WKWebView holds is its page as far as
        // accessibility goes, and a label among its subviews may never reach the test.
        guard let host = view.window else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showPendingProbe() }
            return
        }
        let label = UILabel()
        label.accessibilityIdentifier = "og-pending-notifications"
        label.font = .systemFont(ofSize: 8)
        label.textColor = .systemGray
        label.numberOfLines = 1
        label.isUserInteractionEnabled = false
        label.text = "pending:"
        label.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -2),
        ])
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak label] _ in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let ids = requests.map { $0.identifier }.sorted().joined(separator: ",")
                DispatchQueue.main.async {
                    guard let label = label else { return }
                    label.text = "pending:" + ids
                    label.accessibilityLabel = "pending:" + ids
                    label.superview?.bringSubviewToFront(label)
                }
            }
        }
    }
}
