#property strict
#property version "1.43"
#property description "TrendRecoveryEA v1.43 - hierarchical exit engine, thesis invalidation and hybrid profit trailing."
#include <Trade/Trade.mqh>
CTrade trade;

enum TrendDirection { TREND_NONE=0, TREND_BUY=1, TREND_SELL=-1 };

input ENUM_TIMEFRAMES TrendTimeframe=PERIOD_M15;
input ENUM_TIMEFRAMES HigherTimeframe=PERIOD_H1;
input int FastEMAPeriod=20;
input int SlowEMAPeriod=50;
input int TrendEMAPeriod=200;
input int ADXPeriod=14;
input double MinimumADX=20.0;
input bool UseAsymmetricTrendFilter=true;
input double BuyMinimumADX=23.0;
input double SellMinimumADX=20.0;
input double MaximumATRPoints=0.0;
input bool UseRSIConfirmation=false;
input int RSIPeriod=14;
input double RSIForBuy=50.0;
input double RSIForSell=50.0;
input int ReversalConfirmationBars=2;
input int RegimeBreakConfirmationBars=2;
input int RegimeDamageConfirmationBars=2;
input bool CloseOnRegimeDamage=true;
input bool UseStrongBuyRegimeExit=true;
input int BuyRegimeExitConfirmationBars=1;
input double BuyRegimeExitADX=20.0;

//---------- EXIT ENGINE V1.43
input bool UseHierarchicalExit=true;
input int ExitRegimeDamageScore=6;
input int ExitRegimeWarningScore=3;
input bool ExitOnThesisInvalidation=true;
input int ExitThesisConfirmationBars=2;
input double ATRTrailingHardStartUSD=20.0;
input double CampaignGivebackLevel2USD=5.0;
input double CampaignGivebackLevel3USD=7.0;
input double CampaignGivebackLevel4USD=10.0;
input double CampaignPeakLevel2USD=15.0;
input double CampaignPeakLevel3USD=25.0;
input double CampaignPeakLevel4USD=40.0;
input int CampaignProgressGraceHours=4;
input int CampaignStaleHours=8;
input double CampaignStaleMinProfitUSD=0.0;
input bool UseRecoveryBasketBreakevenExit=true;


input double InitialLot=0.01;
input double MaxLot=0.10;
input int EntryCooldownSeconds=900;
input int MinimumHoldSeconds=300;
input int MaximumPositions=1;
input double MinimumEntryDistance=0.0;
input double MaximumSpread=300.0;
input long MagicNumber=26080901;
input int SlippagePoints=30;

input bool UseInitialSL=true;
input double InitialSL_ATR=1.75;
input double MaxInitialLossUSD=12.0;
input double MaxNormalLossPerTradeUSD=12.0;
input bool UseBreakEven=true;
input double BreakEvenStartUSD=5.0;
input double BreakEvenOffsetUSD=1.5;
input bool UseProfitLock=true;
input double ProfitLockStepUSD=3.0;
input double ProfitLockStartUSD=8.0;
input double ProfitLockOffsetUSD=3.0;
input bool UseATRTrailing=true;
input double ATRTrailingMultiplier=1.8;
input double ATRTrailingStartUSD=20.0;

input double CampaignProfitTargetUSD=0.0;
input double CampaignProfitTrailStartUSD=10.0;
input double CampaignProfitGivebackUSD=3.0;
input double MaxCampaignLossUSD=30.0;
input int MaxCampaignHours=24;

input bool UseRecovery=true;
input double RecoveryTriggerUSD=8.0;
input double RecoveryMultiplier=1.0;
input double MaxRecoveryLot=0.05;
input int MaxRecoveryPositions=1;
input double RecoveryTargetUSD=1.0;
input double RecoveryMinProfitUSD=0.0;
input double RecoveryMaxLossUSD=50.0;
input double RecoveryMaxLossPerTradeUSD=6.0;
input int RecoveryConfirmationBars=4;
input bool CloseOnStrongReversalIfNoRecovery=true;
input bool RecoveryRequireHTFAlignment=true;
input double RecoveryMinimumADX=25.0;
input double RecoveryLockStartUSD=2.0;
input double RecoveryLockProfitUSD=1.0;
input double RecoveryTrailStartUSD=5.0;
input double RecoveryTrailGivebackUSD=2.0;

input int MaximumExposurePositions=2;
input double MaxEquityDrawdownPercent=15.0;
input bool ClosePositionsOnEquityProtection=true;
input double MaxDailyLossUSD=20.0;
input double MaxDailyLossPercent=2.0;
input bool ClosePositionsOnDailyProtection=true;

input bool UseTradingSession=true;
input int TradingStartHour=13;
input int TradingEndHour=23;
input bool UseEquityScaling=false;
input double BaseEquity=1500.0;
input double BaseLot=0.01;
input bool RequireHedgingAccountForRecovery=true;
input bool UseNewBarForEntry=true;
input bool EnableLogging=true;
input bool LogTrendChanges=true;

