import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class PlayerOrientationController {
    private(set) var isLocked = false

    @ObservationIgnored private weak var host: UIViewController?
    @ObservationIgnored private weak var scene: UIWindowScene?
    @ObservationIgnored private var previousMask: UIInterfaceOrientationMask?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var didConsiderAutomaticRotation = false
    @ObservationIgnored private var videoSize: CGSize?
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var isForeground = false
    @ObservationIgnored private var pendingMask: UIInterfaceOrientationMask?
    @ObservationIgnored private var pendingDeadline: ContinuousClock.Instant?
    @ObservationIgnored private var requestID = UUID()

    func start() {
        isActive = true
        considerAutomaticRotation()
    }

    func attach(_ host: UIViewController) {
        guard let scene = host.view.window?.windowScene else { return }
        self.host = host
        self.scene = scene
        if previousMask == nil {
            previousMask = AppDelegate.orientationMask(for: scene)
        }
        if let pendingMask, let currentMask = mask(for: scene.interfaceOrientation),
           pendingMask.contains(currentMask)
        {
            self.pendingMask = nil
            pendingDeadline = nil
            if isLocked {
                AppDelegate.setOrientationMask(currentMask, for: scene)
                invalidateSupportedOrientations()
            }
        }
        considerAutomaticRotation()
    }

    func update(videoSize: CGSize?, enabled: Bool, isForeground: Bool) {
        self.videoSize = videoSize
        isEnabled = enabled
        self.isForeground = isForeground
        considerAutomaticRotation()
    }

    func stop() {
        isActive = false
        requestID = UUID()
        pendingMask = nil
        pendingDeadline = nil
        isLocked = false
        if let scene, let previousMask {
            AppDelegate.setOrientationMask(previousMask, for: scene)
            invalidateSupportedOrientations()
        }
        previousMask = nil
        didConsiderAutomaticRotation = false
    }

    func toggleLock() {
        guard isActive, let scene else { return }
        // A manual choice while media is loading must take precedence over the startup preference.
        didConsiderAutomaticRotation = true
        requestID = UUID()
        if isLocked {
            isLocked = false
            pendingMask = nil
            pendingDeadline = nil
            AppDelegate.setOrientationMask(previousMask ?? .all, for: scene)
            invalidateSupportedOrientations()
        } else {
            let mask: UIInterfaceOrientationMask
            if let pendingMask, let pendingDeadline, ContinuousClock.now < pendingDeadline {
                mask = pendingMask
            } else if let currentMask = self.mask(for: scene.interfaceOrientation) {
                mask = currentMask
            } else {
                return
            }
            let oldMask = AppDelegate.orientationMask(for: scene)
            isLocked = true
            AppDelegate.setOrientationMask(mask, for: scene)
            requestRotation(to: mask, restoringOnFailure: oldMask)
        }
    }

    private func considerAutomaticRotation() {
        guard isActive, isForeground, isEnabled,
              UIDevice.current.userInterfaceIdiom == .phone,
              !isLocked, !didConsiderAutomaticRotation,
              let scene, scene.activationState == .foregroundActive,
              let videoSize, videoSize.width > 0, videoSize.height > 0
        else { return }

        // Once per player presentation, including when the first video is portrait.
        didConsiderAutomaticRotation = true
        guard videoSize.width > videoSize.height, !scene.interfaceOrientation.isLandscape else { return }
        let allowedLandscape = AppDelegate.orientationMask(for: scene).intersection(.landscape)
        guard !allowedLandscape.isEmpty else { return }
        requestRotation(to: allowedLandscape)
    }

    private func requestRotation(
        to mask: UIInterfaceOrientationMask,
        restoringOnFailure previousMask: UIInterfaceOrientationMask? = nil,
    ) {
        guard let scene else { return }
        let id = UUID()
        requestID = id
        pendingMask = mask
        pendingDeadline = .now.advanced(by: .seconds(1))
        invalidateSupportedOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak self] error in
            Task { @MainActor in
                guard let self, self.isActive, self.requestID == id else { return }
                self.pendingMask = nil
                self.pendingDeadline = nil
                if let previousMask {
                    self.isLocked = false
                    AppDelegate.setOrientationMask(previousMask, for: scene)
                    self.invalidateSupportedOrientations()
                }
                ErrorReporter.capture(error)
            }
        }
    }

    private func invalidateSupportedOrientations() {
        var controller = host
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.parent
        }
        let windows = host?.view.window.map { [$0] } ?? scene?.windows ?? []
        for window in windows {
            controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
    }

    private func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask? {
        switch orientation {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: nil
        }
    }
}

struct PlayerOrientationHost: UIViewControllerRepresentable {
    let controller: PlayerOrientationController

    func makeUIViewController(context _: Context) -> OrientationViewController {
        OrientationViewController(controller: controller)
    }

    func updateUIViewController(_: OrientationViewController, context _: Context) {}

    final class OrientationViewController: UIViewController {
        private let controller: PlayerOrientationController

        init(controller: PlayerOrientationController) {
            self.controller = controller
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is unavailable")
        }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            controller.attach(self)
        }

        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                guard let self else { return }
                controller.attach(self)
            }
        }
    }
}
