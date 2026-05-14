import SwiftUI
import UIKit

struct TouchPadView: UIViewRepresentable {

    let onMove: (CGFloat, CGFloat) -> Void
    let onClick: () -> Void
    let onScroll: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.systemGray5
        view.layer.cornerRadius = 24

        let oneFingerPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleOneFingerPan)
        )
        oneFingerPan.minimumNumberOfTouches = 1
        oneFingerPan.maximumNumberOfTouches = 1

        let twoFingerPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTwoFingerPan)
        )
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.numberOfTouchesRequired = 1

        view.addGestureRecognizer(oneFingerPan)
        view.addGestureRecognizer(twoFingerPan)
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMove: onMove,
            onClick: onClick,
            onScroll: onScroll
        )
    }

    class Coordinator: NSObject {
        let onMove: (CGFloat, CGFloat) -> Void
        let onClick: () -> Void
        let onScroll: (CGFloat) -> Void

        var lastOneFingerTranslation: CGPoint = .zero
        var lastTwoFingerTranslation: CGPoint = .zero

        init(
            onMove: @escaping (CGFloat, CGFloat) -> Void,
            onClick: @escaping () -> Void,
            onScroll: @escaping (CGFloat) -> Void
        ) {
            self.onMove = onMove
            self.onClick = onClick
            self.onScroll = onScroll
        }

        @objc func handleOneFingerPan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)

            if gesture.state == .began {
                lastOneFingerTranslation = translation
                return
            }

            let dx = translation.x - lastOneFingerTranslation.x
            let dy = translation.y - lastOneFingerTranslation.y

            lastOneFingerTranslation = translation
            onMove(dx, dy)

            if gesture.state == .ended || gesture.state == .cancelled {
                lastOneFingerTranslation = .zero
            }
        }

        @objc func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)

            if gesture.state == .began {
                lastTwoFingerTranslation = translation
                return
            }

            let dy = translation.y - lastTwoFingerTranslation.y

            lastTwoFingerTranslation = translation
            onScroll(dy)

            if gesture.state == .ended || gesture.state == .cancelled {
                lastTwoFingerTranslation = .zero
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            onClick()
        }
    }
}
