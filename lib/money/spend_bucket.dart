/// Where a sample's fuel cost is put (CLAUDE.md 8.7): each sample goes into
/// exactly one, so that the buckets always add up to the trip's total.
enum SpendBucket {
  /// Everything else.
  normal,

  /// Speed below 2 km/h with the engine running. The one bucket the app calls
  /// avoidable.
  idling,

  /// During a hard acceleration. Never "wasted" (DESIGN.md 10).
  hardAcceleration,

  /// Above the user's speed threshold.
  highSpeed,
}
