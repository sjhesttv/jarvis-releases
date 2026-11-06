# Installing JARVIS on a Mac

These steps set JARVIS up on your own Mac, where he runs on your Claude
subscription with his voice, listening and memory search all running
locally.

> **Source access.** The Mac build is not in this repository's release files,
> which are for the cloud (DigitalOcean) deployment. It is installed from the
> `jarvis-local-refined` branch of the private source repository, so you need
> access to that repository.

Most of the install is one script. It runs as you, never with `sudo`, and you
can safely run it again.

## What you need

- **macOS on Apple Silicon** (M1 or later). An Intel Mac works too, but its
  voice packages are installed without pinned versions.
- **About 3 GB free**: about 600 MB of voice and listening models, plus two
  Python environments.
- **A Claude subscription**, because JARVIS's brain is Claude Code running on
  your login. No API key is used.
- **Homebrew.** The script installs everything else.

## 1. One-time preparation

**Homebrew.** If `brew --version` does not work, install it from
https://brew.sh. Then run the two lines its installer prints under
"Next steps" to add `brew` to your PATH.

**Log in to Claude Code.** The setup script installs Claude Code if it is
missing, but you have to log in once yourself:

```bash
claude
```

Log in with your Claude subscription, then type `/exit`.

**GitHub access to the private source**, if this Mac does not have it yet:

```bash
brew install gh
```

```bash
gh auth login
```

## 2. Get the code

```bash
gh repo clone sjhesttv/jarvis ~/jarvis -- --branch jarvis-local-refined
```

```bash
cd ~/jarvis
```

## 3. Optional: your own voice

If you have a trained Piper voice (a `jarvis.onnx` file and its
`jarvis.onnx.json`), copy both into the repository before running setup. The
files must keep exactly those names:

```bash
cp ~/Downloads/jarvis.onnx ~/Downloads/jarvis.onnx.json ~/jarvis/voice_training/voice/
```

You can also skip this and upload the files later in Settings → Voice.
Without one, JARVIS speaks with the built-in Kokoro voice.

## 4. Run the setup

```bash
scripts/setup-mac.sh --name "Your Name"
```

It installs or checks each of these:

- Python 3.12, Node, and the Claude Code CLI.
- JARVIS's Python environment, and the Chromium that Playwright uses.
- The page, built and served by JARVIS himself.
- The local models service: Kokoro (speaking), Whisper (listening) and the
  memory-search model, downloaded once.
- Your Piper voice, if you did step 3.
- Two login items (`com.jarvis.server` and `com.jarvis.ml`), so JARVIS
  starts when you log in and restarts if he stops. Their logs are in
  `~/Library/Logs/JARVIS/`.

If it stops with **"Claude Code is not logged in"**, run `claude`, log in, and
run the script again. It continues from where it stopped.

`scripts/setup-mac.sh --help` lists the options. The useful ones:

| Option | What it does |
|---|---|
| `--restart` | Restart both services (and start one that is not running) |
| `--permissions` | Ask macOS for the two permissions again (see step 6) |
| `--voice <folder>` | Install a Piper voice from another folder |
| `--no-local-models` | Skip the local voice and listening models (you then need a Fish Audio key) |
| `--stt-model base.en` | Use a smaller listening model |
| `--remove-login-items` | Stop both services and stop them starting at login |

## 5. Open him

- **JARVIS:** http://localhost:8340. Any browser works. Click once to
  allow audio, then speak.
- **Dashboard:** http://localhost:8340/dashboard

The first time, your browser asks for the microphone. Allow it for
`localhost:8340`.

## 6. macOS permissions

JARVIS runs as a login item, so macOS gives his permissions to **Python**,
not to Terminal, even though you ran the setup from Terminal. At the end of
setup, macOS shows its own prompt for each permission. In **System Settings →
Privacy & Security**, switch on **Python** in:

- **Accessibility**, so he can answer a permission prompt in Terminal for
  you. On **macOS 27 (Golden Gate)** this list is called **Device Control
  and Data Access**.
- **Screen & System Audio Recording**, so he can look at your screen when
  you ask.

Also allow **Automation** (Terminal, and Chrome if you use it) the first time
he asks.

If Python is not in a list, macOS has not been asked yet. Open JARVIS's
**Settings → Mac permissions** and press **Ask macOS**, or run:

```bash
scripts/setup-mac.sh --permissions
```

