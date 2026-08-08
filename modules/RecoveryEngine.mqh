#property strict

//---------- RECOVERY ENGINE V1.20 ----------
// Controlled basket recovery module.
// Designed for hedging accounts. The main EA should call:
//   RecoveryEngine.Update(...)
// and use ShouldExit() / ShouldProtect() before opening additional recovery trades.

class CRecoveryEngine
{
private:
   bool     m_active;
   datetime m_startTime;
   double   m_peakBasketProfit;
   int      m_recoveryCount;

public:
   void Reset()
   {
      m_active=false;
      m_startTime=0;
      m_peakBasketProfit=0.0;
      m_recoveryCount=0;
   }

   void Start(datetime startTime,double currentBasketProfit,int recoveryCount)
   {
      m_active=true;
      m_startTime=startTime;
      m_peakBasketProfit=currentBasketProfit;
      m_recoveryCount=recoveryCount;
   }

   void Update(double basketProfit,int recoveryCount)
   {
      if(!m_active)
         return;

      m_recoveryCount=recoveryCount;
      if(basketProfit>m_peakBasketProfit)
         m_peakBasketProfit=basketProfit;
   }

   bool IsActive() const
   {
      return m_active;
   }

   int RecoveryCount() const
   {
      return m_recoveryCount;
   }

   double PeakBasketProfit() const
   {
      return m_peakBasketProfit;
   }

   // Exit once the basket has recovered enough from its worst state.
   bool ShouldExit(double basketProfit,double targetUSD,double minimumProfitUSD) const
   {
      if(!m_active)
         return false;
      if(targetUSD>0.0 && basketProfit>=targetUSD)
         return basketProfit>=minimumProfitUSD;
      return false;
   }

   // Prevent recovery from being allowed to run indefinitely.
   bool ShouldProtect(double basketProfit,double maximumLossUSD) const
   {
      if(!m_active || maximumLossUSD<=0.0)
         return false;
      return basketProfit<=-maximumLossUSD;
   }

   // Optional basket trailing exit. Once recovery produces a positive peak,
   // protect part of that recovered profit instead of waiting for target only.
   bool ShouldTrailExit(double basketProfit,double trailStartUSD,double trailGivebackUSD) const
   {
      if(!m_active || trailStartUSD<=0.0 || trailGivebackUSD<=0.0)
         return false;
      if(m_peakBasketProfit<trailStartUSD)
         return false;
      return basketProfit<=m_peakBasketProfit-trailGivebackUSD;
   }
};
