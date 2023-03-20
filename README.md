# ema
Ema - an abbreviation for Emacs Mindful Assistant. ChatGPT based assistant for Emacs.

## Installation

Install required `request` package. Add `(load "~/path-to-ema/ema.el")` in your `.emacs`. You will need your OpenAI API token to run requests. You can put it in `ema` group settings or read from env variable (by default `OPENAI_API_KEY` but you can change the var name in settings)

## Main usage

Provides following commands:

 * `M-x ema-start-chat` - Asks for a user Prompt, optionally takes selected region and starts a new chat in existing or new temp buffer
 * `M-x ema-insert` - Asks for a user Prompt, optionally takes selected region and queries ChatGPT API, inserts results at point or below the region


## ema-chat-mode major mode

New major mode is introduced based on Markdown mode. In this mode two keybindings are available:

 * `C-c C-c` - sends a new message to the chat
 * `C-c C-r` - automatically renames current chat buffer based on its contents using ChatGPT


## Configuration

Configuration is available through `M-x customize-group ema`


## Arribution

Inspired by https://github.com/CarlQLange/chatgpt-arcana.el Written with the help of ChatGPT :)
