# Private Aggregation W3C Call: Agenda & Notes

Wednesday 15 February 2023 at 4 pm Eastern Time (= 9 pm UTC = 10 pm Paris = 1 pm California).

This notes doc will be editable during the meeting — if you can only comment, hit reload.

Notes will be made available on [GitHub](https://github.com/patcg-individual-drafts/private-aggregation-api) after the meeting.

Additional meetings will be made on an ad hoc basis.

## Agenda

#### Process reminder: Join PATCG and sign in

If you want to participate in the call, please make sure you join the PATCG: <https://www.w3.org/community/patcg/> and add yourself to the attendees list below.

### [Suggest agenda items here]

* Intro to Shared Storage and Private Aggregation
  * What’s possible with Reach in the current design
* Importance of cross-device Reach
  * Supporting statistical methods/adjustments
* Scope of dynamic flexibility
* Issue [#17](https://github.com/patcg-individual-drafts/private-aggregation-api/issues/17): Extending shared storage API to support advanced reach reporting
* Fledge + PAA:

    Can we expect that Private Aggregation API will be available for Fledge on GA (H3’23)?

### Note takers

Zach Mastromatto

### Notes

* Intro to Shared Storage and Private Aggregation - What’s possible with Reach in the current design
  * Shared Storage provides unrestricted write access across sites
  * Companies can use relevant Shared Storage data to aggregate data and return noisy summary reports
  * You can use Shared Storage data to create an aggregation key, send that to your server, then batch them together and send to Aggregation Service to decrypt, add noise, and return an aggregated summary reports
  * Q: How does data delineation look?
    * A: Each adtech will have its own Shared Storage context to read and write from
  * Reach is one of the use cases that Shared Storage is built to support
    * When an unique ad is served to a new user, you can write to Shared Storage that this new user was reached by an ad that was served (frequency =1)
    * Each new user view can then be aggregated and sent in the Private Aggregation flow to aggregate and return a noised summary report from the Aggregation Service
    * How does the batching of these reports work?
      * When a report is sent for batching, it can’t be reprocessed again
      * It is important to write the date/date range then when you write to Shared Storage
    * Q: Is Shared Storage available in incognito mode?
      * A: Unclear at the moment, will need to follow up. You would consider it as a separate bucket though if it is enabled. You can still write to it if it is Incognito, but all of the data would be cleared when the browser is closed.
    * Q: If I setup a weekly reach report, than, I can't send a daily report?
      * No, you would only be able to process data in one of the reports
    * Q: This is browser counting, and not deduplicated right?
      * A: Yes, and we are interested if there are other reach models that are dependent on an extension of that deduplication
    * Q: What use case does this solution map to? What value do advertisers get from doing this specifically within the browser? (from Meta)
      * A: From Google Ads’ perspective, broadly speaking, Reach is pretty established and is an important solution that Google Ads provides in-market. By extending the API just a little bit further can significantly improve the utility from the API. Details are in the GitHub issue that Google Ads wrote.
      * A: From Chrome perspective, is it possible to get per-browser estimates and are there any adjustments that take place after the fact to make Reach closer to a person-based calculation vs browser-based calculation. Our question is when that needs to happen?
      * A: It is unclear if you move the matching to off-device vs on-device (Meta)
    * Q: Would you be able to dedupe users across devices? (Amazon)
      * A: Cross-device is an interesting question in this context. This seems to be in the context of deduping the browser to an actual person. The challenge for Chrome is figuring out the right way to do this with user privacy in mind. We want to be confident from a statistical perspective on where the inflection point is for knowing that a reached impression is a new person or not. This is probably worth a deeper dive in a later discussion.
    * We need as much data flexibility as we can in a dynamic environment (weekly, monthly, mid-campaign flight, etc). (Amazon)
    * Q: Why are there limitations on processing data multiple times in batches?
      * A: To limit the amount of information that is available on users. Also to restrict averaging out the noise if you process the data multiple times. Theoretically you can add more noise in if you reprocess it each time to alleviate this, but it adds more complexity for engineering and for users.
    * Raimundo: The important thing on the first question is what is the unique thing that you are counting, more so than where you are doing the counting?
    * Wendell: Proposing that Chrome simplifies this solution. Investing in testing costs money both from the advertiser and adtech. Suggests that simplification here would make it easier to test and build a business around. Noise being added is tough to manage and it has to behave the same way across long periods of time.
    * Thomas: Counting devices is really the most important thing, as that is correlated most to a person. Counting users is supposed to be the secret sauce of an adtech to do this. Does not think it is Chrome’s responsibility to provide a device graph for users. It is key to have an integration between Android and Chrome.
      * Q: Is there a strong sense that apps and browsers should talk to each other? Or multiple browsers on the same device? Can you elaborate what you mean by a unique device? It is not a question of multiple browsers, but across app and web?
      * A: Device as defined by a physical device. Across both app and web, yes.
    * Q: iFrames and Fenced Frames are fully supported, so Shared Storage should be available everywhere?
      * A: Yes, but Chrome wants to double check the Fenced Frames piece and get back to you.
    * Evgeny: We (Google Ads) are asking for a level of privacy protection from Privacy Sandbox, then enabling engineering on top of that to create a reach metric. Chrome should not provide an identity layer. The blocking of processing batches multiple times that needs to be removed is an example of an area that can improve Reach calculations without sacrificing privacy.
    * Raimundo: Two challenges we need to solve for Reach. 1) How do you count for people not reach (flexibility) and 2) across all data sources and devices. We already count unique people and we need to be able to deduplicate across all devices, not even just browser. How do you bring in unique counts from devices that do not have Privacy Sandbox enabled?
    * Vishal: Reach measurement is very foundational and core to Brand advertisers around the world. We are more than welcome to bring those advertisers in for feedback if Chrome wishes. This is a core metric used to measure across all of TV and digital.
    * Jukka: It sounds like we would need a unique identifier across all platforms and media for a single person. When we talk about counting we’re talking really about estimating. We can deal with a world where browser and app usage on the same device is separate. We use panels for modeling purposes. Not accurate at a per-person level, but can be done in aggregate. Reach is what advertisers want the most and want it automatically without much hassle. They also care about privacy though too. We need to make this solution workable for both.
      * Asha: It is probably not possible to make a universal identity, so we need to support adtechs in facilitating the estimation counts after the fact.
    * Sanjay: The amount of utility for an advertiser decreases when the fidelity of the signal decreases. This isn’t on Chrome to uniquely solve though for all adtechs across all devices. The industry needs to come to a consensus on the signals that are important for Reach and the privacy guardrails. This is true for all browsers, not just Chrome.
    * Evgeny: Allowing count(distinct) would unlock the ability to do modeling and increase flexibility on one or two orders of magnitude over what is possible now. It unlocks a key toolbox of modelling.
    * Alex: Just want to flag that we have a lot to talk about and need more stakeholders in the room, per Vishal. Chrome would like more attendance in these meetings and encourage follow up meetings and sharing.
    * Asha: Are adtechs used to having standard dimensions for reporting or does it need to be very flexible across any dimension?
      * Evgeny: Flexibility across the board is important, date is important. It is important for Reach to be flexible, which is what we hear from our customers. Trying to list the important metrics might not lead to success here, but rather enabling the flexibility for adtechs to decide for themselves.
    * Michal: We plan to use PAA together with FLEDGE. Some of these reports need to be processed daily vs other types of reporting. And the batching frequency needs to be variable. From our perspective, it would be good to have the ability to reprocess the data or to batch data in a way that is not just based on a specific date range.
    * Bo: Strongly agree that dimensions should be fully flexible, instead of picking the specific dimensions to be flexible on. Timezone issues are a concern too. In order for the ecosystem to test the data sent back, we need to gain some confidence in the underlying data. Without that we can’t be confident in using it.
    * Jukka: Exact timestamp is not as important to Comscore. Exact time is less important than other dimensions.
