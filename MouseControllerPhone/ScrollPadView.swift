import SwiftUI
import UIKit

struct TouchPadView: UIViewRepresentable {

    enum SwipeDirection {
        case up, down, left, right
    }

    /// dx, dy in points, plus finger speed in points per second.
    let onMove: (CGFloat, CGFloat, CGFloat) -> Void
    let onClick: () -> Void
    let onDoubleClick: () -> Void
    let onRightClick: () -> Void
    /// dx, dy in points.
    let onScroll: (CGFloat, CGFloat) -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void
    let onThreeFingerSwipe: (SwipeDirection) -> Void
    /// true to zoom in, false to zoom out.
    let onPinch: (Bool) -> Void

    func makeUIView(context: Context) -> TouchSurfaceView {
        let view = TouchSurfaceView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.rippleColor = Theme.accentUIColor

        // A new touch stops any momentum scroll, like a real trackpad.
        view.onTouchDown = { [weak coordinator = context.coordinator] in
            coordinator?.stopMomentum()
        }

        let coordinator = context.coordinator

        let oneFingerPan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleOneFingerPan))
        oneFingerPan.minimumNumberOfTouches = 1
        oneFingerPan.maximumNumberOfTouches = 1

        let twoFingerPan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTwoFingerPan))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2

        let threeFingerPan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleThreeFingerPan))
        threeFingerPan.minimumNumberOfTouches = 3
        threeFingerPan.maximumNumberOfTouches = 3

        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch))

        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap))
        tap.numberOfTouchesRequired = 1

        let twoFingerTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2

        // Holding still starts a drag; moving first makes it a normal pan.
        // UIKit lets only one of these recognize, so they don't conflict.
        let hold = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleHold))
        hold.minimumPressDuration = 0.5
        hold.allowableMovement = 8

        coordinator.twoFingerPan = twoFingerPan
        coordinator.pinch = pinch

        for recognizer in [oneFingerPan, twoFingerPan, threeFingerPan, pinch, tap, twoFingerTap, hold] as [UIGestureRecognizer] {
            // Keep touches flowing to the view so the touch ripples follow
            // the fingers after a gesture is recognized.
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = coordinator
            view.addGestureRecognizer(recognizer)
        }

        return view
    }

    func updateUIView(_ uiView: TouchSurfaceView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ uiView: TouchSurfaceView, coordinator: Coordinator) {
        coordinator.stopMomentum()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Touch surface

    final class TouchSurfaceView: UIView {
        var onTouchDown: (() -> Void)?
        var rippleColor: UIColor = .systemBlue

        private var ripples: [ObjectIdentifier: CALayer] = [:]
        private let rippleSize: CGFloat = 46

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            onTouchDown?()

            for touch in touches {
                let ripple = CALayer()
                ripple.bounds = CGRect(x: 0, y: 0, width: rippleSize, height: rippleSize)
                ripple.cornerRadius = rippleSize / 2
                ripple.borderWidth = 1.5
                ripple.borderColor = rippleColor.cgColor
                ripple.backgroundColor = rippleColor.withAlphaComponent(0.15).cgColor

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                ripple.position = touch.location(in: self)
                layer.addSublayer(ripple)
                CATransaction.commit()

                let grow = CABasicAnimation(keyPath: "transform.scale")
                grow.fromValue = 0.5
                grow.toValue = 1
                grow.duration = 0.12
                ripple.add(grow, forKey: "grow")

                ripples[ObjectIdentifier(touch)] = ripple
            }

            super.touchesBegan(touches, with: event)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for touch in touches {
                ripples[ObjectIdentifier(touch)]?.position = touch.location(in: self)
            }
            CATransaction.commit()

            super.touchesMoved(touches, with: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            removeRipples(for: touches)
            super.touchesEnded(touches, with: event)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            removeRipples(for: touches)
            super.touchesCancelled(touches, with: event)
        }

        private func removeRipples(for touches: Set<UITouch>) {
            for touch in touches {
                guard let ripple = ripples.removeValue(forKey: ObjectIdentifier(touch)) else { continue }

                CATransaction.begin()
                CATransaction.setAnimationDuration(0.2)
                CATransaction.setCompletionBlock { ripple.removeFromSuperlayer() }
                ripple.opacity = 0
                ripple.transform = CATransform3DMakeScale(1.3, 1.3, 1)
                CATransaction.commit()
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TouchPadView

        weak var twoFingerPan: UIPanGestureRecognizer?
        weak var pinch: UIPinchGestureRecognizer?

        var lastOneFingerTranslation: CGPoint = .zero
        var lastTwoFingerTranslation: CGPoint = .zero
        var lastTapTime: TimeInterval = 0

        enum ScrollAxis { case undecided, vertical, horizontal, free }
        var scrollAxis: ScrollAxis = .undecided

        var lastHoldLocation: CGPoint = .zero
        var lastHoldTime: TimeInterval = 0

        var pinchBaseline: CGFloat = 1
        var isZooming = false

        var displayLink: CADisplayLink?
        var momentumVelocity: CGPoint = .zero
        var lastMomentumTimestamp: CFTimeInterval = 0

        init(parent: TouchPadView) {
            self.parent = parent
        }

        // Pinch and two-finger scroll both start with two moving fingers;
        // letting them run together means a scroll is never blocked by a
        // pinch that hasn't reached its zoom threshold yet.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            let pair: Set<UIGestureRecognizer?> = [gestureRecognizer, other]
            return pair == [twoFingerPan, pinch]
        }

        @objc func handleOneFingerPan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)

            if gesture.state == .began {
                lastOneFingerTranslation = translation
                return
            }

            let dx = translation.x - lastOneFingerTranslation.x
            let dy = translation.y - lastOneFingerTranslation.y

            let velocity = gesture.velocity(in: gesture.view)
            let speed = hypot(velocity.x, velocity.y)

            lastOneFingerTranslation = translation
            parent.onMove(dx, dy, speed)

            if gesture.state == .ended || gesture.state == .cancelled {
                lastOneFingerTranslation = .zero
            }
        }

        @objc func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)

            if gesture.state == .began {
                stopMomentum()
                lastTwoFingerTranslation = translation
                scrollAxis = .undecided
                return
            }

            var dx = translation.x - lastTwoFingerTranslation.x
            var dy = translation.y - lastTwoFingerTranslation.y
            lastTwoFingerTranslation = translation

            // Lock to the axis the scroll starts in, so a vertical scroll
            // doesn't drift sideways (and vice versa).
            if scrollAxis == .undecided, hypot(translation.x, translation.y) > 10 {
                if abs(translation.y) > abs(translation.x) * 2 {
                    scrollAxis = .vertical
                } else if abs(translation.x) > abs(translation.y) * 2 {
                    scrollAxis = .horizontal
                } else {
                    scrollAxis = .free
                }
            }

            if scrollAxis == .vertical { dx = 0 }
            if scrollAxis == .horizontal { dy = 0 }

            if !isZooming {
                parent.onScroll(dx, dy)
            }

            if gesture.state == .ended && !isZooming {
                var velocity = gesture.velocity(in: gesture.view)
                if scrollAxis == .vertical { velocity.x = 0 }
                if scrollAxis == .horizontal { velocity.y = 0 }
                startMomentum(velocity: velocity)
            }

            if gesture.state == .ended || gesture.state == .cancelled {
                lastTwoFingerTranslation = .zero
            }
        }

        @objc func handleThreeFingerPan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended else { return }

            let translation = gesture.translation(in: gesture.view)
            guard max(abs(translation.x), abs(translation.y)) > 50 else { return }

            if abs(translation.y) > abs(translation.x) {
                parent.onThreeFingerSwipe(translation.y < 0 ? .up : .down)
            } else {
                parent.onThreeFingerSwipe(translation.x < 0 ? .left : .right)
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchBaseline = gesture.scale

            case .changed:
                // One zoom step per 30% change, like pressing ⌘+ / ⌘−
                // repeatedly; once zooming, the fingers no longer scroll.
                if gesture.scale / pinchBaseline > 1.3 {
                    isZooming = true
                    pinchBaseline = gesture.scale
                    parent.onPinch(true)
                } else if gesture.scale / pinchBaseline < 1 / 1.3 {
                    isZooming = true
                    pinchBaseline = gesture.scale
                    parent.onPinch(false)
                }

            default:
                isZooming = false
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            // First tap clicks immediately (no double-tap wait, which would
            // delay every single click). A second tap within the window
            // upgrades it: the Mac posts a clickState=2 click, which macOS
            // combines with the first into a double-click.
            let now = Date().timeIntervalSinceReferenceDate

            if now - lastTapTime < 0.3 {
                lastTapTime = 0
                parent.onDoubleClick()
            } else {
                lastTapTime = now
                parent.onClick()
            }
        }

        @objc func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
            parent.onRightClick()
        }

        @objc func handleHold(_ gesture: UILongPressGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            let now = CACurrentMediaTime()

            switch gesture.state {
            case .began:
                lastHoldLocation = location
                lastHoldTime = now
                parent.onDragStart()

            case .changed:
                let dx = location.x - lastHoldLocation.x
                let dy = location.y - lastHoldLocation.y
                let elapsed = max(now - lastHoldTime, 0.001)

                lastHoldLocation = location
                lastHoldTime = now
                parent.onMove(dx, dy, hypot(dx, dy) / elapsed)

            case .ended, .cancelled:
                parent.onDragEnd()

            default:
                break
            }
        }

        // MARK: Momentum scrolling

        func startMomentum(velocity: CGPoint) {
            stopMomentum()
            guard hypot(velocity.x, velocity.y) > 150 else { return }

            momentumVelocity = velocity
            lastMomentumTimestamp = 0

            let link = CADisplayLink(target: self, selector: #selector(stepMomentum))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stopMomentum() {
            displayLink?.invalidate()
            displayLink = nil
            momentumVelocity = .zero
        }

        @objc func stepMomentum(_ link: CADisplayLink) {
            let dt = lastMomentumTimestamp == 0
                ? link.duration
                : link.timestamp - lastMomentumTimestamp
            lastMomentumTimestamp = link.timestamp

            // Same decay curve as UIScrollView's normal deceleration rate.
            let decay = pow(0.998, dt * 1000)
            momentumVelocity.x *= decay
            momentumVelocity.y *= decay
            parent.onScroll(momentumVelocity.x * dt, momentumVelocity.y * dt)

            if hypot(momentumVelocity.x, momentumVelocity.y) < 20 {
                stopMomentum()
            }
        }
    }
}