input bool UseEquityProfitProtection=true;
input double EquityProfitLockStartUSD=25.0;
input double EquityProfitGivebackUSD=50.0;

input bool UseHardNormalUSDLoss=true;
input bool UseWeekendProtection=true;
input int FridayCloseHour=22;
input int FridayCloseMinute=0;
input bool BlockSundayTrading=true;

int hFastEMA=-1,hSlowEMA=-1,hTrendEMA=-1,hHTFEMA=-1,hHTFFastEMA=-1,hHTFSlowEMA=-1,hADX=-1,hATR=-1,hRSI=-1;
datetime g_lastEntryTime=0,g_lastBarTime=0,g_lastSafetyTime=0,g_lastExitTime=0;
TrendDirection g_lastTrend=TREND_NONE;
bool g_closePending=false,g_equityLocked=false,g_profitProtectionLocked=false;
long g_dailyLockDay=0;
double g_peakEquity=0.0,g_dailyStartEquity=0.0,g_profitPeak=0.0,g_profitStart=0.0,g_campaignPeak=0.0;

void Log(string s){if(EnableLogging)Print("[TrendRecoveryEA v1.42] ",s);}
datetime Now(){datetime t=TimeTradeServer();if(t<=0)t=TimeCurrent();return t;}
long DayKey(){MqlDateTime d;TimeToStruct(Now(),d);return (long)d.year*10000+(long)d.mon*100+d.day;}
int VolumeDigits(){double x=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);int d=0;while(d<8&&MathAbs(x-MathRound(x))>1e-10){x*=10.0;d++;}return d;}
double NormalizeLot(double lot){double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);if(mn<=0||mx<=0||st<=0)return 0;lot=MathMin(lot,MathMin(mx,MaxLot));lot=MathMax(lot,mn);lot=MathFloor(lot/st+1e-9)*st;if(lot<mn)lot=mn;return NormalizeDouble(lot,VolumeDigits());}
double NormalizePrice(double p){return NormalizeDouble(p,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));}
double MinStopDistance(){long a=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),b=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);return (double)MathMax(a,b)*_Point;}
bool TradeSucceeded(){uint r=trade.ResultRetcode();return r==TRADE_RETCODE_DONE||r==TRADE_RETCODE_DONE_PARTIAL||r==TRADE_RETCODE_PLACED;}
bool IsHedgingAccount(){return (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;}
bool IsSpreadAcceptable(){if(MaximumSpread<=0)return true;MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;return (t.ask-t.bid)/_Point<=MaximumSpread;}
bool IsTradingSession(){if(!UseTradingSession)return true;MqlDateTime d;TimeToStruct(Now(),d);if(TradingStartHour==TradingEndHour)return true;if(TradingStartHour<TradingEndHour)return d.hour>=TradingStartHour&&d.hour<TradingEndHour;return d.hour>=TradingStartHour||d.hour<TradingEndHour;}
bool IsNewBar(){datetime t=iTime(_Symbol,TrendTimeframe,0);if(t<=0)return false;if(t!=g_lastBarTime){g_lastBarTime=t;return true;}return false;}
bool Buf(int h,int b,int sh,double &v){if(h<0)return false;double x[1];if(CopyBuffer(h,b,sh,1,x)!=1)return false;v=x[0];return true;}
bool GetATR(double &v){return Buf(hATR,0,1,v);}
double TrendADXThreshold(TrendDirection dir){if(!UseAsymmetricTrendFilter)return MinimumADX;return dir==TREND_BUY?MathMax(MinimumADX,BuyMinimumADX):MathMax(MinimumADX,SellMinimumADX);}

void UpdateDailyState(){long day=DayKey();if(g_dailyStartEquity<=0.0){g_dailyStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);g_dailyLockDay=0;}if(g_dailyLockDay!=0&&g_dailyLockDay!=day){g_dailyLockDay=0;g_dailyStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);Log("New trading day: DAILY LOCK RESET.");}}
bool WeekendBlocked(){if(!UseWeekendProtection)return false;MqlDateTime d;TimeToStruct(Now(),d);if(d.day_of_week==6)return true;if(d.day_of_week==0&&BlockSundayTrading)return true;if(d.day_of_week==5)return d.hour*60+d.min>=FridayCloseHour*60+FridayCloseMinute;return false;}

