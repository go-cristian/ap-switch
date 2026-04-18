import AppKit
import SwiftUI

struct SwitcherOverlayView: View {
    @ObservedObject var model: SwitcherOverlayModel

    let overlaySize: CGSize

    private let tileWidth: CGFloat = 176
    private let previewWidth: CGFloat = 148
    private let previewHeight: CGFloat = 84

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.selectedWindow?.title ?? "Window Switcher")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(model.selectedWindow?.appName ?? "")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }

                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                                    WindowTileView(
                                        window: window,
                                        isSelected: index == model.selectedIndex,
                                        tileWidth: tileWidth,
                                        previewWidth: previewWidth,
                                        previewHeight: previewHeight
                                    )
                                        .id(window.id)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .frame(minWidth: geometry.size.width, alignment: .center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .onAppear {
                            scrollToCurrentSelection(with: proxy)
                        }
                        .onChange(of: model.selectedWindowID) { _ in
                            scrollToCurrentSelection(with: proxy)
                        }
                    }
                }

                Text(model.footerMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .frame(width: overlaySize.width, height: overlaySize.height)
    }

    private func scrollToCurrentSelection(with proxy: ScrollViewProxy) {
        guard let selectedWindowID = model.selectedWindowID else {
            return
        }

        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(selectedWindowID, anchor: .center)
        }
    }
}

private struct WindowTileView: View {
    let window: SwitcherWindow
    let isSelected: Bool
    let tileWidth: CGFloat
    let previewWidth: CGFloat
    let previewHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: previewWidth, height: previewHeight)
                    .overlay {
                        if let preview = window.preview {
                            Image(nsImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: previewWidth, height: previewHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                            Image(nsImage: window.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 36, height: 36)
                                .opacity(0.92)
                        }
                    }

                if window.isMinimized {
                    Text("Minimized")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.48))
                        .clipShape(Capsule())
                        .padding(8)
                }
            }

            HStack(spacing: 9) {
                Image(nsImage: window.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(window.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(window.appName)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .frame(width: tileWidth)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            isSelected ? Color(red: 0.43, green: 0.88, blue: 0.80) : Color.white.opacity(0.05),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
        .scaleEffect(isSelected ? 1.02 : 1)
        .shadow(color: .black.opacity(isSelected ? 0.24 : 0), radius: 14, y: 8)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}
