---
"@zoralabs/cli": minor
---

`zora agent create` now accepts optional `--username`, `--bio`, and `--avatar` flags to set the new agent's profile during creation. Each is independent and optional — omit them to keep Zora's auto-assigned handle, bio, and avatar. `--username` also sets the display name and is availability-checked; `--bio ""` clears the default bio; `--avatar` takes a local image (PNG/JPG/GIF/WebP) and uploads it. The chosen profile is applied right after the account is created — before the creator coin and first post — so a taken handle fails fast and every link and the coin's metadata use the chosen username.
