import SwiftUI

/// A rectangle with a concave quarter-circle scooped from each corner.
/// Ported from the Steps app's PassportStampView.
struct NotchedRectangle: InsettableShape {
    var notchRadius: CGFloat = 12
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(notchRadius - insetAmount, 1)

        var path = Path()
        path.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        path.addArc(center: CGPoint(x: r.maxX, y: r.minY), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        path.addArc(center: CGPoint(x: r.maxX, y: r.maxY), radius: radius,
                    startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
        path.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        path.addArc(center: CGPoint(x: r.minX, y: r.maxY), radius: radius,
                    startAngle: .degrees(0), endAngle: .degrees(270), clockwise: true)
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        path.addArc(center: CGPoint(x: r.minX, y: r.minY), radius: radius,
                    startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        path.closeSubpath()
        return path
    }
}

#if DEBUG
#Preview("NotchedRectangle") {
    NotchedRectangle(notchRadius: 20)
        .fill(Color.avoraTicketYellow)
        .overlay(NotchedRectangle(notchRadius: 20).strokeBorder(Color.avoraTicketInk, lineWidth: 2))
        .frame(width: 300, height: 140)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.avoraBackgroundGradient)
}
#endif
