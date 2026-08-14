#property strict
#property version "1.36"
#property description "TrendRecoveryEA v1.36 - state-isolated backtest/live protection, hard USD protection, cycle profit protection, strong BUY regime exit and improved payoff protection."
#include <Trade/Trade.mqh>
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
input int MaximumPositions=1;
input double MinimumEntryDistance=0.0;
input double MaximumSpread=300.0;
input long MagicNumber=26080901;
input int SlippagePoints=30;

//---------- PROFIT / POSITION EXIT ----------
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

//---------- CAMPAIGN EXIT ----------
input double CampaignProfitTargetUSD=0.0;
input double CampaignProfitTrailStartUSD=10.0;
input double CampaignProfitGivebackUSD=3.0;
input double MaxCampaignLossUSD=30.0;

//---------- RECOVERY SETTINGS ----------
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

//---------- RECOVERY EXIT v1.30 ----------
input double RecoveryLockStartUSD=2.0;
input double RecoveryLockProfitUSD=1.0;
input double RecoveryTrailStartUSD=5.0;
input double RecoveryTrailGivebackUSD=2.0;

//---------- RISK SETTINGS ----------
input int MaxCampaignHours=24;
input int MaximumExposurePositions=2;
input bool CloseOnRegimeBreak=true;

//---------- EQUITY / DAILY PROTECTION ----------
input double MaxEquityDrawdownPercent=15.0;
input bool ClosePositionsOnEquityProtection=true;
input double MaxDailyLossUSD=20.0;
input double MaxDailyLossPercent=2.0;
input bool ClosePositionsOnDailyProtection=true;

//---------- SESSION / EXECUTION ----------
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

//---------- HARD USD LOSS PROTECTION v1.33 ----------
input bool UseHardNormalUSDLoss=true;

int hFastEMA=-1,hSlowEMA=-1,hTrendEMA=-1,hHTFEMA=-1,hHTFFastEMA=-1,hHTFSlowEMA=-1,hADX=-1,hATR=-1,hRSI=-1;
datetime g_lastEntryTime=0,g_lastBarTime=0;
TrendDirection g_lastTrend=TREND_NONE;
CampaignState g_state=CAMPAIGN_IDLE;
bool g_closePending=false;
double g_campaignPeakProfit=0.0;
bool g_campaignPeakActive=false;
int g_recoveryAttempts=0;
double g_recoveryPeakProfit=0.0;
bool g_recoveryPeakActive=false;
bool g_profitProtectionClosePending=false;

