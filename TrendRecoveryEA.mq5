#property strict
#property version   "1.20"
#property description "Trend following EA with controlled recovery, profit protection and hard risk limits."
#include <Trade/Trade.mqh>
#include "modules/ExitEngine.mqh"
CTrade trade;

enum TrendDirection { TREND_NONE=0, TREND_BUY=1, TREND_SELL=-1 };
enum CampaignState { CAMPAIGN_IDLE=0, CAMPAIGN_TREND, CAMPAIGN_PROFIT, CAMPAIGN_RECOVERY, CAMPAIGN_EXIT, CAMPAIGN_LOCKED };

//---------- TREND SETTINGS ----------
input ENUM_TIMEFRAMES TrendTimeframe=PERIOD_M15;
input ENUM_TIMEFRAMES HigherTimeframe=PERIOD_H1;
input int FastEMAPeriod=20;
input int SlowEMAPeriod=50;
input int TrendEMAPeriod=200;
input int ADXPeriod=14;
input double MinimumADX=20.0;
input double MaximumATRPoints=0.0;
input bool UseRSIConfirmation=true;
input int RSIPeriod=14;
input double RSIForBuy=50.0;
input double RSIForSell=50.0;
input int ReversalConfirmationBars=2;

//---------- ENTRY SETTINGS ----------
input double InitialLot=0.01;
input double MaxLot=0.10;
input int EntryCooldownSeconds=900;
input int MaximumPositions=1;
input double MinimumEntryDistance=0.0;
input double MaximumSpread=80.0;
input long MagicNumber=26080901;
input int SlippagePoints=30;

//---------- PROFIT SETTINGS ----------
input bool UseInitialSL=true;
input double InitialSL_ATR=2.5;
input bool UseBreakEven=true;
input double BreakEvenStartUSD=5.0;
input double BreakEvenOffsetUSD=0.20;
input bool UseProfitLock=true;
input double ProfitLockStepUSD=3.0;
input double ProfitLockStartUSD=8.0;
input double ProfitLockOffsetUSD=3.0;
input bool UseATRTrailing=true;
input double ATRTrailingMultiplier=2.0;
input double ATRTrailingStartUSD=10.0;
input double CampaignProfitTargetUSD=0.0;
input double CampaignProfitTrailStartUSD=10.0;
input double CampaignProfitGivebackUSD=3.0;

//---------- RECOVERY SETTINGS ----------
input bool UseRecovery=true;
input double RecoveryTriggerUSD=5.0;
input double RecoveryMultiplier=1.0;
input double MaxRecoveryLot=0.05;
input int MaxRecoveryPositions=1;
input double RecoveryTargetUSD=1.0;
input double RecoveryMinProfitUSD=0.0;
input double RecoveryMaxLossUSD=50.0;
input bool CloseOnStrongReversalIfNoRecovery=true;

//---------- RISK SETTINGS ----------
input double MaxCampaignLossUSD=100.0;
input int MaxCampaignHours=24;
input int MaximumExposurePositions=2;

//---------- EQUITY PROTECTION ----------
input double MaxEquityDrawdownPercent=15.0;
input bool ClosePositionsOnEquityProtection=true;

//---------- DAILY LOSS PROTECTION ----------
input double MaxDailyLossUSD=0.0;
input double MaxDailyLossPercent=0.0;
input bool ClosePositionsOnDailyProtection=true;

//---------- SESSION SETTINGS ----------
input bool UseTradingSession=true;
input int TradingStartHour=13;
input int TradingEndHour=23;

//---------- LOT MANAGEMENT ----------
input bool UseEquityScaling=false;
input double BaseEquity=1500.0;
input double BaseLot=0.01;

//---------- EXECUTION SETTINGS ----------
input bool RequireHedgingAccountForRecovery=true;
input bool UseNewBarForEntry=true;

//---------- DEBUG SETTINGS ----------
input bool EnableLogging=true;
input bool LogTrendChanges=true;

int hFastEMA=-1,hSlowEMA=-1,hTrendEMA=-1,hHTFEMA=-1,hADX=-1,hATR=-1,hRSI=-1;
datetime g_lastEntryTime=0,g_lastBarTime=0;
TrendDirection g_lastTrend=TREND_NONE;
CampaignState g_state=CAMPAIGN_IDLE;
bool g_closePending=false;
ExitSnapshot g_exitSnapshot;

