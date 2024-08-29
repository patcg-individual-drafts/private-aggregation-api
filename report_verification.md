# Preventing invalid Private Aggregation API reports with report verification

### Table of Contents

- [Background](#background)
- [Security goals](#security-goals)
  - [Existing threat practicality](#existing-threat-practicality)
- [Shared Storage](#shared-storage)
  - [Details](#details)
    - [Deterministic number of reports](#deterministic-number-of-reports)
    - [Allows retrospective filtering](#allows-retrospective-filtering)
    - [Security considerations](#security-considerations)
    - [Privacy considerations](#privacy-considerations)
    - [Reduced delay](#reduced-delay)
- [FLEDGE sellers](#fledge-sellers)
  - [Details](#details-1)
    - [Privacy considerations](#privacy-considerations-1)
- [FLEDGE bidders](#fledge-bidders)
  - [Details](#details-2)
    - [New network requests](#new-network-requests)
    - [Need to list all possible token issuers](#need-to-list-all-possible-token-issuers)
    - [Need to limit the list of token issuers](#need-to-limit-the-list-of-token-issuers)
    - [Allocating returned tokens](#allocating-returned-tokens)
    - [Delegating token issuance](#delegating-token-issuance)
      - [Ensuring delegation consistency](#ensuring-delegation-consistency)
    - [Issuance mechanism](#issuance-mechanism)
    - [Redemption mechanism](#redemption-mechanism)
    - [Security considerations](#security-considerations-1)
    - [Privacy considerations](#privacy-considerations-2)
      - [Partitioning can amplify counting attacks](#partitioning-can-amplify-counting-attacks)
      - [Initial design](#initial-design)
      - [Potential mitigations](#potential-mitigations)
  - [Alternatives considered](#alternatives-considered)
    - [Using signals from interest group joining time](#using-signals-from-interest-group-joining-time)
      - [New network request](#new-network-request)
      - [Different security model](#different-security-model)
      - [Difficult to decide on number of tokens to issue](#difficult-to-decide-on-number-of-tokens-to-issue)
      - [Requires new persistent token storage](#requires-new-persistent-token-storage)
    - [Using signals from both auction running time and interest group joining time](#using-signals-from-both-auction-running-time-and-interest-group-joining-time)
      - [Separate token headers/fields](#separate-token-headersfields)
      - [Each origin picks one option](#each-origin-picks-one-option)
      - [One mechanism preferred, the other a fallback](#one-mechanism-preferred-the-other-a-fallback)
    - [Specifying a contextual ID and each possible IG owner](#specifying-a-contextual-id-and-each-possible-ig-owner)
    - [Trusted server report verification](#trusted-server-report-verification)
- [Shared Storage in Fenced Frames](#shared-storage-in-fenced-frames)
  - [Details](#details-3)
    - [Doesn’t support nesting](#doesnt-support-nesting)
    - [Privacy considerations](#privacy-considerations-3)
  - [Extending to selectURL()](#extending-to-selecturl)

## Background

This document proposes a set of API changes to enhance the security of the
aggregatable reports by making it more difficult for bad actors to interfere
with the accuracy of cross-site measurement. Note that a mechanism based on the
[Private State Tokens API](https://github.com/WICG/trust-token-api) has been
[proposed](https://github.com/WICG/attribution-reporting-api/blob/main/report_verification.md)
for the Attribution Reporting API.

The proposal is separated by the different contexts the Private Aggregation API
can be invoked in as the constraints and designs differ substantially.

## Security goals

Our security goals match the Attribution Reporting proposal’s, see
[here](https://github.com/WICG/attribution-reporting-api/blob/main/report_verification.md#security-goals)
for details. Briefly, our primary security goals are:

1. No reports out of thin air
2. No replaying reports

We also share the secondary goals:

3. Privacy of the invalid traffic (IVT) detector
4. Limit the attack scope for bad actors that can bypass IVT detectors
5. No report mutation (lower priority)

### Existing threat practicality

As with the Attribution Reporting API, we don’t currently prevent reports being
created out of thin air, but practical attacks are challenging. More details
[here](https://github.com/WICG/attribution-reporting-api/blob/main/report_verification.md#existing-mitigations-and-practical-threats).

## Shared Storage

When triggering a Shared Storage operation that could send an aggregatable
report, we propose allowing the site to specify a high-entropy ID from
outside the isolated context. This ID would then be embedded unencrypted in the
report issued by that worklet operation, e.g. adding the following key to the
report:

```jsonc
"context_id" : "example_string",
```

This would be achieved by adding a new optional parameter to the Shared Storage
`run()` and `selectURL()` APIs, e.g.:

```js
sharedStorage.run('someOperation', {'privateAggregationConfig': {'contextId': 'example_string'}});
```

Note that this design does not support report verification for Shared Storage
operations run from within a fenced frame. See
[below](#shared-storage-in-fenced-frames) for a discussion of that case.

An approach based on Private State Tokens was not proposed as it would add
complexity and offer strictly less power than ID-based filtering for invalid
traffic filtering.

### Details

#### Deterministic number of reports

One key concern with this approach is that the number of reports (with that ID)
could be used to exfiltrate cross-site information. So, when an ID is specified
for a Shared Storage operation, we ensure that a single report is sent no matter
how many calls to `sendHistogramReport()` occur (including zero). Instead, this
report would have a variable number of contributions embedded (see [batching
proposal](https://github.com/patcg-individual-drafts/private-aggregation-api#reducing-volume-by-batching)).
To avoid leaking the number of contributions, we will need to
[pad](https://github.com/patcg-individual-drafts/private-aggregation-api#padding)
the encrypted payload. Additionally, if a context has run out of budget, a
report should still be sent (containing no contributions).

#### Allows retrospective filtering

This approach allows for a server to retroactively alter its decisions on report
validity. For example, if a new signal for invalid traffic is determined,
previous reports with that signal could be marked as invalid too (if they have
not yet been processed).

#### Security considerations

This option easily achieves all of the higher priority security goals

- **No reports out of thin air**: Any report without an ID, or with an
  unexpected ID, can be discarded as invalid. These IDs are high-entropy and so
  can be made infeasible to guess.
- **No replaying reports**: Each ID can be unique, allowing discarding of
  reports with a repeated ID.
- **Privacy of the invalid traffic (IVT) detector**: The valid/invalid decision
  associated with an ID can be made server-side and need not be revealed to the
  client. In fact, the decision need not happen immediately, see [Allows
  retrospective filtering](#allows-retrospective-filtering).
- **Limit the attack scope for bad actors that can bypass IVT detectors**: By
  using a unique ID, server-side checks could be added to ensure that the
  metadata fields in the report match the expected values.
- **No report mutation**: Only partially addressed. The server can verify that
  plaintext fields in the report “reasonably match” their expectations. This
  does not prevent mutation of the payload or fields that could have multiple
  reasonable values (e.g. small changes to scheduled\_report\_time).

#### Privacy considerations

Adding a high-entropy ID may allow for timing attacks. E.g. if a report is not
issued until after a Shared Storage operation completes, the reporting origin
could in principle use the scheduled reporting time to learn something about how
long the operation took to run. This is currently mitigated by a randomized
delay, but we also plan to add a timeout in Shared Storage, see [Reduced
delay](#reduced-delay) below.

Adding a high-entropy ID also allows for the reports to be arbitrarily
partitioned. However, by making the count of reports with the given ID
[deterministic](#deterministic-number-of-reports), we avoid the [major concern
this introduces](https://github.com/WICG/attribution-reporting-api/blob/main/report_verification.md#could-we-just-tag-reports-with-a-trigger_id-instead-of-using-anonymous-tokens)
(non-noisy leaks through counts). We do not consider the ability to process only
a chosen subset of reports to be a privacy concern, given other protections
(e.g. adding noise to the summary report).

#### Reduced delay

Currently, reports are delayed by up to one hour to avoid revealing an
association between the issued reports and the original context. As this
approach explicitly reveals this association (with other mitigations), we can
shorten these delays. We plan to impose a 5 second timeout on Shared Storage
operations making contributions. We then plan to wait until the timeout to
send a report, even if execution finishes early. This avoids leaking
information through how long the operation took to run. We also considered
instead keeping a shorter randomized delay (e.g. up to 1 minute), but that
did not seem necessary.

## FLEDGE sellers

We propose a very similar mechanism for FLEDGE seller reporting as for Shared
Storage worklets. That is, we’ll allow the site to specify a high-entropy
ID from outside the isolated context and this ID would then be embedded
unencrypted in the report issued by that seller within that auction, e.g.:

```jsonc
"context_id" : "example_string",
```

The seller would specify this ID through an optional parameter into the
`auctionConfig`, e.g.:

```js
const myAuctionConfig = {
  ...
  'privateAggregationConfig': {
    'contextId': 'example_string',
  }
};
const auctionResultPromise = navigator.runAdAuction(myAuctionConfig);
```

### Details

See the [Shared Storage section](#shared-storage) for more details.

#### Privacy considerations

Like for shared storage, adding a high-entropy ID could allow for timing attacks
as the reporting origin could use the scheduled reporting time to learn
something about when the report was triggered. This is partially mitigated by
the existing randomized reporting delay (10-60 min) imposed as FLEDGE auctions
impose small timeouts (e.g. 0.5 s). As discussed
[above](#privacy-considerations) for Shared Storage, we avoid concerns about
partitioning by making the number of reports deterministic (and other
protections).

## FLEDGE bidders

**Note: Unlike the above sections which offer relatively straightforward approaches,
this section is highly complex and nuanced. Feedback is appreciated!**

We can’t easily use a contextual ID for the FLEDGE bidder case as the existence
of a bidder in a particular auction is inherently cross-site data, see
[below](#specifying-a-contextual-id-and-each-possible-ig-owner). So, our options
are more limited and we focus on mechanisms using Private State Tokens.

However, note also that there are no existing network requests that we can easily reuse
for token issuance. While there is a trusted signals fetch, that is
intentionally uncredentialed. Much like using an ID, we can’t just add a network
request for each bidder as that would reveal cross-site data.

So, we handle token issuance by adding a new optional parameter to
`runAdAuction()`, e.g.:

```js
const myAuctionConfig = {
  ...
  'privateAggregationConfig': {
    ...
    'tokenIssuanceURLs': [
      'https://origin1.example/path?signal1=abc,signal2=def',
      'https://origin2.example/some-other-path',
      'https://origin3.example/etc',
    ],
    // How many tokens to request from each listed issuer. Optional, defaults to
    // each issuer's batch size.
    'numTokensPerIssuer': 10,
  }
}
const auctionResultPromise = navigator.runAdAuction(myAuctionConfig);
```

This would trigger a token issuance request for each listed origin (see
[below](#issuance-mechanism)). Each token would be redeemed along with any later
reports’ network requests (see [below](#redemption-mechanism)).

If this token successfully verifies, then the reporting origin has a guarantee
that the report was associated with a `runAdAuction()` request that was signed.

### Details

#### New network requests

This requires the addition of a new network request for each listed token issuer,
emitted when `runAdAuction` is invoked.

#### Need to list all possible token issuers

As the presence of bidders in an auction is inherently cross-site, we require
listing all possible token issuers from the publisher site. The user agent will
then unconditionally perform a token issuance request for each listed token
issuer to avoid cross-site leakage, i.e. even if the issuer is not used by any
bidder in the auction.

#### Need to limit the list of token issuers

The user agent will also need to impose a limit on the number of token issuers
listed in each auction to avoid too many network requests being added.
Practically, this means interest group owners will likely need to use the
[delegation mechanism](#delegating-token-issuance).

#### Allocating returned tokens

A single bidder origin may own multiple interest groups that a user is enrolled
in. Additionally, multiple interest group owner origins may use the same token
issuer (due to [delegation](#delegating-token-issuance)). In these cases, the
interest groups will have to share the tokens issued.

In the case of multiple owner origins using the same token issuer, tokens can’t
be reused as we don’t want to reveal that both interest group owners were
present in the same auction (for the same user). However, multiple tokens can be
requested from a single token issuer to mitigate this. If not enough tokens were
issued, some reports will be sent unattested.

In the case of multiple interest groups with the same owner, the histogram
contributions should be
[batched](https://github.com/patcg-individual-drafts/private-aggregation-api#reducing-volume-by-batching)
together into a single report, avoiding the need to use multiple tokens.
However, the [extended reporting
plans](https://github.com/WICG/turtledove/blob/main/FLEDGE_extended_PA_reporting.md)
for Private Aggregation allow for fenced frames to trigger reports indirectly
with `window.fence.reportPrivateAggregationEvent()`. This could occur
arbitrarily later, so we may need to ignore events triggered too long after the
auction (e.g. after 1 hour). We could consider replacing the randomized delay
with simply waiting until the timeout, even if execution finishes early.

#### Delegating token issuance

Interest group owners will be able to delegate their token issuance by hosting a
`.well-known` file which specifies the origin to delegate to. This will be
optional (i.e. each origin can choose itself as its token issuer), but note that
all origins choosing themselves would likely exceed limits, see [Need to limit
the list of token issuers](#need-to-limit-the-list-of-token-issuers) above.

##### Ensuring delegation consistency

To ensure that the same file is served across different browser instances, the
user agent vendor may re-distribute these files through a separate mechanism.
Further, to ensure that the origin does not change frequently, the user agent
could impose some limits on the rotation frequency.

#### Issuance mechanism

Token issuance network requests will be sent to the specified token issuer URLs.
The URL path and query string allows for metadata to be embedded by the seller,
but note that only the token issuance _origin_ is used for
[delegation](#delegating-token-issuance). Each request will have a
`Sec-Private-Aggregation-Private-State-Token` header with one or more blinded
messages (each of which embeds a report\_id) according to the number of tokens
requested. If the number of tokens is not requested, the token issuer’s [batch
size](https://source.chromium.org/chromium/chromium/src/+/main:services/network/public/mojom/trust_tokens.mojom;drc=96d76471a47949536f88e90cbf03596cda41f6e1;l=232)
will be used. The token issuer will inspect the request and decide whether it is
valid, i.e. whether the issuer suspects it is coming from a real, honest client
and should therefore be allowed to generate aggregatable reports.

If the request is considered **invalid** and hence shouldn’t be taken into
account to calculate aggregate measurement results, the origin should respond
without adding a `Sec-Private-Aggregation-Private-State-Token` response header.
If this header is omitted or is not valid, the browser will proceed normally,
but any report generated will not contain the report verification header. Note:
more advanced deployments can consider issuing an "invalid" token using private
metadata to avoid the client learning the detection result. See privacy of the
IVT detector in [Security considerations](#security-considerations-1) for more
details.

If the request is considered **valid**, the origin should add a
`Sec-Private-Aggregation-Private-State-Token` header with a blind token (the
blind signature over the blinded message) for each blinded message included in
the original request. The origin could also return a token for only a subset of
the blinded messages if it wishes to limit the number of tokens issued to limit
exfiltration risk.

Internally, the browser will store the token associated with any generated
report until it is sent.

#### Redemption mechanism

If a token is [allocated](#allocating-returned-tokens) to an aggregatable
report, it will be sent along with the report’s request in the form of a new
request header `Sec-Private-Aggregation-Private-State-Token`. If this token is
successfully verified, then the reporting origin has a guarantee that the report
was associated with a previous request that was signed.

Note: unlike the basic Private State Token API (which enables conveying tokens
from one site to another), there are no redemption limits for Private
Aggregation API integration. See [Privacy
considerations](#privacy-considerations-2) for discussion of other mitigations.

#### Security considerations

This option easily achieves the primary security goals plus some secondary
security goals. The considerations largely match the Attribution Reporting
proposal’s given the similar token-based approach, see
[here](https://github.com/WICG/attribution-reporting-api/blob/main/report_verification.md#security-considerations)
for details.

#### Privacy considerations

Much like Attribution Reporting’s
[proposal](https://github.com/WICG/attribution-reporting-api/blob/main/report_verification.md#privacy-considerations),
this integration is intended to be as privacy-neutral as possible. In
particular, we want to avoid cross-site information leakage. While each token’s
issuance occurs using a request from a single site, this token – including its
metadata, or no token if none was issued – will later be sent with a report from
a bidder. The identity of which bidders participated in an auction is cross-site
data.

##### Partitioning can amplify counting attacks

If the count of reports is sensitive, this partitioning could amplify counting
attacks. However, note that reports can already be partitioned by the
`scheduled_report_time` and `api` fields. There are designs for [protecting the
count of encrypted reports](https://github.com/WICG/attribution-reporting-api/blob/main/AGGREGATE.md#hide-the-true-number-of-attribution-reports)
to mitigate or eliminate the risk of counting attacks. These designs target the
Attribution Reporting API, but could be adapted for Private Aggregation. Still,
with less extreme mitigations, there are privacy benefits to reducing the
partitioning available.

##### Initial design

For the initial design, we do not plan to implement any changes to the Private
State Token protocol’s public/private metadata bits. So, each token will have
[six buckets](https://github.com/WICG/trust-token-api/blob/main/ISSUER_PROTOCOL.md#issuance-metadata)
of metadata embedded. Further, each report could either have a token or no
token, allowing up to 7 total possibilities (~2.8 bits). This would therefore
allow the reporting origin to partition its reports into 7 buckets.

##### Potential mitigations

We could consider mitigations in the future. For example:

- restricting the public/private metadata to one bucket – or just a single
  private bit to avoid an invalid traffic oracle.
- refusing to send reports to reporting origins using report verification if no
  token was available/issued.
- sending null reports with some frequency for buyers that delegate to an issuer
  who issued tokens.

### Alternatives considered

#### Using signals from interest group joining time

Alternatively, we could associate any trust signals available at the
`joinAdInterestGroup()` call with reports later sent from a bidder under that
interest group.

Token issuance could be handled by adding a new optional parameter to
`joinAdInterestGroup()`, e.g.:

```js
const myGroup = {
  ...
  'privateAggregationTokens': 10,  // number of tokens to request
}
const joinPromise = navigator.joinAdInterestGroup(myGroup, 30 * kSecsPerDay);
```

This would trigger a token issuance request (see [above](#issuance-mechanism))
with the requested number of blinded messages. Each resulting token would be
redeemed along with the later report’s network request (see
[above](#redemption-mechanism)).

If the token successfully verifies, then the reporting origin has a guarantee
that the report was associated with a previous `joinAdInterestGroup()` request
that was signed.

##### New network request

This requires the addition of one new network request at `joinAdInterestGroup()`
time.

##### Different security model

This approach uses a different security model to Attribution Reporting’s, with a
potentially large time delay between token issuance and use.

##### Difficult to decide on number of tokens to issue

Due to this large time delay between token issuance and last possible use, it
will be difficult to decide on the number of tokens to issue. If too few are
issued, later auctions may not be able to be attested. Issuing too many may
degrade performance, e.g. unnecessarily using storage, and may exacerbate token
exfiltration attacks.

##### Requires new persistent token storage

This approach requires Private State Tokens to be persisted for later use. This
store will need to be separate from the existing Private State Token store. Note
also that key rotations will cause issues here, as any tokens issued before the
rotation would not be able to be used after the rotation.

#### Using signals from both auction running time and interest group joining time

We could combine the functionality of both the proposal and the above
alternative. There are a few different ways we could do this.

##### Separate token headers/fields

We could allow for both mechanisms to be independently implemented. Separate
headers could be used to distinguish between the two. This would allow for
maximum flexibility, but comes at a possible complexity and privacy cost.

**Privacy risk:** By supporting two separate token fields, the number of
possible token states is ‘squared’. That is, without additional mitigations,
adding a second Private State Token field would increase the number of states
from 7 to 49 (~5.6 bits). This partitioning would allow for amplified counting
attacks unless other mitigates are put in place, see
[above](#privacy-considerations-2).

##### Each origin picks one option

We could allow each origin to pick one of the two mechanisms, using a similar
mechanism to picking a token issuer. Any attempt to use the other mechanism
would be ignored or cause an error.

##### One mechanism preferred, the other a fallback

We could allow for both mechanisms, but only allow one token to be bound to each
report. If a token is available via each mechanism, the browser will prefer one
(e.g. the runAdAuction() associated token).

#### Specifying a contextual ID and each possible IG owner

Instead of using Private State Tokens, we could also use a contextual ID here.
But, to avoid a cross-site leak, this would require that a report be sent to
each origin listed in `interestGroupBuyers`, even if that bidder did not
actually participate in the auction. This could lead to a large number of (null)
reports, which would pose a performance concern.

#### Trusted server report verification

Ideally for performance, the user agent would be able to only request a token
for reports that are actually going to be sent. But, that would inherently leak
cross-site data, which we can't allow. But it might be possible to design a
trusted server architecture that can perform the required invalid traffic
determination and token issuance while ensuring that any cross-site data is not
persisted. This is not feasible in the short term, however, requiring
significant design and exploration.

## Shared Storage in Fenced Frames

When a shared storage operation is run from a fenced frame instead of a
document, we can no longer set a contextual ID. Any cross-site information the
fenced frame has could be embedded in the context ID, so the ability to set it
is disabled.

Instead, we propose allowing a Private State Token to be bound to the
FencedFrameConfig output of a FLEDGE auction. We would reuse the FLEDGE bidder
mechanism chosen [above](#fledge-bidders) and take an additional token from the
same source for this purpose. When the shared storage worklet triggers a report
to be sent, any context ID specified would be ignored and the token would be
used instead.

### Details

As it uses the same token source, most details match the FLEDGE bidder
discussion (see [above](#details-2)). Additional considerations are listed
below.

#### Doesn’t support nesting

This proposal does not currently support cross-origin subframes or nested fenced frames
within the top-level fenced frame.

#### Privacy considerations

As discussed [above](#privacy-considerations-2), adding a token allows reports
to be partitioned, which exacerbates the risk of a counting attack.

This design also implicitly reveals whether a Shared Storage worklet’s
aggregatable report came from an operation run by a document or a fenced frame.
This may allow for further partitioning, but is unlikely to be a significant
issue.

### Extending to selectURL()

Further design work is needed to extend this mechanism to fenced frames
rendering the output of a `selectURL()` operation.