//---------- STATE ISOLATION v1.36 ----------
string StateScope(){if((bool)MQLInfoInteger(MQL_TESTER))return "TESTER_"+(string)MagicNumber+"_"+_Symbol;return "LIVE_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+(string)MagicNumber+"_"+_Symbol;}
string GVPeak(){return "TRENDREC_V136_PEAK_"+StateScope();}
string GVDaily(){return "TRENDREC_V136_DAYEQ_"+StateScope();}
string GVDay(){return "TRENDREC_V136_DAY_"+StateScope();}
string GVStart(){return "TRENDREC_V136_START_"+StateScope();}
string GVProfitPeak(){return "TRENDREC_V136_PROFITPEAK_"+StateScope();}
string GVProfitStart(){return "TRENDREC_V136_PROFITSTART_"+StateScope();}
void Log(string s){if(EnableLogging)Print("[TrendRecoveryEA] ",s);}
int VolumeDigits(){double x=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);int d=0;while(d<8&&MathAbs(x-MathRound(x))>1e-10){x*=10.0;d++;}return d;}
double NormalizeLot(double lot){double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),st=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);if(mn<=0||mx<=0||st<=0)return 0;lot=MathMin(lot,MathMin(mx,MaxLot));lot=MathMax(lot,mn);lot=MathFloor(lot/st+1e-9)*st;if(lot<mn)lot=mn;return NormalizeDouble(lot,VolumeDigits());}
double NormalizePrice(double p){return NormalizeDouble(p,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));}
double MinStopDistance(){long a=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),b=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);return (double)MathMax(a,b)*_Point;}
bool TradeSucceeded(){uint r=trade.ResultRetcode();return r==TRADE_RETCODE_DONE||r==TRADE_RETCODE_DONE_PARTIAL||r==TRADE_RETCODE_PLACED;}
bool IsHedgingAccount(){return (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;}
bool IsSpreadAcceptable(){if(MaximumSpread<=0)return true;MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;return (t.ask-t.bid)/_Point<=MaximumSpread;}
bool IsTradingSession(){if(!UseTradingSession)return true;MqlDateTime d;TimeToStruct(TimeTradeServer(),d);if(TradingStartHour==TradingEndHour)return true;if(TradingStartHour<TradingEndHour)return d.hour>=TradingStartHour&&d.hour<TradingEndHour;return d.hour>=TradingStartHour||d.hour<TradingEndHour;}
bool IsNewBar(){datetime t=iTime(_Symbol,TrendTimeframe,0);if(t<=0)return false;if(t!=g_lastBarTime){g_lastBarTime=t;return true;}return false;}
bool Buf(int h,int b,int sh,double &v){if(h<0)return false;double x[1];if(CopyBuffer(h,b,sh,1,x)!=1)return false;v=x[0];return true;}
bool GetATR(double &v){return Buf(hATR,0,1,v);}

TrendDirection DetectTrend(){double f,s,tr,ht,a,atr,r;if(!Buf(hFastEMA,0,1,f)||!Buf(hSlowEMA,0,1,s)||!Buf(hTrendEMA,0,1,tr)||!Buf(hHTFEMA,0,1,ht)||!Buf(hADX,0,1,a)||!GetATR(atr))return TREND_NONE;double c=iClose(_Symbol,TrendTimeframe,1);if(c<=0||a<MinimumADX)return TREND_NONE;if(MaximumATRPoints>0&&atr/_Point>MaximumATRPoints)return TREND_NONE;bool buy=f>s&&c>tr&&c>ht,sell=f<s&&c<tr&&c<ht;if(UseRSIConfirmation){if(!Buf(hRSI,0,1,r))return TREND_NONE;buy=buy&&r>=RSIForBuy;sell=sell&&r<=RSIForSell;}if(buy)return TREND_BUY;if(sell)return TREND_SELL;return TREND_NONE;}
bool ConfirmTrend(TrendDirection dir){int n=MathMax(1,ReversalConfirmationBars);for(int sh=1;sh<=n;sh++){double f,s,tr,ht,a,atr,r;if(!Buf(hFastEMA,0,sh,f)||!Buf(hSlowEMA,0,sh,s)||!Buf(hTrendEMA,0,sh,tr)||!Buf(hHTFEMA,0,sh,ht)||!Buf(hADX,0,sh,a)||!Buf(hATR,0,sh,atr))return false;double c=iClose(_Symbol,TrendTimeframe,sh);if(c<=0||a<MinimumADX)return false;if(MaximumATRPoints>0&&atr/_Point>MaximumATRPoints)return false;bool ok=(dir==TREND_BUY)?f>s&&c>tr&&c>ht:f<s&&c<tr&&c<ht;if(UseRSIConfirmation){if(!Buf(hRSI,0,sh,r))return false;ok=ok&&((dir==TREND_BUY)?r>=RSIForBuy:r<=RSIForSell);}if(!ok)return false;}return true;}
bool ConfirmReversal(TrendDirection dir){int n=MathMax(2,RecoveryConfirmationBars);for(int sh=1;sh<=n;sh++){double f,atr;if(!Buf(hFastEMA,0,sh,f)||!Buf(hATR,0,sh,atr))return false;if(MaximumATRPoints>0&&atr/_Point>MaximumATRPoints)return false;double c=iClose(_Symbol,TrendTimeframe,sh),o=iOpen(_Symbol,TrendTimeframe,sh);if(c<=0||o<=0)return false;bool directional=(dir==TREND_BUY)?c>o:c<o;bool fastSide=(dir==TREND_BUY)?c>f:c<f;if(!directional||!fastSide)return false;}double f1,f2,f3;if(!Buf(hFastEMA,0,1,f1)||!Buf(hFastEMA,0,2,f2)||!Buf(hFastEMA,0,3,f3))return false;bool slopeOK=(dir==TREND_BUY)?f1>=f2&&f2>=f3:f1<=f2&&f2<=f3;if(!slopeOK)return false;if(UseRSIConfirmation){double r;if(!Buf(hRSI,0,1,r))return false;if(dir==TREND_BUY&&r<RSIForBuy)return false;if(dir==TREND_SELL&&r>RSIForSell)return false;}return true;}

int CountPositions(){int n=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)==_Symbol&&(long)PositionGetInteger(POSITION_MAGIC)==MagicNumber)n++;}return n;}
int CountRecoveryPositions(){int n=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)n++;}return n;}
double BasketProfit(){double p=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}return p;}
double NormalProfit(){double p=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)continue;p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}return p;}
double RecoveryProfit(){double p=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")<0)continue;p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);}return p;}
TrendDirection OriginalDirection(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)continue;ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);if(ty==POSITION_TYPE_BUY)return TREND_BUY;if(ty==POSITION_TYPE_SELL)return TREND_SELL;}return TREND_NONE;}
datetime CampaignStart(){datetime x=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;datetime p=(datetime)PositionGetInteger(POSITION_TIME);if(x==0||p<x)x=p;}return x;}

