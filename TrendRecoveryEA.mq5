#property strict
#property version   "1.28"
#property description "Trend following EA with controlled recovery, responsive reversal detection, hierarchical exit and hard risk limits. Recovery Engine v1.28 integrated."
#include "TrendRecoveryEA_v1.27.mq5"

//---------- RECOVERY ENGINE v1.28 SETTINGS ----------
input double RecoveryLockStartUSD=2.0;
input double RecoveryLockProfitUSD=1.0;
input double RecoveryTrailStartUSD=5.0;
input double RecoveryTrailGivebackUSD=2.0;

//---------- RECOVERY ENGINE v1.28 STATE ----------
double g_recoveryPeakProfit_v128=0.0;
bool   g_recoveryPeakActive_v128=false;

//---------- RECOVERY P/L ----------
double RecoveryProfit_v128()
{
   double p=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")<0) continue;
      p+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   return p;
}

void ResetRecoveryState_v128()
{
   g_recoveryPeakProfit_v128=0.0;
   g_recoveryPeakActive_v128=false;
}

//---------- RECOVERY PROFIT LOCK ----------
void RecoveryProfitLock_v128()
{
   if(RecoveryLockStartUSD<=0.0 || RecoveryLockProfitUSD<=0.0) return;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")<0) continue;

      double profit=PositionGetDouble(POSITION_PROFIT);
      if(profit<RecoveryLockStartUSD) continue;

      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volume=PositionGetDouble(POSITION_VOLUME);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double oldSL=PositionGetDouble(POSITION_SL);
      double distance=MoneyDistance(RecoveryLockProfitUSD,volume);
      if(distance<=0.0) continue;

      double sl=(type==POSITION_TYPE_BUY)?open+distance:open-distance;
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol,tick)) continue;

      double minDist=MinStopDistance();
      sl=(type==POSITION_TYPE_BUY)?MathMin(sl,tick.bid-minDist):MathMax(sl,tick.ask+minDist);
      sl=NormalizePrice(sl);

      bool better=(type==POSITION_TYPE_BUY)
                  ?(oldSL<=0.0 || sl>oldSL+_Point)
                  :(oldSL<=0.0 || sl<oldSL-_Point);
      if(better) ModifySL(ticket,sl);
   }
}

//---------- RECOVERY PROFIT TRAIL ----------
void RecoveryProfitTrail_v128(double recoveryProfit)
{
   if(RecoveryTrailStartUSD<=0.0 || RecoveryTrailGivebackUSD<=0.0 || recoveryProfit<RecoveryTrailStartUSD) return;

   if(!g_recoveryPeakActive_v128)
   {
      g_recoveryPeakProfit_v128=recoveryProfit;
      g_recoveryPeakActive_v128=true;
   }
   if(recoveryProfit>g_recoveryPeakProfit_v128)
      g_recoveryPeakProfit_v128=recoveryProfit;

   double lockedProfit=g_recoveryPeakProfit_v128-RecoveryTrailGivebackUSD;
   if(lockedProfit<=0.0) return;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT),"RECOVERY")<0) continue;

      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volume=PositionGetDouble(POSITION_VOLUME);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double oldSL=PositionGetDouble(POSITION_SL);
      double distance=MoneyDistance(lockedProfit,volume);
      if(distance<=0.0) continue;

      double sl=(type==POSITION_TYPE_BUY)?open+distance:open-distance;
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol,tick)) continue;

      double minDist=MinStopDistance();
      sl=(type==POSITION_TYPE_BUY)?MathMin(sl,tick.bid-minDist):MathMax(sl,tick.ask+minDist);
      sl=NormalizePrice(sl);

      bool better=(type==POSITION_TYPE_BUY)
                  ?(oldSL<=0.0 || sl>oldSL+_Point)
                  :(oldSL<=0.0 || sl<oldSL-_Point);
      if(better) ModifySL(ticket,sl);
   }
}

//---------- RECOVERY ENGINE v1.28 ----------
void RecoveryEngine()
{
   int recoveryCount=CountRecoveryPositions();
   if(recoveryCount<=0)
   {
      ResetRecoveryState_v128();
      return;
   }

   g_state=CAMPAIGN_RECOVERY;
   double recovery=RecoveryProfit_v128();
   double normal=NormalProfit();
   double basket=normal+recovery;

   if(!g_recoveryPeakActive_v128)
   {
      g_recoveryPeakProfit_v128=recovery;
      g_recoveryPeakActive_v128=true;
   }
   if(recovery>g_recoveryPeakProfit_v128)
      g_recoveryPeakProfit_v128=recovery;

   // v1.28: hard recovery loss is measured ONLY on the recovery leg.
   if(RecoveryMaxLossUSD>0.0 && recovery<=-RecoveryMaxLossUSD)
   {
      Log("Recovery hard loss reached | recovery="+DoubleToString(recovery,2)+" | limit="+DoubleToString(RecoveryMaxLossUSD,2));
      CloseCampaign();
      return;
   }

   // v1.28: recovery target is a campaign-result gate.
   if(RecoveryTargetUSD>0.0 && recovery>=RecoveryTargetUSD && basket>=RecoveryMinProfitUSD)
   {
      Log("Recovery target + campaign result reached | recovery="+DoubleToString(recovery,2)+" | normal="+DoubleToString(normal,2)+" | basket="+DoubleToString(basket,2));
      CloseCampaign();
      return;
   }

   RecoveryProfitLock_v128();
   RecoveryProfitTrail_v128(recovery);
}

//---------- POSITION MANAGER v1.28 ----------
void ManagePositions()
{
   if(CountPositions()<=0)
   {
      g_campaignPeakProfit=0.0;
      g_campaignPeakActive=false;
      ResetRecoveryState_v128();
      if(!g_closePending && g_state!=CAMPAIGN_LOCKED)
      {
         g_state=CAMPAIGN_IDLE;
         g_recoveryAttempts=0;
      }
      return;
   }

   if(CampaignExit()) return;

   if(CountRecoveryPositions()>0)
   {
      RecoveryEngine();
      if(CountPositions()>0) ProfitEngine();
      return;
   }

   ReversalEngine();
   if(CountPositions()<=0) return;
   ProfitEngine();
   g_state=BasketProfit()>0.0?CAMPAIGN_PROFIT:CAMPAIGN_TREND;
}

//---------- TICK ENGINE v1.28 ----------
void OnTick()
{
   DailyState();

   if(g_closePending)
   {
      if(CountPositions()==0)
      {
         g_closePending=false;
         if(g_state!=CAMPAIGN_LOCKED) g_state=CAMPAIGN_IDLE;
      }
      else
      {
         ProfitEngine();
         return;
      }
   }

   TrendDirection trend=DetectTrend();
   TrendLog(trend);
   RiskEngine();

   if(g_state==CAMPAIGN_EXIT || g_closePending)
   {
      if(CountPositions()==0 && g_state!=CAMPAIGN_LOCKED) g_state=CAMPAIGN_IDLE;
      return;
   }

   ManagePositions();
   if(g_state==CAMPAIGN_LOCKED || g_closePending) return;
   if(UseNewBarForEntry && !IsNewBar()) return;
   EntryEngine(trend);
}
