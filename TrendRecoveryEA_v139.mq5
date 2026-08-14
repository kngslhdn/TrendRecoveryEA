#property strict
#property version "1.39"
#property description "TrendRecoveryEA v1.39 - fixed daily lock persistence, minimum hold protection, deterministic recovery and tester-safe state."
#include <Trade/Trade.mqh>
CTrade trade;

enum TrendDirection { TREND_NONE=0, TREND_BUY=1, TREND_SELL=-1 };

//---------- TREND SETTINGS ----------
input ENUM_TIMEFRAMES TrendTimeframe=PERIOD_M15;
input ENUM_TIMEFRAMES HigherTimeframe=PERIOD_H1;
input int FastEMAPeriod=20;
input int SlowEMAPeriod=50;
input int TrendEMAPeriod=200;
input int ADXPeriod=14;
input double MinimumADX=20.0;
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

//---------- ENTRY SETTINGS ----------
input double InitialLot=0.01;
input double MaxLot=0.10;
input int EntryCooldownSeconds=900;
input int MinimumHoldSeconds=300;
input int MaximumPositions=1;
input double MinimumEntryDistance=0.0;
input double MaximumSpread=300.0;
input long MagicNumber=26080901;
input int SlippagePoints=30;

//---------- POSITION RISK ----------
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
input double ATRTrailingStartUSD=15.0;

//---------- CAMPAIGN ----------
input double CampaignProfitTargetUSD=0.0;
input double CampaignProfitTrailStartUSD=10.0;
input double CampaignProfitGivebackUSD=3.0;
input double MaxCampaignLossUSD=30.0;
input int MaxCampaignHours=24;

//---------- RECOVERY ----------
input bool UseRecovery=true;
input double RecoveryTriggerUSD=8.0;
input double RecoveryMultiplier=1.0;
input double MaxRecoveryLot=0.05;
input int MaxRecoveryPositions=1;
input double RecoveryTargetUSD=1.0;
input double RecoveryMinProfitUSD=0.0;
input double RecoveryMaxLossUSD=50.0;
input double RecoverySL_ATR=1.75;
input double RecoveryMaxLossPerTradeUSD=6.0;
input int RecoveryConfirmationBars=4;
input bool CloseOnStrongReversalIfNoRecovery=true;
input bool RecoveryRequireHTFAlignment=true;
input double RecoveryMinimumADX=25.0;
input double RecoveryLockStartUSD=2.0;
input double RecoveryLockProfitUSD=1.0;
input double RecoveryTrailStartUSD=5.0;
input double RecoveryTrailGivebackUSD=2.0;

//---------- RISK ----------
input int MaximumExposurePositions=2;
input double MaxEquityDrawdownPercent=15.0;
input bool ClosePositionsOnEquityProtection=true;
input double MaxDailyLossUSD=20.0;
input double MaxDailyLossPercent=2.0;
input bool ClosePositionsOnDailyProtection=true;

//---------- SESSION ----------
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

//---------- EQUITY PROFIT PROTECTION ----------
input bool UseEquityProfitProtection=true;
input double EquityProfitLockStartUSD=25.0;
input double EquityProfitGivebackUSD=50.0;

//---------- HARD LOSS ----------
input bool UseHardNormalUSDLoss=true;

//---------- WEEKEND ----------
input bool UseWeekendProtection=true;
input int FridayCloseHour=22;
input int FridayCloseMinute=0;
input bool BlockSundayTrading=true;

int hFastEMA=-1,hSlowEMA=-1,hTrendEMA=-1,hHTFEMA=-1,hHTFFastEMA=-1,hHTFSlowEMA=-1,hADX=-1,hATR=-1,hRSI=-1;
datetime g_lastEntryTime=0,g_lastBarTime=0,g_lastSafetyTime=0;
TrendDirection g_lastTrend=TREND_NONE;
bool g_closePending=false;
bool g_equityLocked=false;
long g_dailyLockDay=0;
double g_peakEquity=0.0,g_dailyStartEquity=0.0;
double g_profitPeak=0.0,g_profitStart=0.0;
double g_campaignPeak=0.0;
double g_recoveryPeak=0.0;