bool EquityLocked(){if(MaxEquityDrawdownPercent<=0)return false;double e=AccountInfoDouble(ACCOUNT_EQUITY),p=GlobalVariableGet(GVPeak());if(p<=0){p=e;GlobalVariableSet(GVPeak(),p);}if(e>p){p=e;GlobalVariableSet(GVPeak(),p);}return p>0&&(p-e)/p*100.0>=MaxEquityDrawdownPercent;}
void DailyState(){MqlDateTime d;TimeToStruct(TimeTradeServer(),d);long day=(long)d.year*10000+(long)d.mon*100+d.day;if(GlobalVariableGet(GVDay())!=(double)day){GlobalVariableSet(GVDay(),(double)day);GlobalVariableSet(GVDaily(),AccountInfoDouble(ACCOUNT_EQUITY));}}
bool DailyLocked(){DailyState();double s=GlobalVariableGet(GVDaily());if(s<=0)return false;double loss=s-AccountInfoDouble(ACCOUNT_EQUITY);return (MaxDailyLossUSD>0&&loss>=MaxDailyLossUSD)||(MaxDailyLossPercent>0&&loss/s*100.0>=MaxDailyLossPercent);}
bool CloseCampaign(){bool ok=true;bool locked=(g_state==CAMPAIGN_LOCKED);g_state=CAMPAIGN_EXIT;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);bool sent=trade.PositionClose(t);if(!sent||!TradeSucceeded()){ok=false;Log("Close failed ticket="+(string)t+" retcode="+(string)trade.ResultRetcode()+" "+trade.ResultRetcodeDescription());}}g_closePending=CountPositions()>0;if(!g_closePending&&ok){g_state=locked?CAMPAIGN_LOCKED:CAMPAIGN_IDLE;g_campaignPeakProfit=0;g_campaignPeakActive=false;g_recoveryAttempts=0;g_recoveryPeakProfit=0;g_recoveryPeakActive=false;}return ok;}

void ResetEquityProfitProtection(){double e=AccountInfoDouble(ACCOUNT_EQUITY);GlobalVariableSet(GVProfitPeak(),e);GlobalVariableSet(GVProfitStart(),e);}
bool EquityProfitProtection(){if(!UseEquityProfitProtection||EquityProfitLockStartUSD<=0||EquityProfitGivebackUSD<=0)return false;double e=AccountInfoDouble(ACCOUNT_EQUITY),peak=GlobalVariableGet(GVProfitPeak()),start=GlobalVariableGet(GVProfitStart());if(peak<=0||start<=0){ResetEquityProfitProtection();return false;}if(e>peak){peak=e;GlobalVariableSet(GVProfitPeak(),peak);return false;}if(peak-start<EquityProfitLockStartUSD)return false;return (peak-e)>=EquityProfitGivebackUSD;}

bool HardNormalLossProtection(){if(!UseHardNormalUSDLoss||MaxNormalLossPerTradeUSD<=0)return false;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)continue;double pnl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);if(pnl<=-MaxNormalLossPerTradeUSD){Log("HARD USD LOSS: normal position reached -$"+DoubleToString(MaxNormalLossPerTradeUSD,2)+". Force closing campaign.");CloseCampaign();return true;}}return false;}

void RiskEngine(){if(HardNormalLossProtection())return;if(EquityLocked()){g_state=CAMPAIGN_LOCKED;if(ClosePositionsOnEquityProtection&&CountPositions()>0)CloseCampaign();return;}if(EquityProfitProtection()){Log("Equity profit protection triggered. Closing current campaign and resetting profit-protection cycle.");g_profitProtectionClosePending=true;if(CountPositions()>0)CloseCampaign();if(CountPositions()==0){ResetEquityProfitProtection();g_profitProtectionClosePending=false;g_state=CAMPAIGN_IDLE;}return;}if(DailyLocked()){g_state=CAMPAIGN_LOCKED;Log("Daily loss protection triggered.");if(ClosePositionsOnDailyProtection&&CountPositions()>0)CloseCampaign();return;}if(MaxCampaignLossUSD>0&&BasketProfit()<=-MaxCampaignLossUSD){CloseCampaign();return;}if(MaxCampaignHours>0&&CountPositions()>0){datetime s=CampaignStart();if(s>0&&TimeCurrent()-s>=MaxCampaignHours*3600)CloseCampaign();}}