That makes macOS add Python to the list, opens the right page in System
Settings, and shows Python in Finder so you can drag it into the list if
needed. You can also add it yourself with the **+** button. To print the path
to add, run:

```bash
~/jarvis/.venv/bin/python -c 'import sys,os;print(os.path.join(sys.base_prefix,"Resources","Python.app"))'
```

After granting Screen Recording, restart JARVIS. Use **Restart JARVIS** in
that Settings section, or run:

```bash
scripts/setup-mac.sh --restart
```

After `brew upgrade python@3.12`, Python's path changes and the permissions
must be granted again.

## 7. Optional: a local brain in LM Studio

JARVIS can think with a model running on your Mac instead of Claude.

1. Install LM Studio **0.4.1 or newer** from https://lmstudio.ai.
2. Download a model that is large enough to use his tools. On a 32 GB Mac,
   **gpt-oss 20B** or **Qwen3 30B A3B Instruct 2507**. Small models (1–4B)
   cannot drive his tools.
3. Load it with a **context length of 64k (65,536) or more**. His
   instructions and tools alone take about 27k tokens, so a 32k window
   leaves almost nothing.
4. Start LM Studio's server: Developer → Start Server (port 1234).
5. In JARVIS, open **Settings → Brain**, choose the model, press **Test**,
   then **Local**.

He switches by himself as well, unless you turn it off there:

- **Fallback.** When Claude's usage limit is reached, or Claude cannot be
  reached, he moves to the local model and back again later.
- **By task.** He moves up to Claude for real work and down to local for
  private chat. If the local model fails, he moves back to Claude and
  answers the same question there.

Coding runs always stay on Claude.

## Day to day

- **Mute:** the microphone button on the voice page closes the microphone
  completely. Mute is remembered across reloads.
- **Restart:**

  ```bash
  scripts/setup-mac.sh --restart
  ```

- **Update to new commits:**

  ```bash
  cd ~/jarvis && git pull && scripts/setup-mac.sh
  ```

- **Logs:** `~/Library/Logs/JARVIS/jarvis.log` (the server) and `ml.log` (the
  voice service). What was said is left out of the logs. To include it for
  debugging, set `JARVIS_LOG_TRANSCRIPTS=1` in `.env`.
- **Shut down:** Settings → **Shut down JARVIS**, pressed twice. This stops
  him and everything he started. He starts again at your next login, or with
  `--restart`.

## Uninstalling

Settings → **Uninstall JARVIS**, at the very bottom, lists everything it will
delete and asks you to type `UNINSTALL`. You can also run it from Terminal:

```bash
~/jarvis/scripts/uninstall-mac.sh
```

It deletes:

- his folder, including `.env` (your keys) and `voice_training/` (your voice);
- his memory, conversation history, runs, files and jobs;
- his models and installed voice (`~/Library/Application Support/JARVIS`);
- his logs, `~/.jarvis`, and both login items;
- `~/Projects/uploads`;
- Claude Code's record of his own conversations.

It keeps your projects, Homebrew, the Claude Code CLI and your login, and LM
Studio. To keep his memory or your voice, export the memory (Settings →
Memory) and copy `voice_training/voice/` somewhere else first.

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| "My language systems are down", or "not logged in" in the log | Claude Code's login has expired. Run `claude` and log in, then `scripts/setup-mac.sh --restart`. |
| He is silent, and the log shows `127.0.0.1:8341 ... All connection attempts failed` | The voice service is not running. Run `scripts/setup-mac.sh --restart`. If that does not help, read `~/Library/Logs/JARVIS/ml.log`. |
| The page loads but he does not hear you | The browser has blocked the microphone for `localhost:8340`. Allow it in the site settings next to the address bar, and check that mute is off. |
| No "Accessibility" setting in Privacy & Security | On macOS 27 it is called **Device Control and Data Access**. |
| Python is not listed under a permission | Settings → Mac permissions → **Ask macOS**, or `scripts/setup-mac.sh --permissions`. |
| "Still starting" for a long time on the local model | The model is loaded with too little context or is too small. Load gpt-oss 20B or Qwen3 30B A3B Instruct 2507 with 64k or more. He moves back to Claude after a minute by himself, or press **Claude** in Settings → Brain. |
| LM Studio says "tokens to keep ... greater than the context length" | Same cause: reload the model in LM Studio with a larger context length. |
| "Can't get application Google Chrome" | Chrome is not installed. Opening pages in a browser uses Chrome or Firefox; he can show the page in a window on his own page instead. |
