# Save Behavior Notes

The exact save timing for `Librarian: Tidy Up the Arcane Library!` is still treated as unknown.

The launcher assumes save files can change while the game is running. For that reason, the first version:

- backs up the active save folder before profile switching;
- loads the chosen profile into the active save folder;
- starts the game;
- waits for the game process to exit;
- copies the final active save folder back into the selected profile.

This protects against games that save on exit, level completion, checkpoints, or periodic autosave.
