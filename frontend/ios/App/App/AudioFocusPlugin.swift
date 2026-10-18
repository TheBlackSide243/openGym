import Foundation
import AVFoundation
import Capacitor

/**
 * Turns other apps' audio down while a timer sound plays, instead of stopping it (lib/sound.js).
 *
 * A web page can only ask for the 'playback' audio session to be heard on silent, and that one is
 * exclusive: the music app is paused and never told it may go on. The app itself can ask iOS to
 * duck it instead, for as long as the sound lasts, and to tell it to come back up afterwards.
 *
 *   duck()     the music turns down; sounds play even with the phone on silent
 *   release()  the music comes back up; the app no longer holds the audio
 */
@objc(AudioFocusPlugin)
public class AudioFocusPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AudioFocusPlugin"
    public let jsName = "AudioFocus"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "duck", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "release", returnType: CAPPluginReturnPromise),
    ]

    @objc func duck(_ call: CAPPluginCall) {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default, options: [.duckOthers])
            try s.setActive(true)
            call.resolve()
        } catch {
            call.reject(error.localizedDescription, "failed")
        }
    }

    @objc func release(_ call: CAPPluginCall) {
        let s = AVAudioSession.sharedInstance()
        // Inactive first, with the notice that lets the music app raise its volume again; then
        // back to a category that mixes, so an idle app never interrupts anything.
        try? s.setActive(false, options: [.notifyOthersOnDeactivation])
        try? s.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        call.resolve()
    }
}
