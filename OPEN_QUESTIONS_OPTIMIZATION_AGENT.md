Open Questions: Optimization Agent

Logged for later review and sanitization. Not yet answered or validated with the team.

1. GAM Reporting API data has a processing delay of a few hours. How fresh does data need to be for the agent to act on it.

2. The pacing signal (expected versus actual delivery percentage) comes from LineItemService, not the Reporting API. That means two separate data pulls need to be joined by line item ID. Who owns building that second sync.

3. Portfolio benchmarks (median CPM, CTR, fill rate, viewability) can be calculated across the whole account, per advertiser, per line item type, or per vertical. Which grouping is the right comparison basis.

4. Viewability and video quartile metrics only apply to certain inventory types. Should the agent skip those checks for display only line items, or always include them and mark as not applicable.

5. How many days of history should feed pacing and trend calculations. Current build uses 7 day and 30 day windows. Does that match real flight lengths in production, especially short flights.

6. What exact thresholds should trigger Needs Attention versus At Risk. Current thresholds are reasonable defaults, not yet validated against business risk tolerance.

7. Which change types should the agent be allowed to propose. Targeting changes feel lower risk than budget or priority changes. Should scope be restricted at first.

8. Who approves a proposed change. The account executive, ad ops, or yield manager, and does that vary by advertiser size or deal value.
