@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import os.log

/// Errors surfaced by `AudioCapture` when the capture path fails in a
/// way the caller needs to distinguish. Device/driver errors are wrapped
/// rather than swallowed so `RecorderController` can render a message.
public enum AudioCaptureError: Error, Sendable {
    case alreadyRunning
    case notRunning
    case converterUnavailable
    case engineStart(Error)
    case engineStartTimeout
    case fileCreate(Error)
    case conversion(Error)

    /// User-facing message shown when we detect the CoreAudio subsystem is
    /// wedged. Callers that surface `engineStartTimeout` should show this
    /// as-is (no "Could not start recording:" prefix) and leave the
    /// follow-up instructions to the Help → Troubleshooting card.
    public static let engineStartTimeoutMessage =
        "Audio system isn't responding — see Help → Troubleshooting."
}

/// Direct CoreAudio AUHAL (`kAudioUnitSubType_HALOutput`) capture path.
///
/// This mirrors `mic-test/variant-4-coreaudio-auhal/Source/Recorder.swift`
/// at the AUHAL boundary, with one Jot-specific addition: rendered
/// device-rate Float32 mono buffers are converted on a dedicated writer
/// queue to `AudioFormat.target` before being appended to memory and WAV.
public actor AudioCapture: AudioCapturing {
    private let log = Logger(subsystem: "com.jot.Jot", category: "AudioCapture")

    nonisolated(unsafe) public weak var amplitudePublisher: AmplitudePublisher?

    private var unit: AudioUnit?
    private var renderABL: UnsafeMutablePointer<AudioBufferList>?
    private var renderBytes: UnsafeMutableRawPointer?
    private var maxFrames: UInt32 = 0
    private var fileURL: URL?
    private var startedAt: Date?
    private var ctx: CallbackContext?
    private var attempt: SetupAttempt?
    private var cancelRequestedDuringSetup = false

    private let recordingsDirectory: URL
    private let writerQueue = DispatchQueue(label: "com.jot.AudioCapture.writer", qos: .userInitiated)
    private let outstandingLock = OSAllocatedUnfairLock(initialState: 0)
    private static let outstandingLimit = 64

    public init(recordingsDirectory: URL = AudioCapture.defaultRecordingsDirectory) {
        self.recordingsDirectory = recordingsDirectory
    }

    public func setAmplitudePublisher(_ publisher: AmplitudePublisher?) {
        amplitudePublisher = publisher
    }

    /// `~/Library/Application Support/Jot/Recordings/`. Kept identical to
    /// `AudioCapture` so callers see the same on-disk recording location.
    public static var defaultRecordingsDirectory: URL {
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("Jot/Recordings", isDirectory: true)
    }

    // MARK: - Start / Stop

    public func start() async throws {
        guard unit == nil, attempt == nil else { throw AudioCaptureError.alreadyRunning }

        try FileManager.default.createDirectory(
            at: recordingsDirectory,
            withIntermediateDirectories: true
        )

        let url = recordingsDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        let selectedUID = UserDefaults.standard.string(forKey: "jot.inputDeviceUID") ?? ""
        let publisher = amplitudePublisher
        let setupAttempt = SetupAttempt()
        setupAttempt.fileURL = url
        attempt = setupAttempt
        cancelRequestedDuringSetup = false
        defer {
            attempt = nil
            cancelRequestedDuringSetup = false
        }

        let setup: AUHALSetup
        do {
            setup = try await Self.configureAUHALWithTimeout(
                attempt: setupAttempt,
                selectedUID: selectedUID,
                url: url,
                amplitudePublisher: publisher,
                writerQueue: writerQueue,
                outstandingLock: outstandingLock,
                log: log,
                seconds: 5
            )
        } catch {
            try? FileManager.default.removeItem(at: url)
            if cancelRequestedDuringSetup || Task.isCancelled {
                throw CancellationError()
            }
            switch error {
            case AudioCaptureError.engineStartTimeout:
                Task { await ErrorLog.shared.error(component: "AudioCapture", message: "AUHAL setup timed out (>5s) — coreaudiod may be stuck; see Help → Troubleshooting") }
            case AudioCaptureError.engineStart(let inner):
                Task { await ErrorLog.shared.error(component: "AudioCapture", message: "AUHAL start failed", context: ["error": ErrorLog.redactedAppleError(inner)]) }
            case AudioCaptureError.fileCreate(let inner):
                Task { await ErrorLog.shared.error(component: "AudioCapture", message: "Recording file create failed", context: ["error": ErrorLog.redactedAppleError(inner)]) }
            case AudioCaptureError.converterUnavailable:
                Task { await ErrorLog.shared.error(component: "AudioCapture", message: "AVAudioConverter unavailable") }
            default:
                Task { await ErrorLog.shared.error(component: "AudioCapture", message: "AUHAL setup failed", context: ["error": ErrorLog.redactedAppleError(error)]) }
            }
            throw error
        }

        if cancelRequestedDuringSetup || Task.isCancelled {
            disposeCommittedSetup(setup, deleteFile: true)
            throw CancellationError()
        }

        unit = setup.unit
        renderABL = setup.renderABL
        renderBytes = setup.renderBytes
        maxFrames = setup.maxFrames
        fileURL = setup.fileURL
        startedAt = Date()
        ctx = setup.ctx
    }

    public func stop() async throws -> AudioRecording {
        guard let activeUnit = unit,
              let context = ctx,
              let url = fileURL,
              let startedAt
        else {
            throw AudioCaptureError.notRunning
        }

        context.markStopping()
        AudioOutputUnitStop(activeUnit)
        AudioUnitUninitialize(activeUnit)
        AudioComponentInstanceDispose(activeUnit)

        let captured = writerQueue.sync {
            let snapshot = context.queueState.samples
            context.queueState.audioFile = nil
            context.queueState.converter = nil
            context.queueState.samples.removeAll(keepingCapacity: false)
            return snapshot
        }

        freeRenderBuffers()
        resetState()

        let publisher = amplitudePublisher
        Task { @MainActor [weak publisher] in
            publisher?.reset()
        }

        return AudioRecording(
            samples: captured,
            fileURL: url,
            duration: TimeInterval(captured.count) / AudioFormat.sampleRate,
            createdAt: startedAt
        )
    }

    public func cancel() {
        if unit == nil, attempt != nil {
            cancelRequestedDuringSetup = true
            if let url = attempt?.fileURL {
                try? FileManager.default.removeItem(at: url)
            }
            let publisher = amplitudePublisher
            Task { @MainActor [weak publisher] in
                publisher?.reset()
            }
            return
        }

        if let activeUnit = unit {
            ctx?.markStopping()
            AudioOutputUnitStop(activeUnit)
            AudioUnitUninitialize(activeUnit)
            AudioComponentInstanceDispose(activeUnit)
        }

        if let context = ctx {
            writerQueue.sync {
                context.queueState.audioFile = nil
                context.queueState.converter = nil
                context.queueState.samples.removeAll(keepingCapacity: false)
            }
        }

        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }

        freeRenderBuffers()
        resetState()

        let publisher = amplitudePublisher
        Task { @MainActor [weak publisher] in
            publisher?.reset()
        }
    }

    private func disposeCommittedSetup(_ setup: AUHALSetup, deleteFile: Bool) {
        setup.ctx.markStopping()
        AudioOutputUnitStop(setup.unit)
        AudioUnitUninitialize(setup.unit)
        AudioComponentInstanceDispose(setup.unit)
        writerQueue.sync {
            setup.ctx.queueState.audioFile = nil
            setup.ctx.queueState.converter = nil
            setup.ctx.queueState.samples.removeAll(keepingCapacity: false)
        }
        setup.renderABL.deallocate()
        setup.renderBytes.deallocate()
        if deleteFile {
            try? FileManager.default.removeItem(at: setup.fileURL)
        }
    }

    private func freeRenderBuffers() {
        renderABL?.deallocate()
        renderBytes?.deallocate()
    }

    private func resetState() {
        unit = nil
        renderABL = nil
        renderBytes = nil
        maxFrames = 0
        fileURL = nil
        startedAt = nil
        ctx = nil
    }

    // MARK: - AUHAL setup

    private struct AUHALSetup: @unchecked Sendable {
        let unit: AudioUnit
        let renderABL: UnsafeMutablePointer<AudioBufferList>
        let renderBytes: UnsafeMutableRawPointer
        let maxFrames: UInt32
        let fileURL: URL
        let ctx: CallbackContext
    }

    private static func configureAUHALWithTimeout(
        attempt: SetupAttempt,
        selectedUID: String,
        url: URL,
        amplitudePublisher: AmplitudePublisher?,
        writerQueue: DispatchQueue,
        outstandingLock: OSAllocatedUnfairLock<Int>,
        log: Logger,
        seconds: Double
    ) async throws -> AUHALSetup {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AUHALSetup, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                func fail(_ error: Error) {
                    attempt.dispose(writerQueue: writerQueue)
                    if attempt.tryAbandon() {
                        cont.resume(throwing: error)
                    }
                }

                // 1. Find the AUHAL component.
                var desc = AudioComponentDescription(
                    componentType: kAudioUnitType_Output,
                    componentSubType: kAudioUnitSubType_HALOutput,
                    componentManufacturer: kAudioUnitManufacturer_Apple,
                    componentFlags: 0,
                    componentFlagsMask: 0
                )
                guard let comp = AudioComponentFindNext(nil, &desc) else {
                    log.error("AudioComponentFindNext returned nil for HALOutput")
                    fail(AudioCaptureError.engineStart(Self.osStatusError(OSStatus(paramErr))))
                    return
                }
                var newUnit: AudioUnit?
                var status = AudioComponentInstanceNew(comp, &newUnit)
                guard status == noErr, let u = newUnit else {
                    log.error("AudioComponentInstanceNew failed: \(status, privacy: .public)")
                    fail(AudioCaptureError.engineStart(Self.osStatusError(status)))
                    return
                }
                attempt.unit = u

                // 2. Enable input scope (bus 1), disable output scope (bus 0).
                var on: UInt32 = 1
                var off: UInt32 = 0
                status = AudioUnitSetProperty(
                    u,
                    kAudioOutputUnitProperty_EnableIO,
                    kAudioUnitScope_Input,
                    1,
                    &on,
                    UInt32(MemoryLayout<UInt32>.size)
                )
                if status != noErr {
                    log.error("EnableIO(input) failed: \(status, privacy: .public)")
                    fail(AudioCaptureError.engineStart(Self.osStatusError(status)))
                    return
                }
                status = AudioUnitSetProperty(
                    u,
                    kAudioOutputUnitProperty_EnableIO,
                    kAudioUnitScope_Output,
                    0,
                    &off,
                    UInt32(MemoryLayout<UInt32>.size)
                )
                if status != noErr {
                    log.error("EnableIO(output, off) failed: \(status, privacy: .public)")
                    fail(AudioCaptureError.engineStart(Self.osStatusError(status)))
                    return
                }

                // 3. Resolve and bind the device.
                var devID: AudioDeviceID = 0
                if !selectedUID.isEmpty {
                    if let resolved = Self.audioDeviceID(forUID: selectedUID) {
                        devID = resolved
                        log.info("Resolved UID \(selectedUID, privacy: .public) → AudioDeviceID=\(devID, privacy: .public)")
                    } else {
                        log.error("Could not resolve UID \(selectedUID, privacy: .public); falling back to system default")
                        devID = Self.systemDefaultInputDevice() ?? 0
                    }
                } else {
                    devID = Self.systemDefaultInputDevice() ?? 0
                    log.info("Using system default input AudioDeviceID=\(devID, privacy: .public)")
                }
                guard devID != 0 else {
                    log.error("No input device available")
                    fail(AudioCaptureError.engineStart(Self.osStatusError(kAudioHardwareBadDeviceError)))
                    return
                }

                status = AudioUnitSetProperty(
                    u,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &devID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                if status != noErr {
                    if !selectedUID.isEmpty,
                       let fallbackID = Self.systemDefaultInputDevice(),
                       fallbackID != 0,
                       fallbackID != devID {
                        log.warning("CurrentDevice set failed for selected UID; falling back to system default: \(status, privacy: .public)")
                        devID = fallbackID
                        status = AudioUnitSetProperty(
                            u,
                            kAudioOutputUnitProperty_CurrentDevice,
                            kAudioUnitScope_Global,
                            0,
                            &devID,
                            UInt32(MemoryLayout<AudioDeviceID>.size)
                        )
                    }
                    if status != noErr {
                        log.error("CurrentDevice set failed: \(status, privacy: .public)")
                        fail(AudioCaptureError.engineStart(Self.osStatusError(status)))
                        return
                    }
                }

                // 4. Read the device's native ASBD on input scope, element 1.
                var deviceASBD = AudioStreamBasicDescription()
                var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                status = AudioUnitGetProperty(
                    u,
                    kAudioUnitProperty_StreamFormat,
                    kAudioUnitScope_Input,
                    1,
                    &deviceASBD,
                    &asbdSize
                )
                if status != noErr {
                    log.error("Get device StreamFormat failed: \(status, privacy: .public)")
                    fail(AudioCaptureError.engineStart(Self.osStatusError(status)))
                    return
                }
                log.info("Device input ASBD: sr=\(deviceASBD.mSampleRate, privacy: .public) ch=\(deviceASBD.mChannelsPerFrame, privacy: .public) fmtFlags=\(deviceASBD.mFormatFlags, privacy: .public)")

                guard deviceASBD.mSampleRate > 0 else {
                    log.error("Device reports sample rate 0 — aborting")
                    fail(AudioCaptureError.engineStart(Self.osStatusError(kAudio_ParamError)))
                    return
                }

                // 5. Set client ASBD on **output** scope, element 1 — mono
                // Float32 packed at the device's sample rate. AUHAL down-mixes.
                var clientASBD = AudioStreamBasicDescription(
                    mSampleRate: deviceASBD.mSampleRate,
                    mFormatID: kAudioFormatLinearPCM,
                    mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                    mBytesPerPacket: 4,
                    mFramesPerPacket: 1,
                    mBytesPerFrame: 4,
                    mChannelsPerFrame: 1,
                    mBitsPerChannel: 32,
                    mReserved: 0
                )
                status = AudioUnitSetProperty(
                    u,
                    kAudioUnitProperty_StreamFormat,
                    kAudioUnitScope_Output,
                    1,
                    &clientASBD,
                    UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                )
                if status != noErr {
                    log.error("Set client StreamFormat failed: \(status, privacy: .public)")
                    fail(AudioCaptureError.engineStart(Self.osStatusError(status)))
                    return
                }

                let formatString = "device sr=\(Int(deviceASBD.mSampleRate)) ch=\(deviceASBD.mChannelsPerFrame) → client sr=\(Int(clientASBD.mSampleRate)) ch=1 Float32"
                log.info("Client render ASBD: \(formatString, privacy: .public)")

                // 6. Determine the maximum frames-per-slice the unit will
                // deliver. Match variant 4's 4096 floor.
                var slice: UInt32 = 4096
                var sliceSize = UInt32(MemoryLayout<UInt32>.size)
                let sliceStatus = AudioUnitGetProperty(
                    u,
                    kAudioUnitProperty_MaximumFramesPerSlice,
                    kAudioUnitScope_Global,
                    0,
                    &slice,
                    &sliceSize
                )
                let chosenMaxFrames: UInt32 = (sliceStatus == noErr && slice > 0)
                    ? max(slice, 4096)
                    : 4096
                log.info("MaximumFramesPerSlice=\(chosenMaxFrames, privacy: .public)")

                // 7. Build the AVAudioFormat used to wrap rendered chunks.
                guard let avFmt = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: clientASBD.mSampleRate,
                    channels: 1,
                    interleaved: false
                ) else {
                    log.error("Could not build AVAudioFormat for client ASBD")
                    fail(AudioCaptureError.engineStart(Self.osStatusError(kAudio_ParamError)))
                    return
                }

                // 8. Pre-allocate the render AudioBufferList and its backing
                // bytes. Mono Float32 packed -> 4 bytes per frame.
                let bytesPerFrame: UInt32 = 4
                let bufferCapacity = Int(chosenMaxFrames * bytesPerFrame)
                let bytes = UnsafeMutableRawPointer.allocate(
                    byteCount: bufferCapacity,
                    alignment: MemoryLayout<Float>.alignment
                )
                let abl = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
                abl.pointee.mNumberBuffers = 1
                abl.pointee.mBuffers.mNumberChannels = 1
                abl.pointee.mBuffers.mDataByteSize = UInt32(bufferCapacity)
                abl.pointee.mBuffers.mData = bytes
                attempt.renderABL = abl
                attempt.renderBytes = bytes

                // 9. Open the WAV file and converter at Jot's target format.
                let audioFile: AVAudioFile
                do {
                    audioFile = try AVAudioFile(
                        forWriting: url,
                        settings: AudioFormat.target.settings,
                        commonFormat: .pcmFormatFloat32,
                        interleaved: false
                    )
                } catch {
                    log.error("AVAudioFile init failed: \(error.localizedDescription, privacy: .public)")
                    fail(AudioCaptureError.fileCreate(error))
                    return
                }

                guard let converter = AVAudioConverter(from: avFmt, to: AudioFormat.target) else {
                    log.error("AVAudioConverter unavailable")
                    fail(AudioCaptureError.converterUnavailable)
                    return
                }

                // 10. Build the callback context. Heap-allocated so its
                // address is stable for the refcon's lifetime.
                let queueState = QueueState()
                queueState.audioFile = audioFile
                queueState.converter = converter
                let context = CallbackContext(
                    unit: u,
                    renderABL: abl,
                    renderBytes: bytes,
                    maxFrames: chosenMaxFrames,
                    avFormat: avFmt,
                    amplitudePublisher: amplitudePublisher,
                    writerQueue: writerQueue,
                    outstandingLock: outstandingLock,
                    outstandingLimit: Self.outstandingLimit,
                    log: log,
                    queueState: queueState
                )
                attempt.ctx = context

                // 11. Wire the input callback. Pass the box as the refcon.
                var cb = AURenderCallbackStruct(
                    inputProc: audioCaptureAUHALInputCallback,
                    inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())
                )
                status = AudioUnitSetProperty(
                    u,
                    kAudioOutputUnitProperty_SetInputCallback,
                    kAudioUnitScope_Global,
                    0,
                    &cb,
                    UInt32(MemoryLayout<AURenderCallbackStruct>.size)
                )
                if status != noErr {
                    log.error("SetInputCallback failed: \(status, privacy: .public)")
                    fail(AudioCaptureError.engineStart(Self.osStatusError(status)))
                    return
                }

                // 12. Initialize and start.
                status = AudioUnitInitialize(u)
                if status != noErr {
                    log.error("AudioUnitInitialize failed: \(status, privacy: .public)")
                    fail(AudioCaptureError.engineStart(Self.osStatusError(status)))
                    return
                }

                status = AudioOutputUnitStart(u)
                if status != noErr {
                    log.error("AudioOutputUnitStart failed: \(status, privacy: .public)")
                    fail(AudioCaptureError.engineStart(Self.osStatusError(status)))
                    return
                }

                let setup = AUHALSetup(
                    unit: u,
                    renderABL: abl,
                    renderBytes: bytes,
                    maxFrames: chosenMaxFrames,
                    fileURL: url,
                    ctx: context
                )

                if attempt.tryCommit() {
                    cont.resume(returning: setup)
                } else {
                    attempt.dispose(writerQueue: writerQueue)
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                if attempt.tryAbandon() {
                    cont.resume(throwing: AudioCaptureError.engineStartTimeout)
                }
            }
        }
    }

    // MARK: - CoreAudio helpers

    private static func osStatusError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }

    private static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &dataSize
        ) == noErr else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBytes { raw in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &addr, 0, nil, &dataSize,
                raw.baseAddress!
            )
        }
        guard status == noErr else { return nil }

        for id in ids {
            if let candidate = stringProperty(id, selector: kAudioDevicePropertyDeviceUID),
               candidate == uid {
                return id
            }
        }
        return nil
    }

    private static func systemDefaultInputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &devID
        )
        guard status == noErr, devID != 0 else { return nil }
        return devID
    }

    private static func stringProperty(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cfStr: CFString? = nil
        let status = withUnsafeMutablePointer(to: &cfStr) { ptr -> OSStatus in
            ptr.withMemoryRebound(to: UInt8.self, capacity: Int(size)) { _ in
                AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, ptr)
            }
        }
        guard status == noErr, let s = cfStr else { return nil }
        return s as String
    }
}

