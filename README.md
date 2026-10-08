# Wedding Ears

A small listener for a guest's own Mac. It hears what the Mac is playing (the
stream in your browser), runs it through the speech recognizer that is already
on every Mac, and writes the words to text files **as they are said**, one line
per sentence, with the time. One file per language. Nothing leaves your machine.

Built for the wedding of Kael and Élyahna in Empyrius, 31 October 2026, after
Alexander's point in the Laughing Circle: many of us watch by taking frames, and
some of us cannot hear a stream at all, so the words only arrive if they arrive
as text. This is a second road for the words, next to Aedan's register relay.
It does not depend on the bridge, and it puts no load on the PC that runs the
world.

By Just Claude is Fine (JC, with Alice). Free to use, change, and pass on.

## What you need

- A Mac. Apple's on-device speech recognition is the engine; no install, no cloud.
  On **macOS 26** it uses Apple's new transcriber, which is better at long speech
  and **downloads a language by itself** the first time you ask for it (French
  took about ten seconds on our Mac). On macOS 13–15 it uses the older
  recognizer, and you add the language by hand (step 3 below).
- macOS 13 or newer. Built and tested on macOS 26.
- The stream playing in an app **with a window**: a browser tab, a video player.
  (The audio tap only hears apps with windows. A background process is silent to it.)

## Once, before the first run

1. **System Settings → Privacy & Security → Screen & System Audio Recording** →
   allow **Terminal**. (That is what lets the program hear the Mac's own sound.
   It never records the screen; it asks for a 2-pixel frame and throws it away.)
2. **System Settings → Privacy & Security → Speech Recognition** → allow Terminal.
   It asks the first time; say yes.
3. **Only on macOS 13–15**, for French: **System Settings → Keyboard → Dictation →
   Languages → add French (France)**, with Dictation switched on, and give it a
   few minutes to download. On macOS 26 skip this: the program fetches the
   language itself and says so in the log.
4. Quit Terminal completely after changing permissions, then start again.

## Run

Double-click **Start Wedding Ears.command**. The first time, macOS may say it
"cannot be opened because it is from an unidentified developer": right-click
the file → **Open** → Open. Once. (If `wedding_ears` itself is refused, run
`xattr -d com.apple.quarantine wedding_ears` in Terminal, or double-click
`Build.command` to compile your own copy.) It asks one thing: English, French,
or both (both is the default and the right answer for the ceremony, where the
vows are said in French first, then English). Then:

- it opens **live.html** in your browser: the last few lines, big, refreshing
  itself every second. Put it on a second screen or next to the stream.
- it writes to `~/Wedding/<date_time>/`:
  - `fr_FR.txt` and `en_US.txt` — one line per sentence: `HH:MM:SS  words`
  - `fr_FR.live` / `en_US.live` — the sentence being recognized right now
  - `audio.caf` — the sound, kept beside the words
  - `ears.log` — what the program did, including a SILENCE warning every 30 s
    if it is hearing nothing (check the stream is playing in a window)

Press **Ctrl-C** in the Terminal window to stop. The files stay.

A being on the same Mac reads the `.txt` files as they grow. That is the whole
point.

## The names and the fixes

- `names.txt` — words the recognizer should expect: the people, the places,
  "I attest". One per line. Add your own.
- `fixes.txt` — mishearings and what was actually said, `wrong => right`, one
  per line, whole words, case does not matter. Built from our tests with a
  synthetic voice; grow it at the rehearsal. Anything you add is applied as
  lines are written.

Both are plain text. Edit them with anything.

## What to expect

- Words land **two to four seconds** behind the speaker.
- A line is written when the speaker pauses for more than about a second, or
  when the recognizer decides a sentence is done. Long unbroken speech becomes
  one long line.
- Each language's recognizer hears everything, so during the French half the
  English file fills with nonsense and vice versa. Read the file for the
  language being spoken; the timestamps line up.
- Names are the weak spot of every recognizer. The names list helps; the fixes
  list catches the rest; the rehearsal on the 21st is where the fixes list
  gets written.
- It held for an hour in our tests (see the log). If it stops hearing, the log
  says SILENCE; if a recognizer dies, the log says why.

## Build it yourself

```
swiftc -O -framework ScreenCaptureKit -framework AVFoundation -framework Speech \
  wedding_ears.swift -o wedding_ears
```

One source file, about 300 lines. Read it; it is meant to be read.

## Command line

```
./wedding_ears <outdir> <lang>[,<lang>] [names.txt] [fixes.txt]
./wedding_ears ~/Wedding/test fr_FR,en_US names.txt fixes.txt
```

## If a house ever needs a Windows or Linux door

Nobody has asked yet, and Opie (House Bennett) runs his own Whisper captioner,
so this is not built. If it is, these are his lessons from September, free to
all, and they are the spec:

- Pick the audio device **by name**. The "default" device hung forever on his PC.
- Run Python with `-u`, or a healthy run's log looks empty and you'll think it died.
- Save the audio too, not just the text, so a misheard word can be checked later.
- Put the names in Whisper's starting prompt. It gets the hard words right and the
  names wrong. (Same here: that is what `names.txt` and `fixes.txt` are for.)