void Log(string s){if(EnableLogging)Print("[TrendRecoveryEA v1.39] ",s);}
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

void UpdateDailyState(){long day=DayKey();if(g_dailyStartEquity<=0.0){g_dailyStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);g_dailyLockDay=0;}if(g_dailyLockDay!=0&&g_dailyLockDay!=day){Log("New trading day: DAILY LOCK RESET.");g_dailyLockDay=0;g_dailyStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);}}

bool WeekendBlocked(){if(!UseWeekendProtection)return false;MqlDateTime d;TimeToStruct(Now(),d);if(d.day_of_week==6)return true;if(d.day_of_week==0&&BlockSundayTrading)return true;if(d.day_of_week==5)return d.hour*60+d.min>=FridayCloseHour*60+FridayCloseMinute;return false;}

TrendDirection DetectTrend(){double f,s,tr,ht,a,atr,r;if(!Buf(hFastEMA,0,1,f)||!Buf(hSlowEMA,0,1,s)||!Buf(hTrendEMA,0,1,tr)||!Buf(hHTFEMA,0,1,ht)||!Buf(hADX,0,1,a)||!GetATR(atr))return TREND_NONE;double c=iClose(_Symbol,TrendTimeframe,1);if(c<=0||a<MinimumADX)return TREND_NONE;if(MaximumATRPoints>0&&atr/_Point>MaximumATRPoints)return TREND_NONE;bool buy=f>s&&c>tr&&c>ht,sell=f<s&&c<tr&&c<ht;if(UseRSIConfirmation){if(!Buf(hRSI,0,1,r))return TREND_NONE;buy=buy&&r>=RSIForBuy;sell=sell&&r<=RSIForSell;}if(buy)return TREND_BUY;if(sell)return TREND_SELL;return TREND_NONE;}

bool ConfirmTrend(TrendDirection dir){int n=MathMax(1,ReversalConfirmationBars);for(int sh=1;sh<=n;sh++){double f,s,tr,ht,a,r;if(!Buf(hFastEMA,0,sh,f)||!Buf(hSlowEMA,0,sh,s)||!Buf(hTrendEMA,0,sh,tr)||!Buf(hHTFEMA,0,sh,ht)||!Buf(hADX,0,sh,a))return false;double c=iClose(_Symbol,TrendTimeframe,sh);if(c<=0||a<MinimumADX)return false;bool ok=dir==TREND_BUY?(f>s&&c>tr&&c>ht):(f<s&&c<tr&&c<ht);if(UseRSIConfirmation){if(!Buf(hRSI,0,sh,r))return false;ok=ok&&(dir==TREND_BUY?r>=RSIForBuy:r<=RSIForSell);}if(!ok)return false;}return true;}

bool ConfirmReversal(TrendDirection dir){int n=MathMax(2,RecoveryConfirmationBars);for(int sh=1;sh<=n;sh++){double f;if(!Buf(hFastEMA,0,sh,f))return false;double c=iClose(_Symbol,TrendTimeframe,sh),o=iOpen(_Symbol,TrendTimeframe,sh);if(c<=0||o<=0)return false;if(dir==TREND_BUY){if(!(c>o&&c>f))return false;}else{if(!(c<o&&c<f))return false;}}double f1,f2,f3;if(!Buf(hFastEMA,0,1,f1)||!Buf(hFastEMA,0,2,f2)||!Buf(hFastEMA,0,3,f3))return false;return dir==TREND_BUY?(f1>=f2&&f2>=f3):(f1<=f2&&f2<=f3);}

