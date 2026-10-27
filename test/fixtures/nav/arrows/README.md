# Real arrows

The manoeuvre pictures Google Maps 25.33 put in its navigation notification (the
capture of docs/NAV.md, N1): 126 x 126, one byte of coverage a pixel, row by row,
as `NavArrow.alpha`. The name is the first part of the capture's image name.

| File | What Maps was saying when it posted it |
|---|---|
| `5c317d6e0e.alpha` | `Head north`, `toward Vittal Mallya Rd`: straight ahead |
| `5e259b7bb6.alpha` | `Turn left toward Vittal Mallya Rd` |
| `e687a80d8d.alpha` | `650 m \u00B7 Turn right at Richmond Cir onto Mission Rd` |

They are Google's pictures, kept here only as test data for reading which way an
arrow turns.

## Maps 26.42, on the human's phone (135 x 135)

From the capture of 2026-10-27 (Android 16, `docs/NAV.md`), the classic shape. Same
format; the name is the capture's image hash.

| File | What Maps was saying when it posted it |
|---|---|
| `762942fb95.alpha` | `Head east`, `towards Vittal Mallya Rd`: straight ahead |
| `3056e8deb3.alpha` | `120 m`, `Turn left` |
| `26a50ee8c7.alpha` | `30 m`, `Turn right` |
| `3abbe8783c.alpha` | `90 m`, `Sharp right`: a hairpin, which the bend reader once read as **left** and now leaves `unknown` |
