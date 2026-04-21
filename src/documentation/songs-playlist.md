# Songs Playlist

The manual source of truth for the music list is [`songs_manifest.lua`](../../songs_manifest.lua).

It is split into two parts:

- `songs`: metadata indexed by track id
- `playlist`: ordered list of track ids

## Change The Playback Order

Only edit the `playlist` array.

Example:

```lua
local playlist = {
	"takeoff_willbe",
	"aeroplane_willbe",
	"starglider_med",
}
```

The build keeps that exact order for:

- audio playback
- walkman title selection
- generated `songs.lua`
- generated `songs_titles.png`

## Add A Song

1. Add `works/audio/<track_id>.wav`.
2. Add the song metadata to the `songs` table.
3. Add the same `track_id` to `playlist`.
4. Run `1-build.bat`.

## Notes

- Track ids must match the WAV filename without the `.wav` extension.
- If a track id contains `-`, declare it in Lua with bracket syntax such as `["my-track"] = { ... }`.
- The build only includes tracks listed in `playlist`.
- You can keep metadata entries in `songs` without using them yet, as long as they are not referenced by `playlist`.