TrendDirection DetectTrend(){double f,s,tr,ht,a,atr,r;if(!Buf(hFastEMA,0,1,f)||!Buf(hSlowEMA,0,1,s)||!Buf(hTrendEMA,0,1,tr)||!Buf(hHTFEMA,0,1,ht)||!Buf(hADX,0,1,a)||!GetATR(atr))return TREND_NONE;double c=iClose(_Symbol,TrendTimeframe,1);if(c<=0)return TREND_NONE;if(MaximumATRPoints>0&&atr/_Point>MaximumATRPoints)return TREND_NONE;bool buy=f>s&&c>tr&&c>ht,sell=f<s&&c<tr&&c<ht;if(buy&&a<TrendADXThreshold(TREND_BUY))buy=false;if(sell&&a<TrendADXThreshold(TREND_SELL))sell=false;if(UseRSIConfirmation){if(!Buf(hRSI,0,1,r))return TREND_NONE;buy=buy&&r>=RSIForBuy;sell=sell&&r<=RSIForSell;}if(buy)return TREND_BUY;if(sell)return TREND_SELL;return TREND_NONE;}

bool ConfirmTrend(TrendDirection dir){int n=MathMax(1,ReversalConfirmationBars);double adxThreshold=TrendADXThreshold(dir);for(int sh=1;sh<=n;sh++){double f,s,tr,ht,a,r;if(!Buf(hFastEMA,0,sh,f)||!Buf(hSlowEMA,0,sh,s)||!Buf(hTrendEMA,0,sh,tr)||!Buf(hHTFEMA,0,sh,ht)||!Buf(hADX,0,sh,a))return false;double c=iClose(_Symbol,TrendTimeframe,sh);if(c<=0||a<adxThreshold)return false;bool ok=dir==TREND_BUY?(f>s&&c>tr&&c>ht):(f<s&&c<tr&&c<ht);if(UseRSIConfirmation){if(!Buf(hRSI,0,sh,r))return false;ok=ok&&(dir==TREND_BUY?r>=RSIForBuy:r<=RSIForSell);}if(!ok)return false;}return true;}

bool ConfirmReversal(TrendDirection dir){int n=MathMax(2,RecoveryConfirmationBars);for(int sh=1;sh<=n;sh++){double f,s,tr,ht,a;if(!Buf(hFastEMA,0,sh,f)||!Buf(hSlowEMA,0,sh,s)||!Buf(hTrendEMA,0,sh,tr)||!Buf(hHTFEMA,0,sh,ht)||!Buf(hADX,0,sh,a))return false;double c=iClose(_Symbol,TrendTimeframe,sh),o=iOpen(_Symbol,TrendTimeframe,sh);if(c<=0||o<=0||a<MinimumADX)return false;bool ok=dir==TREND_BUY?(c>o&&c>f&&f>s):(c<o&&c<f&&f<s);if(!ok)return false;}double f1,f2,f3;if(!Buf(hFastEMA,0,1,f1)||!Buf(hFastEMA,0,2,f2)||!Buf(hFastEMA,0,3,f3))return false;return dir==TREND_BUY?(f1>=f2&&f2>=f3):(f1<=f2&&f2<=f3);}

int CountPositions(){int n=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)==_Symbol&&(long)PositionGetInteger(POSITION_MAGIC)==MagicNumber)n++;}return n;}
int CountRecoveryPositions(){int n=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)n++;}return n;}
double BasketProfit(){double p=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}return p;}
double NormalProfit(){double p=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)continue;p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}return p;}
double RecoveryProfit(){double p=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")<0)continue;p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}return p;}
TrendDirection OriginalDirection(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)continue;return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?TREND_BUY:TREND_SELL;}return TREND_NONE;}
datetime CampaignStart(){datetime x=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;datetime p=(datetime)PositionGetInteger(POSITION_TIME);if(x==0||p<x)x=p;}return x;}

bool CloseCampaign(){if(CountPositions()<=0){g_closePending=false;return true;}trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);bool all=true;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(!trade.PositionClose(t)||!TradeSucceeded())all=false;}g_closePending=CountPositions()>0;if(!g_closePending)g_lastExitTime=Now();return all;}

