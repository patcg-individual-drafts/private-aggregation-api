**This document is an individual draft proposal. It has not been adopted by the Private Advertising Technology Community Group.**

-------

# Private Aggregation API explainer

Author: Alex Turner (alexmt@chromium.org)

### Table of Contents

- [Introduction](#introduction)
- [Examples](#examples)
  - [Protected Audience reporting](#protected-audience-reporting)
  - [Measuring user demographics with cross-site information](#measuring-user-demographics-with-cross-site-information)
- [Goals](#goals)
  - [Non-goals](#non-goals)
- [Operations](#operations)
- [Reports](#reports)
  - [Temporary debugging mechanism](#temporary-debugging-mechanism)
    - [Enabling](#enabling)
    - [Debug keys](#debug-keys)
    - [Duplicate debug report](#duplicate-debug-report)
  - [Reducing volume by batching](#reducing-volume-by-batching)
    - [Batching scope](#batching-scope)
    - [Contributions limit](#contributions-limit)
    - [Padding](#padding)
- [Privacy and security](#privacy-and-security)
  - [Metadata readable by the reporting origin](#metadata-readable-by-the-reporting-origin)
    - [Open question: what metadata to allow](#open-question-what-metadata-to-allow)
  - [Contribution bounding and budgeting](#contribution-bounding-and-budgeting)
    - [Scaling values](#scaling-values)
    - [Examples](#examples-1)
    - [Partition choice](#partition-choice)
- [Future Iterations](#future-iterations)
  - [Supporting different aggregation services](#supporting-different-aggregation-services)
  - [Shared contribution budget](#shared-contribution-budget)
  - [Authentication and data integrity](#authentication-and-data-integrity)
  - [Aggregate error reporting](#aggregate-error-reporting)

## Introduction

This proposal introduces a generic mechanism for measuring aggregate, cross-site
data in a privacy preserving manner.

Browsers are now working to prevent cross-site user tracking, including by
[partitioning storage and removing third-party
cookies](https://blog.chromium.org/2020/01/building-more-private-web-path-towards.html).
There are a range of API proposals to continue supporting legitimate use cases
in a way that respects user privacy. Many of these proposals, including [Shared
Storage](https://github.com/WICG/shared-storage) and [Protected
Audience](https://github.com/WICG/turtledove), plan to isolate potentially
identifying cross-site data in special contexts, which ensures that the data
cannot escape the user agent.

Relative to cross-site data from an individual user, aggregate data about groups
of users can be less sensitive and yet would be sufficient for a wide range of
use cases. An [aggregation
service](https://github.com/WICG/conversion-measurement-api/blob/main/AGGREGATION_SERVICE_TEE.md)
has been proposed to allow reporting noisy, aggregated cross-site data. This
service was originally proposed for use by the [Attribution Reporting
API](https://github.com/WICG/conversion-measurement-api/blob/main/AGGREGATE.md),
but allowing more general aggregation would support additional use cases. In
particular, the [Protected Audience](https://github.com/WICG/turtledove)
and [Shared Storage](https://github.com/WICG/shared-storage)
proposals expect this functionality to become available.

So, to complement the Attribution Reporting API, we propose a general-purpose
Private Aggregation API that can be called from a wide array of contexts,
including isolated contexts that have access to cross-site data (such as a
shared storage worklet). Within these contexts, potentially identifying data
could be encapsulated into "aggregatable reports". To prevent leakage, the
cross-site data in these reports would be encrypted to ensure it can only be
processed by the aggregation service. During processing, this service will add
noise and impose limits on how many queries can be performed.

This API introduces a `sendHistogramReport()` function; see
[examples](#examples) below. This call constructs an aggregatable report, which
contains an encrypted payload for later computation via the aggregation service.
The API queues the constructed report to be sent to the reporting endpoint of
the script's origin (in other words, the reporting origin) after a delay. The
report format and endpoint paths are detailed [below](#reports).
After the endpoint receives the reports, it batches the reports and sends them
to the aggregation service for processing. The output of that process is a
summary report containing the (approximate) result, which is dispatched back to
the reporting origin.

## Examples

### Protected Audience reporting

The [Protected
Audience](https://github.com/WICG/turtledove/blob/main/FLEDGE.md#5-event-level-reporting-for-now)
API plans to run on-device ad
auctions using cross-site data as an input. The Private Aggregation API will
allow measurement of the auction results from within the isolated execution
environments.

For example, a key measurement use case is to report the price of the auctions'
winning bids. This tells the seller how much they should be paid and who should
pay them. To support this, each seller's JavaScript could define a
`reportResult()` function. For example:

```javascript
function reportResult(auctionConfig, browserSignals) {
  // Helper functions that map each buyer to its predetermined bucket and scales
  // each bid appropriately for measurement, see scaling values below.
  function convertBuyerToBucketId(buyer_origin) { … }
  function convertBidToReportingValue(winning_bid_price) { … }

  // The user agent sends the report to the reporting endpoint of the script's
  // origin (that is, the caller of `runAdAuction()`) after a delay.
  privateAggregation.sendHistogramReport({
    // Note: the bucket must be a BigInt and the value an integer Number.
    bucket: convertBuyerToBucketId(browserSignals.interestGroupOwner),
    value: convertBidToReportingValue(browserSignals.bid)
  });
}
```

The buyer can make their own measurements, which could be used to verify the
seller's information. To support this, each buyer's JavaScript would define a
`reportWin()` function (and possibly also a `reportLoss()` function). For
example:

```javascript
function reportWin(auctionSignals, perBuyerSignals, sellerSignals, browserSignals) {
  // The buyer defines their own similar functions.
  function convertSellerToBucketId(seller_origin) { … }
  function convertBidToReportingValue(winning_bid_price) { … }

  privateAggregation.sendHistogramReport({
    bucket: convertSellerToBucketId(browserSignals.seller),
    value: convertBidToReportingValue(browserSignals.bid),
  });
}
```

### Measuring user demographics with cross-site information

`publisher.example` wants to measure the demographics of its user base, for
example, a histogram of number of users split by age ranges. `demo.example` is a
popular site that knows the demographics of its users. `publisher.example`
embeds `demo.example` as a third-party, allowing it to measure the demographics
of the overlapping users.

First, `demo.example` saves these demographics to its shared storage when it is
the top level site:

```javascript
sharedStorage.set("demo", '{"age": "40-49", ...}');
```

Then, in a `demo.example` iframe on `publisher.example`, the appropriate shared
storage operation is triggered once for each user:

```javascript
await sharedStorage.worklet.addModule("measure-demo.js");
await sharedStorage.run("send-demo-report");
```

Shared storage worklet script (i.e. `measure-demo.js`):

```javascript
class SendDemoReportOperation {
  async function run() {
    let demo_string = await sharedStorage.get("demo");
    let demo = {};
    if (demo_string) {
      demo = JSON.parse(demo_string);
    }

    // Helper function that maps each age range to its predetermined bucket, or
    // a special unknown bucket e.g. if the user has not visited `demo.example`.
    function convertAgeToBucketId(country_string_or_undefined) { … }

    // The report will be sent to `demo.example`'s reporting endpoint after a
    // delay.
    privateAggregation.sendHistogramReport({
      bucket: convertAgeToBucketId(demo["age"]);
      value: 128,  // A predetermined fixed value, see scaling values below.
    });

    // Could add more sendHistogramReport() calls to measure other demographics.
  }
}
register("send-demo-report", SendDemoReportOperation);
```

## Goals

This API aims to support a wide range of aggregation use cases, including
measurement of demographics and reach, while remaining generic and flexible. We
intend for this API to be callable in as many contexts and situations as
possible, including the isolated contexts used by other privacy-preserving API
proposals for processing cross-site data. This will help to foster continued
growth, experimentation, and rapid iteration in the web ecosystem; to support a
thriving, open web; and to prevent ossification and unnecessary rigidity.

This API also intends to avoid the privacy risks presented by unpartitioned
storage and third-party cookies. In particular, it seeks to prevent off-browser
cross-site recognition of users. Developer adoption of this API will help to
replace the usage of third-party cookies, making the web more private by
default.

### Non-goals

This API does not intend to regulate what data is allowed as an input to
aggregation. Instead, the aggregation service will protect this input by adding
noise to limit the impact of any individual's input data on the output. Learn
more about [contribution bounding and
budgeting](#contribution-bounding-and-budgeting) below.

Further, this API does not seek to prevent (probabilistic) cross-site inference
about sufficiently large groups of people. That is, learning high confidence
properties of large groups is ok as long as we can bound how much an individual
affects the aggregate measurement. See also [discussion of this non-goal in
other
settings](https://differentialprivacy.org/inference-is-not-a-privacy-violation/).

## Operations

This current design supports one operation: constructing a histogram. This
operation matches the description in the [Attribution Reporting API with
Aggregatable Reports
explainer](http://github.com/WICG/conversion-measurement-api/blob/main/AGGREGATE.md#two-party-flow),
with a fixed domain of 'buckets' that the reports contribute bounded integer
'values' to. Note that sums can be computed using the histogram operation by
contributing values to a fixed, predetermined bucket and ignoring the returned
values for all other buckets after querying.

Over time, we should be able to support additional operations by extending the
aggregation service infrastructure. For example, we could add a 'count
distinct' operation that, like the histogram operation, uses a fixed domain of
buckets, but without any values. Instead, the computed result would be
(approximately) how many _unique_ buckets the reports contributed to. Other
possible additions include supporting federated learning via privately
aggregating machine learning update vectors or extending the histogram operation
to support values that are vectors of integers rather than only scalars.

The operation would be indicated by using the appropriate JavaScript call, e.g.
`sendHistogramReport()` and `sendCountDistinctReport()` for histograms and count
distinct, respectively.

## Reports

The report, including the payload, will mirror the [structure proposed for the Attribution Reporting
API](https://github.com/WICG/conversion-measurement-api/blob/main/AGGREGATE.md#aggregatable-reports).
However, a few details will change. For example, fields with no equivalent
on this API (e.g. `attribution_destination` and `source_registration_time`)
won't be present. Additionally, the `api` field will contain either
`"protected-audience"`
or `"shared-storage"` to reflect which API's context requested the report.

The following is an example report showing the JSON format
```jsonc
{
  "shared_info": "{\"api\":\"protected-audience\",\"report_id\":\"[UUID]\",\"reporting_origin\":\"https://reporter.example\",\"scheduled_report_time\":\"[timestamp in seconds]\",\"version\":\"[api version]\"}",

  "aggregation_service_payloads": [
    {
      "payload": "[base64-encoded data]",
      "key_id": "[string]",

      // Optional debugging information if debugging is enabled
      "debug_cleartext_payload": "[base64-encoded unencrypted payload]",
    }
  ],

  // Optional debugging information if debugging is enabled and debug key specified
  "debugKey": "[64 bit unsigned integer]"
}
```

As described earlier, these reports will be sent to the reporting origin after a
delay. The URL path used for sending the reports will be
`/.well-known/private-aggregation/report-protected-audience` and
`/.well-known/private-aggregation/report-shared-storage` for reports triggered
within a Protected Audience or Shared Storage context, respectively.

### Temporary debugging mechanism

_While third-party cookies are still available_, we plan to have a temporary
mechanism available that allows for easier debugging. This mechanism involves
temporarily relaxing some privacy constraints. It will help ensure that the API
can be fully understood during roll-out and help flush out any bugs (either in
browser or caller code), and more easily compare the performance to cookie-based
alternatives.

This mechanism is similar to Attribution Reporting API's [debug aggregatable
reports](https://github.com/WICG/attribution-reporting-api/blob/main/EVENT.md#optional-extended-debugging-reports).
When the debug mode is enabled for a report, a cleartext version of the payload
will be included in the report. Additionally, the shared_info will also include
the flag `"debug_mode": "enabled"` to allow the aggregation service to support
debugging functionality on these reports.

This data will only be available in a transitional phase while third-party
cookies are available and are already capable of user tracking. The debug mode
will be disabled if third-party cookies are disabled/deprecated.

#### Enabling

The following javascript call will then enable debug mode for all future reports
requested in that context (e.g. Shared Storage operation or Protected Audience
function call):
```
privateAggregation.enableDebugMode();
```
The browser can optionally apply debug mode to reports requested earlier in that
context.

#### Debug keys
To allow sites to associate reports with the contexts that triggered them, we
also allow setting 64-bit unsigned integer debug keys. These keys are passed as
an optional field to the javascript call, for example:
```
privateAggregation.enableDebugMode({debugKey: 1234n});
```

This javascript function can only be called once per context. Any subsequent
calls will be ignored.

#### Duplicate debug report

When debug mode is enabled, an additional, duplicate debug report will be sent
immediately (i.e. without the random delay) to a separate debug endpoint. This
endpoint will use a path like
`/.well-known/debug/private-aggregation/report-protected-audience` (and the
equivalent for Shared Storage).

The debug reports should be almost identical to the normal reports, including
the additional debug fields. However, the payload ciphertext will differ due to
repeating the encryption operation and the `key_id` may differ if the previous
key had since expired or the browser randomly chose a different valid public
key.

### Reducing volume by batching

In the case of multiple calls to `sendHistogramReport()`, we can reduce report
volume by sending a single report with multiple contributions instead of
multiple reports. For this to be possible, the different calls must involve the
same reporting origin and the same API (i.e. Protected Audience or Shared
Storage).
Additionally, the calls must be made at a similar time as the reporting time
will necessarily be shared.

#### Batching scope

For calls within a Shared Storage worklet, calls within the same Shared Storage
operation should be batched together.

For calls within a Protected Audience worklet, calls using the same reporting
origin within the same auction should be batched together. This should happen
even between different interest groups or Protected Audience function calls.
However, reports triggered via `window.fence.reportEvent()` (see
[here](https://github.com/WICG/turtledove/blob/main/FLEDGE_extended_PA_reporting.md#reporting-bidding-data-associated-with-an-event-in-a-frame)
for more detail), should only be batched per-event. This avoids excessive delay
if this event is triggered substantially later.

One consideration in the short term is that these calls may have different
associated [debug modes or keys](#temporary-debugging-mechanism). In this case,
only calls sharing those details should be batched together.

#### Contributions limit

We will also need a limit on the number of contributions within a single report.
In the case that too many contributions are specified with a ‘batching scope’,
we should truncate them to the limit.

If necessary, we could instead split the contributions back into multiple
reports, each respecting the limit.

Strawman limit: 20 contributions per report.

#### Padding

The size of the encrypted payload may reveal information about the number of
contributions embedded in the aggregatable report. This can be mitigated by
padding the plaintext payload (e.g. to a fixed size).

## Privacy and security

### Metadata readable by the reporting origin

Reports will, by default, come with a variety of (unencrypted) metadata that the
reporting origin will be able to directly read. While this metadata can be
useful, we must be careful to balance the impact on privacy. Here are some
examples of metadata that could be included, along with some potential risks:

- The originally scheduled reporting time (noised within an ~hour granularity)
  - Could be used to identify users on the reporting site within a time window
  - Note that combining this with the actual timestamp the report was received
    could reveal if the user's device was offline, etc.
- The reporting origin
  - Determined by the execution context's origin, but a site could use different
    subdomains, e.g. to separate use cases.
- Which API triggered the report
  - The `api` field and the endpoint path indicates which API triggered the
    report (e.g. Protected Audience or Shared Storage).
- The API version
  - A version string used to allow future incompatible changes to the API. This
    should usually correspond to the browser version and should not change
    often.
- Encrypted payload sizes
  - If we do not carefully add padding or enforce that all reports are of the
    same natural size, this may expose some information about the contents of
    the report.
- Debugging information
  - If [debugging](#temporary-debug-mechanism) is enabled, some additional
    metadata will be provided. While this information may be potentially
    identifying, it will only be available temporarily: while third-party
    cookies are enabled.
- Developer-selected metadata
  - See [open question: what metadata to
    allow](#open-question-what-metadata-to-allow).

#### Open question: what metadata to allow

It remains an open question what metadata should be included or allowed in the
report and how that metadata could be selected or configured. Note that any
variation in the reporting endpoint (such as the URL path) would, for this
analysis, be equivalent to including the selected endpoint as additional
metadata.

While allowing a developer to specify arbitrary metadata from an isolated
context would negate the privacy goals of the API, specifying a report's
metadata from a non-isolated context (e.g. a main document) may be less
worrisome. This could improve the API's utility and flexibility. For example,
allowing this might simplify usage for a single origin using the API for
different use cases. This non-isolated metadata selection could also allow for
first-party trust signals to be associated with a report.

Alternatively, there may be ways to "noise" the metadata to achieve
differential privacy. Further study and consideration is needed here.

### Contribution bounding and budgeting

As described above, the aggregation service protects user privacy by adding
noise, aiming to have a framework that could support differential privacy.
However, simply protecting each _query_ to the aggregation service or each
_report_ sent from a user agent would be vulnerable to an adversary that repeats
queries or issues multiple reports, and combines the results. Instead, we
propose the following.

First, each user agent will limit the contribution that it could make to the
output of a query. In the case of a histogram operation, the user agent could
bound the L<sub>1</sub> norm of the _values_, i.e. the sum of all the
contributions across all buckets. The user agent could consider other bounds,
e.g. the L<sub>2</sub> norm. It remains an open question what the appropriate
'partition' is for this budgeting, see [partition choice](#partition-choice)
below. For example, there could be a separate L<sub>1</sub> 'budget' for each
origin, resetting every week. Exceeding these limits will cause future
contributions to silently drop.

Second, the server-side processing will limit the number of queries that can be
performed on reports containing the same 'shared ID' to a small number (e.g. a
single query). See
[here](https://github.com/WICG/attribution-reporting-api/blob/main/AGGREGATION_SERVICE_TEE.md#disjoint-batches)
for more detail.
This also limits the number of queries that can contain the same report. The
shared ID is a hash representing the partition. It is computed by the aggregation
service using data available in each aggregatable report. Note that the hash's
input data will need to differ from the Attribution Reporting API (e.g. to
exclude fields like the destination site that don't exist in this API).

With the above restrictions, the processing servers only need to sample the
noise for each query from a fixed distribution. In principle, this fixed noise
could be used to achieve differential privacy, e.g. by using Laplace noise with
the following parameter: (max number of queries per report) \* (max
L<sub>1</sub> per user per partition) / epsilon.

#### Scaling values

Developers will need to choose an appropriate scale for their measurements. In
other words, they will likely want to multiply their values by a fixed,
predetermined constant.

Scaling the values up, i.e. choosing a larger constant, will reduce the
_relative_ noise added by the server (as the noise has constant magnitude).
However, this will also cause the limit on the L<sub>1</sub> norm of the values
contributed to reports, i.e. the sum of all contributions across all buckets, to
be reached faster. Recall that no more reports can be sent after depleting the
budget.

Scaling the values down, i.e. choosing a smaller constant, will increase the
relative noise, but would also reduce the risk of reaching the budget limit.
Developers will have to balance these considerations to choose the appropriate
scale. The examples below explore this in more detail.

#### Examples

These examples use the L<sub>1</sub> bound of 2<sup>16</sup> = 65 536 as
proposed by the [Attribution Reporting API with Aggregatable Reports
explainer](https://github.com/WICG/conversion-measurement-api/blob/main/AGGREGATE.md#privacy-budgeting).

Let's consider a basic measurement case: a binary histogram of counts. For
example, using bucket 0 to indicate a user is a member of some group and bucket
1 to indicate they are not. Suppose that we don't want to measure anything
else and we've set up our measurement so that each user is only measured once
(per partition per time period). Then, each user could contribute their full limit
(i.e. 2<sup>16</sup>) to the appropriate bucket. After all the reports for all
users are collected, a single query would be performed and the server would add
noise (from a fixed distribution) to each bucket. We would then divide the
values by 2<sup>16</sup> to obtain a fairly precise result (with standard
deviation of 1/2<sup>16</sup> of the server's noise distribution).

If each user had instead just contributed a value of 1, we wouldn't have to
divide the query result by 2<sup>16</sup>. However, each user would end the week
with the vast majority of their budget remaining -- and the processing servers
would still add the same noise. So, our result would be much less precise (with
standard deviation equal to the server's noise distribution).

On the other hand, suppose we wanted to allow each user to report multiple times
per time period to this same binary histogram. In this case, we would have to reduce
each contribution from 2<sup>16</sup> to a lower predetermined value, say,
2<sup>12</sup>. Then, each user would be allowed to contribute up to 16 times to
the histogram. Note that you have to reduce each contribution by the _worst
case_ number of contributions per user. Otherwise, users contributing too much
will have reports dropped.

#### Partition choice

A narrow partition (e.g. giving each top-level _URL_ a separate budget) may not
sufficiently protect privacy. Unfortunately, very broad partitions (e.g. a
single budget for the browser) may allow malicious (or simply greedy) actors to
exhaust the budget, denying service to all others.

The ergonomics of the partition should also be considered. Some choices might
require coordination between different entities (e.g. different third parties on
one site) or complex delegation mechanism. Other choices would require complex
accounting; for example, requiring [Shared
storage](https://github.com/pythagoraskitty/shared-storage) to record the source
of each piece of data that could have contributed (even indirectly) to a report.

Note also that it is important to include a time component to the partition,
e.g. resetting limits periodically. This does risk long-term information leakage
from dedicated adversaries, but is essential for utility. Other options for
recovering from an exhausted budget may be possible but need further
exploration, e.g. allowing a site to clear its data to reset its budget.

We initially plan to enforce a per-origin budget that resets daily; that is, we
will bound the contributions that any origin can make to a histogram each day.
This origin will match the origin of the execution environment, i.e. the
reporting origin, no matter which top-level sites are involved. For the earlier
[example](#examples), this would correspond to the `runAdAuction()` caller
within `reportResult()` and the interest group owner within
`reportWin()`/`reportLoss()`.

We initially plan to have two separate budgets: one for calls within Shared
Storage worklets and one for Protected Audience worklets. However, see [shared
contribution budget](#shared-contribution-budget) below.

## Future Iterations

### Supporting different aggregation services

This API will support an optional parameter `alternativeAggregationMode` that
accepts a string value. This parameter will allow developers to choose among
different options for aggregation infrastructure supported by the user agent.
This will allow experimentation with new technologies, and allows us to test new
approaches without removing core functionality provided by the default option.
The `"experimental-poplar"` option will implement a protocol similar to
[poplar](https://github.com/cjpatton/vdaf/blob/main/draft-patton-cfrg-vdaf.md#poplar1-poplar1)
VDAF in the [PPM
Framework](https://datatracker.ietf.org/doc/draft-gpew-priv-ppm/).

### Shared contribution budget

Separating contribution budgets for Shared Storage worklets and Protected
Audience worklets
provides additional flexibility; for example, some partition choices may not be
compatible (e.g. a per-interest group budget). However, we could consider
merging the two budgets in the future.

### Authentication and data integrity

To ensure the integrity of the aggregated data, it may be desirable to support a
mechanism for authentication. This would help limit the impact of reports sent
from malicious or misbehaving clients on the results of each query.

To ensure privacy, the reporting endpoint should be able to determine whether a
report came from a trusted client without determining _which_ client sent it. We
may be able to use [trust tokens](https://github.com/WICG/trust-token-api) for
this, but further design work is required.

### Aggregate error reporting

Unfortunately, errors that occur within isolated execution contexts cannot be
easily reported (e.g. to a non-isolated document or over the network). If
allowed, such errors could be used as an information channel. While these errors
could still appear in the console, it would also aid developers if we add a
mechanism for aggregate error reporting. This reporting could be automatic or
could be required to be configured according to the developers' preferences.

------

**This document is an individual draft proposal. It has not been adopted by the Private Advertising Technology Community Group.**
