# Aggregate error reporting

#### Table of contents

- [Introduction](#introduction)
- [Motivating use cases](#motivating-use-cases)
  - [Measuring reports dropped due to insufficient budget](#measuring-reports-dropped-due-to-insufficient-budget)
  - [Detecting unhandled crashes](#detecting-unhandled-crashes)
- [Defining histogram contributions to send on error events](#defining-histogram-contributions-to-send-on-error-events)
  - [New JavaScript API surface](#new-javascript-api-surface)
  - [Error events](#error-events)
    - [Associating error events with a single interest group](#associating-error-events-with-a-single-interest-group)
  - [Measuring insufficient contribution budget](#measuring-insufficient-contribution-budget)
- [Privacy and security](#privacy-and-security)
- [Future iterations](#future-iterations)
  - [Global config](#global-config)
  - [Per-interest group error-event contributions](#per-interest-group-error-event-contributions)

## Introduction

There are a range of error conditions that can be hit when using the Private
Aggregation API. For example, the privacy budget could run out, preventing any
further histogram contributions. As the errors themselves may be cross-site
information, we cannot simply expose them to the page for users who have
disabled third-party cookies. Instead, we propose a new aggregate, noised error
reporting mechanism that leverages the existing reporting pipelines through the
Aggregation Service.

We aim to allow developers to measure the frequency of certain 'error events'
and to split these measurements on relevant developer-specified dimensions (e.g.
version of deployed code). We aim to also support measuring certain error events
in the Shared Storage and Protected Audience APIs that cannot be directly
exposed due to similar cross-site information risks. We aim to support these use
cases with minimal or no privacy regressions.

The proposed mechanism limits privacy impacts by embedding these debugging
measurements in the same aggregatable reports already used by the API. Ad techs
will be able to avoid interfering with their existing measurements by using
filtering IDs or separate bucket spaces. Note that we have also
[proposed](https://github.com/patcg-individual-drafts/private-aggregation-api/blob/main/named_budgets.md)
a mechanism to reserve privacy budget for different types of contributions. This
is necessary to allow for budget exhaustion measurement, but will support
additional uses too.

Note that the Attribution Reporting API (ARA) has introduced a similar feature
called [Aggregate Debug
Reporting](https://github.com/WICG/attribution-reporting-api/blob/main/aggregate_debug_reporting.md).
This allows for measuring events like reaching rate limits. Our proposal has a
few differences in design due to differences in our setting.

## Motivating use cases

### Measuring reports dropped due to insufficient budget

Developers using the Private Aggregation API need to [choose an appropriate
scale](https://github.com/patcg-individual-drafts/private-aggregation-api#scaling-values)
for their measurements. This choice is a trade off between the relative noise
added by the aggregation service and the risk of dropped reports due to budget
limits. Measuring the fraction of reports that are dropped due to insufficient
budget would allow developers to better evaluate the impact of their scale
choice.

### Detecting unhandled crashes

Developers using Shared Storage or Protected Audience may accidentally ship code
that crashes, i.e. by triggering a JavaScript exception that isn't caught.
Measuring these situations directly would improve detection. Being able to split
these measurements by relevant dimensions would also ease debugging.

## Defining histogram contributions to send on error events

### New JavaScript API surface

To support measuring these error conditions, we propose extending the
[existing](https://github.com/WICG/turtledove/blob/main/FLEDGE_extended_PA_reporting.md#reporting-api-informal-specification)
`contributeToHistogramOnEvent()` API, currently only exposed in Protected
Audience script runners. For example:

```js
privateAggregation.contributeToHistogramOnEvent(
  "reserved.uncaught-error", { bucket: 123n, value: 45, filteringId: 6n });
```

We would expand the existing list of `reserved.` events supported. We would also
expose this API to Shared Storage, but without the ['filling
in'](https://github.com/WICG/turtledove/blob/main/FLEDGE_extended_PA_reporting.md#reporting-api-informal-specification)
logic (i.e. without support for signalBuckets and signalValues). Note also that
certain events would only be valid in one type of context; for example, the
existing Protected Audience-specific
[events](https://github.com/WICG/turtledove/blob/main/FLEDGE_extended_PA_reporting.md#triggering-reports)
would not be exposed to Shared Storage callers.

These 'conditional' histogram contributions would be scoped to that specific
JavaScript context.

This approach is flexible. For example, it allows callers to ignore error events
that are not interested in, or to have two different error events trigger the
same contribution. However, it is also somewhat verbose, requiring these calls
to be repeated for each JavaScript context. There are also certain error cases
that cannot be measured with this approach. However, see [Future
iterations](#future-iterations) below for some extensions that may
address these issues.

### Error events

We propose the following events, but this list could be expanded in the future.

The following events would be available in both Shared Storage and Protected
Audience contexts:

- `reserved.report-success`: a report was scheduled and no contributions were
  dropped
- `reserved.too-many-contributions`: a report was scheduled, but some
  contributions were dropped due to the per-report limit
- `reserved.empty-report-dropped`: a report was not scheduled as it had no
  contributions
- `reserved.pending-report-limit-reached`: a report was scheduled, but the limit
  of pending reports was reached. That is, attempting to schedule one more
  report would fail due to the limit.
- `reserved.insufficient-budget`: one or more contributions were dropped from a
  scheduled report (or the entire report was not scheduled) as there was not
  enough budget
- `reserved.uncaught-error`: a JavaScript exception or other error was thrown
  and not caught in this context

The following event would only be available in Shared Storage contexts:

- `reserved.contribution-timeout-reached`: the JavaScript context was still
  running when the contribution timeout occurred

The following events would only be available in Protected Audience contexts:

- The existing events (`reserved.win`, `reserved.loss`, `reserved.always`)
- Possibly additional events for various network failures, see [Future
  iterations](#future-iterations) below.

Note that errors in the reporting pipeline used by public key fetching failures
or running out of retries are not exposed. These errors would be difficult to
report on given that they indicate the reporting pipeline is not functioning
properly; additionally, it would be difficult to perform budgeting for these
cases given these occur well after the original report was scheduled.

#### Associating error events with a single interest group

Contributions associated with different interest groups but with the same
reporting origin are [batched
together](https://github.com/patcg-individual-drafts/private-aggregation-api#batching-scope)
into a single report. However, the number of these other interest groups is not
revealed to Protected Audience contexts. If this single report encounters an
error, we do not want to trigger duplicate contributions due to multiple
contexts registering the same contributions.

So, we propose each reporting-related error should only trigger an error event
for one of the contexts that contributed to the report. The browser should pick
one at random. Note that this aligns with the
[proposal](https://github.com/WICG/turtledove/issues/1170) to define a new
`reserved.once` event.

### Measuring insufficient contribution budget

To measure the error events representing insufficient [contribution
budget](https://github.com/patcg-individual-drafts/private-aggregation-api#contribution-bounding-and-budgeting),
some of the budget for histogram contributions that measure this error event
must be reserved. Otherwise, those contributions would likely also be dropped
due to the budget limit. This “named budget” functionality also supports other
use cases and has been proposed in [a separate
explainer](https://github.com/patcg-individual-drafts/private-aggregation-api/blob/main/named_budgets.md).

### Two phase processing

We propose a two phase processing model where first contributions that are not
conditional on error events are tentatively processed. (For example, testing
whether there is sufficient budget for all the contributions and whether they
fit into the limit on the number of contributions.) The outcome of that
processing will then be used to determine which error events should be
triggered. Then, the entire report, including both the unconditional
contributions and triggered conditional contributions is processed again.

This avoids complexity from the possibility that error events being triggered
could affect whether other error events could be triggered. However, it does
mean that errors caused by conditional contributions only may be more difficult
to measure. To prioritize measuring errors, unconditional contributions will be
dropped first if truncation is required.

## Privacy and security

This feature does not introduce any new privacy or security considerations as it
only allows you to send histogram contributions that would've been permitted
without the new feature. (That is, the only change is allowing these
contributions to be conditional on an error event.) These contributions are
embedded into the existing reports sent by the API and use contribution budget
just like existing contributions.

## Future iterations

### Global config

As a future extension, we could consider allowing these error-event
contributions to be set up globally for a reporting origin (or site). A global
config has already been proposed for other use cases (see issues
[#81](https://github.com/patcg-individual-drafts/private-aggregation-api/issues/81#issuecomment-2091524214)
and
[#143](https://github.com/patcg-individual-drafts/private-aggregation-api/issues/143))
so we could potentially use a single config for these use cases.

This would reduce verbosity as calls that don't need to change frequently could
be replaced. It could also allow for the addition of new error events for
failures that would prevent scripts from being run, e.g. if a bidding script
fails to load. Note that this wouldn't allow for contributions to vary based on
specific details like the interest group or the user, and wouldn't allow
sampling. We may need to consider a mechanism that allows for canceling or
overriding these globally configured details.

### Per-interest group error-event contributions

We could also consider allowing error-event contributions to be set per interest
group. As with the global config, this allow for the addition of new error
events for failures that would prevent scripts from being run, e.g. if a bidding
script fails to load. It would also allow these contributions to vary per-user
or per-interest group. However, this configuration would use up some of the
interest group storage budget, which may not be desired.
