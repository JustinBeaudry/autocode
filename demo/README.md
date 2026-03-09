# Recording an AutoCode Demo

## Option 1: asciinema (terminal recording)

```bash
# Install
brew install asciinema

# Record
asciinema rec demo.cast --title "AutoCode Demo"

# Play back
asciinema play demo.cast

# Upload to asciinema.org
asciinema upload demo.cast

# Convert to GIF (install agg first)
cargo install --git https://github.com/asciinema/agg
agg demo.cast demo.gif --theme monokai --font-size 14
```

## Option 2: VHS (Charm.sh)

```bash
# Install
brew install charmbracelet/tap/vhs

# Create a .tape file with the demo steps
# VHS can automate the typing and pausing
vhs demo.tape
```

## Option 3: Screen capture

Use OBS, QuickTime (macOS), or any screen recorder:
1. Set terminal font to 16pt+ for readability
2. Use a dark theme (Monokai, Dracula, or similar)
3. Record at 1920x1080 or 1280x720
4. Convert to GIF with: `ffmpeg -i demo.mp4 -vf "fps=10,scale=800:-1" demo.gif`

## Adding to README

Once you have a demo.gif:

```markdown
## Demo

![AutoCode Demo](demo/demo.gif)
```

Or for an asciinema embed:

```markdown
## Demo

[![asciicast](https://asciinema.org/a/XXXXX.svg)](https://asciinema.org/a/XXXXX)
```
