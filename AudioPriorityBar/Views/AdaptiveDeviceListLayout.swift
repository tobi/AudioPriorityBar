import Foundation

struct AdaptiveDeviceListHeights: Equatable {
    let output: CGFloat
    let input: CGFloat
}

enum AdaptiveDeviceListLayout {
    static let maximumPreferredMenuHeight: CGFloat = 640
    static let screenEdgeMargin: CGFloat = 24
    static let estimatedFixedChromeHeight: CGFloat = 296
    static let dividerHeight: CGFloat = 1
    static let emptyStateHeight: CGFloat = 38
    static let rowHeight: CGFloat = 42
    static let rowSpacing: CGFloat = 4
    static let listVerticalPadding: CGFloat = 8

    static func requiredHeight(deviceCount: Int) -> CGFloat {
        guard deviceCount > 0 else { return emptyStateHeight }
        return CGFloat(deviceCount) * rowHeight
            + CGFloat(max(0, deviceCount - 1)) * rowSpacing
            + listVerticalPadding
    }

    static func allocate(
        outputCount: Int,
        inputCount: Int,
        availableHeight: CGFloat
    ) -> AdaptiveDeviceListHeights {
        let budget = max(0, availableHeight)
        let outputNeed = requiredHeight(deviceCount: outputCount)
        let inputNeed = requiredHeight(deviceCount: inputCount)

        guard outputNeed + inputNeed > budget else {
            return AdaptiveDeviceListHeights(output: outputNeed, input: inputNeed)
        }

        let half = budget / 2
        if outputNeed <= half {
            return AdaptiveDeviceListHeights(
                output: outputNeed,
                input: min(inputNeed, budget - outputNeed)
            )
        }
        if inputNeed <= half {
            return AdaptiveDeviceListHeights(
                output: min(outputNeed, budget - inputNeed),
                input: inputNeed
            )
        }

        return AdaptiveDeviceListHeights(
            output: min(outputNeed, half),
            input: min(inputNeed, budget - half)
        )
    }
}
