# 0004. Export and account deletion

Status: accepted (2026-10-16).

## Export (Spec 4.11)
- `POST /exports` starts a job with FastAPI's built-in background tasks (no queue library yet;
  Spec 12.4 leaves Dramatiq versus RQ open). The request returns at once with `202`.
- JSON, or a ZIP with one CSV per table. Includes active, archived and deleted rows with ids,
  links, versions and timestamps.
- The file is fetched through a link signed with HMAC-SHA256 and valid for
  `OMNI_EXPORT_LINK_TTL_MINUTES` (default 60). The link needs no login, so a browser can open
  it, and it cannot be altered or reused after it expires.
- At most 10 exports per user per hour.
- Files are stored in the `exports` table. Move them to object storage when exports get large.

## Account deletion
- `DELETE /me` with body `{"confirm": "DELETE"}` (typed by the user in the app).
- One transaction removes every workspace the user owns and all of its data, the user's
  sign-in credentials and refresh tokens, and the user row. Unexpired access tokens of a
  deleted account are refused from that moment (the local provider checks the account exists).
- The app then clears all data on the device.
- Retention (Spec 12.4 left it open): nothing is kept in the live database. Copies in database
  backups disappear when those backups expire; set the backup retention to match your
  privacy notice.
