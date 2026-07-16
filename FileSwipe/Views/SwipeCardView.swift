import SwiftUI

struct SwipeCardView: View {
    let item: FileItem
    let onKeep: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGSize = .zero
    @State private var isExiting = false

    private let swipeThreshold: CGFloat = 120

    private var dragProgress: CGFloat {
        min(1, abs(offset.width) / swipeThreshold)
    }

    private var keepOpacity: Double {
        offset.width > 0 ? Double(dragProgress) : 0
    }

    private var deleteOpacity: Double {
        offset.width < 0 ? Double(dragProgress) : 0
    }

    private var rotation: Angle {
        .degrees(Double(offset.width / 20))
    }

    var body: some View {
        ZStack {
            // Decision stamps
            VStack {
                HStack {
                    stamp(text: "DELETE", color: .red, opacity: deleteOpacity)
                    Spacer()
                    stamp(text: "KEEP", color: .green, opacity: keepOpacity)
                }
                .padding(24)
                Spacer()
            }
            .zIndex(2)

            VStack(spacing: 0) {
                FilePreviewView(item: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                fileMetaBar
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
        .offset(offset)
        .rotationEffect(rotation)
        .gesture(dragGesture)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.82), value: offset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File \(item.name)")
        .accessibilityHint("Swipe right to keep, left to delete")
    }

    private var borderColor: Color {
        if offset.width > 40 { return .green.opacity(0.7) }
        if offset.width < -40 { return .red.opacity(0.7) }
        return Color.primary.opacity(0.08)
    }

    private var fileMetaBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(item.kindLabel) · \(item.sizeString) · Added \(item.dateAddedString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func stamp(text: String, color: Color, opacity: Double) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .black, design: .rounded))
            .tracking(2)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(color, lineWidth: 4)
            )
            .foregroundStyle(color)
            .rotationEffect(.degrees(text == "DELETE" ? -12 : 12))
            .opacity(opacity)
    }

    private var dragGesture: some Gesture {
        // minimumDistance keeps taps (Play, list rows, Trash this) from starting a swipe
        DragGesture(minimumDistance: 36)
            .onChanged { value in
                guard !isExiting else { return }
                // Prefer horizontal swipes so vertical scrolling inside previews still works
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > vertical * 0.85 else { return }
                offset = CGSize(width: value.translation.width, height: value.translation.height * 0.15)
            }
            .onEnded { value in
                guard !isExiting else { return }
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > vertical * 0.85 else {
                    offset = .zero
                    return
                }
                let predicted = value.predictedEndTranslation.width
                if predicted > swipeThreshold || value.translation.width > swipeThreshold {
                    complete(direction: .right)
                } else if predicted < -swipeThreshold || value.translation.width < -swipeThreshold {
                    complete(direction: .left)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        offset = .zero
                    }
                }
            }
    }

    private enum Direction { case left, right }

    private func complete(direction: Direction) {
        isExiting = true
        let flyOut: CGFloat = direction == .right ? 900 : -900
        withAnimation(.easeIn(duration: 0.22)) {
            offset = CGSize(width: flyOut, height: offset.height * 0.3)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if direction == .right {
                onKeep()
            } else {
                onDelete()
            }
            // Reset for next card (view may be recreated with new identity)
            offset = .zero
            isExiting = false
        }
    }
}
