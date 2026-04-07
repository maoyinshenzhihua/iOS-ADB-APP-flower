import Foundation
import CoreGraphics

class TouchMapper {
    var deviceWidth: UInt32 = 1080
    var deviceHeight: UInt32 = 1920
    var viewSize: CGSize = .zero
    var contentFrame: CGRect = .zero

    func mapTouch(iosPoint: CGPoint) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return iosPoint
        }

        let scaleX = CGFloat(deviceWidth) / contentFrame.width
        let scaleY = CGFloat(deviceHeight) / contentFrame.height

        let x = (iosPoint.x - contentFrame.origin.x) * scaleX
        let y = (iosPoint.y - contentFrame.origin.y) * scaleY

        return CGPoint(
            x: max(0, min(CGFloat(deviceWidth), x)),
            y: max(0, min(CGFloat(deviceHeight), y))
        )
    }

    func updateContentFrame(in viewSize: CGSize) {
        self.viewSize = viewSize

        let deviceAspect = CGFloat(deviceWidth) / CGFloat(deviceHeight)
        let viewAspect = viewSize.width / viewSize.height

        if viewAspect > deviceAspect {
            let contentWidth = viewSize.height * deviceAspect
            let offsetX = (viewSize.width - contentWidth) / 2
            contentFrame = CGRect(x: offsetX, y: 0, width: contentWidth, height: viewSize.height)
        } else {
            let contentHeight = viewSize.width / deviceAspect
            let offsetY = (viewSize.height - contentHeight) / 2
            contentFrame = CGRect(x: 0, y: offsetY, width: viewSize.width, height: contentHeight)
        }
    }

    func isInsideContent(point: CGPoint) -> Bool {
        contentFrame.contains(point)
    }
}
