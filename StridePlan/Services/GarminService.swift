import ConnectIQ
import Foundation
import Observation

enum GarminStatus: Equatable {
    /// No watch chosen in Garmin Connect yet.
    case noWatch
    case bluetoothOff(watch: String)
    case disconnected(watch: String)
    /// `appInstalled` is nil until the watch has answered.
    case connected(watch: String, appInstalled: Bool?)

    var watchName: String? {
        switch self {
        case .noWatch: nil
        case .bluetoothOff(let name), .disconnected(let name), .connected(let name, _): name
        }
    }

    var isReady: Bool {
        if case .connected(_, let installed) = self { return installed != false }
        return false
    }
}

enum GarminEvent {
    /// The StridePlan app was opened on the watch and wants its workouts.
    case watchAppOpened
    case runReceived(GarminRun)
}

enum GarminError: LocalizedError {
    case noWatch
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWatch: "Connect a Garmin watch in Settings first."
        case .sendFailed(let reason): "Couldn't reach your watch (\(reason)). Make sure it's nearby and connected in Garmin Connect."
        }
    }
}

protocol GarminConnecting: AnyObject {
    var status: GarminStatus { get }
    /// Receives watch events. Events that arrive before a handler is set are held and delivered when it is.
    var onEvent: ((GarminEvent) -> Void)? { get set }
    /// Opens Garmin Connect to pick a watch. The choice comes back through `handleOpenURL`.
    func pairWatch()
    @discardableResult func handleOpenURL(_ url: URL) -> Bool
    func forgetWatch()
    func send(_ message: [String: Any]) async throws
    /// Asks the watch to show an "Open Kadence?" prompt.
    func promptToOpenWatchApp()
    func showWatchAppInStore()
}

/// Talks to the StridePlan Connect IQ app through Garmin's Connect IQ SDK (via the Garmin Connect app).
@Observable
final class GarminService: GarminConnecting {
    /// Garmin Connect returns the chosen watch to this URL scheme (registered in StridePlan-Info.plist).
    static let urlScheme = "strideplan-ciq"
    /// The watch app's id from `Garmin/manifest.xml`.
    static let watchAppID = UUID(uuidString: "6F1C2A8E-4B3D-4E59-9A7C-2D5E8B0F3C61")!

    private static let deviceKey = "garmin.device"

    private(set) var status: GarminStatus = .noWatch

    @ObservationIgnored var onEvent: ((GarminEvent) -> Void)? {
        didSet { flushEvents() }
    }

    @ObservationIgnored private var device: IQDevice?
    @ObservationIgnored private var app: IQApp?
    @ObservationIgnored private var assembler = GarminRunAssembler()
    @ObservationIgnored private var pendingEvents: [GarminEvent] = []
    @ObservationIgnored private let bridge = ConnectIQBridge()
    @ObservationIgnored private var isStarted = false
    private var sdk: ConnectIQ { ConnectIQ.sharedInstance() }

    init() {
        bridge.owner = self
        if let data = UserDefaults.standard.data(forKey: Self.deviceKey),
           let saved = try? NSKeyedUnarchiver.unarchivedObject(ofClass: IQDevice.self, from: data) {
            use(saved)
        }
    }

    /// The SDK starts Bluetooth when initialized, so it waits until the user has a watch to avoid an
    /// unexpected Bluetooth permission prompt.
    private func startSDK() {
        guard !isStarted else { return }
        isStarted = true
        sdk.initialize(withUrlScheme: Self.urlScheme, uiOverrideDelegate: bridge)
    }

    // MARK: Pairing

    func pairWatch() {
        startSDK()
        sdk.showDeviceSelection()
    }

