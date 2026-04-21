# Music Deliverables Specification

Please deliver each track as an individual `.wav` file.

## Required Deliverables

For each song, please provide:

- `1` stereo WAV file
- File extension: `.wav`
- File name: `{track_id}.wav`

Example:

- `opening_theme.wav`
- `boss-fight.wav`

## File Naming Rules

The file name must match the track ID exactly, without spaces.

Allowed characters:

- letters: `A-Z`, `a-z`
- numbers: `0-9`
- underscore: `_`
- hyphen: `-`

Not allowed:

- spaces
- accents / special characters
- extra dots in the name

## Audio Format

The build pipeline expects a WAV source file and converts it internally to OGG.

Target runtime encode:

- Format: `OGG Vorbis`
- Sample rate: `44.1 kHz`
- Channels: `stereo`
- Quality setting: `Vorbis quality 9`

## What You Should Deliver

Please send:

- uncompressed stereo WAV
- clean final master
- no file normalization or conversion to OGG on your side

## Recommended Source Specs

To avoid unnecessary conversion issues, please export your WAV files as:

- `44.1 kHz`
- `16-bit` or `24-bit`
- `stereo`
- PCM WAV

## Delivery Notes

Please make sure that:

- each track is final and properly trimmed
- the WAV starts and ends exactly where intended
- file names are definitive
- no alternate versions are included unless explicitly requested

## Metadata Provided Separately

Track metadata is handled separately in the project:

- track title
- artist name
- track ID

Only the WAV file is required from the musician unless requested otherwise.