// MARK: - Callback state

/// Touched only by blocks dispatched onto `writerQueue`.
fileprivate final class QueueState: @unchecked Sendable {
    var samples: [Float] = []
    var audioFile: AVAudioFile?
    var converter: AVAudioConverter?
}

/// Holds everything the C input callback needs without crossing actor
/// isolation. Mutable audio state lives in `queueState` and is touched only
/// on `writerQueue`.
fileprivate final class CallbackContext: @unchecked Sendable {
    let unit: AudioUnit
    let renderABL: UnsafeMutablePointer<AudioBufferList>
    let renderBytes: UnsafeMutableRawPointer
    let maxFrames: UInt32
    let avFormat: AVAudioFormat
    weak var amplitudePublisher: AmplitudePublisher?
    let writerQueue: DispatchQueue
    let outstandingLock: OSAllocatedUnfairLock<Int>
    let outstandingLimit: Int
    let log: Logger
    let queueState: QueueState
    private let stopLock = OSAllocatedUnfairLock(initialState: false)
    private let droppedLock = OSAllocatedUnfairLock(initialState: 0)

    init(
        unit: AudioUnit,
        renderABL: UnsafeMutablePointer<AudioBufferList>,
        renderBytes: UnsafeMutableRawPointer,
        maxFrames: UInt32,
        avFormat: AVAudioFormat,
        amplitudePublisher: AmplitudePublisher?,
        writerQueue: DispatchQueue,
        outstandingLock: OSAllocatedUnfairLock<Int>,
        outstandingLimit: Int,
        log: Logger,
        queueState: QueueState
    ) {
        self.unit = unit
        self.renderABL = renderABL
        self.renderBytes = renderBytes
        self.maxFrames = maxFrames
        self.avFormat = avFormat
        self.amplitudePublisher = amplitudePublisher
        self.writerQueue = writerQueue
        self.outstandingLock = outstandingLock
        self.outstandingLimit = outstandingLimit
        self.log = log
        self.queueState = queueState
    }

    func markStopping() {
        stopLock.withLock { $0 = true }
    }

    func isStoppingNow() -> Bool {
        stopLock.withLock { $0 }
    }

    func incrementDropped() -> Int {
        droppedLock.withLock {
            $0 += 1
            return $0
        }
    }
}

