# Security and Privacy Questionnaire

Responses to the W3C TAG’s [Self-Review Questionnaire: Security and
Privacy](https://w3ctag.github.io/security-questionnaire/) for the Private
Aggregation API.

### 2.1. What information does this feature expose, and for what purposes?

This API lets isolated contexts with access to cross-site data (i.e. [Shared
Storage](https://github.com/WICG/shared-storage) worklets/[Protected
Audience](https://github.com/WICG/turtledove) script runners) send aggregatable
reports over the network. Aggregatable reports contain encrypted high entropy
cross-site information, in the form of key-value pairs (i.e. contributions to a
histogram), but this information is not exposed directly. Instead, these reports
can only be processed by a trusted aggregation service. This trusted aggregation
service sums the values across the reports for each key and adds noise to each
of these values to produce ‘summary reports’. It also limits the number of times
that reports may be queried.

The aggregatable reports also contain some unencrypted metadata that is not
based on cross-site information.

The purpose of this API is to allow generic aggregate cross-site measurement for
a range of use cases, even if third-party cookies are no longer available. Use
cases include reach measurement, and Protected Audience auction reporting.

### 2.2. Do features in your specification expose the minimum amount of information necessary to implement the intended functionality?

We strictly limit access to the cross-site information embedded in the
aggregatable reports. The cross-site information embedded in these reports is
encrypted and only processable by a trusted aggregation service. The output of
that processing will be an aggregate, noised histogram. The service ensures that
any report can not be processed multiple times. Further, information exposure is
limited by contribution budgets on the client. In principle, this framework can
support specifying a noise parameter which satisfies differential privacy.

The plaintext portion of an aggregatable report includes information necessary
to organize (batch) reports for aggregation. The encrypted portion is assumed to
be not readable by an attacker (except for ciphertext size).

The amount of information exposed by this API is a product of the privacy
parameters used (e.g. contribution limits and the noise distribution). While we
aim to minimize the amount of information exposed, we also aim to support a wide
range of use cases. The privacy parameters can be customized to reflect the
appropriate tradeoff between information exposure and utility. The exact choice
of parameters is currently left unfixed to allow for exploration of this
tradeoff and will eventually be fixed based on community feedback.

These reports also expose a limited amount of metadata, which is not based on
cross-site data. However, the number of reports with the given metadata could
expose some cross-site information. To protect against this, we make the number
of reports deterministic in certain situations (sending reports containing no
contributions in the payloads if necessary). We are considering mitigations for
other situations, e.g. adding noise to the report count.

The recipient of the report may also be able to observe side-channel information
such as the time when the report was sent, or IP address of the sender.

### 2.3. Do the features in your specification expose personal information, personally-identifiable information (PII), or information derived from either?

This API does not directly expose PII or personal information. However, it is a
generic mechanism that does not place any limits on the kinds of data that sites
may encapsulate into the reports. See above for how all cross-site information
is protected.

### 2.4. How do the features in your specification deal with sensitive information?

See 2.3.

### 2.5. Do the features in your specification introduce state that persists across browsing sessions?

Yes, we introduce new storage for reports that are not yet sent (i.e. scheduled
to be sent in the future), for enforcing limits on the total sum of contribution
values (per-reporting site, per-context type, per-10 min / per-day) and for
caching the public keys of the trusted aggregation service. These all persist
across browsing sessions, but will be cleared along with other site data when
requested by a user and are not exposed to JavaScript.

### 2.6. Do the features in your specification expose information about the underlying platform to origins?

No

### 2.7. Does this specification allow an origin to send data to the underlying platform?

No

### 2.8. Do features in this specification enable access to device sensors?

No

### 2.9. Do features in this specification enable new script execution/loading mechanisms?

No, but this API is proposed only for the new isolated script execution contexts
specified by other proposed features (i.e. Shared Storage worklets/Protected
Audience script runners).

### 2.10. Do features in this specification allow an origin to access other devices?

No

### 2.11. Do features in this specification allow an origin some measure of control over a user agent’s native UI?

No

### 2.12. What temporary identifiers do the features in this specification create or expose to the web?

None

### 2.13. How does this specification distinguish between behavior in first-party and third-party contexts?

This API is only exposed in isolated contexts that may have access to cross-site
data. There are mechanisms proposed for controlling access to those isolated
contexts, e.g. see Protected Audience’s response
[here](https://github.com/w3ctag/design-reviews/issues/723).

### 2.14. How do the features in this specification work in the context of a browser’s Private Browsing or Incognito mode?

The contexts this API is exposed in (Shared Storage worklets and Protected
Audience script runners) are not available in Private Browsing/Incognito mode,
so it is not possible to use this API in that mode.

### 2.15. Does this specification have both "Security Considerations" and "Privacy Considerations" sections?

We are still working on the spec, but it will include both sections.

### 2.16. Do features in your specification enable origins to downgrade default security protections?

No

### 2.17. What happens when a document that uses your feature is kept alive in BFCache (instead of getting destroyed) after navigation, and potentially gets reused on future navigations back to the document?

This API is not available in document contexts, so there is no need to handle
this case.

### 2.18. What happens when a document that uses your feature gets disconnected?

This API is not available in document contexts, so there is no need to handle
this case.

### 2.19. What should this questionnaire have asked?

N/A
