# Batch editing

## Selection

- One file selected: the editor shows that file and every field is editable.
- Several files selected: the header says "N files" and lists their names in a tooltip. Each field is computed across the selection:

| State | When | Shown as |
|---|---|---|
| same | every selected file that supports the field has the same value, including all absent | normal field with the value |
| mixed | values differ | empty field, italic placeholder "Multiple values", info icon whose tooltip lists up to five distinct values with counts |
| partial | the field is not supported by some of the selected files | as same or mixed for the files that support it, plus a hint "not available for N of M files" |

Fields that no selected file supports are hidden. The File group is always present. `name` is hidden when more
than one file is selected.

## Editing

- Typing into a field stages the value for every selected file that supports it. The row gets a pending marker and a revert button.
- A mixed field left untouched changes nothing. Focusing it changes nothing either; only an edit stages a value.
- The info button of a mixed field lists the distinct values with their counts; clicking one applies it to every selected file.
- Clearing a field that had one common value stages removal of the tag. Clearing a mixed field returns it to "Multiple values";
  the separate remove button next to it removes the field from every selected file.
- Cover: a mixed cover shows a stacked placeholder. Dropping or choosing an image sets it for all selected files; Remove removes it from all.
- A staged value can be limited to files where the field is currently empty: "Only where empty", offered per field in the confirmation dialog, off by default.
- Lists (keywords, tags) in a mixed state offer "Add to all" for appending without replacing existing items (planned).
- General fields (title, artist, keywords, ...) are shared across file types: one Keywords row edits ID3, Vorbis, MP4 and XMP keywords alike.

## Unsaved changes

- A file with staged changes shows a dot next to its name in the list and a Modified badge in the header.
- Revert per field, Revert file in the header, Revert all in the File menu.
- Closing the window or quitting with staged changes asks: Save, Discard, Cancel.
- Removing a file from the list with staged changes asks first.

## Saving

- Save (Cmd+S on macOS, Ctrl+S elsewhere) writes the selected files. Save all writes every file with staged changes.
- If the save affects more than one file, a confirmation dialog lists every field with its new value and the number of affected files,
  for example "Genre = Rock, 12 files", with an expandable file list and the per-field "Only where empty" checkbox.
  The primary button says "Change 12 files".
- Writes run one file at a time with a progress indicator; the list stays browsable.
- Each file is re-read after writing. Success clears its staged changes; failure keeps them and shows the error next to the file,
  with Retry and Show details. Other files continue.
- Saving never renames files except through the `name` field, which is single-file only.

## Adding files

- Files and folders come in through the open dialog, drag and drop onto the list or the app icon, or Open With from the file manager.
- Folders are added recursively. Hidden files are skipped. Files of unknown type still appear, with only the File group.
  A file already in the list is not added twice.
- The list keeps insertion order; sorting by name, type, folder or modification date is available (planned).
- The list can be filtered by typing; filtering does not change the selection.
- Select All Files (Shift+Cmd+A) selects every listed file; Delete or Cmd+Backspace removes the selection from the list.