/// Coordinates setup timeout with late-success cleanup. Timeout abandons the
/// attempt but never disposes live CoreAudio memory; the background setup
/// queue owns disposal once setup eventually exits.
fileprivate final class SetupAttempt: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: ())
    var unit: AudioUnit?
    var ctx: CallbackContext?
    var renderABL: UnsafeMutablePointer<AudioBufferList>?
    var renderBytes: UnsafeMutableRawPointer?
    var fileURL: URL?
    private var isCommitted = false
    private var isAbandoned = false

    func tryCommit() -> Bool {
        lock.withLock {
            guard !isCommitted, !isAbandoned else { return false }
            isCommitted = true
            return true
        }
    }

    func tryAbandon() -> Bool {
        lock.withLock {
            guard !isCommitted, !isAbandoned else { return false }
            isAbandoned = true
            return true
        }
    }

    func dispose(writerQueue: DispatchQueue) {
        ctx?.markStopping()
        if let activeUnit = unit {
            AudioOutputUnitStop(activeUnit)
            AudioUnitUninitialize(activeUnit)
            AudioComponentInstanceDispose(activeUnit)
            unit = nil
        }
        if let context = ctx {
            writerQueue.sync {
                context.queueState.audioFile = nil
                context.queueState.converter = nil
                context.queueState.samples.removeAll(keepingCapacity: false)
            }
            ctx = nil
        } else {
            writerQueue.sync {}
        }
        renderABL?.deallocate()
        renderABL = nil
        renderBytes?.deallocate()
        renderBytes = nil
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
            fileURL = nil
        }
    }
}