string GVPeak(){return "TRENDREC_PEAK_"+(string)MagicNumber+"_"+_Symbol;}
string GVDaily(){return "TRENDREC_DAYEQ_"+(string)MagicNumber+"_"+_Symbol;}
string GVDay(){return "TRENDREC_DAY_"+(string)MagicNumber+"_"+_Symbol;}
void Log(string text){if(EnableLogging)Print("[TrendRecoveryEA] ",text);}

int VolumeDigits(){double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);int d=0;while(d<8&&MathAbs(step-MathRound(step))>1e-10){step*=10.0;d++;}return d;}

double NormalizeLot(double lot)
{
   double vmin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),vmax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0||vmin<=0||vmax<=0)return 0;
   lot=MathMin(lot,vmax);lot=MathMin(lot,MaxLot);lot=MathMax(lot,vmin);lot=MathFloor(lot/step+1e-9)*step;if(lot<vmin)lot=vmin;
   return NormalizeDouble(lot,VolumeDigits());
}

double NormalizePrice(double price){return NormalizeDouble(price,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));}

double MinStopDistance()
{
   long stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)MathMax(stops,freeze)*_Point;
}

bool TradeSucceeded()
{
   uint rc=trade.ResultRetcode();
   return rc==TRADE_RETCODE_DONE||rc==TRADE_RETCODE_DONE_PARTIAL||rc==TRADE_RETCODE_PLACED;
}

bool IsSpreadAcceptable()
{
   if(MaximumSpread<=0)return true;MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return false;
   return (tick.ask-tick.bid)/_Point<=MaximumSpread;
}

bool IsTradingSession()
{
   if(!UseTradingSession)return true;MqlDateTime dt;TimeToStruct(TimeTradeServer(),dt);
   if(TradingStartHour==TradingEndHour)return true;
   if(TradingStartHour<TradingEndHour)return dt.hour>=TradingStartHour&&dt.hour<TradingEndHour;
   return dt.hour>=TradingStartHour||dt.hour<TradingEndHour;
}

bool IsNewBar()
{
   datetime t=iTime(_Symbol,TrendTimeframe,0);if(t<=0)return false;if(t!=g_lastBarTime){g_lastBarTime=t;return true;}return false;
}

bool GetBufferValue(int handle,int buffer,int shift,double &value)
{
   if(handle<0)return false;double data[1];if(CopyBuffer(handle,buffer,shift,1,data)!=1)return false;value=data[0];return true;
}
bool GetATR(double &atr){return GetBufferValue(hATR,0,1,atr);}

TrendDirection DetectTrend()
{
   double fast,slow,trend,htf,adx,atr,rsi;
   if(!GetBufferValue(hFastEMA,0,1,fast)||!GetBufferValue(hSlowEMA,0,1,slow)||!GetBufferValue(hTrendEMA,0,1,trend)||!GetBufferValue(hHTFEMA,0,1,htf)||!GetBufferValue(hADX,0,1,adx)||!GetATR(atr))return TREND_NONE;
   double close=iClose(_Symbol,TrendTimeframe,1);if(close<=0||adx<MinimumADX)return TREND_NONE;if(MaximumATRPoints>0&&atr/_Point>MaximumATRPoints)return TREND_NONE;
   bool buy=fast>slow&&close>trend&&close>htf,sell=fast<slow&&close<trend&&close<htf;
   if(UseRSIConfirmation){if(!GetBufferValue(hRSI,0,1,rsi))return TREND_NONE;buy=buy&&rsi>=RSIForBuy;sell=sell&&rsi<=RSIForSell;}
   if(buy)return TREND_BUY;if(sell)return TREND_SELL;return TREND_NONE;
}

bool ConfirmTrend(TrendDirection direction)
{
   int bars=MathMax(1,ReversalConfirmationBars);
   for(int shift=1;shift<=bars;shift++)
   {
      double fast,slow,trend,htf,adx,atr,rsi;
      if(!GetBufferValue(hFastEMA,0,shift,fast)||!GetBufferValue(hSlowEMA,0,shift,slow)||!GetBufferValue(hTrendEMA,0,shift,trend)||!GetBufferValue(hHTFEMA,0,shift,htf)||!GetBufferValue(hADX,0,shift,adx)||!GetBufferValue(hATR,0,shift,atr))return false;
      double close=iClose(_Symbol,TrendTimeframe,shift);if(close<=0||adx<MinimumADX)return false;if(MaximumATRPoints>0&&atr/_Point>MaximumATRPoints)return false;
      bool ok=(direction==TREND_BUY)?(fast>slow&&close>trend&&close>htf):(fast<slow&&close<trend&&close<htf);
      if(UseRSIConfirmation){if(!GetBufferValue(hRSI,0,shift,rsi))return false;ok=ok&&((direction==TREND_BUY)?rsi>=RSIForBuy:rsi<=RSIForSell);}
      if(!ok)return false;
   }
   return true;
}