bool HasDistance(TrendDirection d){if(MinimumEntryDistance<=0)return true;MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;double p=d==TREND_BUY?t.ask:t.bid;for(int i=PositionsTotal()-1;i>=0;i--){ulong x=PositionGetTicket(i);if(x==0||!PositionSelectByTicket(x))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(MathAbs(p-PositionGetDouble(POSITION_PRICE_OPEN))<MinimumEntryDistance)return false;}return true;}
bool CanOpen(TrendDirection d){if(d==TREND_NONE||g_state==CAMPAIGN_LOCKED||g_closePending)return false;if(EquityLocked()||DailyLocked()||!IsTradingSession()||!IsSpreadAcceptable())return false;if(CountPositions()>=MaximumPositions)return false;if(MaximumExposurePositions>0&&CountPositions()>=MaximumExposurePositions)return false;if(g_lastEntryTime>0&&TimeCurrent()-g_lastEntryTime<EntryCooldownSeconds)return false;return HasDistance(d)&&ConfirmTrend(d);}
double EntryLot(){return NormalizeLot(UseEquityScaling&&BaseEquity>0?BaseLot*AccountInfoDouble(ACCOUNT_EQUITY)/BaseEquity:InitialLot);}
double MoneyDistance(double money,double vol){if(money<=0||vol<=0)return 0;double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE),ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);if(tv<=0||ts<=0)return 0;return money/(tv*vol)*ts;}
double CalcLossUSD(ENUM_POSITION_TYPE ty,double volume,double openPrice,double stopPrice){if(volume<=0||openPrice<=0||stopPrice<=0)return 0;ENUM_ORDER_TYPE ot=ty==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL;double pnl=0;if(!OrderCalcProfit(ot,_Symbol,volume,openPrice,stopPrice,pnl))return 0;return MathMax(0.0,-pnl);}
double RiskSLByUSD(ENUM_POSITION_TYPE ty,double volume,double openPrice,double riskUSD){if(volume<=0||openPrice<=0||riskUSD<=0)return 0;double minDist=MinStopDistance(),dist=MathMax(minDist,MoneyDistance(riskUSD,volume)),loss=0;if(dist<=0)return 0;for(int k=0;k<12;k++){double sl=ty==POSITION_TYPE_BUY?openPrice-dist:openPrice+dist;if(sl<=_Point||sl>=openPrice*2.0)return 0;loss=CalcLossUSD(ty,volume,openPrice,sl);if(loss>=riskUSD)break;dist*=2.0;}if(loss<riskUSD)return 0;double lo=minDist,hi=dist;for(int i=0;i<40;i++){double mid=(lo+hi)*0.5,sl=ty==POSITION_TYPE_BUY?openPrice-mid:openPrice+mid,x=CalcLossUSD(ty,volume,openPrice,sl);if(x>=riskUSD)hi=mid;else lo=mid;}return NormalizePrice(ty==POSITION_TYPE_BUY?openPrice-hi:openPrice+hi);}
bool ValidSL(ENUM_POSITION_TYPE ty,double sl){MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;double d=MinStopDistance();return ty==POSITION_TYPE_BUY?sl<=t.bid-d:sl>=t.ask+d;}
bool ModifySL(ulong ticket,double sl){if(!PositionSelectByTicket(ticket))return false;ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);double old=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);sl=NormalizePrice(sl);if(!ValidSL(ty,sl))return false;if(ty==POSITION_TYPE_BUY&&old>0&&sl<=old+_Point)return false;if(ty==POSITION_TYPE_SELL&&old>0&&sl>=old-_Point)return false;trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);return trade.PositionModify(ticket,sl,tp)&&TradeSucceeded();}

bool OpenTrade(TrendDirection d,string comment,double lot,double slMult){MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;double atr;if(!GetATR(atr))return false;ENUM_POSITION_TYPE ty=d==TREND_BUY?POSITION_TYPE_BUY:POSITION_TYPE_SELL;double p=d==TREND_BUY?t.ask:t.bid,sl=0;if(slMult>0){double atrDist=MathMax(atr*slMult,MinStopDistance());double riskUSD=0;if(MaxInitialLossUSD>0&&MaxNormalLossPerTradeUSD>0)riskUSD=MathMin(MaxInitialLossUSD,MaxNormalLossPerTradeUSD);else if(MaxInitialLossUSD>0)riskUSD=MaxInitialLossUSD;else if(MaxNormalLossPerTradeUSD>0)riskUSD=MaxNormalLossPerTradeUSD;double usdSL=0;if(riskUSD>0)usdSL=RiskSLByUSD(ty,lot,p,riskUSD);if(usdSL>0){sl=usdSL;double usdRisk=CalcLossUSD(ty,lot,p,sl);if(usdRisk>riskUSD+0.05){Log("Normal entry rejected: USD SL exceeds configured risk.");return false;}}else{double dist=atrDist;sl=NormalizePrice(d==TREND_BUY?p-dist:p+dist);if(riskUSD>0){double fallbackRisk=CalcLossUSD(ty,lot,p,sl);if(fallbackRisk>riskUSD+0.05){Log("Normal entry rejected: broker/price constraints cannot satisfy USD risk limit.");return false;}}}}trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);bool sent=d==TREND_BUY?trade.Buy(lot,_Symbol,0,sl,0,comment):trade.Sell(lot,_Symbol,0,sl,0,comment);return sent&&TradeSucceeded();}

