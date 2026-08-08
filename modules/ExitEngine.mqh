#ifndef __TRENDRECOVERY_EXIT_ENGINE_MQH__
#define __TRENDRECOVERY_EXIT_ENGINE_MQH__

//---------- EXIT ENGINE ----------
// Generic basket/position exit helpers for TrendRecoveryEA.
// The module is intentionally self-contained so it can be integrated
// into the main EA without changing the existing entry engine.

struct ExitSnapshot
{
   double profit;
   double peakProfit;
   double drawdownFromPeak;
   int positions;
};

void ResetExitSnapshot(ExitSnapshot &s)
{
   s.profit=0.0;
   s.peakProfit=0.0;
   s.drawdownFromPeak=0.0;
   s.positions=0;
}

void UpdateExitSnapshot(ExitSnapshot &s,double currentProfit)
{
   s.profit=currentProfit;
   if(currentProfit>s.peakProfit)
      s.peakProfit=currentProfit;
   s.drawdownFromPeak=s.peakProfit-currentProfit;
}

bool ExitTargetReached(const ExitSnapshot &s,double targetUSD)
{
   return targetUSD>0.0 && s.profit>=targetUSD;
}

bool ExitDrawdownReached(const ExitSnapshot &s,double trailUSD)
{
   return trailUSD>0.0 && s.peakProfit>0.0 && s.drawdownFromPeak>=trailUSD;
}

bool ExitLossReached(const ExitSnapshot &s,double maxLossUSD)
{
   return maxLossUSD>0.0 && s.profit<=-maxLossUSD;
}

bool ExitDurationReached(datetime startTime,int maxHours)
{
   if(startTime<=0 || maxHours<=0)
      return false;
   return (TimeCurrent()-startTime)>=(maxHours*3600);
}

#endif