int CountPositions()
{
   int n=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)==_Symbol&&(long)PositionGetInteger(POSITION_MAGIC)==MagicNumber)n++;}return n;
}

int CountRecoveryPositions()
{
   int n=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)n++;}return n;
}

double GetBasketProfit()
{
   double total=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;total+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}return total;
}

double GetNormalProfit()
{
   double total=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)continue;total+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}return total;
}

TrendDirection GetOriginalDirection()
{
   for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)continue;ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);if(type==POSITION_TYPE_BUY)return TREND_BUY;if(type==POSITION_TYPE_SELL)return TREND_SELL;}return TREND_NONE;
}

datetime GetCampaignStartTime()
{
   datetime oldest=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;datetime x=(datetime)PositionGetInteger(POSITION_TIME);if(oldest==0||x<oldest)oldest=x;}return oldest;
}

bool HasMinEntryDistance(TrendDirection direction)
{
   if(MinimumEntryDistance<=0)return true;MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return false;double price=(direction==TREND_BUY)?tick.ask:tick.bid;
   for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(MathAbs(price-PositionGetDouble(POSITION_PRICE_OPEN))<MinimumEntryDistance)return false;}return true;
}

bool IsHedgingAccount(){return (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;}

bool RiskLocked()
{
   if(MaxEquityDrawdownPercent<=0)return false;double equity=AccountInfoDouble(ACCOUNT_EQUITY),peak=GlobalVariableGet(GVPeak());
   if(peak<=0){GlobalVariableSet(GVPeak(),equity);peak=equity;}if(equity>peak){peak=equity;GlobalVariableSet(GVPeak(),peak);}
   return peak>0&&(peak-equity)/peak*100.0>=MaxEquityDrawdownPercent;
}

void UpdateDailyState()
{
   MqlDateTime dt;TimeToStruct(TimeTradeServer(),dt);long day=(long)dt.year*10000+(long)dt.mon*100+dt.day;
   if(GlobalVariableGet(GVDay())!=(double)day){GlobalVariableSet(GVDay(),(double)day);GlobalVariableSet(GVDaily(),AccountInfoDouble(ACCOUNT_EQUITY));}
}

bool DailyLossLocked()
{
   UpdateDailyState();double start=GlobalVariableGet(GVDaily());if(start<=0)return false;double loss=start-AccountInfoDouble(ACCOUNT_EQUITY);
   if(MaxDailyLossUSD>0&&loss>=MaxDailyLossUSD)return true;if(MaxDailyLossPercent>0&&loss/start*100.0>=MaxDailyLossPercent)return true;return false;
}

bool CanOpenEntry(TrendDirection direction)
{
   if(direction==TREND_NONE||g_state==CAMPAIGN_LOCKED||g_closePending)return false;if(RiskLocked()||DailyLossLocked())return false;if(!IsTradingSession()||!IsSpreadAcceptable())return false;
   if(CountPositions()>=MaximumPositions)return false;if(MaximumExposurePositions>0&&CountPositions()>=MaximumExposurePositions)return false;if(g_lastEntryTime>0&&TimeCurrent()-g_lastEntryTime<EntryCooldownSeconds)return false;
   if(!HasMinEntryDistance(direction)||!ConfirmTrend(direction))return false;return true;
}

double CalculateLot(){double lot=InitialLot;if(UseEquityScaling&&BaseEquity>0)lot=BaseLot*(AccountInfoDouble(ACCOUNT_EQUITY)/BaseEquity);return NormalizeLot(lot);}

bool BuildInitialSL(TrendDirection direction,double entry,double &sl)
{
   sl=0;if(!UseInitialSL||InitialSL_ATR<=0)return true;double atr;if(!GetATR(atr))return false;double distance=MathMax(atr*InitialSL_ATR,MinStopDistance());if(direction==TREND_BUY)sl=NormalizePrice(entry-distance);else sl=NormalizePrice(entry+distance);return true;
}

bool ExecuteEntry(TrendDirection direction)
{
   double lot=CalculateLot();if(lot<=0)return false;MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return false;double entry=(direction==TREND_BUY)?tick.ask:tick.bid,sl;if(!BuildInitialSL(direction,entry,sl))return false;
   trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);
   bool sent=(direction==TREND_BUY)?trade.Buy(lot,_Symbol,0,sl,0,"TREND BUY"):trade.Sell(lot,_Symbol,0,sl,0,"TREND SELL");
   if(!sent||!TradeSucceeded()){Log("Entry failed retcode="+(string)trade.ResultRetcode()+" "+trade.ResultRetcodeDescription());return false;}
   g_lastEntryTime=TimeCurrent();g_state=CAMPAIGN_TREND;Log("Entry executed "+(direction==TREND_BUY?"BUY":"SELL")+" lot="+DoubleToString(lot,2));return true;
}