bool OpenRecoveryTrade(TrendDirection d,double lot){MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;double atr;if(!GetATR(atr))return false;ENUM_POSITION_TYPE ty=d==TREND_BUY?POSITION_TYPE_BUY:POSITION_TYPE_SELL;double p=d==TREND_BUY?t.ask:t.bid,sl=0;if(RecoveryMaxLossPerTradeUSD>0){sl=RiskSLByUSD(ty,lot,p,RecoveryMaxLossPerTradeUSD);if(sl<=0){Log("Recovery skipped: unable to create USD-accurate SL.");return false;}double expected=CalcLossUSD(ty,lot,p,sl);if(expected>RecoveryMaxLossPerTradeUSD+0.05){Log("Recovery skipped: SL risk exceeds limit.");return false;}}else if(RecoverySL_ATR>0){double dist=MathMax(atr*RecoverySL_ATR,MinStopDistance());sl=NormalizePrice(d==TREND_BUY?p-dist:p+dist);}if(sl>0&&!ValidSL(ty,sl)){Log("Recovery skipped: broker stop constraint invalidates risk SL.");return false;}trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);bool sent=d==TREND_BUY?trade.Buy(lot,_Symbol,0,sl,0,"RECOVERY BUY"):trade.Sell(lot,_Symbol,0,sl,0,"RECOVERY SELL");if(!sent||!TradeSucceeded()){Log("Recovery entry failed retcode="+(string)trade.ResultRetcode()+" "+trade.ResultRetcodeDescription());return false;}return true;}

void PositionProtection(ulong ticket){if(!PositionSelectByTicket(ticket))return;ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);double profit=PositionGetDouble(POSITION_PROFIT),open=PositionGetDouble(POSITION_PRICE_OPEN),vol=PositionGetDouble(POSITION_VOLUME),sl=0;if(UseATRTrailing&&profit>=ATRTrailingStartUSD){double atr;MqlTick t;if(GetATR(atr)&&SymbolInfoTick(_Symbol,t))sl=ty==POSITION_TYPE_BUY?t.bid-atr*ATRTrailingMultiplier:t.ask+atr*ATRTrailingMultiplier;}else if(UseProfitLock&&profit>=ProfitLockStartUSD&&ProfitLockStepUSD>0){int n=(int)MathFloor((profit-ProfitLockStartUSD)/ProfitLockStepUSD)+1;double locked=ProfitLockOffsetUSD+(n-1)*ProfitLockStepUSD,dist=MoneyDistance(locked,vol);if(dist>0)sl=ty==POSITION_TYPE_BUY?open+dist:open-dist;}else if(UseBreakEven&&profit>=BreakEvenStartUSD){double dist=MoneyDistance(BreakEvenOffsetUSD,vol);if(dist>0)sl=ty==POSITION_TYPE_BUY?open+dist:open-dist;}if(sl>0)ModifySL(ticket,sl);}
void ProfitEngine(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;PositionProtection(t);}}
void EntryEngine(TrendDirection d){if(g_state==CAMPAIGN_LOCKED||g_closePending||CountPositions()>0||d==TREND_NONE)return;if(CanOpen(d)){double lot=EntryLot();if(lot>0&&OpenTrade(d,"TREND "+(d==TREND_BUY?"BUY":"SELL"),lot,UseInitialSL?InitialSL_ATR:0)){g_lastEntryTime=TimeCurrent();g_state=CAMPAIGN_TREND;g_campaignPeakProfit=BasketProfit();g_campaignPeakActive=true;}}}

