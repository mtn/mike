# Mike

Mike is a macOS microphone router that keeps dictation out of calls.

The planned audio path keeps VoiceInk connected directly to the physical
microphone while call applications receive a separately gated virtual feed:

```text
                     ┌──> VoiceInk
Physical microphone ─┤
                     └──> Mike ──> BlackHole 2ch ──> call applications
```

Mike will combine two signals:

1. Karabiner-Elements pre-mutes the call feed before forwarding the existing
   VoiceInk toggle shortcut.
2. CoreAudio process activity for `com.prakashjoshipax.VoiceInk` remains the
   lifecycle source of truth, so cancellation and recording failures cannot
   leave the toggle state out of sync.

## Activity probe

The first implementation milestone is `mike-probe`, a command-line utility
that reports when VoiceInk starts and stops capturing microphone input.
CoreAudio process objects require macOS 14.2 or later.

```sh
swift run mike-probe
```

List all process objects currently known to CoreAudio:

```sh
swift run mike-probe --list
```

Inspect BlackHole without changing its state:

```sh
swift run mike-gate status
```

Gate BlackHole automatically while VoiceInk captures:

```sh
swift run mike-gate watch
```

The watcher remembers whether BlackHole was already muted. It only unmutes the
device on exit or after recording when Mike was responsible for muting it.

Run the tests:

```sh
swift test
```
