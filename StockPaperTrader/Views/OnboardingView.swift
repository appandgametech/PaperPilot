import SwiftUI

struct OnboardingView: View {
    let onComplete: (Double) -> Void
    @EnvironmentObject var portfolio: PortfolioManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var currentPage = 0
    @State private var selectedCash: Double = 100_000
    @State private var selectedTheme: AccentTheme = .blue

    private var isWide: Bool { sizeClass == .regular }

    private let cashOptions: [(label: String, value: Double)] = [
        ("$10,000", 10_000),
        ("$25,000", 25_000),
        ("$50,000", 50_000),
        ("$100,000", 100_000),
        ("$500,000", 500_000),
        ("$1,000,000", 1_000_000),
    ]

    private let pages: [(icon: String, title: String, subtitle: String, color: Color)] = [
        ("airplane", "Welcome to PaperPilot", "3 trading apps in 1 platform. Practice with simulations, trade live with Alpaca, or explore futures with NinjaTrader.", .blue),
        ("square.stack.3d.up", "3 Isolated Apps", "Paper (Yahoo simulation), Equities (Alpaca broker), and Futures (NinjaTrader). Each has its own portfolio, watchlist, and settings — zero data mixing.", .purple),
        ("arrow.left.arrow.right.circle", "Place Real Trades", "Market, limit, stop loss, and stop limit orders. Dollar-based investing. Trade journal to track your reasoning.", .green),
        ("chart.xyaxis.line", "Pro-Level Charts", "Candlestick charts, RSI, MACD, Bollinger Bands, moving averages, volume — all the tools the pros use.", .cyan),
        ("gearshape.2", "Automate Your Strategy", "Build rules like Stop Loss, Take Profit, and Buy the Dip. The engine watches prices and executes for you.", .orange),
    ]

    private var totalPages: Int { pages.count + 2 }

    var body: some View {
        VStack(spacing: 0) {
            // Page indicator dots (moved to top so they don't overlap content)
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { i in
                    Circle()
                        .fill(i == currentPage ? buttonColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(i == currentPage ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }
            .padding(.top, isWide ? 24 : 16)
            .padding(.bottom, 8)

            // Pages
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    onboardingPage(pages[index])
                        .tag(index)
                }
                customizePage.tag(pages.count)
                cashPickerPage.tag(pages.count + 1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Bottom buttons
            Button {
                if currentPage < totalPages - 1 {
                    withAnimation { currentPage += 1 }
                } else {
                    portfolio.accentTheme = selectedTheme
                    portfolio.saveUserPreferences()
                    onComplete(selectedCash)
                }
            } label: {
                Text(currentPage < totalPages - 1 ? "Next" : "Start Trading")
                    .font(.headline)
                    .frame(maxWidth: isWide ? 400 : .infinity)
                    .padding(.vertical, isWide ? 16 : 14)
                    .background(buttonColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, isWide ? 80 : 32)
            .padding(.bottom, 12)

            if currentPage < totalPages - 1 {
                Button("Skip") {
                    portfolio.accentTheme = selectedTheme
                    portfolio.saveUserPreferences()
                    onComplete(selectedCash)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, isWide ? 28 : 20)
            } else {
                Spacer().frame(height: isWide ? 28 : 40)
            }
        }
        .frame(minWidth: isWide ? 600 : nil, minHeight: isWide ? 700 : nil)
        .interactiveDismissDisabled()
    }

    private var buttonColor: Color {
        if currentPage < pages.count { return pages[currentPage].color }
        if currentPage == pages.count { return selectedTheme.color }
        return .green
    }

    // MARK: - Feature Page
    private func onboardingPage(_ page: (icon: String, title: String, subtitle: String, color: Color)) -> some View {
        VStack(spacing: isWide ? 32 : 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.color.opacity(0.12))
                    .frame(width: isWide ? 180 : 140, height: isWide ? 180 : 140)

                Image(systemName: page.icon)
                    .font(.system(size: isWide ? 80 : 64))
                    .foregroundStyle(page.color)
                    .symbolEffect(.bounce, value: currentPage)
            }

            Text(page.title)
                .font(isWide ? .largeTitle.bold() : .title.bold())
                .multilineTextAlignment(.center)

            Text(page.subtitle)
                .font(isWide ? .title3 : .body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, isWide ? 80 : 36)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Spacer().frame(height: isWide ? 40 : 20)
        }
    }

    // MARK: - Cash Picker
    private var cashPickerPage: some View {
        VStack(spacing: isWide ? 32 : 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: isWide ? 160 : 140, height: isWide ? 160 : 140)
                Image(systemName: "banknote")
                    .font(.system(size: isWide ? 72 : 64))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: currentPage)
            }

            Text("Choose Starting Cash")
                .font(isWide ? .largeTitle.bold() : .title.bold())
                .multilineTextAlignment(.center)

            Text("How much virtual money do you want to start with? You can always change this in Settings.")
                .font(isWide ? .title3 : .body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, isWide ? 80 : 36)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), isWide ? GridItem(.flexible()) : nil].compactMap { $0 }, spacing: 10) {
                ForEach(cashOptions, id: \.value) { option in
                    Button {
                        selectedCash = option.value
                        HapticManager.selectionFeedback()
                    } label: {
                        Text(option.label)
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                selectedCash == option.value ? Color.green : Color.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .foregroundStyle(selectedCash == option.value ? .white : .primary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedCash == option.value ? Color.green : .clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, isWide ? 80 : 32)

            Spacer()
            Spacer().frame(height: isWide ? 40 : 20)
        }
    }

    // MARK: - Customization Page
    private var customizePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: isWide ? 28 : 20) {
                Spacer().frame(height: isWide ? 16 : 8)

                ZStack {
                    Circle()
                        .fill(selectedTheme.color.opacity(0.12))
                        .frame(width: isWide ? 140 : 110, height: isWide ? 140 : 110)
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: isWide ? 60 : 48))
                        .foregroundStyle(selectedTheme.color)
                        .symbolEffect(.bounce, value: currentPage)
                }

                Text("Make It Yours")
                    .font(isWide ? .largeTitle.bold() : .title.bold())

                Text("Pick an accent color. Change anytime in Settings.")
                    .font(isWide ? .title3 : .body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, isWide ? 80 : 36)

                // Accent color
                VStack(alignment: .leading, spacing: 10) {
                    Text("Accent Color").font(.headline).padding(.horizontal, isWide ? 80 : 32)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: isWide ? 8 : 6), spacing: 12) {
                        ForEach(AccentTheme.allCases) { theme in
                            Button {
                                selectedTheme = theme
                                HapticManager.selectionFeedback()
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle().fill(theme.color).frame(width: 44, height: 44)
                                        if selectedTheme == theme {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold()).foregroundStyle(.white)
                                        }
                                    }
                                    Text(theme.rawValue).font(.caption2)
                                        .foregroundStyle(selectedTheme == theme ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, isWide ? 80 : 32)
                }

                Spacer().frame(height: isWide ? 40 : 20)
            }
        }
    }
}