int CountPositions(){int n=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)==_Symbol&&(long)PositionGetInteger(POSITION_MAGIC)==MagicNumber)n++;}return n;}
int CountRecoveryPositions(){int n=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)n++;}return n;}
double BasketProfit(){double p=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}return p;}
double NormalProfit(){double p=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)continue;p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}return p;}
double RecoveryProfit(){double p=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")<0)continue;p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}return p;}
TrendDirection OriginalDirection(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)continue;ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);return ty==POSITION_TYPE_BUY?TREND_BUY:TREND_SELL;}return TREND_NONE;}
datetime CampaignStart(){datetime x=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;datetime p=(datetime)PositionGetInteger(POSITION_TIME);if(x==0||p<x)x=p;}return x;}

bool CloseCampaign(){if(CountPositions()<=0){g_closePending=false;return true;}trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);bool all=true;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(!trade.PositionClose(t)||!TradeSucceeded())all=false;}g_closePending=CountPositions()>0;return all;}

double MoneyDistance(double money,double vol){if(money<=0||vol<=0)return 0;double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE),ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);if(tv<=0||ts<=0)return 0;return money/(tv*vol)*ts;}
double CalcLossUSD(ENUM_POSITION_TYPE ty,double volume,double openPrice,double stopPrice){ENUM_ORDER_TYPE ot=ty==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL;double pnl=0;if(!OrderCalcProfit(ot,_Symbol,volume,openPrice,stopPrice,pnl))return 0;return MathMax(0.0,-pnl);}
double RiskSLByUSD(ENUM_POSITION_TYPE ty,double volume,double openPrice,double riskUSD){double md=MathMax(MinStopDistance(),2.0*_Point),dist=MoneyDistance(riskUSD,volume);if(dist<md)dist=md;if(dist<=0)return 0;double lo=md,hi=dist*2.0;for(int k=0;k<20&&CalcLossUSD(ty,volume,openPrice,ty==POSITION_TYPE_BUY?openPrice-hi:openPrice+hi)<riskUSD;k++)hi*=2.0;for(int i=0;i<45;i++){double mid=(lo+hi)*0.5;double loss=CalcLossUSD(ty,volume,openPrice,ty==POSITION_TYPE_BUY?openPrice-mid:openPrice+mid);if(loss>=riskUSD)hi=mid;else lo=mid;}return NormalizePrice(ty==POSITION_TYPE_BUY?openPrice-hi:openPrice+hi);}
bool ValidSL(ENUM_POSITION_TYPE ty,double sl){MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;double md=MinStopDistance();return ty==POSITION_TYPE_BUY?sl<=t.bid-md:sl>=t.ask+md;}
bool ModifySL(ulong ticket,double sl){if(!PositionSelectByTicket(ticket))return false;ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);double old=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);sl=NormalizePrice(sl);if(!ValidSL(ty,sl))return false;if(ty==POSITION_TYPE_BUY&&old>0&&sl<=old+_Point)return false;if(ty==POSITION_TYPE_SELL&&old>0&&sl>=old-_Point)return false;return trade.PositionModify(ticket,sl,tp)&&TradeSucceeded();}

bool OpenTrade(TrendDirection d,string comment,double lot,double riskUSD){MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;double atr;if(!GetATR(atr))return false;ENUM_POSITION_TYPE ty=d==TREND_BUY?POSITION_TYPE_BUY:POSITION_TYPE_SELL;double p=d==TREND_BUY?t.ask:t.bid,sl=0;if(riskUSD>0)sl=RiskSLByUSD(ty,lot,p,riskUSD);if(sl<=0&&InitialSL_ATR>0){double dist=MathMax(atr*InitialSL_ATR,MinStopDistance());sl=NormalizePrice(ty==POSITION_TYPE_BUY?p-dist:p+dist);}if(sl<=0||!ValidSL(ty,sl))return false;trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);bool ok=d==TREND_BUY?trade.Buy(lot,_Symbol,0,sl,0,comment):trade.Sell(lot,_Symbol,0,sl,0,comment);if(!ok||!TradeSucceeded()){Log("ENTRY FAILED "+trade.ResultRetcodeDescription());return false;}return true;}

