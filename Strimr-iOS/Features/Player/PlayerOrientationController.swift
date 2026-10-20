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
    @ObservationIgnored private var pendingOrientation: UIInterfaceOrientation?
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
        if pendingOrientation == scene.interfaceOrientation {
            pendingOrientation = nil
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
        pendingOrientation = nil
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
            pendingOrientation = nil
            AppDelegate.setOrientationMask(previousMask ?? .all, for: scene)
            invalidateSupportedOrientations()
        } else {
            let orientation = pendingOrientation ?? scene.interfaceOrientation
            guard let mask = mask(for: orientation) else { return }
            let oldMask = AppDelegate.orientationMask(for: scene)
            isLocked = true
            AppDelegate.setOrientationMask(mask, for: scene)
            requestRotation(to: orientation, restoringOnFailure: oldMask)
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
        let target: UIInterfaceOrientation = UIDevice.current.orientation == .landscapeRight
            ? .landscapeLeft : .landscapeRight
        guard let targetMask = mask(for: target),
              AppDelegate.orientationMask(for: scene).contains(targetMask)
        else { return }
        requestRotation(to: target)
    }

    private func requestRotation(
        to orientation: UIInterfaceOrientation,
        restoringOnFailure previousMask: UIInterfaceOrientationMask? = nil,
    ) {
        guard let scene, let mask = mask(for: orientation) else { return }
        let id = UUID()
        requestID = id
        pendingOrientation = orientation
        invalidateSupportedOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                guard self.isActive, self.requestID == id else { return }
                self.pendingOrientation = nil
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
        guard let root = host?.view.window?.rootViewController else { return }
        root.setNeedsUpdateOfSupportedInterfaceOrientations()
        controller = root.presentedViewController
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.presentedViewController
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
