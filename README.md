# Input Monitor Overlay

A small, lightweight overlay for WoW: Forever that shows every key and mouse button you press, in order, with the time between presses. Made for recording clips, testing keybinds and addons, and showing exactly what you pressed.

Type **/imo** to open it, and **/imo** again (or the x) to close it. While closed it listens to nothing.

## Features

- **Two layouts, picked by where you drag it** - near the top or bottom of the screen it shows a list of rows; near the left or right edge it turns into a slim "/imo" tab with keys running sideways.
- **List mode** - each press on its own line, with what the key is bound to, the time since the last press and the clock time.
- **Key mode** - each press as its own keycap: wide keys for Space, Enter, Ctrl, Alt and Tab, arrow pictures for Shift, Backspace and the arrow keys, and a Windows key. Mouse clicks show as a mouse with the pressed button lit, including the middle button, side buttons 4 and 5, and the scroll wheel.
- **Held modifiers** - shown above the key they were held with.
- **Timings** - the time since the previous press, in alternating shades so neighbours are easy to tell apart.
- **Sort order** - new presses next to the bar, or at the far end like a chat log.
- **Grows and shrinks** - the panel grows instantly for each press and eases away as presses fade.

## Controls

- **Left-drag** - move it. It snaps to screen edges and picks its layout from the edge you bring it to.
- **Right-click** - the menu, where every setting lives.
- **Click the light** - pause or resume recording (red while paused).
- **Arrow button** - left-click switches the side the list grows from, right-click switches old/new order.
- **Lock** - unlock to show an outline with a resize grip for the width and number of lines or keys.

## Settings

- **Lines / Keys** - how many presses show, kept separately for list mode and key mode.
- **Life / Fade** - how long a press stays, and how long it takes to fade.
- **Key bindings / Clock time** - extra details in list mode.
- **Layer** - which of the game's drawing layers it sits in.

## Credits

- **Font** - [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono), SIL Open Font License 1.1.

## License

MIT