double EntryLot(){double lot=UseEquityScaling&&BaseEquity>0?BaseLot*AccountInfoDouble(ACCOUNT_EQUITY)/BaseEquity:InitialLot;return NormalizeLot(lot);}
bool HasDistance(TrendDirection d){if(MinimumEntryDistance<=0)return true;MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;double p=d==TREND_BUY?t.ask:t.bid;for(int i=PositionsTotal()-1;i>=0;i--){ulong x=PositionGetTicket(i);if(x==0||!PositionSelectByTicket(x))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(MathAbs(p-PositionGetDouble(POSITION_PRICE_OPEN))<MinimumEntryDistance)return false;}return true;}
bool CanOpen(TrendDirection d){if(d==TREND_NONE||g_equityLocked||g_dailyLockDay==DayKey()||g_closePending)return false;if(WeekendBlocked()||!IsTradingSession()||!IsSpreadAcceptable())return false;if(CountPositions()>=MaximumPositions)return false;if(MaximumExposurePositions>0&&CountPositions()>=MaximumExposurePositions)return false;if(g_lastEntryTime>0&&Now()-g_lastEntryTime<EntryCooldownSeconds)return false;return HasDistance(d)&&ConfirmTrend(d);}

void PositionProtection(ulong ticket){if(!PositionSelectByTicket(ticket))return;ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);double profit=PositionGetDouble(POSITION_PROFIT),open=PositionGetDouble(POSITION_PRICE_OPEN),vol=PositionGetDouble(POSITION_VOLUME),sl=0;if(UseATRTrailing&&profit>=ATRTrailingStartUSD){double atr;MqlTick t;if(GetATR(atr)&&SymbolInfoTick(_Symbol,t))sl=ty==POSITION_TYPE_BUY?t.bid-atr*ATRTrailingMultiplier:t.ask+atr*ATRTrailingMultiplier;}else if(UseProfitLock&&profit>=ProfitLockStartUSD&&ProfitLockStepUSD>0){int n=(int)MathFloor((profit-ProfitLockStartUSD)/ProfitLockStepUSD)+1;double locked=ProfitLockOffsetUSD+(n-1)*ProfitLockStepUSD,dist=MoneyDistance(locked,vol);if(dist>0)sl=ty==POSITION_TYPE_BUY?open+dist:open-dist;}else if(UseBreakEven&&profit>=BreakEvenStartUSD){double dist=MoneyDistance(BreakEvenOffsetUSD,vol);if(dist>0)sl=ty==POSITION_TYPE_BUY?open+dist:open-dist;}if(sl>0)ModifySL(ticket,sl);}
void ProfitEngine(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;PositionProtection(t);}}