* Importance of cross-device Reach
  * Supporting statistical methods/adjustments
* Scope of dynamic flexibility
* Issue [#17](https://github.com/patcg-individual-drafts/private-aggregation-api/issues/17): Extending shared storage API to support advanced reach reporting
* Fledge + PAA:

    Can we expect that Private Aggregation API will be available for Fledge on GA (H3’23)?

### To join the speaker queue

Please use the "Raise My Hand" feature in Google Meet

### Attendees: please sign yourself in

1. Wendell Baker (Yahoo)
2. David Dabbs (Epsilon)
3. Alex Turner (Google Chrome)
4. Anish Ahmed (Google, Privacy Sandbox)
5. Asha Menon (Google Chrome)
6. Vishal Radhakrishnan (Google Ads - Cross-Media Measurement )
7. Sid Sahoo (Google Chrome)
8. Robert Kubis (Google Chrome)
9. Renan Feldman (Google Chrome)
10. Maybelline Boon (Google Chrome)
11. Christina Ilvento (Google Chrome)
12. Bo Xiong (Amazon Ads)
13. Hannah Chang (Google)
14. Thomas Prieur (Criteo)
15. Craig Wright (Google Ads)
16. (RTB House)
17. Jonathan Frederic (Google Ads)
18. Chris McAndrew (Google Ads - Measurement)
19. Evgeny Skvortsov(Google Ads)
20. Michael Perry (Amazon)
21. Michael Kleber (Google Chrome)
22. Nan Li (Amazon)
23. Zach Mastromatto (Google Chrome)
24. Jonas Schulte (Amazon Ads)
25. Gaurav Bajaj (Amazon Ads)
26. Anatolii Bed (Amazon Ads)
27. Sanjay Saravanan (Meta)
28. Jukka Ranta (ComScore)
29. Ruchi Lohani (Google, Privacy Sandbox)
30. Martin Pal (Google Privacy Sandbox)
31. Kuang Yi Chen (Amazon)

**Cursor Parking**

**🚗🚗🚗🚗🚗🚗**
