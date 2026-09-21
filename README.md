# EGEC-597-Final-Project
Final Project for EGEC 597


                    Cache / CPU Events
                           │
       ┌───────────────────┼─────────────────────┐
       │                   │                     │
       ▼                   ▼                     ▼
   Cache Misses        Evictions             Bursts
       │                   │                     │
       └──────────────┐    │    ┌────────────────┘
                      ▼    ▼    ▼
                    Counters
                       │
         ┌─────────────┼─────────────┐
         │                           │
         ▼                           ▼
   Stall Cycles              Conflict Pattern
                                   Detector
         │                           │
         └─────────────┬─────────────┘
                       ▼
                 Threat Score
                       │
                 ┌─────┴─────┐
                 ▼           ▼
               Alert      Hardened

---------------------------------------------------

          Normal

Set 17

Way 0 ──────────┐
Way 1 ──────────┤ Any process
Way 2 ──────────┤
Way 3 ──────────┘


          Hardened

Set 17

Way 0 ─── Victim
Way 1 ─── Victim

---------------- Security boundary

Way 2 ─── Untrusted
Way 3 ─── Untrusted


-----------------------------------------------------