bool RegimeBreakDetected(TrendDirection orig){int n=MathMax(1,RegimeBreakConfirmationBars);for(int sh=1;sh<=n;sh++){double f,s,tr,ht,a;if(!Buf(hFastEMA,0,sh,f)||!Buf(hSlowEMA,0,sh,s)||!Buf(hTrendEMA,0,sh,tr)||!Buf(hHTFEMA,0,sh,ht)||!Buf(hADX,0,sh,a))return false;double c=iClose(_Symbol,TrendTimeframe,sh);if(c<=0||a<MinimumADX)return false;if(orig==TREND_BUY&&!(f<s&&c<tr&&c<ht))return false;if(orig==TREND_SELL&&!(f>s&&c>tr&&c>ht))return false;}return true;}
bool RegimeDamageDetected(TrendDirection orig){int n=MathMax(1,RegimeDamageConfirmationBars);for(int sh=1;sh<=n;sh++){double f,fp;if(!Buf(hFastEMA,0,sh,f)||!Buf(hFastEMA,0,sh+1,fp))return false;double c=iClose(_Symbol,TrendTimeframe,sh);if(c<=0)return false;if(orig==TREND_BUY&&!(c<f&&f<fp))return false;if(orig==TREND_SELL&&!(c>f&&f>fp))return false;}return true;}
bool StrongBuyRegimeExitDetected(){if(!UseStrongBuyRegimeExit)return false;int n=MathMax(1,BuyRegimeExitConfirmationBars);for(int sh=1;sh<=n;sh++){double f,fp,adx,plusDI,minusDI;if(!Buf(hFastEMA,0,sh,f)||!Buf(hFastEMA,0,sh+1,fp)||!Buf(hADX,0,sh,adx)||!Buf(hADX,1,sh,plusDI)||!Buf(hADX,2,sh,minusDI))return false;double c=iClose(_Symbol,TrendTimeframe,sh);if(c<=0||!(c<f&&f<fp&&adx>=BuyRegimeExitADX&&minusDI>plusDI))return false;}return true;}

bool ConfirmHTFRecovery(TrendDirection rev){if(!RecoveryRequireHTFAlignment)return true;double ema,fast,slow,adx;if(!Buf(hHTFEMA,0,1,ema)||!Buf(hHTFFastEMA,0,1,fast)||!Buf(hHTFSlowEMA,0,1,slow)||!Buf(hADX,0,1,adx))return false;if(adx<RecoveryMinimumADX)return false;double c=iClose(_Symbol,HigherTimeframe,1);if(c<=0)return false;return rev==TREND_SELL?(c<ema&&fast<slow):(c>ema&&fast>slow);}