double MoneyToPriceDistance(double money,double volume)
{
   if(money<=0||volume<=0)return 0;double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE),tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);if(tickValue<=0||tickSize<=0)return 0;return money/(tickValue*volume)*tickSize;
}

bool IsValidSLForMarket(ENUM_POSITION_TYPE type,double sl)
{
   MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return false;double minDist=MinStopDistance();if(type==POSITION_TYPE_BUY)return sl<=tick.bid-minDist;return sl>=tick.ask+minDist;
}

bool ModifyPositionSL(ulong ticket,double newSL)
{
   if(!PositionSelectByTicket(ticket))return false;ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);double old=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);newSL=NormalizePrice(newSL);
   if(!IsValidSLForMarket(type,newSL))return false;if(type==POSITION_TYPE_BUY&&old>0&&newSL<=old+_Point)return false;if(type==POSITION_TYPE_SELL&&old>0&&newSL>=old-_Point)return false;
   trade.SetExpertMagicNumber(MagicNumber);if(!trade.PositionModify(ticket,newSL,tp)||!TradeSucceeded()){Log("SL modify failed retcode="+(string)trade.ResultRetcode()+" "+trade.ResultRetcodeDescription());return false;}return true;
}

void ApplyProfitProtection(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))return;ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);double profit=PositionGetDouble(POSITION_PROFIT),open=PositionGetDouble(POSITION_PRICE_OPEN),volume=PositionGetDouble(POSITION_VOLUME),currentSL=PositionGetDouble(POSITION_SL),desired=0;
   if(UseBreakEven&&profit>=BreakEvenStartUSD){double dist=MoneyToPriceDistance(BreakEvenOffsetUSD,volume);if(dist>0)desired=(type==POSITION_TYPE_BUY)?open+dist:open-dist;}
   if(UseProfitLock&&profit>=ProfitLockStartUSD&&ProfitLockStepUSD>0){int steps=(int)MathFloor((profit-ProfitLockStartUSD)/ProfitLockStepUSD)+1;double locked=ProfitLockOffsetUSD+(steps-1)*ProfitLockStepUSD,dist=MoneyToPriceDistance(locked,volume);if(dist>0){double candidate=(type==POSITION_TYPE_BUY)?open+dist:open-dist;if(desired==0||(type==POSITION_TYPE_BUY?candidate>desired:candidate<desired))desired=candidate;}}
   if(UseATRTrailing&&profit>=ATRTrailingStartUSD){double atr;MqlTick tick;if(GetATR(atr)&&SymbolInfoTick(_Symbol,tick)){double candidate=(type==POSITION_TYPE_BUY)?tick.bid-atr*ATRTrailingMultiplier:tick.ask+atr*ATRTrailingMultiplier;if(desired==0||(type==POSITION_TYPE_BUY?candidate>desired:candidate<desired))desired=candidate;}}
   if(desired<=0)return;double minDist=MinStopDistance();MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))return;if(type==POSITION_TYPE_BUY)desired=MathMin(desired,tick.bid-minDist);else desired=MathMax(desired,tick.ask+minDist);desired=NormalizePrice(desired);
   if(type==POSITION_TYPE_BUY&&currentSL>0&&desired<=currentSL+_Point)return;if(type==POSITION_TYPE_SELL&&currentSL>0&&desired>=currentSL-_Point)return;ModifyPositionSL(ticket,desired);
}

void ProfitEngine()
{
   for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;ApplyProfitProtection(t);}
}

