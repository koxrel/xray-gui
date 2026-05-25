import Testing
@testable import XrayGUI

@Suite("Statistics Navigation Tests")
struct StatisticsNavigationTests {
    @Test("SidebarTab includes Statistics with chart icon")
    func sidebarIncludesStatisticsTab() {
        #expect(SidebarTab.allCases.contains(.statistics))
        #expect(SidebarTab.statistics.rawValue == "Statistics")
        #expect(SidebarTab.statistics.icon == "chart.xyaxis.line")
    }
}
