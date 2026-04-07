import SwiftUI

struct TouchOverlay: UIViewRepresentable {
    let touchMapper: TouchMapper
    let onTouch: (CGPoint) -> Void

    func makeUIView(context: Context) -> TouchOverlayView {
        let view = TouchOverlayView()
        view.touchMapper = touchMapper
        view.onTouch = onTouch
        return view
    }

    func updateUIView(_ uiView: TouchOverlayView, context: Context) {
        uiView.touchMapper = touchMapper
        uiView.onTouch = onTouch
    }
}

class TouchOverlayView: UIView {
    var touchMapper: TouchMapper?
    var onTouch: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        touchMapper?.updateContentFrame(in: bounds.size)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let mapper = touchMapper else { return }
        let point = touch.location(in: self)
        if mapper.isInsideContent(point: point) {
            onTouch?(point)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let mapper = touchMapper else { return }
        let point = touch.location(in: self)
        if mapper.isInsideContent(point: point) {
            onTouch?(point)
        }
    }
}