// MARK: - C input callback trampoline

/// AUHAL input callback. Called on a CoreAudio real-time thread.
///
/// Per Apple TN2091, an input callback's job is to call `AudioUnitRender`
/// to pull freshly-captured samples into the callback-supplied buffer list.
private func audioCaptureAUHALInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let ctx = Unmanaged<CallbackContext>.fromOpaque(inRefCon).takeUnretainedValue()
    guard !ctx.isStoppingNow() else { return noErr }

    // Reset the available capacity hint each call: AudioUnitRender wants
    // mDataByteSize set to how much room our buffer can hold.
    let capacity = ctx.maxFrames * 4   // mono Float32 = 4 B/frame
    ctx.renderABL.pointee.mBuffers.mDataByteSize = capacity

    let renderStatus = AudioUnitRender(
        ctx.unit,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        ctx.renderABL
    )
    if renderStatus != noErr {
        ctx.log.error("AudioUnitRender failed: \(renderStatus, privacy: .public)")
        Task { await ErrorLog.shared.error(component: "AudioCapture", message: "AudioUnitRender failed", context: ["status": "\(renderStatus)"]) }
        return renderStatus
    }

    // Wrap the rendered samples in a fresh AVAudioPCMBuffer so the meter,
    // converter, and writer operate on the same Float32 mono shape.
    guard inNumberFrames > 0,
          let bytes = ctx.renderABL.pointee.mBuffers.mData,
          let scratch = AVAudioPCMBuffer(pcmFormat: ctx.avFormat, frameCapacity: inNumberFrames)
    else {
        return noErr
    }
    scratch.frameLength = inNumberFrames
    if let dst = scratch.floatChannelData?[0] {
        let byteCount = Int(inNumberFrames) * MemoryLayout<Float>.size
        memcpy(dst, bytes, byteCount)
    }

    let level = AmplitudePublisher.rms(from: scratch)
    Task { @MainActor [weak publisher = ctx.amplitudePublisher] in
        publisher?.append(rms: level)
    }

    // Backpressure check.
    let outstanding = ctx.outstandingLock.withLock { $0 }
    if outstanding > ctx.outstandingLimit {
        let dropped = ctx.incrementDropped()
        if dropped == 1 || dropped.isMultiple(of: 64) {
            ctx.log.error("Dropping AUHAL buffer; writerQueue outstanding=\(outstanding, privacy: .public) dropped=\(dropped, privacy: .public)")
        }
        return noErr
    }

    ctx.outstandingLock.withLock { $0 += 1 }
    let lockRef = ctx.outstandingLock
    let queueState = ctx.queueState
    let log = ctx.log
    let sourceFormat = ctx.avFormat
    ctx.writerQueue.async {
        defer { lockRef.withLock { $0 -= 1 } }
        convertAndWrite(
            scratch,
            sourceFormat: sourceFormat,
            queueState: queueState,
            log: log
        )
    }

    return noErr
}

