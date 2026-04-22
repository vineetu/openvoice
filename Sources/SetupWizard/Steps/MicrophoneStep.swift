import AVFoundation
import AppKit
import SwiftUI

struct MicrophoneStep: View {
    @EnvironmentObject private var coordinator: SetupWizardCoordinator
    @AppStorage("jot.inputDeviceUID") private var inputDeviceUID: String = ""
    @StateObject private var meter = InputLevelMeter()
    @StateObject private var deviceList = WizardInputDeviceWatcher()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pick your microphone")
                    .font(.system(size: 22, weight: .semibold))
                Text("Jot records from this device whenever you use the hotkey. Speak to see the level meter respond.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Input device:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("System default")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
                        .help("Custom input device selection is temporarily disabled — known bug. Jot follows your macOS Sound settings default for now; a fix is coming.")
                }
                Text("Custom device selection is temporarily disabled while we fix a bug — Jot follows your macOS Sound settings default for now.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Input level")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                LevelMeterView(level: meter.level)
                    .frame(height: 48)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            // Bug: custom device pinning records from the wrong device.
            // Force system default until fixed.
            inputDeviceUID = ""
            deviceList.refresh()
            meter.start()
            coordinator.setChrome(WizardStepChrome(
                primaryTitle: "Continue",
                canAdvance: true,
                isPrimaryBusy: false,
                showsSkip: true
            ))
        }
        .onDisappear { meter.stop() }
    }
}

// MARK: - Level meter

private struct LevelMeterView: View {
    let level: Float
    private let barCount = 10

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 4
            let barWidth = (geo.size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: index))
                        .frame(width: max(barWidth, 2), height: height(for: index, container: geo.size.height))
                        .animation(.easeOut(duration: 0.08), value: level)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func height(for index: Int, container: CGFloat) -> CGFloat {
        // Map the continuous level into 10 discrete bars: bar `i` lights once
        // the level crosses `(i + 1) / barCount`.
        let threshold = Float(index) / Float(barCount)
        let overshoot = max(0, min(1, (level - threshold) * Float(barCount)))
        let min = container * 0.15
        return min + CGFloat(overshoot) * (container - min)
    }

    private func color(for index: Int) -> Color {
        let fraction = Double(index) / Double(barCount - 1)
        if fraction > 0.85 { return .red }
        if fraction > 0.6 { return .orange }
        return .green
    }
}

@MainActor
private final class InputLevelMeter: ObservableObject {
    @Published var level: Float = 0

    private var engine: AVAudioEngine?
    private var timer: Timer?
    fileprivate var peak: Float = 0
    private var setupTask: Task<Void, Never>?

    func start() {
        guard engine == nil, setupTask == nil else { return }
        // Microphone permission is required to actually see meaningful values;
        // if it's not granted we still spin up the engine but the tap will
        // emit silence — the UI degrades to "bars sit idle" rather than
        // crashing. PermissionsStep is the gate; users reach this step only
        // after that (though Skip can bypass it).
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }

        // Decay timer runs regardless of engine state — bars sit idle at 0
        // if engine setup fails/times out (same UX as a silent mic).
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.peak *= 0.88
                self.level = min(1.0, self.peak)
            }
        }

        // CoreAudio-touching setup runs on a background GCD queue under a
        // 5s timeout. Accessing `engine.inputNode`, querying
        // `outputFormat`, `installTap`, and `engine.start()` can each block
        // indefinitely when `coreaudiod` is wedged (iOS Simulator hogging
        // hardware, Bluetooth glitch, sleep/wake race). Doing this inline
        // on @MainActor froze the wizard pane. Offloading keeps the UI
        // responsive — on timeout we log and the bars stay at 0 until the
        // user fixes coreaudiod (Help → Troubleshooting shows how).
        setupTask = Task { [weak self] in
            guard let meter = self else { return }
            let engine = await Self.configureMeterEngineWithTimeout(meter: meter, seconds: 5)
            meter.setupTask = nil
            guard !Task.isCancelled, meter.engine == nil else {
                // stop() ran before setup finished — tear down the orphan
                if let engine {
                    engine.inputNode.removeTap(onBus: 0)
                    engine.stop()
                }
                return
            }
            meter.engine = engine
        }
    }

    /// Mirrors `AudioCapture.configureEngineWithTimeout` — wraps all the
    /// CoreAudio-touching calls in a background-queue closure with a
    /// timeout so a wedged `coreaudiod` can't hang the main thread.
    /// Returns the running engine on success, `nil` on failure or timeout.
    private static func configureMeterEngineWithTimeout(
        meter: InputLevelMeter,
        seconds: Double
    ) async -> AVAudioEngine? {
        await withCheckedContinuation { (cont: CheckedContinuation<AVAudioEngine?, Never>) in
            let lock = NSLock()
            var hasResumed = false
            func resumeOnce(_ value: AVAudioEngine?) {
                lock.lock(); defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                cont.resume(returning: value)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let engine = AVAudioEngine()
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak meter] buffer, _ in
                    let frames = Int(buffer.frameLength)
                    guard frames > 0, let channel = buffer.floatChannelData?[0] else { return }
                    var maxAmp: Float = 0
                    for i in 0..<frames {
                        let v = abs(channel[i])
                        if v > maxAmp { maxAmp = v }
                    }
                    Task { @MainActor [weak meter] in
                        guard let meter else { return }
                        // Smooth decay so the bars don't flap violently.
                        meter.peak = Swift.max(maxAmp, meter.peak * 0.8)
                        meter.level = min(1.0, meter.peak)
                    }
                }

                do {
                    try engine.start()
                    resumeOnce(engine)
                } catch {
                    input.removeTap(onBus: 0)
                    Task { await ErrorLog.shared.warn(component: "SetupWizard", message: "Mic preview engine start failed", context: ["error": ErrorLog.redactedAppleError(error)]) }
                    resumeOnce(nil)
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                Task { await ErrorLog.shared.warn(component: "SetupWizard", message: "Mic preview engine setup timed out (>5s) — coreaudiod may be stuck; see Help → Troubleshooting") }
                resumeOnce(nil)
            }
        }
    }

    func stop() {
        setupTask?.cancel()
        setupTask = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        timer?.invalidate()
        timer = nil
        level = 0
        peak = 0
    }

    deinit {
        timer?.invalidate()
    }
}

@MainActor
private final class WizardInputDeviceWatcher: ObservableObject {
    @Published var devices: [AVCaptureDevice] = []

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        devices = session.devices
    }
}