bool CloseCampaign()
{
   bool requestOK=true;g_state=CAMPAIGN_EXIT;
   for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);bool sent=trade.PositionClose(t);if(!sent||!TradeSucceeded()){requestOK=false;Log("Close failed ticket="+(string)t+" retcode="+(string)trade.ResultRetcode()+" "+trade.ResultRetcodeDescription());}}
   g_closePending=(CountPositions()>0);if(!g_closePending&&requestOK)g_state=CAMPAIGN_IDLE;return requestOK;
}

bool StartRecovery(TrendDirection reversal)
{
   if(!UseRecovery||CountRecoveryPositions()>=MaxRecoveryPositions)return false;
   if(!IsHedgingAccount()&&RequireHedgingAccountForRecovery){Log("Recovery skipped: account is not hedging.");if(CloseOnStrongReversalIfNoRecovery)CloseCampaign();return false;}
   TrendDirection original=GetOriginalDirection();if(original==TREND_NONE||reversal==original)return false;if(GetNormalProfit()>-RecoveryTriggerUSD)return false;
   double totalLot=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)continue;totalLot+=PositionGetDouble(POSITION_VOLUME);}
   double lot=NormalizeLot(MathMin(totalLot*RecoveryMultiplier,MaxRecoveryLot));if(lot<=0)return false;
   trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);bool sent=(reversal==TREND_BUY)?trade.Buy(lot,_Symbol,0,0,0,"RECOVERY BUY"):trade.Sell(lot,_Symbol,0,0,0,"RECOVERY SELL");
   if(!sent||!TradeSucceeded()){Log("Recovery failed retcode="+(string)trade.ResultRetcode()+" "+trade.ResultRetcodeDescription());if(CloseOnStrongReversalIfNoRecovery)CloseCampaign();return false;}
   g_state=CAMPAIGN_RECOVERY;Log("Controlled recovery activated lot="+DoubleToString(lot,2));return true;
}

void RecoveryEngine()
{
   if(CountRecoveryPositions()<=0)return;g_state=CAMPAIGN_RECOVERY;double basket=GetBasketProfit();
   if(RecoveryTargetUSD>0&&basket>=RecoveryTargetUSD&&basket>=RecoveryMinProfitUSD){Log("Recovery target reached; closing basket.");CloseCampaign();return;}
   if(RecoveryMaxLossUSD>0&&basket<=-RecoveryMaxLossUSD){Log("Recovery max loss reached; closing basket.");CloseCampaign();}
}

void CheckTrendReversal(TrendDirection trend)
{
   TrendDirection original=GetOriginalDirection();if(original==TREND_NONE||trend==TREND_NONE||trend==original)return;if(!ConfirmTrend(trend))return;
   if(!StartRecovery(trend)&&!UseRecovery&&CloseOnStrongReversalIfNoRecovery)CloseCampaign();
}

void RiskEngine()
{
   if(RiskLocked()){if(g_state!=CAMPAIGN_LOCKED)Log("Hard equity protection triggered.");g_state=CAMPAIGN_LOCKED;if(ClosePositionsOnEquityProtection&&CountPositions()>0)CloseCampaign();return;}
   if(DailyLossLocked()){if(g_state!=CAMPAIGN_LOCKED)Log("Daily loss protection triggered.");g_state=CAMPAIGN_LOCKED;if(ClosePositionsOnDailyProtection&&CountPositions()>0)CloseCampaign();return;}
   if(MaxCampaignLossUSD>0&&GetBasketProfit()<=-MaxCampaignLossUSD){Log("Maximum campaign loss reached.");CloseCampaign();return;}
   if(MaxCampaignHours>0&&CountPositions()>0){datetime start=GetCampaignStartTime();if(start>0&&TimeCurrent()-start>=MaxCampaignHours*3600){Log("Maximum campaign duration reached.");CloseCampaign();}}
}

void ResetExitState()
{
   ResetExitSnapshot(g_exitSnapshot);
}