double MoneyDistance(double money,double vol){if(money<=0||vol<=0)return 0;double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE),ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);if(tv<=0||ts<=0)return 0;return money/(tv*vol)*ts;}
double CalcLossUSD(ENUM_POSITION_TYPE ty,double volume,double openPrice,double stopPrice){double pnl=0;ENUM_ORDER_TYPE ot=ty==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL;if(!OrderCalcProfit(ot,_Symbol,volume,openPrice,stopPrice,pnl))return 0;return MathMax(0.0,-pnl);}
double RiskSLByUSD(ENUM_POSITION_TYPE ty,double volume,double openPrice,double riskUSD){double md=MathMax(MinStopDistance(),2.0*_Point),dist=MoneyDistance(riskUSD,volume);if(dist<md)dist=md;if(dist<=0)return 0;double lo=md,hi=dist*2.0;for(int k=0;k<20&&CalcLossUSD(ty,volume,openPrice,ty==POSITION_TYPE_BUY?openPrice-hi:openPrice+hi)<riskUSD;k++)hi*=2.0;for(int i=0;i<45;i++){double mid=(lo+hi)*0.5;double loss=CalcLossUSD(ty,volume,openPrice,ty==POSITION_TYPE_BUY?openPrice-mid:openPrice+mid);if(loss>=riskUSD)hi=mid;else lo=mid;}return NormalizePrice(ty==POSITION_TYPE_BUY?openPrice-hi:openPrice+hi);}
bool ValidSL(ENUM_POSITION_TYPE ty,double sl){MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;double md=MinStopDistance();return ty==POSITION_TYPE_BUY?sl<=t.bid-md:sl>=t.ask+md;}
bool ModifySL(ulong ticket,double sl){if(!PositionSelectByTicket(ticket))return false;ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);double old=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);sl=NormalizePrice(sl);if(!ValidSL(ty,sl))return false;if(ty==POSITION_TYPE_BUY&&old>0&&sl<=old+_Point)return false;if(ty==POSITION_TYPE_SELL&&old>0&&sl>=old-_Point)return false;return trade.PositionModify(ticket,sl,tp)&&TradeSucceeded();}

bool OpenTrade(TrendDirection d,string comment,double lot,double riskUSD){MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;double atr;if(!GetATR(atr))return false;ENUM_POSITION_TYPE ty=d==TREND_BUY?POSITION_TYPE_BUY:POSITION_TYPE_SELL;double p=d==TREND_BUY?t.ask:t.bid,sl=0;if(riskUSD>0)sl=RiskSLByUSD(ty,lot,p,riskUSD);if(sl<=0&&UseInitialSL&&InitialSL_ATR>0){double dist=MathMax(atr*InitialSL_ATR,MinStopDistance());sl=NormalizePrice(ty==POSITION_TYPE_BUY?p-dist:p+dist);}if(sl<=0||!ValidSL(ty,sl))return false;trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);bool ok=d==TREND_BUY?trade.Buy(lot,_Symbol,0,sl,0,comment):trade.Sell(lot,_Symbol,0,sl,0,comment);if(!ok||!TradeSucceeded()){Log("ENTRY FAILED "+trade.ResultRetcodeDescription());return false;}return true;}
double EntryLot(){double lot=UseEquityScaling&&BaseEquity>0?BaseLot*AccountInfoDouble(ACCOUNT_EQUITY)/BaseEquity:InitialLot;return NormalizeLot(lot);}
bool HasDistance(TrendDirection d){if(MinimumEntryDistance<=0)return true;MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;double p=d==TREND_BUY?t.ask:t.bid;for(int i=PositionsTotal()-1;i>=0;i--){ulong x=PositionGetTicket(i);if(x==0||!PositionSelectByTicket(x))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(MathAbs(p-PositionGetDouble(POSITION_PRICE_OPEN))<MinimumEntryDistance)return false;}return true;}
bool CanOpen(TrendDirection d){if(d==TREND_NONE||g_equityLocked||g_profitProtectionLocked||g_dailyLockDay==DayKey()||g_closePending)return false;if(WeekendBlocked()||!IsTradingSession()||!IsSpreadAcceptable())return false;if(CountPositions()>0)return false;if(MaximumPositions>0&&CountPositions()>=MaximumPositions)return false;if(MaximumExposurePositions>0&&CountPositions()>=MaximumExposurePositions)return false;if(g_lastEntryTime>0&&Now()-g_lastEntryTime<EntryCooldownSeconds)return false;if(g_lastExitTime>0&&Now()-g_lastExitTime<EntryCooldownSeconds)return false;return HasDistance(d)&&ConfirmTrend(d);}

double ProtectiveSL(ENUM_POSITION_TYPE ty,double a,double b){if(a<=0)return b;if(b<=0)return a;return ty==POSITION_TYPE_BUY?MathMax(a,b):MathMin(a,b);}