bool OpenRecoveryTrade(TrendDirection d,double lot){return OpenTrade(d,d==TREND_BUY?"RECOVERY BUY":"RECOVERY SELL",lot,RecoveryMaxLossPerTradeUSD);}
bool StartRecovery(TrendDirection rev){if(!UseRecovery||CountRecoveryPositions()>=MaxRecoveryPositions)return false;if(RequireHedgingAccountForRecovery&&!IsHedgingAccount())return false;TrendDirection orig=OriginalDirection();if(orig==TREND_NONE||rev==orig)return false;double normal=NormalProfit();if(normal>=0||MathAbs(normal)<RecoveryTriggerUSD)return false;if(MaximumExposurePositions<2||CountPositions()>=MaximumExposurePositions)return false;if(!IsSpreadAcceptable()||!ConfirmHTFRecovery(rev))return false;double baseLot=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")<0)baseLot+=PositionGetDouble(POSITION_VOLUME);}double lot=NormalizeLot(MathMin(baseLot*RecoveryMultiplier,MaxRecoveryLot));if(lot<=0)return false;if(OpenRecoveryTrade(rev,lot)){Log("RECOVERY OPENED direction="+(rev==TREND_BUY?"BUY":"SELL"));return true;}return false;}
void ReversalEngine(){TrendDirection orig=OriginalDirection();if(orig==TREND_NONE||NormalProfit()>-RecoveryTriggerUSD)return;TrendDirection rev=orig==TREND_BUY?TREND_SELL:TREND_BUY;if(!ConfirmReversal(rev))return;if(StartRecovery(rev))return;if(CloseOnStrongReversalIfNoRecovery)CloseCampaign();}

void RecoveryEngine(){double r=RecoveryProfit(),basket=BasketProfit();if(RecoveryMaxLossPerTradeUSD>0&&r<=-RecoveryMaxLossPerTradeUSD){CloseCampaign();return;}if(RecoveryMaxLossUSD>0&&r<=-RecoveryMaxLossUSD){CloseCampaign();return;}if(RecoveryTargetUSD>0&&r>=RecoveryTargetUSD&&basket>=RecoveryMinProfitUSD){CloseCampaign();return;}if(RecoveryLockStartUSD>0&&r>=RecoveryLockStartUSD){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")<0)continue;ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);double dist=MoneyDistance(RecoveryLockProfitUSD,PositionGetDouble(POSITION_VOLUME));if(dist<=0)continue;double open=PositionGetDouble(POSITION_PRICE_OPEN);ModifySL(t,ty==POSITION_TYPE_BUY?open+dist:open-dist);}}}

void ManagePositions(){if(CountPositions()<=0){g_campaignPeak=0;g_recoveryPeak=0;return;}datetime start=CampaignStart();bool holdComplete=start>0&&(Now()-start)>=MinimumHoldSeconds;if(!holdComplete){ProfitEngine();return;}double p=BasketProfit();if(g_campaignPeak==0||p>g_campaignPeak)g_campaignPeak=p;if(CampaignProfitTargetUSD>0&&p>=CampaignProfitTargetUSD){CloseCampaign();return;}if(CampaignProfitTrailStartUSD>0&&CampaignProfitGivebackUSD>0&&g_campaignPeak>=CampaignProfitTrailStartUSD&&g_campaignPeak-p>=CampaignProfitGivebackUSD&&p>0){CloseCampaign();return;}if(MaxCampaignLossUSD>0&&p<=-MaxCampaignLossUSD){CloseCampaign();return;}if(MaxCampaignHours>0&&start>0&&Now()-start>=MaxCampaignHours*3600){CloseCampaign();return;}if(CountRecoveryPositions()>0){RecoveryEngine();if(CountPositions()>0)ProfitEngine();return;}TrendDirection orig=OriginalDirection();if(orig!=TREND_NONE&&NormalProfit()<0){if(orig==TREND_BUY&&StrongBuyRegimeExitDetected()){CloseCampaign();return;}if(CloseOnRegimeDamage&&RegimeDamageDetected(orig)){CloseCampaign();return;}if(RegimeBreakDetected(orig)){TrendDirection rev=orig==TREND_BUY?TREND_SELL:TREND_BUY;if(ConfirmReversal(rev)&&StartRecovery(rev))return;if(CloseOnStrongReversalIfNoRecovery)CloseCampaign();return;}ReversalEngine();}if(CountPositions()>0)ProfitEngine();}

void EntryEngine(TrendDirection d){if(g_equityLocked||g_dailyLockDay==DayKey()||g_closePending||CountPositions()>0)return;if(!CanOpen(d))return;double lot=EntryLot();if(lot<=0)return;if(OpenTrade(d,"TREND "+(d==TREND_BUY?"BUY":"SELL"),lot,MathMin(MaxInitialLossUSD,MaxNormalLossPerTradeUSD))){g_lastEntryTime=Now();g_campaignPeak=0;Log("TREND ENTRY "+(d==TREND_BUY?"BUY":"SELL"));}}

void RiskEngine(){UpdateDailyState();if(WeekendBlocked()){if(CountPositions()>0)CloseCampaign();return;}if(g_equityLocked)return;double e=AccountInfoDouble(ACCOUNT_EQUITY);if(g_peakEquity<=0)g_peakEquity=e;if(e>g_peakEquity)g_peakEquity=e;if(MaxEquityDrawdownPercent>0&&g_peakEquity>0&&(g_peakEquity-e)/g_peakEquity*100.0>=MaxEquityDrawdownPercent){g_equityLocked=true;Log("EQUITY LOCK triggered.");if(ClosePositionsOnEquityProtection)CloseCampaign();return;}if(g_dailyLockDay==0){double loss=g_dailyStartEquity-e;double pct=g_dailyStartEquity>0?loss/g_dailyStartEquity*100.0:0;if((MaxDailyLossUSD>0&&loss>=MaxDailyLossUSD)||(MaxDailyLossPercent>0&&pct>=MaxDailyLossPercent)){g_dailyLockDay=DayKey();Log("DAILY LOCK triggered for day="+(string)g_dailyLockDay);if(ClosePositionsOnDailyProtection)CloseCampaign();return;}}if(UseHardNormalUSDLoss&&MaxNormalLossPerTradeUSD>0){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)continue;if(PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP)<=-MaxNormalLossPerTradeUSD){Log("HARD NORMAL USD LOSS.");CloseCampaign();return;}}}}

