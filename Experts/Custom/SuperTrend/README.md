# SuperTrend Expert Advisors

This folder contains two Expert Advisors (EAs) that trade based on SuperTrend indicator signals.

## Files

1. **SuperTrend_EA.mq5** - Advanced version with comprehensive features
2. **SuperTrend_Simple_EA.mq5** - Simple version for beginners
3. **SuperTrend_MultiTimeframe.mq5** - Multi-timeframe strategy with 30M trend filter
4. **README.md** - This documentation file

## SuperTrend Indicator

Both EAs use the SuperTrend indicator located at `Indicators\Supertrend.mq5`. The indicator provides:
- **TrendDirection buffer (index 2)**: 
  - 0 = Uptrend (Green)
  - 1 = Downtrend (Red)
- **Trend buffer (index 0)**: SuperTrend line value

## SuperTrend_EA.mq5 (Advanced Version)

### Features:
- Configurable SuperTrend parameters (ATR Multiplier, ATR Period)
- Risk management with Stop Loss and Take Profit
- Option to use SuperTrend line as dynamic SL/TP
- Trailing stop loss functionality
- Position management options

### Input Parameters:
- **ATRMultiplier**: 9.0 (default) - SuperTrend ATR multiplier
- **ATRPeriod**: 27 (default) - ATR calculation period
- **LotSize**: 0.1 - Trade lot size
- **Magic**: 123456 - Unique identifier for trades
- **CloseOpposite**: true - Close opposite trades on signal change
- **OnlyOnePosition**: true - Limit to one position per direction
- **StopLoss**: 0 - Fixed stop loss in points (0 = disabled)
- **TakeProfit**: 0 - Fixed take profit in points (0 = disabled)
- **UseSupertrendSLTP**: true - Use SuperTrend line as dynamic SL/TP

### Trading Logic:
1. **Buy Signal**: When SuperTrend changes to uptrend (TrendDirection = 0)
2. **Sell Signal**: When SuperTrend changes to downtrend (TrendDirection = 1)
3. **Position Management**: Automatically closes opposite positions
4. **Dynamic SL**: Updates stop loss based on SuperTrend line movement

## SuperTrend_Simple_EA.mq5 (Beginner Version)

### Features:
- Simple and easy to understand code
- Basic position management
- Uses default SuperTrend parameters
- No stop loss or take profit (manual management required)

### Input Parameters:
- **LotSize**: 0.1 - Trade lot size
- **Magic**: 123456 - Unique identifier for trades
- **CloseOpposite**: true - Close opposite trades on signal change

### Trading Logic:
1. **Buy Signal**: When SuperTrend changes to uptrend
2. **Sell Signal**: When SuperTrend changes to downtrend
3. **Position Management**: One position per direction, closes opposite trades

## SuperTrend_MultiTimeframe.mq5 (Advanced Multi-TF Strategy)

### Features:
- **30M Trend Filter**: Uses 30-minute SuperTrend as major trend direction
- **Multi-Timeframe Entries**: Places trades on M1, M2, M3, M5, M10, M15 when conditions are met
- **Smart Entry Logic**: Only enters when price is near SuperTrend line
- **Spread Consideration**: Adds spread buffer for better entry timing
- **Automatic Position Management**: Closes all positions when 30M trend changes

### Input Parameters:
- **LotSize**: 0.1 - Trade lot size per order
- **Magic**: 123456 - Unique identifier for trades
- **SpreadBuffer**: 10 - Additional points to add to spread for entry
- **ATRMultiplier**: 9.0 - SuperTrend ATR multiplier
- **ATRPeriod**: 27 - ATR calculation period
- **MaxDistanceFromLine**: 50 - Maximum distance from SuperTrend line to enter (points)
- **UseFixedSL**: false - Use fixed stop loss instead of SuperTrend line
- **FixedSL**: 100 - Fixed stop loss in points

### Trading Logic:
1. **Trend Filter**: Checks 30-minute SuperTrend for major trend direction
2. **Bullish 30M**: 
   - Looks for buy opportunities on M1, M2, M3, M5, M10, M15
   - Enters buy when price is near green SuperTrend line (support)
   - Uses SuperTrend line as stop loss (or fixed SL if enabled)
3. **Bearish 30M**:
   - Looks for sell opportunities on M1, M2, M3, M5, M10, M15
   - Enters sell when price is near red SuperTrend line (resistance)
   - Uses SuperTrend line as stop loss (or fixed SL if enabled)
4. **Trend Change**: When 30M trend changes, closes ALL positions and switches direction

### Position Management:
- **One position per timeframe per direction**
- **Comment-based tracking**: "ST_Buy_M1", "ST_Sell_M5", etc.
- **Automatic closure**: All positions closed when 30M trend changes
- **Smart entry**: Only enters when price is within specified distance from SuperTrend line

## Installation Instructions

1. Copy the EA files to `Experts\Custom\SuperTrend\` folder
2. Ensure the SuperTrend indicator is in `Indicators\` folder
3. Compile the EA files in MetaEditor
4. Attach the EA to a chart in MetaTrader 5

## Important Notes

### Risk Warning
- These EAs are for educational purposes
- Always test on demo account first
- Use proper risk management
- Monitor trades regularly

### SuperTrend Signal Timing
- Signals are generated on bar close (previous completed bar)
- No repainting - signals are final once bar closes
- Works on any timeframe

### Recommended Settings
- **Timeframe**: H1 or H4 for swing trading
- **ATR Multiplier**: 2.0-3.0 for active trading, 9.0+ for long-term trends
- **ATR Period**: 10-14 for short-term, 27+ for long-term
- **Lot Size**: Start with 0.01 for testing

## Troubleshooting

### Common Issues:
1. **"Failed to create SuperTrend indicator handle"**
   - Ensure SuperTrend.ex5 is compiled and in Indicators folder
   - Check indicator name and path

2. **No trades opening**
   - Check if AutoTrading is enabled
   - Verify sufficient margin
   - Check Expert Advisor settings

3. **Trades closing immediately**
   - Check stop loss settings
   - Verify spread and slippage tolerance

### Debug Information:
- Both EAs print debug information to the Experts log
- Monitor the log for signal detection and trade execution

## Customization

### Modifying Signal Logic:
You can modify the signal detection in the `OnTick()` function to add:
- Additional filters (moving averages, RSI, etc.)
- Time-based trading restrictions
- News filter integration

### Adding Risk Management:
Consider adding:
- Maximum daily loss limits
- Equity-based position sizing
- Correlation filters for multiple pairs

## Support

For questions or modifications:
- Study the code comments
- Test modifications on demo account
- Use proper version control for code changes

---

**Disclaimer**: Trading involves risk. Past performance does not guarantee future results. Use these EAs at your own risk.
