# Named budgets

Sharing budget between different use cases or different products can pose a
challenge. If one of the use cases/products uses the [contribution
budget](https://github.com/patcg-individual-drafts/private-aggregation-api#contribution-bounding-and-budgeting)
more quickly, it may exhaust the budget, preventing the others from being able
to report. (For example, see issue
[#145](https://github.com/patcg-individual-drafts/private-aggregation-api/issues/145).)

We propose a generic mechanism to better support this. Each reporting site would
be able to define a series of _named budgets_ and would allocate a fraction of
their total budget to each, e.g.:

```js
privateAggregation.reserveBudget("example-budget", 0.5);
privateAggregation.reserveBudget("debug", 0.125);
```

Then, when making histogram contributions (including via
`contributeToHistogramOnEvent()`), a named budget can optionally be specified,
e.g.:

```js
privateAggregation.contributeToHistogram({
  bucket: 123n,
  value: 45,
  filteringId: 6n,
  namedBudget: "example-budget"
});
```

When approving or rejecting contributions, the browser would then check both
whether the chosen named budget has enough allocated budget left and whether
there is enough overall budget left. This ensures the overall budget is always
respected, even if the named budget allocations change.

### Fractional budget

We propose using a fraction to represent the budget allocation, i.e. not a
direct limit on the contributions’ values sum. Given the two separate time
windows used in Private Aggregation budgeting (per-10 min and per-day), using a
fraction more clearly allocates a portion of both limits simultaneously.

### Reservation persistence

To avoid the complexity of persisting configurations over time, we propose that
the `reserveBudget()` calls are scoped to just the single worklet/script runner
context. That is, the budget allocations would need to be set up at the start of
each Shared Storage operation or Protected Audience function call. Note that the
browser would still keep track of the budget usage for each group over the last
10 min and last 24 hours, but the per-named budget _limits_ themselves would not
be persisted.

See [Future iteration: global config](?tab=t.0#heading=h.4nsl8koqxkk0) below for
some discussion of a more persistent choice.

### Default (null) budget

If no named budget is explicitly specified for a contribution, it would default
to using a special “null” budget. This “null” budget is implicitly allocated the
remaining budget after all the explicit reservations are accounted for. In the
example above, the “null” budget would be allocated the remaining 37.5% of the
budget. Note that this behavior means that this feature is fully backwards
compatible.

### Allocating more than the entire budget

If more than 100% of the budget is allocated to different named budgets, a
JavaScript error will be thrown.

### Privacy considerations

This feature also does not introduce any concerns as the overall existing budget
is still always enforced. Note that contribution budgets are enforced per
reporting site and so one reporting origin on a site could exhaust the budget
for its entire reporting site. However, this is intended and is unchanged by the
new feature.

### Future iteration: global config

As a future extension, we could consider allowing these budget reservations to
be set up globally for a reporting origin (or site). A global config has already
been proposed for other use cases (see issues
[#81](https://github.com/patcg-individual-drafts/private-aggregation-api/issues/81#issuecomment-2091524214)
and
[#143](https://github.com/patcg-individual-drafts/private-aggregation-api/issues/143))
so we could potentially use a single config for these use cases. This would
reduce verbosity as reservations that don’t need to change frequently could be
replaced. We may need to consider a mechanism that allows for canceling or
overriding these globally configured details.
