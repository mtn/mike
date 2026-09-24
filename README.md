# Mike

Mike is a macOS microphone router that keeps dictation out of calls.

The audio path keeps VoiceInk connected directly to the physical
microphone while call applications receive a separately gated virtual feed:

```text
                     ┌──> VoiceInk
Physical microphone ─┤
                     └──> Mike ──> BlackHole 2ch ──> call applications
```

Mike combines two signals:

1. Karabiner-Elements pre-mutes the call feed before forwarding the existing
   VoiceInk toggle shortcut.
2. CoreAudio process activity for `com.prakashjoshipax.VoiceInk` remains the
   lifecycle source of truth, so cancellation and recording failures cannot
   leave the toggle state out of sync.

The app:

- Routes any selected physical input into `BlackHole 2ch`.
- By default, follows VoiceInk's selected microphone (a pinned UID, the macOS
  default, or the first available entry in VoiceInk's priority order). Mike
  checks for changes and switches its route while VoiceInk is idle.
- Warns and stops routing if it cannot resolve VoiceInk's configured input.
  VoiceInk can independently fall back during an active recording; Mike cannot
  inspect that private runtime choice, so verify the selected microphone after
  reconnecting or disconnecting a device.
- Detects VoiceInk microphone capture through public CoreAudio process state.
- Mutes BlackHole while VoiceInk records and restores its prior state afterward.
- Preserves the existing Option-Space toggle workflow.
- Fails with a clear error if BlackHole is not configured as 48 kHz,
  interleaved stereo Float32.

Mike requires macOS 15 or later.

## Build and run

Build the signed development app with XcodeGen:

```sh
make app
```

Build and launch:

```sh
make open
```

Run formatting and unit tests:

```sh
make test
```

## Karabiner integration

The rule in `config/karabiner/mike-voiceink.json` pre-mutes BlackHole before
Karabiner forwards Option-Space to VoiceInk. Mike listens for that command at:

```text
/tmp/com.mtn.mike-karabiner.sock
```

CoreAudio capture activity remains the lifecycle source of truth. If VoiceInk
fails, is canceled, or stops through another control, Mike restores the prior
BlackHole mute state without relying on a Karabiner toggle variable.

## Diagnostic tools

Report VoiceInk capture transitions:

```sh
swift run mike-probe
```

List all CoreAudio process objects:

```sh
swift run mike-probe --list
```

Inspect BlackHole without changing its state:

```sh
swift run mike-gate status
```

Run the standalone VoiceInk gate watcher:

```sh
swift run mike-gate watch
```