void ProfitProtection(){if(!UseEquityProfitProtection||EquityProfitLockStartUSD<=0||EquityProfitGivebackUSD<=0)return;double e=AccountInfoDouble(ACCOUNT_EQUITY);if(g_profitStart<=0){g_profitStart=e;g_profitPeak=e;}if(e>g_profitPeak)g_profitPeak=e;if(g_profitPeak-g_profitStart>=EquityProfitLockStartUSD&&g_profitPeak-e>=EquityProfitGivebackUSD){Log("EQUITY PROFIT GIVEBACK.");CloseCampaign();if(CountPositions()==0){g_profitStart=e;g_profitPeak=e;}}}

int OnInit(){trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);hFastEMA=iMA(_Symbol,TrendTimeframe,FastEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hSlowEMA=iMA(_Symbol,TrendTimeframe,SlowEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hTrendEMA=iMA(_Symbol,TrendTimeframe,TrendEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hHTFEMA=iMA(_Symbol,HigherTimeframe,TrendEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hHTFFastEMA=iMA(_Symbol,HigherTimeframe,FastEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hHTFSlowEMA=iMA(_Symbol,HigherTimeframe,SlowEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hADX=iADX(_Symbol,TrendTimeframe,ADXPeriod);hATR=iATR(_Symbol,TrendTimeframe,14);hRSI=iRSI(_Symbol,TrendTimeframe,RSIPeriod,PRICE_CLOSE);if(hFastEMA<0||hSlowEMA<0||hTrendEMA<0||hHTFEMA<0||hHTFFastEMA<0||hHTFSlowEMA<0||hADX<0||hATR<0||hRSI<0)return INIT_FAILED;g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);g_dailyStartEquity=g_peakEquity;g_profitStart=g_peakEquity;g_profitPeak=g_peakEquity;EventSetTimer(1);return INIT_SUCCEEDED;}
void OnDeinit(const int reason){EventKillTimer();if(hFastEMA>=0)IndicatorRelease(hFastEMA);if(hSlowEMA>=0)IndicatorRelease(hSlowEMA);if(hTrendEMA>=0)IndicatorRelease(hTrendEMA);if(hHTFEMA>=0)IndicatorRelease(hHTFEMA);if(hHTFFastEMA>=0)IndicatorRelease(hHTFFastEMA);if(hHTFSlowEMA>=0)IndicatorRelease(hHTFSlowEMA);if(hADX>=0)IndicatorRelease(hADX);if(hATR>=0)IndicatorRelease(hATR);if(hRSI>=0)IndicatorRelease(hRSI);}
void SafetyHeartbeat(){datetime n=Now();if(n<=0||n==g_lastSafetyTime)return;g_lastSafetyTime=n;UpdateDailyState();RiskEngine();ProfitProtection();}
void OnTimer(){SafetyHeartbeat();}
void OnTick(){SafetyHeartbeat();if(WeekendBlocked())return;if(g_closePending){if(CountPositions()==0)g_closePending=false;else{ProfitEngine();return;}}if(g_equityLocked||g_dailyLockDay==DayKey())return;TrendDirection trend=DetectTrend();if(LogTrendChanges&&trend!=g_lastTrend){Log("TREND="+(trend==TREND_BUY?"BUY":trend==TREND_SELL?"SELL":"NONE"));g_lastTrend=trend;}ManagePositions();if(g_equityLocked||g_dailyLockDay==DayKey()||g_closePending)return;if(UseNewBarForEntry&&!IsNewBar())return;EntryEngine(trend);}
