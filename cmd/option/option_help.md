`nixos option -i` is a tool designed to help search through available options on
a given NixOS system with ease.

## Basic Features

A purple border means that a given window is active. If a window is active, then
its keybinds will work.

The main windows are the:

- Input/Result List Window
- Preview Window
- Help Window (this one)
- Option Value Window

## Help Window

Use the arrow keys or `h`, `j`, `k`, and `l` to scroll around.

`<Esc>` or `q` will close this help window.

## Option Input Window

Type anything into the input box and all available options that match will be
filtered into a list. Scroll this list with the up or down cursor keys, and the
information for that option will show in the option preview window.

`<Tab>` moves to the option preview window.

`<Enter>` previews that option's current value, if it is able to be evaluated.
This will toggle the option value window.

## Option Preview Window

Use the cursor keys or `h`, `j`, `k`, and `l` to scroll around.

The input box is not updated when this window is active.

`<Tab>` will move back to the input window for searching.

`<Enter>` will also evaluate the value, if possible. This will toggle the option
value window.

## Option Value Window

Use the cursor keys or `h`, `j`, `k`, and `l` to scroll around.

`<Esc>` or `q` will close this window.