void PositionProtection(ulong ticket){
   if(!PositionSelectByTicket(ticket))return;
   ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double profit=PositionGetDouble(POSITION_PROFIT),open=PositionGetDouble(POSITION_PRICE_OPEN),vol=PositionGetDouble(POSITION_VOLUME);
   double sl=0;
   bool recovery=StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0;

   if(recovery){
      double lockSL=0,trailSL=0;
      if(RecoveryLockStartUSD>0&&RecoveryLockProfitUSD>0&&profit>=RecoveryLockStartUSD){
         double dist=MoneyDistance(RecoveryLockProfitUSD,vol);
         if(dist>0)lockSL=ty==POSITION_TYPE_BUY?open+dist:open-dist;
      }
      if(RecoveryTrailStartUSD>0&&RecoveryTrailGivebackUSD>0&&profit>=RecoveryTrailStartUSD){
         double dist=MoneyDistance(RecoveryTrailGivebackUSD,vol); MqlTick t;
         if(dist>0&&SymbolInfoTick(_Symbol,t))trailSL=ty==POSITION_TYPE_BUY?t.bid-dist:t.ask+dist;
      }
      sl=ProtectiveSL(ty,lockSL,trailSL);
   }else{
      double beSL=0,lockSL=0,atrSL=0;
      if(UseBreakEven&&profit>=BreakEvenStartUSD){
         double dist=MoneyDistance(BreakEvenOffsetUSD,vol);
         if(dist>0)beSL=ty==POSITION_TYPE_BUY?open+dist:open-dist;
      }
      if(UseProfitLock&&profit>=ProfitLockStartUSD&&ProfitLockStepUSD>0){
         int n=(int)MathFloor((profit-ProfitLockStartUSD)/ProfitLockStepUSD)+1;
         double locked=ProfitLockOffsetUSD+(n-1)*ProfitLockStepUSD;
         double dist=MoneyDistance(locked,vol);
         if(dist>0)lockSL=ty==POSITION_TYPE_BUY?open+dist:open-dist;
      }
      if(UseATRTrailing&&profit>=ATRTrailingHardStartUSD){
         double atr; MqlTick t;
         if(GetATR(atr)&&SymbolInfoTick(_Symbol,t))atrSL=ty==POSITION_TYPE_BUY?t.bid-atr*ATRTrailingMultiplier:t.ask+atr*ATRTrailingMultiplier;
      }
      sl=ProtectiveSL(ty,beSL,lockSL);
      sl=ProtectiveSL(ty,sl,atrSL);
   }
   if(sl>0)ModifySL(ticket,sl);
}

void ProfitEngine(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;PositionProtection(t);}}

bool RegimeBreakDetected(TrendDirection orig){int n=MathMax(1,RegimeBreakConfirmationBars);for(int sh=1;sh<=n;sh++){double f,s,tr,ht,a;if(!Buf(hFastEMA,0,sh,f)||!Buf(hSlowEMA,0,sh,s)||!Buf(hTrendEMA,0,sh,tr)||!Buf(hHTFEMA,0,sh,ht)||!Buf(hADX,0,sh,a))return false;double c=iClose(_Symbol,TrendTimeframe,sh);if(c<=0||a<MinimumADX)return false;if(orig==TREND_BUY&&!(f<s&&c<tr&&c<ht))return false;if(orig==TREND_SELL&&!(f>s&&c>tr&&c>ht))return false;}return true;}
bool RegimeDamageDetected(TrendDirection orig){int n=MathMax(1,RegimeDamageConfirmationBars);for(int sh=1;sh<=n;sh++){double f,fp;if(!Buf(hFastEMA,0,sh,f)||!Buf(hFastEMA,0,sh+1,fp))return false;double c=iClose(_Symbol,TrendTimeframe,sh);if(c<=0)return false;if(orig==TREND_BUY&&!(c<f&&f<fp))return false;if(orig==TREND_SELL&&!(c>f&&f>fp))return false;}return true;}
bool StrongBuyRegimeExitDetected(){if(!UseStrongBuyRegimeExit)return false;int n=MathMax(1,BuyRegimeExitConfirmationBars);for(int sh=1;sh<=n;sh++){double f,fp,adx,plusDI,minusDI;if(!Buf(hFastEMA,0,sh,f)||!Buf(hFastEMA,0,sh+1,fp)||!Buf(hADX,0,sh,adx)||!Buf(hADX,1,sh,plusDI)||!Buf(hADX,2,sh,minusDI))return false;double c=iClose(_Symbol,TrendTimeframe,sh);if(c<=0||!(c<f&&f<fp&&adx>=BuyRegimeExitADX&&minusDI>plusDI))return false;}return true;}
bool ConfirmHTFRecovery(TrendDirection rev){if(!RecoveryRequireHTFAlignment)return true;double ema,fast,slow;if(!Buf(hHTFEMA,0,1,ema)||!Buf(hHTFFastEMA,0,1,fast)||!Buf(hHTFSlowEMA,0,1,slow))return false;int hHTFADX=iADX(_Symbol,HigherTimeframe,ADXPeriod);if(hHTFADX<0)return false;double adx;if(!Buf(hHTFADX,0,1,adx)){IndicatorRelease(hHTFADX);return false;}IndicatorRelease(hHTFADX);if(adx<RecoveryMinimumADX)return false;double c=iClose(_Symbol,HigherTimeframe,1);if(c<=0)return false;return rev==TREND_SELL?(c<ema&&fast<slow):(c>ema&&fast>slow);}