bool CampaignExitEngine()
{
   if(CountPositions()<=0)
      return false;

   double basket=GetBasketProfit();
   UpdateExitSnapshot(g_exitSnapshot,basket);

   if(ExitLossReached(g_exitSnapshot,MaxCampaignLossUSD))
   {
      Log("ExitEngine: campaign loss limit reached.");
      CloseCampaign();
      return true;
   }

   if(ExitDurationReached(GetCampaignStartTime(),MaxCampaignHours))
   {
      Log("ExitEngine: campaign timeout reached.");
      CloseCampaign();
      return true;
   }

   if(ExitTargetReached(g_exitSnapshot,CampaignProfitTargetUSD))
   {
      Log("ExitEngine: campaign profit target reached.");
      CloseCampaign();
      return true;
   }

   if(CampaignProfitGivebackUSD>0.0 &&
      g_exitSnapshot.peakProfit>=CampaignProfitTrailStartUSD &&
      ExitDrawdownReached(g_exitSnapshot,CampaignProfitGivebackUSD))
   {
      Log("ExitEngine: campaign profit giveback reached.");
      CloseCampaign();
      return true;
   }

   return false;
}

void ManagePositions(TrendDirection trend)
{
   if(CountPositions()==0)
   {
      ResetExitState();
      if(!g_closePending&&g_state!=CAMPAIGN_LOCKED)g_state=CAMPAIGN_IDLE;
      return;
   }

   if(CampaignExitEngine())
      return;

   ProfitEngine();
   if(CountRecoveryPositions()>0)
      RecoveryEngine();
   else
   {
      g_state=(GetBasketProfit()>0)?CAMPAIGN_PROFIT:CAMPAIGN_TREND;
      CheckTrendReversal(trend);
   }
}

void EntryEngine(TrendDirection trend){if(g_state==CAMPAIGN_LOCKED||g_closePending||CountPositions()>0||trend==TREND_NONE)return;if(CanOpenEntry(trend))ExecuteEntry(trend);}
void UpdateTrendLog(TrendDirection trend){if(!LogTrendChanges||trend==g_lastTrend)return;Log("Trend changed to "+(trend==TREND_BUY?"BUY":trend==TREND_SELL?"SELL":"NONE"));g_lastTrend=trend;}

int OnInit()
{
   ResetExitState();
   trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);
   hFastEMA=iMA(_Symbol,TrendTimeframe,FastEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hSlowEMA=iMA(_Symbol,TrendTimeframe,SlowEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hTrendEMA=iMA(_Symbol,TrendTimeframe,TrendEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hHTFEMA=iMA(_Symbol,HigherTimeframe,TrendEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hADX=iADX(_Symbol,TrendTimeframe,ADXPeriod);hATR=iATR(_Symbol,TrendTimeframe,14);hRSI=iRSI(_Symbol,TrendTimeframe,RSIPeriod,PRICE_CLOSE);
   if(hFastEMA<0||hSlowEMA<0||hTrendEMA<0||hHTFEMA<0||hADX<0||hATR<0||hRSI<0){Log("Indicator initialization failed.");return INIT_FAILED;}
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);if(!GlobalVariableCheck(GVPeak())||GlobalVariableGet(GVPeak())<=0)GlobalVariableSet(GVPeak(),eq);UpdateDailyState();
   int positions=CountPositions();g_state=(positions>0)?(CountRecoveryPositions()>0?CAMPAIGN_RECOVERY:CAMPAIGN_TREND):CAMPAIGN_IDLE;Log("Initialized on "+_Symbol+" positions="+(string)positions);return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hFastEMA>=0)IndicatorRelease(hFastEMA);if(hSlowEMA>=0)IndicatorRelease(hSlowEMA);if(hTrendEMA>=0)IndicatorRelease(hTrendEMA);if(hHTFEMA>=0)IndicatorRelease(hHTFEMA);if(hADX>=0)IndicatorRelease(hADX);if(hATR>=0)IndicatorRelease(hATR);if(hRSI>=0)IndicatorRelease(hRSI);
}

void OnTick()
{
   UpdateDailyState();
   if(g_closePending){if(CountPositions()==0){g_closePending=false;if(g_state!=CAMPAIGN_LOCKED)g_state=CAMPAIGN_IDLE;}else{ProfitEngine();return;}}
   TrendDirection trend=DetectTrend();UpdateTrendLog(trend);RiskEngine();
   if(g_state==CAMPAIGN_EXIT||g_closePending){if(CountPositions()==0&&g_state!=CAMPAIGN_LOCKED)g_state=CAMPAIGN_IDLE;return;}
   ManagePositions(trend);if(g_state==CAMPAIGN_LOCKED||g_closePending)return;if(UseNewBarForEntry&&!IsNewBar())return;EntryEngine(trend);
}
