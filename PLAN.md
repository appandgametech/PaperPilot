# PaperPilot Hub Isolation Refactor Plan

## Goal
Transform the app from a shared-state single portfolio into 3 fully isolated hub "mini-apps":
1. **Paper** — Yahoo data, local execution, no signup, full sandbox (8 tabs incl. Markets + Tools)
2. **Alpaca** — Alpaca API for data + execution, paper/live toggle (7 tabs, no Tools)
3. **NinjaTrader** — Tradovate API for execution, Yahoo for charts, demo/live toggle (6 tabs, no Markets/Tools)

Each hub has its own: cash, positions, trade history, pending orders, portfolio snapshots, safety controls, price alerts.

## Architecture Decisions
- `HubPortfolio` class holds all per-hub state (cash, positions, trades, orders, snapshots, alerts, safety controls)
- `PortfolioManager` owns 3 `HubPortfolio` instances, exposes `activeHubPortfolio` based on `activeHub`
- Each `HubPortfolio` persists with hub-prefixed UserDefaults keys (e.g. `paper_cash`, `equities_cash`, `futures_cash`)
- `AutomationEngine` evaluates rules only for the active hub (via `rule.hub` field filter)
- Hub-specific tab enums: `PaperTab` (8), `AlpacaTab` (7), `FuturesTab` (6)
- Hub switcher bar at top swaps the entire app context
- `HubLauncherView` sheet for choosing which hub to enter
- Settings shows ONLY relevant sections per hub + shared sections
- One shared `StockService` for market data
- Removed: `AppBackground` enum, `TradingMode` enum, background configs

## Phases

### Phase 1: HubPortfolio Model + Isolated Persistence ✅
- [x] Create `HubPortfolio` class with all per-hub state
- [x] Hub-prefixed UserDefaults keys for persistence
- [x] Migrate existing portfolio data to Paper hub on first launch

### Phase 2: Refactor PortfolioManager ✅
- [x] PortfolioManager holds 3 HubPortfolio instances
- [x] `activeHubPortfolio` computed property
- [x] Route buy/sell/pending orders through active hub portfolio
- [x] Remove shared cash/positions/trades — delegate to hub portfolio
- [x] Remove `AppBackground` enum and all background config code
- [x] Remove `TradingMode` picker logic — each hub has fixed broker
- [x] Keep appearance mode + accent theme (those are app-wide)

### Phase 3: Hub-Specific Tab Bars + ContentView ✅
- [x] `PaperTab`, `AlpacaTab`, `FuturesTab` enums with hub-specific tabs
- [x] Hub switcher bar with visual indicators
- [x] Hub-specific tab views (compact) and sidebar (regular)
- [x] `HubLauncherView` for choosing hub
- [x] Live trading banner + emergency stop banner
- [x] iPad/Mac sidebar with hub-specific items + connection status

### Phase 4: Hub-Specific Dashboard ✅
- [x] Hub header card (icon, broker name, live/paper badge)
- [x] Paper: Yahoo info + top movers + portfolio chart
- [x] Alpaca: connection status + features card + top movers
- [x] Futures: NT connection status + features card
- [x] Hub-specific getting started tips
- [x] Automation status shows hub-filtered rule count

### Phase 5: Hub-Specific Settings ✅
- [x] Paper: data provider picker, local sim info
- [x] Alpaca: live toggle, credentials, connection test, setup guide
- [x] NinjaTrader: live toggle, environment picker, credentials, connection test, setup guide
- [x] Shared: refresh interval, portfolio reset, appearance, safety controls, hub visibility, about
- [x] `AlpacaSetupGuide` and `NinjaTraderSetupGuide` structs

### Phase 6: AutomationView Hub Filtering ✅
- [x] `hubRules` computed property filters rules by `portfolio.activeHub.rawValue`
- [x] Rules tab shows only rules for active hub
- [x] Empty state message is hub-specific
- [x] Delete action maps filtered indices back to engine indices
- [x] New rules get `rule.hub` set to active hub on creation
- [x] AutomationEngine evaluates rules only for active hub

### Phase 7: Cleanup + QA ✅
- [x] Remove dead code: `TradingMode` enum removed from StockService.swift
- [x] getDiagnostics on ALL 16 files — zero errors
- [x] All views compile cleanly

## Files Modified (Task 30)
- `StockPaperTrader/Views/ContentView.swift` — fully rewritten: hub-specific tab bars, sidebar, HubLauncherView
- `StockPaperTrader/Views/DashboardView.swift` — fully rewritten: hub-specific content, filtered automation count
- `StockPaperTrader/Views/SettingsView.swift` — fully rewritten: hub-specific + shared sections, setup guides
- `StockPaperTrader/Views/AutomationView.swift` — hub-filtered rules display
- `StockPaperTrader/Services/PortfolioManager.swift` — HubPortfolio model, 3 isolated portfolios
- `StockPaperTrader/Services/AutomationEngine.swift` — hub-aware rule evaluation
- `StockPaperTrader/Services/StockService.swift` — removed TradingMode enum
- `StockPaperTrader/Views/OnboardingView.swift` — removed AppBackground picker

## Current Status: COMPLETE ✅
All phases done. Zero diagnostics errors across all files. Each hub is a fully isolated mini-app experience.
