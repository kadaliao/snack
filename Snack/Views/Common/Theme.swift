import SnackKit
import SwiftUI

extension Color {
    static let snack = Color.orange
    static let right = Color.green
    static let wrong = Color.red
}

/// A big button that sits on a lip of a darker shade and presses down into it.
struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = .snack

    func makeBody(configuration: Configuration) -> some View {
        Chunky(label: configuration.label, color: color, isPressed: configuration.isPressed)
    }

    private struct Chunky<Label: View>: View {
        let label: Label
        let color: Color
        let isPressed: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let fill = isEnabled ? color : Color(.systemGray4)
            label
                .font(.headline)
                .foregroundStyle(isEnabled ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(fill, in: .rect(cornerRadius: 16))
                .background(RoundedRectangle(cornerRadius: 16).fill(fill.mix(with: .black, by: 0.2)).offset(y: isPressed ? 0 : 4))
                .offset(y: isPressed ? 4 : 0)
                .padding(.bottom, 4)
                .animation(.snappy(duration: 0.1), value: isPressed)
        }
    }
}

/// How an answer card looks: waiting, chosen, right, wrong, or out of play.
enum Tone {
    case plain, picked, right, wrong, muted
}

/// A white card with a border and a lip, for options and tiles.
struct CardButtonStyle: ButtonStyle {
    var tone: Tone = .plain
    var radius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        let edge: Color = switch tone {
        case .plain: Color(.systemGray4)
        case .picked: .snack
        case .right: .right
        case .wrong: .wrong
        case .muted: Color(.systemGray5)
        }
        let tint: Color = switch tone {
        case .plain: .clear
        case .muted: Color(.systemGray6)
        case .picked: Color.snack.opacity(0.12)
        case .right: Color.right.opacity(0.15)
        case .wrong: Color.wrong.opacity(0.15)
        }
        let text: Color = switch tone {
        case .plain, .picked: .primary
        case .muted: .secondary
        case .right: .right
        case .wrong: .wrong
        }
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: radius)
        // The face is opaque, so the lip under it shows only below.
        return configuration.label
            .foregroundStyle(text)
            .background { shape.fill(Color(.systemBackground)).overlay(shape.fill(tint)) }
            .overlay(shape.strokeBorder(edge, lineWidth: 2))
            .background(shape.fill(edge).offset(y: pressed ? 0 : 3))
            .offset(y: pressed ? 3 : 0)
            .padding(.bottom, 3)
            .animation(.snappy(duration: 0.1), value: pressed)
    }
}

/// A ring filled to `value`, 0 to 1.
struct Ring: View {
    var value: Double
    var color: Color = .snack
    var width: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(Color(.systemGray5), lineWidth: width)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(duration: 0.6), value: value)
    }
}

/// Lays its views out like words in a paragraph, onto the next line when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let frames = arrange(subviews, width: width)
        let height = frames.map(\.maxY).max() ?? 0
        let used = frames.map(\.maxX).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > width {
                size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            if x > 0 && x + size.width > width {
                x = 0
                y += line + lineSpacing
                line = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            line = max(line, size.height)
        }
        return frames
    }
}

extension Mastery {
    var label: String {
        switch self {
        case .new: "没学"
        case .learning: "在学"
        case .young: "初识"
        case .familiar: "熟悉"
        case .strong: "牢固"
        case .mastered: "精通"
        }
    }

    var color: Color {
        switch self {
        case .new: Color(.systemGray4)
        case .learning: .red.opacity(0.7)
        case .young: .orange
        case .familiar: .yellow
        case .strong: .green
        case .mastered: .blue
        }
    }
}

extension Game {
    var label: String {
        switch self {
        case .choose: "选一选"
        case .build: "拼一拼"
        case .type: "默一默"
        case .flip: "翻一翻"
        }
    }

    var symbol: String {
        switch self {
        case .choose: "square.grid.2x2"
        case .build: "puzzlepiece"
        case .type: "keyboard"
        case .flip: "rectangle.portrait.on.rectangle.portrait.angled"
        }
    }
}
