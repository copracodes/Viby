# Step 1.6 — On-device verification checklist

These need a real device (S22 / R3CTA0V554L) — they exercise native paths that
`flutter test` can't: MediaStore mojibake, GPU scroll smoothness, real file I/O,
and audio focus. Automated coverage (120 unit/widget tests) backs the pure
logic; this list covers what only hardware can prove.

> Tip: `flutter run` drops on screen-sleep on this device — enable **Stay awake**
> in Developer options (the installed app keeps running regardless).

## 1. Mojibake titles now readable
- [ ] Before: confirm the library shows the garbled/`????` Arabic titles.
- [ ] Settings › Rescan. Watch the status reach the **repair** phase, then
      "Done: … N tags repaired".
- [ ] Arabic titles/albums/artists now render correctly across Library, Now
      Playing, and the media notification.
- [ ] Re-run Rescan → "0 tags repaired" (idempotent; nothing re-mangled).
- [ ] A correct (UTF-8) English/Arabic title was **not** altered.
- [ ] The audio files on disk are untouched (tags unchanged in an external tool).

## 2. 10k-track scroll smoothness
- [ ] Settings › Developer › **Seed 10k**. Wait for "Seeded 10,000 tracks".
- [ ] Library › Tracks: fling-scroll top→bottom. No jank / no dropped frames
      (optionally verify with the performance overlay / DevTools timeline).
- [ ] Library › Albums grid: fling-scroll. Artwork thumbnails stay smooth
      (downsampled decode); memory doesn't balloon.
- [ ] Library › Artists: fling-scroll — constant-time (fixed `itemExtent`).
- [ ] Search "Track 05" — results appear effectively instantly (< 100ms budget).
- [ ] Settings › Developer › **Clear synthetic** — only synthetic rows vanish;
      any real scanned library remains.

## 3. Pull-the-rug (missing / corrupt file mid-queue)
- [ ] Queue several real tracks and start playback.
- [ ] Delete one queued track's file from disk (via a file manager / `adb`).
- [ ] Skip to / let playback reach it → it is **skipped** with a
      "Couldn't play X — skipped" SnackBar; the queue keeps moving; no crash.
- [ ] The skipped track is now marked unplayable (`playable = false`).
- [ ] Delete **all** queued files → playback **stops gracefully** with the
      terminal message; the app does not crash or spin.
- [ ] Rescan restores the (still-present) tracks to playable.

## 4. Lifecycle sweep (no state loss / no duplicate work)
- [ ] Rotate the device **during a scan** → progress continues; no second scan
      kicks off; the DB isn't double-written.
- [ ] Rotate **during playback** → audio uninterrupted; Now Playing/mini-player
      state intact.
- [ ] Rotate **during a queue reorder** → the reorder result is preserved.
- [ ] Background → foreground during each of the above → same guarantees.
- [ ] Cold start with a large saved queue → app boots without a visible stall
      (restore runs async, guarded; budget < 500ms for the DB fetch path).

## 5. Audio-focus regression (re-verify; the handler changed in 1.3 + 1.6)
- [ ] Incoming call ducks/pauses, then resumes after (transient interruption).
- [ ] Another app taking focus permanently → we stay paused (no auto-resume).
- [ ] Unplug headphones / BT disconnect → playback pauses (becoming-noisy).
- [ ] Notification + lock-screen controls (play/pause/next/prev/seek) work, and
      a skip-past-a-bad-file still surfaces correctly in the notification.