bool ConfirmHTFRecovery(TrendDirection rev){if(!RecoveryRequireHTFAlignment)return true;double ema,fast,slow,adx;if(!Buf(hHTFEMA,0,1,ema)||!Buf(hHTFFastEMA,0,1,fast)||!Buf(hHTFSlowEMA,0,1,slow)||!Buf(hADX,0,1,adx))return false;if(adx<RecoveryMinimumADX)return false;double c=iClose(_Symbol,HigherTimeframe,1);if(c<=0)return false;return rev==TREND_SELL?(c<ema&&fast<slow):(c>ema&&fast>slow);}
bool RegimeBreakDetected(TrendDirection orig){int n=MathMax(1,RegimeBreakConfirmationBars);for(int sh=1;sh<=n;sh++){double f,s,tr,ht,a,atr;if(!Buf(hFastEMA,0,sh,f)||!Buf(hSlowEMA,0,sh,s)||!Buf(hTrendEMA,0,sh,tr)||!Buf(hHTFEMA,0,sh,ht)||!Buf(hADX,0,sh,a)||!Buf(hATR,0,sh,atr))return false;double c=iClose(_Symbol,TrendTimeframe,sh);if(c<=0||a<MinimumADX)return false;if(orig==TREND_BUY){if(!(f<s&&c<tr&&c<ht))return false;}else if(orig==TREND_SELL){if(!(f>s&&c>tr&&c>ht))return false;}else return false;}return true;}
bool RegimeDamageDetected(TrendDirection orig){int n=MathMax(1,RegimeDamageConfirmationBars);for(int sh=1;sh<=n;sh++){double f,fp,c,o;if(!Buf(hFastEMA,0,sh,f)||!Buf(hFastEMA,0,sh+1,fp))return false;c=iClose(_Symbol,TrendTimeframe,sh);o=iOpen(_Symbol,TrendTimeframe,sh);if(c<=0||o<=0)return false;if(orig==TREND_BUY){if(!(c<f&&f<fp))return false;}else if(orig==TREND_SELL){if(!(c>f&&f>fp))return false;}else return false;}return true;}
bool StrongBuyRegimeExitDetected(){if(!UseStrongBuyRegimeExit)return false;int n=MathMax(1,BuyRegimeExitConfirmationBars);for(int sh=1;sh<=n;sh++){double f,fp,adx,plusDI,minusDI;if(!Buf(hFastEMA,0,sh,f)||!Buf(hFastEMA,0,sh+1,fp)||!Buf(hADX,0,sh,adx)||!Buf(hADX,1,sh,plusDI)||!Buf(hADX,2,sh,minusDI))return false;double c=iClose(_Symbol,TrendTimeframe,sh);if(c<=0)return false;if(!(c<f&&f<fp&&adx>=BuyRegimeExitADX&&minusDI>plusDI))return false;}return true;}