    func handleOpenURL(_ url: URL) -> Bool {
        guard url.scheme == Self.urlScheme else { return false }
        startSDK()
        let devices = (sdk.parseDeviceSelectionResponse(from: url) as? [IQDevice]) ?? []
        guard let chosen = devices.first else { return true }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: chosen, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: Self.deviceKey)
        }
        use(chosen)
        return true
    }

    func forgetWatch() {
        guard isStarted else { return }
        sdk.unregister(forAllDeviceEvents: bridge)
        sdk.unregister(forAllAppMessages: bridge)
        UserDefaults.standard.removeObject(forKey: Self.deviceKey)
        device = nil
        app = nil
        status = .noWatch
    }

    private func use(_ newDevice: IQDevice) {
        startSDK()
        sdk.unregister(forAllDeviceEvents: bridge)
        sdk.unregister(forAllAppMessages: bridge)
        device = newDevice
        let watchApp = IQApp(uuid: Self.watchAppID, store: Self.watchAppID, device: newDevice)
        app = watchApp
        sdk.register(forDeviceEvents: newDevice, delegate: bridge)
        sdk.register(forAppMessages: watchApp, delegate: bridge)
        deviceStatusChanged(newDevice, status: sdk.getDeviceStatus(newDevice))
    }

    // MARK: SDK callbacks

    fileprivate func deviceStatusChanged(_ changed: IQDevice, status newStatus: IQDeviceStatus) {
        guard let device, changed.uuid == device.uuid else { return }
        let name = device.friendlyName ?? device.modelName ?? "Garmin watch"
        switch newStatus {
        case .connected:
            status = .connected(watch: name, appInstalled: nil)
            checkAppInstalled(name: name)
        case .bluetoothNotReady:
            status = .bluetoothOff(watch: name)
        default:
            status = .disconnected(watch: name)
        }
    }

    private func checkAppInstalled(name: String) {
        guard let app else { return }
        sdk.getAppStatus(app) { [weak self] appStatus in
            DispatchQueue.main.async {
                guard let self, case .connected = self.status else { return }
                self.status = .connected(watch: name, appInstalled: appStatus?.isInstalled ?? false)
            }
        }
    }

    fileprivate func received(_ message: Any) {
        guard let incoming = GarminProtocol.parse(message) else {
            print("[Garmin] ignored message: \(message)")
            return
        }
        if case .hello = incoming {
            // The app is evidently installed, even if the status check said otherwise.
            if case .connected(let name, _) = status { status = .connected(watch: name, appInstalled: true) }
            emit(.watchAppOpened)
        } else if let run = assembler.receive(incoming) {
            emit(.runReceived(run))
        }
    }

    private func emit(_ event: GarminEvent) {
        pendingEvents.append(event)
        flushEvents()
    }

    private func flushEvents() {
        guard let onEvent else { return }
        let events = pendingEvents
        pendingEvents = []
        events.forEach(onEvent)
    }

    // MARK: Sending

    func send(_ message: [String: Any]) async throws {
        guard let app else { throw GarminError.noWatch }
        let result: IQSendMessageResult = await withCheckedContinuation { continuation in
            sdk.sendMessage(message, to: app, progress: nil) { result in
                continuation.resume(returning: result)
            }
        }
        guard result == .success else {
            throw GarminError.sendFailed(NSStringFromSendMessageResult(result) ?? "error \(result.rawValue)")
        }
    }

    func promptToOpenWatchApp() {
        guard let app else { return }
        sdk.openAppRequest(app) { _ in }
    }

    func showWatchAppInStore() {
        guard let app else { return }
        sdk.showStore(for: app)
    }
}

/// The SDK's delegates are Objective-C protocols, so they live on an NSObject that forwards to the service.
private final class ConnectIQBridge: NSObject, IQUIOverrideDelegate, IQDeviceEventDelegate, IQAppMessageDelegate {
    weak var owner: GarminService?

    func needsToInstallConnectMobile() {
        ConnectIQ.sharedInstance().showAppStoreForConnectMobile()
    }

    func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        guard let device else { return }
        DispatchQueue.main.async { self.owner?.deviceStatusChanged(device, status: status) }
    }

    func receivedMessage(_ message: Any!, from app: IQApp!) {
        guard let message else { return }
        DispatchQueue.main.async { self.owner?.received(message) }
    }
}

final class MockGarminService: GarminConnecting {
    var status: GarminStatus = .noWatch
    var onEvent: ((GarminEvent) -> Void)?
    private(set) var sentMessages: [[String: Any]] = []

    func pairWatch() { status = .connected(watch: "Forerunner 265", appInstalled: true) }
    func handleOpenURL(_ url: URL) -> Bool { false }
    func forgetWatch() { status = .noWatch }
    func send(_ message: [String: Any]) async throws { sentMessages.append(message) }
    func promptToOpenWatchApp() {}
    func showWatchAppInStore() {}
}
