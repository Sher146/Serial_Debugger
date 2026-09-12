import Foundation

enum BaudRateCatalog {
    /// Values represented by macOS's built-in `termios` speed constants.
    static let standardRates = [
        50, 75, 110, 134, 150, 200, 300, 600, 1_200, 1_800,
        2_400, 4_800, 7_200, 9_600, 14_400, 19_200, 28_800,
        38_400, 57_600, 76_800, 115_200, 230_400
    ]

    /// Common USB-UART rates configured through macOS `IOSSIOSPEED`.
    static let highSpeedRates = [
        460_800, 500_000, 576_000, 921_600, 1_000_000,
        1_500_000, 2_000_000, 3_000_000
    ]

    static let presetRates = standardRates + highSpeedRates

    static func rates(including currentRate: Int) -> [Int] {
        guard currentRate > 0, !presetRates.contains(currentRate) else { return presetRates }
        return (presetRates + [currentRate]).sorted()
    }

    static func label(for rate: Int) -> String {
        rate.formatted(.number.grouping(.automatic))
    }

    static func isStandard(_ rate: Int) -> Bool {
        standardRates.contains(rate)
    }
}
