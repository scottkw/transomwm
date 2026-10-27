import Foundation

/// Where a floating window can be snapped inside the Desktop tile (TILE-14).
public enum SnapTarget: String, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftThird, centerThird, rightThird
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, center
}

public enum Snap {
    /// The frame for `target` inside `desktop` inset by `gap` on every side, with gap-wide spacing between
    /// parts (A9). Whole points like `resolve`: each part but the last is rounded down and the last takes
    /// the remainder. `center` keeps the window's size, shrunk to fit, and centres it.
    public static func frame(_ target: SnapTarget, window: Rect, desktop: Rect, gap: Double) -> Rect {
        let gap = max(0, gap.rounded())
        let minX = desktop.minX.rounded(.up) + gap
        let minY = desktop.minY.rounded(.up) + gap
        // shortcut: a Desktop narrower than two gaps gives an empty rect at its inset origin; fine at real sizes.
        let inset = Rect(
            x: minX, y: minY,
            width: max(0, desktop.maxX.rounded(.down) - gap - minX),
            height: max(0, desktop.maxY.rounded(.down) - gap - minY))

        /// Part `i` of `n` along a length starting at `start`: (offset, size).
        func part(_ i: Int, of n: Int, from start: Double, _ length: Double) -> (Double, Double) {
            let size = max(0, ((length - gap * Double(n - 1)) / Double(n)).rounded(.down))
            let offset = start + Double(i) * (size + gap)
            return (offset, i == n - 1 ? max(0, start + length - offset) : size)
        }
        func cell(_ column: Int, of columns: Int, _ row: Int, of rows: Int) -> Rect {
            let (x, width) = part(column, of: columns, from: inset.minX, inset.width)
            let (y, height) = part(row, of: rows, from: inset.minY, inset.height)
            return Rect(x: x, y: y, width: width, height: height)
        }

        switch target {
        case .leftHalf: return cell(0, of: 2, 0, of: 1)
        case .rightHalf: return cell(1, of: 2, 0, of: 1)
        case .topHalf: return cell(0, of: 1, 0, of: 2)
        case .bottomHalf: return cell(0, of: 1, 1, of: 2)
        case .leftThird: return cell(0, of: 3, 0, of: 1)
        case .centerThird: return cell(1, of: 3, 0, of: 1)
        case .rightThird: return cell(2, of: 3, 0, of: 1)
        case .topLeft: return cell(0, of: 2, 0, of: 2)
        case .topRight: return cell(1, of: 2, 0, of: 2)
        case .bottomLeft: return cell(0, of: 2, 1, of: 2)
        case .bottomRight: return cell(1, of: 2, 1, of: 2)
        case .maximize: return inset
        case .center:
            let width = min(max(0, window.width), inset.width)
            let height = min(max(0, window.height), inset.height)
            return Rect(
                x: inset.minX + ((inset.width - width) / 2).rounded(.down),
                y: inset.minY + ((inset.height - height) / 2).rounded(.down),
                width: width, height: height)
        }
    }
}
