import SwiftUI

struct ToolsView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var portfolio: PortfolioManager

    var body: some View {
        NavigationStack {
            List {
                Section("Find Opportunities") {
                    NavigationLink {
                        ScreenerView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Stock Screener").font(.subheadline.bold())
                                Text("Filter by price, volume, market cap, sector")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.title3)
                        }
                    }

                    NavigationLink {
                        SectorMapView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sector Performance").font(.subheadline.bold())
                                Text("See which sectors are hot or cold")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "chart.bar.xaxis")
                                .foregroundStyle(.orange)
                                .font(.title3)
                        }
                    }

                    NavigationLink {
                        NewsView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Market News").font(.subheadline.bold())
                                Text("Headlines for your watchlist stocks")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "newspaper.fill")
                                .foregroundStyle(.purple)
                                .font(.title3)
                        }
                    }
                }

                Section("Decision Tools") {
                    NavigationLink {
                        ComparisonView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Compare Stocks").font(.subheadline.bold())
                                Text("Side-by-side performance comparison")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundStyle(.green)
                                .font(.title3)
                        }
                    }

                    NavigationLink {
                        RiskCalculatorView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Risk Calculator").font(.subheadline.bold())
                                Text("Position sizing based on risk tolerance")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "shield.checkered")
                                .foregroundStyle(.red)
                                .font(.title3)
                        }
                    }
                }

                Section("Alerts") {
                    NavigationLink {
                        PriceAlertsView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Price Alerts").font(.subheadline.bold())
                                let active = portfolio.priceAlerts.filter(\.isActive).count
                                Text(active > 0 ? "\(active) active alert\(active == 1 ? "" : "s")" : "Get notified at target prices")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(.yellow)
                                .font(.title3)
                        }
                    }
                }
            }
            .navigationTitle("Tools")
        }
    }
}