bool StartRecovery(TrendDirection rev){if(!UseRecovery||CountRecoveryPositions()>=MaxRecoveryPositions)return false;if(RequireHedgingAccountForRecovery&&!IsHedgingAccount())return false;TrendDirection orig=OriginalDirection();if(orig==TREND_NONE||rev==orig)return false;double normal=NormalProfit();if(normal>=0.0||MathAbs(normal)<RecoveryTriggerUSD)return false;if(MaximumExposurePositions>0&&CountPositions()>=MaximumExposurePositions)return false;if(!IsSpreadAcceptable()||!ConfirmHTFRecovery(rev)||!ConfirmReversal(rev))return false;double baseLot=0.0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")<0)baseLot+=PositionGetDouble(POSITION_VOLUME);}if(baseLot<=0)return false;double lot=NormalizeLot(MathMin(baseLot*RecoveryMultiplier,MaxRecoveryLot));if(lot<=0)return false;if(OpenTrade(rev,rev==TREND_BUY?"RECOVERY BUY":"RECOVERY SELL",lot,RecoveryMaxLossPerTradeUSD)){Log("RECOVERY OPENED "+(rev==TREND_BUY?"BUY":"SELL")+" normal="+DoubleToString(normal,2));return true;}return false;}
void RecoveryEngine(){
   double r=RecoveryProfit(),basket=BasketProfit();
   if(RecoveryMaxLossPerTradeUSD>0&&r<=-RecoveryMaxLossPerTradeUSD){Log("RECOVERY HARD LOSS EXIT.");CloseCampaign();return;}
   if(RecoveryMaxLossUSD>0&&r<=-RecoveryMaxLossUSD){Log("RECOVERY CAMPAIGN LOSS EXIT.");CloseCampaign();return;}
   if(UseRecoveryBasketBreakevenExit&&basket>=0.0&&r>=RecoveryTargetUSD&&basket>=RecoveryMinProfitUSD){Log("RECOVERY BASKET BREAKEVEN/PROFIT EXIT.");CloseCampaign();return;}
   ProfitEngine();
}

double CampaignGiveback(double peak){
   if(peak>=CampaignPeakLevel4USD&&CampaignGivebackLevel4USD>0)return CampaignGivebackLevel4USD;
   if(peak>=CampaignPeakLevel3USD&&CampaignGivebackLevel3USD>0)return CampaignGivebackLevel3USD;
   if(peak>=CampaignPeakLevel2USD&&CampaignGivebackLevel2USD>0)return CampaignGivebackLevel2USD;
   return CampaignProfitGivebackUSD;
}

bool CampaignTimeDecayExit(datetime start,double profit){
   if(start<=0)return false;
   double hours=(double)(Now()-start)/3600.0;
   if(CampaignStaleHours<=0||hours<CampaignStaleHours)return false;
   return profit<=CampaignStaleMinProfitUSD;
}

int RegimeExitScore(TrendDirection orig){
   int score=0;
   double f,f1,s,tr,ht,adx,plusDI,minusDI;
   if(!Buf(hFastEMA,0,1,f)||!Buf(hFastEMA,0,2,f1)||!Buf(hSlowEMA,0,1,s)||!Buf(hTrendEMA,0,1,tr)||!Buf(hHTFEMA,0,1,ht)||!Buf(hADX,0,1,adx)||!Buf(hADX,1,1,plusDI)||!Buf(hADX,2,1,minusDI))return 0;
   double c=iClose(_Symbol,TrendTimeframe,1);
   if(c<=0)return 0;
   if(orig==TREND_BUY){
      if(c<f)score+=1;
      if(f<f1)score+=1;
      if(f<s)score+=2;
      if(c<tr)score+=3;
      if(c<ht)score+=3;
      if(minusDI>plusDI)score+=2;
   }else if(orig==TREND_SELL){
      if(c>f)score+=1;
      if(f>f1)score+=1;
      if(f>s)score+=2;
      if(c>tr)score+=3;
      if(c>ht)score+=3;
      if(plusDI>minusDI)score+=2;
   }
   return score;
}

bool ConfirmExitThesis(TrendDirection orig){
   int n=MathMax(1,ExitThesisConfirmationBars);
   for(int sh=1;sh<=n;sh++){
      double f,f1,s,tr,ht,plusDI,minusDI;
      if(!Buf(hFastEMA,0,sh,f)||!Buf(hFastEMA,0,sh+1,f1)||!Buf(hSlowEMA,0,sh,s)||!Buf(hTrendEMA,0,sh,tr)||!Buf(hHTFEMA,0,sh,ht)||!Buf(hADX,1,sh,plusDI)||!Buf(hADX,2,sh,minusDI))return false;
      double c=iClose(_Symbol,TrendTimeframe,sh); if(c<=0)return false;
      if(orig==TREND_BUY){if(!(c<f&&f<f1&&f<s&&c<tr&&c<ht&&minusDI>plusDI))return false;}
      else if(orig==TREND_SELL){if(!(c>f&&f>f1&&f>s&&c>tr&&c>ht&&plusDI>minusDI))return false;}
   }
   return true;
}

void ManagePositions(){
   if(CountPositions()<=0){g_campaignPeak=0;return;}
   datetime start=CampaignStart();
   bool holdComplete=start>0&&(Now()-start)>=MinimumHoldSeconds;
   if(!holdComplete){ProfitEngine();return;}

   double p=BasketProfit();
   if(g_campaignPeak==0||p>g_campaignPeak)g_campaignPeak=p;

   if(CampaignProfitTargetUSD>0&&p>=CampaignProfitTargetUSD){Log("CAMPAIGN TARGET EXIT.");CloseCampaign();return;}
   double giveback=CampaignGiveback(g_campaignPeak);
   if(CampaignProfitTrailStartUSD>0&&giveback>0&&g_campaignPeak>=CampaignProfitTrailStartUSD&&g_campaignPeak-p>=giveback&&p>0){Log("DYNAMIC CAMPAIGN GIVEBACK EXIT.");CloseCampaign();return;}
   if(MaxCampaignLossUSD>0&&p<=-MaxCampaignLossUSD){Log("CAMPAIGN HARD LOSS EXIT.");CloseCampaign();return;}
   if(CampaignTimeDecayExit(start,p)){Log("STALE CAMPAIGN EXIT.");CloseCampaign();return;}

   if(CountRecoveryPositions()>0){RecoveryEngine();return;}

   TrendDirection orig=OriginalDirection();
   if(orig!=TREND_NONE){
      double normal=NormalProfit();
      if(normal<0){
         TrendDirection rev=orig==TREND_BUY?TREND_SELL:TREND_BUY;
         bool reversalConfirmed=ConfirmReversal(rev);
         int score=RegimeExitScore(orig);

         bool thesisExit=UseHierarchicalExit&&ExitOnThesisInvalidation&&score>=ExitRegimeDamageScore&&ConfirmExitThesis(orig);
         if(thesisExit){
            if(normal<=-RecoveryTriggerUSD&&reversalConfirmed&&StartRecovery(rev))return;
            Log("THESIS INVALIDATION EXIT score="+(string)score);
            CloseCampaign();return;
         }

         if(orig==TREND_BUY&&StrongBuyRegimeExitDetected()){Log("STRONG BUY REGIME EXIT.");CloseCampaign();return;}
         if(CloseOnRegimeDamage&&RegimeDamageDetected(orig)&&reversalConfirmed){
            if(StartRecovery(rev))return;
            if(CloseOnStrongReversalIfNoRecovery){Log("REGIME DAMAGE + REVERSAL EXIT.");CloseCampaign();return;}
         }

         if(normal<=-RecoveryTriggerUSD&&reversalConfirmed){
            if(StartRecovery(rev))return;
            if(CloseOnStrongReversalIfNoRecovery){Log("STRONG REVERSAL WITHOUT RECOVERY EXIT.");CloseCampaign();return;}
         }

         if(RegimeBreakDetected(orig)){
            if(reversalConfirmed&&StartRecovery(rev))return;
            if(CloseOnStrongReversalIfNoRecovery&&reversalConfirmed){Log("REGIME BREAK EXIT.");CloseCampaign();return;}
         }
      }
   }
   ProfitEngine();
}
void EntryEngine(TrendDirection d){if(g_equityLocked||g_profitProtectionLocked||g_dailyLockDay==DayKey()||g_closePending||CountPositions()>0)return;if(!CanOpen(d))return;double lot=EntryLot();if(lot<=0)return;if(OpenTrade(d,"TREND "+(d==TREND_BUY?"BUY":"SELL"),lot,MathMin(MaxInitialLossUSD,MaxNormalLossPerTradeUSD))){g_lastEntryTime=Now();g_campaignPeak=0;Log("TREND ENTRY "+(d==TREND_BUY?"BUY":"SELL"));}}

void RiskEngine(){UpdateDailyState();if(WeekendBlocked()){if(CountPositions()>0)CloseCampaign();return;}if(g_equityLocked||g_profitProtectionLocked)return;double e=AccountInfoDouble(ACCOUNT_EQUITY);if(g_peakEquity<=0)g_peakEquity=e;if(e>g_peakEquity)g_peakEquity=e;if(MaxEquityDrawdownPercent>0&&g_peakEquity>0&&(g_peakEquity-e)/g_peakEquity*100.0>=MaxEquityDrawdownPercent){g_equityLocked=true;Log("EQUITY LOCK triggered.");if(ClosePositionsOnEquityProtection)CloseCampaign();return;}if(g_dailyLockDay==0){double loss=g_dailyStartEquity-e,pct=g_dailyStartEquity>0?loss/g_dailyStartEquity*100.0:0;if((MaxDailyLossUSD>0&&loss>=MaxDailyLossUSD)||(MaxDailyLossPercent>0&&pct>=MaxDailyLossPercent)){g_dailyLockDay=DayKey();Log("DAILY LOCK triggered day="+(string)g_dailyLockDay);if(ClosePositionsOnDailyProtection)CloseCampaign();return;}}if(UseHardNormalUSDLoss&&MaxNormalLossPerTradeUSD>0){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)continue;double pp=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);if(pp<=-MaxNormalLossPerTradeUSD){TrendDirection orig=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?TREND_BUY:TREND_SELL;TrendDirection rev=orig==TREND_BUY?TREND_SELL:TREND_BUY;bool recoveryWindow=UseRecovery&&IsHedgingAccount()&&CountRecoveryPositions()==0&&MathAbs(pp)>=RecoveryTriggerUSD&&ConfirmReversal(rev);if(recoveryWindow&&StartRecovery(rev)){Log("HARD LOSS HANDLED BY RECOVERY.");continue;}Log("HARD NORMAL USD LOSS - FORCE CLOSE.");CloseCampaign();return;}}}}

