import Foundation

struct WindowIdentity: Hashable, Sendable {
    let appPID: pid_t
    let title: String
    let frame: WindowFrame
    let ordinal: Int
}

struct WindowFrame: Hashable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    init(_ rect: CGRect) {
        x = Int(rect.origin.x.rounded())
        y = Int(rect.origin.y.rounded())
        width = Int(rect.size.width.rounded())
        height = Int(rect.size.height.rounded())
    }
}

struct WindowOrderingCandidate: Sendable {
    let identity: WindowIdentity
    let fallbackIndex: Int
    let isMinimized: Bool
}

enum WindowSwitchingLogic {
    static func orderedWindowIdentities(
        from windows: [WindowOrderingCandidate],
        recent: [WindowIdentity]
    ) -> [WindowIdentity] {
        let recentRanks = Dictionary(uniqueKeysWithValues: recent.enumerated().map { ($0.element, $0.offset) })

        return windows.sorted { lhs, rhs in
            let lhsRecentRank = recentRanks[lhs.identity] ?? Int.max
            let rhsRecentRank = recentRanks[rhs.identity] ?? Int.max

            if lhsRecentRank != rhsRecentRank {
                return lhsRecentRank < rhsRecentRank
            }

            if lhs.isMinimized != rhs.isMinimized {
                return !lhs.isMinimized
            }

            if lhs.fallbackIndex != rhs.fallbackIndex {
                return lhs.fallbackIndex < rhs.fallbackIndex
            }

            if lhs.identity.appPID != rhs.identity.appPID {
                return lhs.identity.appPID < rhs.identity.appPID
            }

            return lhs.identity.title.localizedCaseInsensitiveCompare(rhs.identity.title) == .orderedAscending
        }.map(\.identity)
    }

    static func initialSelectionIndex(windowCount: Int, selectingBackward: Bool) -> Int {
        guard windowCount > 1 else {
            return 0
        }

        return selectingBackward ? windowCount - 1 : 1
    }

    static func nextSelectionIndex(currentIndex: Int, count: Int, movingForward: Bool) -> Int {
        guard count > 0 else {
            return 0
        }

        let delta = movingForward ? 1 : -1
        return (currentIndex + delta + count) % count
    }
}
