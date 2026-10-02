## 2026-10-02 - Avoid Array Concatenation in PowerShell
**Learning:** Using `+=` to accumulate items in an array inside loops (like a `process` block iterating over pipeline items) causes an O(N²) performance degradation because PowerShell creates a new array and copies all elements every time.
**Action:** Replace `$array = @()` and `$array += $item` with `$list = [System.Collections.Generic.List[object]]::new()` and `$list.Add($item)`.

## 2026-10-02 - Direct Directory Role Member Retrieval

### The Bottleneck
Previously, the `Get-GTInactiveUser` function made an unnecessary network call to resolve the internal `id` of a directory role (such as Global Administrator) by querying with a filter on `roleTemplateId`. Only after obtaining that internal ID did it execute a second API call to fetch the role's members. In an architecture governed by latency, a synchronous graph API operation constitutes a significant performance penalty.

### The Optimization Strategy
Instead of the two-step resolution, we can hit the directory role's `/members` endpoint directly by exploiting OData key specification on the `roleTemplateId` property:
`GET /v1.0/directoryRoles(roleTemplateId='{roleTemplateId}')/members`

### Edge Case Handled
A direct `roleTemplateId` query acts slightly differently than a `$filter` query on the root collection if the role is *not* active in the tenant.
* Old way: Returning `$null`/empty array without throwing.
* Direct way: Returns an HTTP `404 Not Found`.

This was resolved by intercepting the 404 via the internal `Get-GTGraphHttpStatus` helper, discarding the error, and emitting a diagnostic message correctly mimicking the previous behavior.

### Measurement
A simulated local benchmark intercepting `Invoke-GTGraphRequest` with an artificial 200ms delay demonstrated:
* **Baseline**: 3 API calls, 730ms execution time.
* **Optimized**: 2 API calls, 509ms execution time.
* **Improvement**: ~30% reduction in end-to-end processing time for this specific path.