void ProfitProtection(){if(!UseEquityProfitProtection||EquityProfitLockStartUSD<=0||EquityProfitGivebackUSD<=0||g_profitProtectionLocked)return;double e=AccountInfoDouble(ACCOUNT_EQUITY);if(g_profitStart<=0){g_profitStart=e;g_profitPeak=e;}if(e>g_profitPeak)g_profitPeak=e;double lockedProfit=g_profitPeak-g_profitStart;if(lockedProfit>=EquityProfitLockStartUSD&&g_profitPeak-e>=EquityProfitGivebackUSD){Log("EQUITY PROFIT PROTECTION TRIGGERED. Peak="+DoubleToString(g_profitPeak,2)+" Equity="+DoubleToString(e,2));if(CountPositions()>0)CloseCampaign();if(CountPositions()==0){g_profitProtectionLocked=true;g_equityLocked=true;}}}

int OnInit(){trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);hFastEMA=iMA(_Symbol,TrendTimeframe,FastEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hSlowEMA=iMA(_Symbol,TrendTimeframe,SlowEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hTrendEMA=iMA(_Symbol,TrendTimeframe,TrendEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hHTFEMA=iMA(_Symbol,HigherTimeframe,TrendEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hHTFFastEMA=iMA(_Symbol,HigherTimeframe,FastEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hHTFSlowEMA=iMA(_Symbol,HigherTimeframe,SlowEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hADX=iADX(_Symbol,TrendTimeframe,ADXPeriod);hATR=iATR(_Symbol,TrendTimeframe,14);hRSI=iRSI(_Symbol,TrendTimeframe,RSIPeriod,PRICE_CLOSE);if(hFastEMA<0||hSlowEMA<0||hTrendEMA<0||hHTFEMA<0||hHTFFastEMA<0||hHTFSlowEMA<0||hADX<0||hATR<0||hRSI<0)return INIT_FAILED;g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);g_dailyStartEquity=g_peakEquity;g_profitStart=g_peakEquity;g_profitPeak=g_peakEquity;EventSetTimer(1);return INIT_SUCCEEDED;}
void OnDeinit(const int reason){EventKillTimer();if(hFastEMA>=0)IndicatorRelease(hFastEMA);if(hSlowEMA>=0)IndicatorRelease(hSlowEMA);if(hTrendEMA>=0)IndicatorRelease(hTrendEMA);if(hHTFEMA>=0)IndicatorRelease(hHTFEMA);if(hHTFFastEMA>=0)IndicatorRelease(hHTFFastEMA);if(hHTFSlowEMA>=0)IndicatorRelease(hHTFSlowEMA);if(hADX>=0)IndicatorRelease(hADX);if(hATR>=0)IndicatorRelease(hATR);if(hRSI>=0)IndicatorRelease(hRSI);}
void SafetyHeartbeat(){datetime n=Now();if(n<=0||n==g_lastSafetyTime)return;g_lastSafetyTime=n;UpdateDailyState();RiskEngine();ProfitProtection();}
void OnTimer(){SafetyHeartbeat();}
void OnTick(){SafetyHeartbeat();if(WeekendBlocked())return;if(g_closePending){if(CountPositions()==0)g_closePending=false;else{ProfitEngine();return;}}if(g_equityLocked||g_profitProtectionLocked||g_dailyLockDay==DayKey())return;TrendDirection trend=DetectTrend();if(LogTrendChanges&&trend!=g_lastTrend){Log("TREND="+(trend==TREND_BUY?"BUY":trend==TREND_SELL?"SELL":"NONE"));g_lastTrend=trend;}ManagePositions();if(g_equityLocked||g_profitProtectionLocked||g_dailyLockDay==DayKey()||g_closePending)return;if(UseNewBarForEntry&&!IsNewBar())return;EntryEngine(trend);}