private func convertAndWrite(
    _ buffer: AVAudioPCMBuffer,
    sourceFormat: AVAudioFormat,
    queueState: QueueState,
    log: Logger
) {
    guard let audioFile = queueState.audioFile,
          let converter = queueState.converter
    else {
        return
    }

    let ratio = AudioFormat.sampleRate / sourceFormat.sampleRate
    let estimatedFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
    guard
        let outBuffer = AVAudioPCMBuffer(
            pcmFormat: AudioFormat.target,
            frameCapacity: estimatedFrames
        )
    else {
        log.error("Failed to allocate AUHAL conversion output buffer")
        return
    }

    var suppliedOnce = false
    var error: NSError?
    let status = converter.convert(to: outBuffer, error: &error) { _, inputStatus in
        if suppliedOnce {
            inputStatus.pointee = .noDataNow
            return nil
        }
        suppliedOnce = true
        inputStatus.pointee = .haveData
        return buffer
    }

    switch status {
    case .error:
        if let error {
            log.error("AUHAL AudioConverter error: \(error.localizedDescription)")
        } else {
            log.error("AUHAL AudioConverter error")
        }
        return
    case .inputRanDry, .haveData, .endOfStream:
        break
    @unknown default:
        break
    }

    let frameCount = Int(outBuffer.frameLength)
    guard frameCount > 0, let channelData = outBuffer.floatChannelData else { return }

    let channelPtr = channelData[0]
    queueState.samples.append(contentsOf: UnsafeBufferPointer(start: channelPtr, count: frameCount))

    do {
        try audioFile.write(from: outBuffer)
    } catch {
        log.error("AUHAL AVAudioFile write failed: \(error.localizedDescription)")
    }
}
