# PaperPilot — 3 Apps in 1

## Vision
PaperPilot is one app that contains 3 fully separate mini-apps. When you select a hub, you enter that app entirely — every screen, chart, title, branding, and data source is specific to that integration. Zero bleed between hubs.

## The 3 Apps

### 1. Paper Trading (Green theme)
- **Broker:** None — local simulation on-device
- **Data:** Yahoo Finance (unofficial, free, no signup)
- **Charts:** Yahoo Finance chart data (candlestick, line, indicators)
- **What you can trade:** Any stock/ETF available on Yahoo
- **Tabs:** Home, Charts, Markets, Trade, Automate, Analytics, Tools, Settings (8 tabs)
- **Unique features:** Stock screener, sector map, news, comparison tool, risk calculator, price alerts
- **No account needed** — start immediately with virtual cash

### 2. Alpaca Equities (Blue theme)
- **Broker:** Alpaca Markets (paper + live toggle)
- **Data:** Alpaca IEX feed for quotes; Alpaca Bars API for charts
- **Charts:** Alpaca Bars API (`/v2/stocks/{symbol}/bars`) with Yahoo fallback
- **What you can trade:** Stocks, ETFs, options, crypto, fractional shares
- **Tabs:** Home, Charts, Markets, Trade, Automate, Analytics, Settings (7 tabs — no Tools)
- **Unique features:** Fractional shares, crypto, paper/live toggle, account sync
- **Requires:** Free Alpaca account + API keys

### 3. NinjaTrader Futures (Orange theme)
- **Broker:** NinjaTrader via Tradovate API (demo + live toggle)
- **Data:** Yahoo Finance for chart data (futures symbols ES=F, NQ=F, etc.)
- **Charts:** Yahoo chart data with futures-specific default symbols
- **What you can trade:** Futures contracts, commodities
- **Tabs:** Home, Charts, Trade, Automate, Analytics, Settings (6 tabs — no Markets, no Tools)
- **Unique features:** Futures-specific contract list, demo/live toggle, Tradovate integration
- **Requires:** NinjaTrader/Tradovate account + credentials

---

## Chart Data Sources Per Hub

| Hub | Quote Data | Chart Data | Order Execution |
|-----|-----------|------------|-----------------|
| Paper | Yahoo Finance | Yahoo `/v8/finance/chart/` | Local on-device simulation |
| Alpaca | Alpaca IEX snapshots | Alpaca Bars API (fallback: Yahoo) | Alpaca REST API |
| Futures | Yahoo Finance | Yahoo `/v8/finance/chart/` (ES=F, NQ=F, etc.) | Tradovate REST API |

---

## Implementation Status — ALL PHASES COMPLETE ✅

### Phase 1: Hub Branding on Every Screen ✅
- [x] Every view has hub-prefixed nav title ("Paper Charts", "Alpaca Trade", "Futures Analytics")
- [x] Tab bar tint = hub accent color (green/blue/orange)
- [x] TradeView hub identity banner (broker name + live/paper badge)
- [x] TradingDashboardView hub-branded symbol bar + timeframe buttons
- [x] WatchlistView hub branding
- [x] AnalyticsView hub branding
- [x] AutomationView hub branding
- [x] ToolsView hub branding

### Phase 2: Hub-Specific Chart Data ✅
- [x] Added `fetchAlpacaBars()` to StockService for Alpaca charts
- [x] Added `AlpacaBarsResponse` / `AlpacaBarData` models to YahooModels.swift
- [x] TradingDashboardView switches chart data source per hub
- [x] Futures hub defaults to futures symbols (ES=F, NQ=F, CL=F, GC=F, SI=F, ZB=F, YM=F, RTY=F)
- [x] Paper hub defaults to stock symbols (AAPL, GOOGL, etc.)
- [x] Alpaca hub uses Alpaca Bars API with Yahoo fallback

### Phase 3: Hub-Specific Watchlists ✅
- [x] Paper watchlist: user-customizable stock watchlist (persisted)
- [x] Alpaca watchlist: separate user-customizable watchlist (persisted)
- [x] Futures: fixed contract list (ES=F, NQ=F, CL=F, GC=F, SI=F, ZB=F, YM=F, RTY=F)
- [x] `watchlistForHub()` accessor on StockService
- [x] `addToWatchlist/removeFromWatchlist/moveWatchlistItem` all hub-aware
- [x] SearchStockSheet uses hub-aware add
- [x] WatchlistView reads from hub-specific watchlist
- [x] `refreshAll()` fetches quotes for all watchlists + futures symbols

### Phase 4: QA ✅
- [x] getDiagnostics on ALL files — zero errors
- [x] All views compile cleanly
- [x] Pushed to GitHub

---

## Files Modified (This Session)
- `StockPaperTrader/Views/ContentView.swift` — tab bar tint = hub accent color
- `StockPaperTrader/Views/TradingDashboardView.swift` — hub-specific chart data, symbol bar, timeframe colors, nav title
- `StockPaperTrader/Views/TradeView.swift` — hub identity banner, hub nav title
- `StockPaperTrader/Views/WatchlistView.swift` — hub-specific watchlist, hub nav title, hub-aware add/remove/move
- `StockPaperTrader/Views/AutomationView.swift` — hub nav title
- `StockPaperTrader/Views/AnalyticsView.swift` — hub nav title
- `StockPaperTrader/Views/ToolsView.swift` — hub nav title
- `StockPaperTrader/Services/StockService.swift` — futuresSymbols, alpacaWatchlist, fetchAlpacaBars(), hub-aware watchlist methods
- `StockPaperTrader/Services/YahooModels.swift` — AlpacaBarsResponse, AlpacaBarData models
