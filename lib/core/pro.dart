/// Viby Pro gating — the single flag that decides whether Pro-marked features
/// (themes 3-6 today) are unlocked.
///
/// The paywall / entitlement provider isn't built yet, so this is a const:
/// features carry the [ProBadge] but stay usable. Flipping to a real check is a
/// one-line change here.
///
/// TODO(3.4): replace with `ref.watch(proProvider)` once billing lands, and
/// gate selection (show the paywall when locked) instead of always allowing it.
const bool kProThemesUnlocked = true;
