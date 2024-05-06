# More flexible contribution filtering for Aggregation Service queries

_Note: This document proposes a new backwards compatible change in the Private
Aggregation API, Attribution Reporting API and Aggregation Service. While this
new functionality is being developed, we still highly encourage testing the
existing API functionalities to support core utility and compatibility needs._

#### Table of Contents

- [Introduction](#introduction)
- [Motivating use cases](#motivating-use-cases)
  - [Processing contributions at different cadences](#processing-contributions-at-different-cadences)
  - [Processing contributions by campaign ID](#processing-contributions-by-campaign-id)
- [Non-goals](#non-goals)
- [Proposal: filtering ID in the encrypted payload](#proposal-filtering-id-in-the-encrypted-payload)
  - [Use case examples](#use-case-examples)
    - [Processing contributions at different cadences](#processing-contributions-at-different-cadences-1)
    - [Processing contributions by campaign ID](#processing-contributions-by-campaign-id-1)
  - [Details](#details)
    - [Small ID space by default, but configurable](#small-id-space-by-default-but-configurable)
    - [Backwards compatibility](#backwards-compatibility)
    - [One ID per contribution](#one-id-per-contribution)
- [Possible future extension: batching ID in the shared_info](#possible-future-extension-batching-id-in-the-shared_info)
  - [Use case examples](#use-case-examples-1)
    - [Processing contributions at different cadences](#processing-contributions-at-different-cadences-2)
    - [Processing contributions by campaign ID](#processing-contributions-by-campaign-id-2)
  - [Details](#details-1)
    - [Requires deterministic reports and specifying batching ID from a single-site context](#requires-deterministic-reports-and-specifying-batching-id-from-a-single-site-context)
    - [Backwards compatibility](#backwards-compatibility-1)
    - [One ID per report](#one-id-per-report)
    - [Use with filtering ID](#use-with-filtering-id)
- [Limits on number of IDs used](#limits-on-number-of-ids-used)
- [Application to Attribution Reporting API](#application-to-attribution-reporting-api)
- [Privacy considerations](#privacy-considerations)

## Introduction

Currently, the Aggregation Service only allows each '[shared
ID](https://github.com/WICG/attribution-reporting-api/blob/main/AGGREGATION_SERVICE_TEE.md#disjoint-batches)'
to be present in one query. A set of reports with the same shared ID cannot be
split for separate queries, even if the resulting batches are disjoint. However,
there have been requests to introduce additional flexibility to this query model
(see GitHub issues for [Private
Aggregation](https://github.com/patcg-individual-drafts/private-aggregation-api/issues/92)
and [Attribution Reporting](https://github.com/WICG/attribution-reporting-api/issues/732)).

Here, we propose introducing a new _filtering ID_ set when a contribution is
made and embedded in the encrypted payload. This allows for these queries to be
split further, with the aggregation service filtering contributions based on the
provided IDs.

We also propose a possible future extension where a _batching ID_ is set from a
first-party context and embedded in the `shared_info`. This would allow for the
ad tech to filter the reports directly, improving the ergonomics for some use
cases.

## Motivating use cases

#### Processing contributions at different cadences

For some measurements, it may be desirable to query the Aggregation Service less
frequently; this would allow for more contributions to be aggregated before
noise is added, improving the signal-to-noise ratio. However, for other
measurements, it may be more valuable to receive a result faster. (Support for
this use case has been requested for Attribution Reporting
[here](https://github.com/WICG/attribution-reporting-api/issues/732).) Filtering
IDs could be used to separate these measurements into different queries.

#### Processing contributions by campaign ID

An ad tech might want to process measurements — for example, reach measurements
— separately for each advertising campaign. To allow for this, it might want to
use a different filtering ID or batching ID for each campaign. Note that,
without this new functionality, the advertiser is not part of the shared ID and
so it's not currently possible to process these separately.

## Non-goals

While we aim to increase the flexibility of report batching strategies, we don't
intend to allow every report or every contribution to be queried separately.
Further, we don't intend to allow for arbitrary groupings decided after
reporting is complete. This is to ensure that the scale of aggregatable
reporting accounting remains feasible, see  [discussion
below](#limits-on-number-of-ids-used).

## Proposal: filtering ID in the encrypted payload

We plan to introduce additional IDs in the payload called _filtering IDs_. By
embedding these IDs within the encrypted payload, their values could be set
within a worklet/script runner — e.g. for a Protected Audience bidder — and
could even be chosen based on cross-site data. For example:

```js
privateAggregation.contributeToHistogram(
    {bucket: 1234n, value: 56, filteringId: 3n});
```

If no filtering ID is provided, a default ID of 0 will be used. (See also
[Backwards compatibility](#backwards-compatibility) below.)

As the reporting endpoint cannot determine the IDs within a given report, the
aggregation service will provide new functionality for filtering contributions
based on their IDs. In particular, each aggregation service query's parameters
should provide a list of allowed filtering IDs and all contributions with other
IDs will be filtered out. For example:

```jsonc
// ...
"job_parameters": {
  "output_domain_blob_prefix": "domain/domain.avro",
  "output_domain_bucket_name": "<data_bucket>",
  "filtering_ids": [1, 3]  // IDs to keep in the query
},
```

Note that this API is not final, e.g. it might make more sense to specify the
IDs via an avro file.

The aggregation service would include a filtering ID in the computation of each
'[shared ID](https://github.com/WICG/attribution-reporting-api/blob/main/AGGREGATION_SERVICE_TEE.md#disjoint-batches)'
hash. For aggregatable report accounting, the aggregation service would assume
that each filtering ID listed in the job parameters is present in every report.
This avoids leaking any information about which IDs were actually present in
each report.

### Use case examples

#### Processing contributions at different cadences

As discussed [above](#processing-contributions-at-different-cadences), a
reporting site may want to query the Aggregation Service at different cadences
for different kinds of measurements.

Filtering IDs could be used to separate these measurements into different
queries. For example, you could specify a filtering ID of 1 for measurements
that should be queried daily and an ID of 2 for measurements that should be
queried monthly. Each day, the reporting site would then send a day's reports to
the aggregation service and specify that only contributions with a filtering ID
1 should be processed. Each month, the reporting site would send an entire
month's payloads (which have been sent earlier in the daily queries), but
specify that only contributions with a filtering ID 2 should be processed.

Note that, in this flow, every report needs to be sent to the aggregation
service multiple times. However,  as the filtering IDs are different, no
_contribution_ is being included in an aggregation twice and so there are no
issues with aggregatable report accounting.

#### Processing contributions by campaign ID

For certain use cases, the filtering ID may be a deterministic function of the
context. For example, if an ad tech wants to process measurements separately for
each campaign, it could use a different filtering ID for each campaign. As the
campaign would be known outside the Shared Storage worklet, the ad tech could
externally maintain a mapping from the [context
ID](https://patcg-individual-drafts.github.io/private-aggregation-api/#aggregatable-report-context-id)
to the filtering ID.

When batching reports for the aggregation service, the ad tech could use this
mapping to separate the reports by filtering ID, even though it cannot decrypt
the payload. By avoiding reprocessing every report for each campaign ID, the
number of IDs used can be much larger while keeping processing costs reasonable.

### Details

#### Small ID space by default, but configurable

The filtering ID would be an unsigned integer limited to a small number of bytes
(1 byte = 8 bits) by default. If no filtering ID is provided, a value of 0 will
be used. We limit the size of the ID space to prevent unnecessarily increasing
the payload size and thus storage and processing costs. As filtering IDs are not
readable by the reporting endpoint, processing multiple filtering IDs separately
would typically require reprocessing the same reports for each query (see [the
first example use](#processing-contributions-at-different-cadences-1) above).
Given this performance constraint, it is unlikely that a larger ID space will be
practical with this flow.

However, other flows could make use of a larger ID space (see [the second
example use case](#processing-contributions-by-campaign-id-1) above), so we plan
to allow for the ID space to be configurable per-report, up to 8 bytes (i.e. 64
bits). To avoid amplifying a counting attack due to the different payload size,
we plan to make the number of reports emitted with this custom label size
deterministic. This will result in a null report being sent if no contributions
are made. Note that this means the filtering ID _space_ for Private Aggregation
reports must also be specified outside Shared Storage worklets/Protected
Audience script runners.

For Shared Storage and Protected Audience sellers, we propose reusing the
`privateAggregationConfig` implemented/proposed for report verification, adding
a new field, e.g.

```js
sharedStorage.run('example-operation', {
  privateAggregationConfig: {
    contextId: 'example-id',
    filteringIdMaxBytes: 8  // i.e. allow up to a 64-bit integer
  }
});
```

We do not currently plan to allow the filtering ID bit size to be configured for
Protected Audience bidders as these flows require context IDs to make the scale
practical; we do not currently plan to expose context IDs to bidders (see the
[explainer](https://github.com/patcg-individual-drafts/private-aggregation-api/blob/main/report_verification.md#specifying-a-contextual-id-and-each-possible-ig-owner)
for more discussion).

#### Backwards compatibility

For backwards compatibility, if no list of `filtering_ids` is provided in an
aggregation query, the list containing only the default ID will be used (i.e.
`[0]`). This means that any contributions that don't specify a filtering ID
would be included in that aggregation, along with any contributions that
explicitly specify the default ID. Additionally, the aggregation service will
process reports using older format versions (i.e. before labels were supported)
as if every contribution uses the default filtering ID.

This should ensure that no changes need to be made to existing pipelines if
filtering IDs are not needed.

#### One ID per contribution

We plan to allow for a filtering ID to be set individually for each contribution
in a report's payload. To reduce the impact on payload size, we could consider
instead limiting the number of distinct filtering IDs per report to a smaller
number. However, this may pose ergonomic difficulties.

## Possible future extension: batching ID in the shared\_info

Later, to improve ergonomics (see [example
below](#processing-contributions-by-campaign-id-2)), we could consider
introducing a new, optional field to an aggregatable
[report](https://github.com/patcg-individual-drafts/private-aggregation-api#reports)'s
shared\_info called a _batching ID_. For example:

```jsonc
"shared_info": "{\"api\":\"shared-storage\",\"batching_id\":1234,\"report_id\":\"[UUID]\",\"reporting_origin\":\"https://reporter.example\",\"scheduled_report_time\":\"[timestamp in seconds]\",\"version\":\"[api version]\"}",
```

This ID would be an unsigned 32-bit integer. The aggregation service would
include the batching ID in computation of the '[shared
ID](https://github.com/WICG/attribution-reporting-api/blob/main/AGGREGATION_SERVICE_TEE.md#disjoint-batches)'
hash, allowing reports with differing batching IDs to be batched and queried
separately.

### Use case examples

#### Processing contributions by campaign ID

As discussed [above](#processing-contributions-by-campaign-id-1), an ad tech may
want to process measurements separately for each campaign. In that example, the
filtering ID used is a deterministic function of the context. Instead of setting
a filtering ID, a batching ID could be specified.

As the batching ID would be readable by the ad tech, it would then be able to
use this batching ID to identify what campaign the report is for and to batch
and query the reports for each campaign separately. It would no longer have to
rely on maintaining a context ID to filtering ID mapping, which would provide
improved ergonomics and might reduce the risk of bugs from the context ID to
filtering ID mapping.

#### Processing contributions at different cadences

While a reporting site could potentially use a batching ID for processing
contributions at different cadences, it has a few downsides relative to a
filtering ID. As only one batching ID can be set per report, multiple reports
would need to be triggered, e.g. through multiple Shared Storage operations.
Further, as the batching ID [requires deterministic
reports](#requires-deterministic-reports-and-specifying-batching-id-from-a-single-site-context),
this would result in a report being sent for each ID, even if there are no
contributions for that cadence. These additional reports would negate the
benefit of being able to split reports into separate batches at the reporting
endpoint.

### Details

#### Requires deterministic reports and specifying batching ID from a single-site context

As this option embeds highly specific information about the context that
triggered a particular report (in plaintext), we need to make the number of
reports emitted with the batching ID deterministic. (See the [report
verification explainer](https://github.com/patcg-individual-drafts/private-aggregation-api/blob/main/report_verification.md#deterministic-number-of-reports)
for a similar discussion with respect to context IDs.) This will result in a
null report being sent if no contributions are made. Note that this means the
batching ID for Private Aggregation reports must also be specified outside
Shared Storage worklets/Protected Audience script runners.

For Shared Storage and Protected Audience sellers, we propose reusing the
`privateAggregationConfig` implemented/proposed for report verification, adding
a new field, e.g.

```js
sharedStorage.run('example-operation', {
  privateAggregationConfig: {
    contextId: 'example-id',
    batchingId: 1234
  }
});
```

We do not currently plan to use a context ID for Protected Audience bidders due
to the potential for a large number of null reports, see
[explainer](https://github.com/patcg-individual-drafts/private-aggregation-api/blob/main/report_verification.md#specifying-a-contextual-id-and-each-possible-ig-owner)
for more discussion. Identical considerations would apply to this batching ID in
the `shared_info`; so, we would not allow a batching ID to be set for bidders.
Note that Protected Audience auction winners could still report using Shared
Storage in the rendering (fenced) frame.

#### Backwards compatibility

If no batching ID is specified, the field will not be present in the
`shared_info`. This should ensure the change is backwards compatible.

#### One ID per report

Each report can have at most one batching ID (unlike filtering IDs which are
per-contribution). This aligns with the behavior for context IDs, given they are
both readable by the reporting endpoint.

#### Use with filtering ID

Both a batching ID and a filtering ID could be used at the same time.

## Limits on number of IDs used

This proposal increases the number of '[shared
IDs](https://github.com/WICG/attribution-reporting-api/blob/main/AGGREGATION_SERVICE_TEE.md#disjoint-batches)'
that the Aggregatable Report Accounting service will need to keep track of. So,
we will need to ensure there are limits to this increase to prevent scale
issues. (Note that it is not practical for each report to have its own entry
recorded in the accounting service.)

We plan to impose a limit on the number of shared IDs for any particular
aggregation. That is, if too many are used by a query, an error would occur. The
effect of this limit on the number of filtering IDs or batching IDs (or both)
that can be provided will depend on other details of the batching strategy.

Straw proposal: a limit of 1000 shared IDs per aggregation.

## Application to Attribution Reporting API

The filtering ID approach should be extendable to the Attribution Reporting API
and, in principle, we could allow the label to be set based on either source or
trigger-side information.

The batching ID approach may not be viable for all Attribution Reporting API
callers as a null report would need to be sent for every unattributed trigger.
This could increase report volume substantially (e.g. 4 to 20 times); however,
some callers may be able to tolerate this increase (see the discussion in [ARA
issue #974](https://github.com/WICG/attribution-reporting-api/issues/974) about
introducing a trigger ID). If making reports deterministic is acceptable for
some callers, we could support setting a batching ID for a trigger with a
similar mechanism to the already proposed trigger ID.

The details of these approaches will be explored in a separate GitHub issue.

## Privacy considerations

While this change does allow for reprocessing the same report in different
aggregations, each query will only aggregate distinct contributions from that
report. In other words, each contribution is still guaranteed to only be
aggregated once, maintaining our current [privacy protection
model](https://github.com/patcg-individual-drafts/private-aggregation-api#contribution-bounding-and-budgeting).

One other potential concern is that introducing new (plaintext) metadata to the
report might amplify counting attacks (see related discussion for context IDs
[here](https://github.com/patcg-individual-drafts/private-aggregation-api/blob/main/report_verification.md#privacy-considerations)).
However, we ensure that any new metadata (including a batching ID and any
non-default payload size) is paired with making the sending of that report
deterministic. This avoids any risk of the report count leaking information.