bool StartRecovery(TrendDirection rev){if(!UseRecovery||rev==TREND_NONE)return false;if(g_recoveryAttempts>=1||CountRecoveryPositions()>=MaxRecoveryPositions)return false;if(RequireHedgingAccountForRecovery&&!IsHedgingAccount())return false;TrendDirection orig=OriginalDirection();if(orig==TREND_NONE||rev==orig)return false;double normal=NormalProfit();if(normal>=0||MathAbs(normal)<RecoveryTriggerUSD)return false;if(MaximumExposurePositions>0&&CountPositions()>=MaximumExposurePositions)return false;if(MaximumExposurePositions>0&&MaximumExposurePositions<2)return false;if(!IsSpreadAcceptable()||!ConfirmHTFRecovery(rev))return false;double baseLot=0;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")>=0)continue;baseLot+=PositionGetDouble(POSITION_VOLUME);}if(baseLot<=0)return false;double lot=NormalizeLot(MathMin(baseLot*RecoveryMultiplier,MaxRecoveryLot));if(lot<=0)return false;if(OpenRecoveryTrade(rev,lot)){g_recoveryAttempts=1;g_state=CAMPAIGN_RECOVERY;Log("Recovery opened: M15 reversal + HTF alignment confirmed.");return true;}return false;}
void ReversalEngine(){TrendDirection orig=OriginalDirection();if(orig==TREND_NONE)return;if(NormalProfit()>-RecoveryTriggerUSD)return;TrendDirection rev=orig==TREND_BUY?TREND_SELL:TREND_BUY;if(!ConfirmReversal(rev))return;if(UseRecovery&&StartRecovery(rev))return;if(CloseOnStrongReversalIfNoRecovery){Log("Strong reversal detected without safe recovery alignment. Closing campaign.");CloseCampaign();}}

bool CampaignExit(){if(CountPositions()<=0){g_campaignPeakProfit=0;g_campaignPeakActive=false;return false;}double p=BasketProfit();if(!g_campaignPeakActive){g_campaignPeakProfit=p;g_campaignPeakActive=true;}if(p>g_campaignPeakProfit)g_campaignPeakProfit=p;if(CampaignProfitTargetUSD>0&&p>=CampaignProfitTargetUSD){CloseCampaign();return true;}if(CampaignProfitTrailStartUSD>0&&CampaignProfitGivebackUSD>0&&g_campaignPeakProfit>=CampaignProfitTrailStartUSD&&(g_campaignPeakProfit-p)>=CampaignProfitGivebackUSD&&p>0){CloseCampaign();return true;}return false;}

void ResetRecoveryState(){g_recoveryPeakProfit=0;g_recoveryPeakActive=false;}
void RecoveryProfitLock(){if(RecoveryLockStartUSD<=0||RecoveryLockProfitUSD<=0)return;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")<0)continue;double profit=PositionGetDouble(POSITION_PROFIT);if(profit<RecoveryLockStartUSD)continue;ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);double vol=PositionGetDouble(POSITION_VOLUME),open=PositionGetDouble(POSITION_PRICE_OPEN),dist=MoneyDistance(RecoveryLockProfitUSD,vol);if(dist<=0)continue;double sl=ty==POSITION_TYPE_BUY?open+dist:open-dist;MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))continue;double md=MinStopDistance();sl=ty==POSITION_TYPE_BUY?MathMin(sl,tick.bid-md):MathMax(sl,tick.ask+md);ModifySL(t,NormalizePrice(sl));}}
void RecoveryProfitTrail(double recoveryProfit){if(RecoveryTrailStartUSD<=0||RecoveryTrailGivebackUSD<=0||recoveryProfit<RecoveryTrailStartUSD)return;if(!g_recoveryPeakActive){g_recoveryPeakProfit=recoveryProfit;g_recoveryPeakActive=true;}if(recoveryProfit>g_recoveryPeakProfit)g_recoveryPeakProfit=recoveryProfit;double locked=g_recoveryPeakProfit-RecoveryTrailGivebackUSD;if(locked<=0)return;for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i);if(t==0||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=_Symbol||(long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")<0)continue;ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);double vol=PositionGetDouble(POSITION_VOLUME),open=PositionGetDouble(POSITION_PRICE_OPEN),dist=MoneyDistance(locked,vol);if(dist<=0)continue;double sl=ty==POSITION_TYPE_BUY?open+dist:open-dist;MqlTick tick;if(!SymbolInfoTick(_Symbol,tick))continue;double md=MinStopDistance();sl=ty==POSITION_TYPE_BUY?MathMin(sl,tick.bid-md):MathMax(sl,tick.ask+md);ModifySL(t,NormalizePrice(sl));}}
void RecoveryEngine(){if(CountRecoveryPositions()<=0){ResetRecoveryState();return;}g_state=CAMPAIGN_RECOVERY;double recovery=RecoveryProfit(),normal=NormalProfit(),basket=normal+recovery;if(!g_recoveryPeakActive){g_recoveryPeakProfit=recovery;g_recoveryPeakActive=true;}if(recovery>g_recoveryPeakProfit)g_recoveryPeakProfit=recovery;if(RecoveryMaxLossPerTradeUSD>0&&recovery<=-RecoveryMaxLossPerTradeUSD){Log("Recovery hard USD loss limit reached. Closing campaign.");CloseCampaign();return;}if(RecoveryMaxLossUSD>0&&recovery<=-RecoveryMaxLossUSD){Log("Recovery campaign loss limit reached. Closing campaign.");CloseCampaign();return;}if(RecoveryTargetUSD>0&&recovery>=RecoveryTargetUSD&&basket>=RecoveryMinProfitUSD){CloseCampaign();return;}RecoveryProfitLock();RecoveryProfitTrail(recovery);}

void ManagePositions(){if(CountPositions()<=0){g_campaignPeakProfit=0;g_campaignPeakActive=false;ResetRecoveryState();if(!g_closePending&&g_state!=CAMPAIGN_LOCKED){g_state=CAMPAIGN_IDLE;g_recoveryAttempts=0;}return;}if(CampaignExit())return;if(CountRecoveryPositions()>0){TrendDirection orig=OriginalDirection();if(orig!=TREND_NONE&&NormalProfit()<0&&CloseOnRegimeDamage&&RegimeDamageDetected(orig)){Log("Trend regime damage detected during recovery. Closing campaign.");CloseCampaign();return;}RecoveryEngine();if(CountPositions()>0)ProfitEngine();return;}TrendDirection orig=OriginalDirection();if(orig==TREND_BUY&&NormalProfit()<0&&StrongBuyRegimeExitDetected()){Log("STRONG BUY regime exit: price below Fast EMA, EMA slope down and bearish DI pressure confirmed. Closing BUY campaign.");CloseCampaign();return;}if(orig!=TREND_NONE&&NormalProfit()<0){if(CloseOnRegimeDamage&&RegimeDamageDetected(orig)){Log("Trend regime damage detected while position is losing. Closing campaign.");return;}if(CloseOnRegimeBreak&&RegimeBreakDetected(orig)){Log("Trend regime fully broken while position is losing. Closing campaign.");CloseCampaign();return;}}ReversalEngine();if(CountPositions()<=0)return;ProfitEngine();g_state=BasketProfit()>0?CAMPAIGN_PROFIT:CAMPAIGN_TREND;}
void TrendLog(TrendDirection d){if(!LogTrendChanges||d==g_lastTrend)return;Log("Trend="+(d==TREND_BUY?"BUY":d==TREND_SELL?"SELL":"NONE"));g_lastTrend=d;}

int OnInit(){trade.SetExpertMagicNumber(MagicNumber);trade.SetDeviationInPoints(SlippagePoints);trade.SetTypeFillingBySymbol(_Symbol);hFastEMA=iMA(_Symbol,TrendTimeframe,FastEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hSlowEMA=iMA(_Symbol,TrendTimeframe,SlowEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hTrendEMA=iMA(_Symbol,TrendTimeframe,TrendEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hHTFEMA=iMA(_Symbol,HigherTimeframe,TrendEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hHTFFastEMA=iMA(_Symbol,HigherTimeframe,FastEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hHTFSlowEMA=iMA(_Symbol,HigherTimeframe,SlowEMAPeriod,0,MODE_EMA,PRICE_CLOSE);hADX=iADX(_Symbol,TrendTimeframe,ADXPeriod);hATR=iATR(_Symbol,TrendTimeframe,14);hRSI=iRSI(_Symbol,TrendTimeframe,RSIPeriod,PRICE_CLOSE);if(hFastEMA<0||hSlowEMA<0||hTrendEMA<0||hHTFEMA<0||hHTFFastEMA<0||hHTFSlowEMA<0||hADX<0||hATR<0||hRSI<0)return INIT_FAILED;double e=AccountInfoDouble(ACCOUNT_EQUITY);bool tester=(bool)MQLInfoInteger(MQL_TESTER);if(tester){GlobalVariableSet(GVPeak(),e);GlobalVariableSet(GVStart(),e);GlobalVariableSet(GVDaily(),e);MqlDateTime td;TimeToStruct(TimeTradeServer(),td);long day=(long)td.year*10000+(long)td.mon*100+td.day;GlobalVariableSet(GVDay(),(double)day);ResetEquityProfitProtection();}else{if(!GlobalVariableCheck(GVPeak())||GlobalVariableGet(GVPeak())<=0)GlobalVariableSet(GVPeak(),e);if(!GlobalVariableCheck(GVStart())||GlobalVariableGet(GVStart())<=0)GlobalVariableSet(GVStart(),e);if(!GlobalVariableCheck(GVProfitPeak())||GlobalVariableGet(GVProfitPeak())<=0||!GlobalVariableCheck(GVProfitStart())||GlobalVariableGet(GVProfitStart())<=0)ResetEquityProfitProtection();DailyState();}int n=CountPositions();g_state=n>0?(CountRecoveryPositions()>0?CAMPAIGN_RECOVERY:CAMPAIGN_TREND):CAMPAIGN_IDLE;if(n>0){g_campaignPeakProfit=BasketProfit();g_campaignPeakActive=true;}return INIT_SUCCEEDED;}
void OnDeinit(const int reason){if(hFastEMA>=0)IndicatorRelease(hFastEMA);if(hSlowEMA>=0)IndicatorRelease(hSlowEMA);if(hTrendEMA>=0)IndicatorRelease(hTrendEMA);if(hHTFEMA>=0)IndicatorRelease(hHTFEMA);if(hHTFFastEMA>=0)IndicatorRelease(hHTFFastEMA);if(hHTFSlowEMA>=0)IndicatorRelease(hHTFSlowEMA);if(hADX>=0)IndicatorRelease(hADX);if(hATR>=0)IndicatorRelease(hATR);if(hRSI>=0)IndicatorRelease(hRSI);}
void OnTick(){DailyState();if(g_closePending){if(CountPositions()==0){g_closePending=false;if(g_profitProtectionClosePending){ResetEquityProfitProtection();g_profitProtectionClosePending=false;g_state=CAMPAIGN_IDLE;}else if(g_state!=CAMPAIGN_LOCKED)g_state=CAMPAIGN_IDLE;}else{HardNormalLossProtection();ProfitEngine();return;}}RiskEngine();if(g_state==CAMPAIGN_EXIT||g_closePending){if(CountPositions()==0&&g_state!=CAMPAIGN_LOCKED)g_state=CAMPAIGN_IDLE;return;}TrendDirection trend=DetectTrend();TrendLog(trend);ManagePositions();if(g_state==CAMPAIGN_LOCKED||g_closePending)return;if(UseNewBarForEntry&&!IsNewBar())return;EntryEngine(trend);}
