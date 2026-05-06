# rename

`rename` is a small filename renaming utility.

By default it behaves like the util-linux style `rename`: it replaces a plain substring in each filename.

It also has a friendly glob-template mode with `-g`, where `*` in the source pattern captures part of the filename and `*` in the target pattern inserts it.

## Usage

```sh
rename [options] FROM TO FILE...
rename -g [options] FROMPAT TOPAT FILE...
```

## Options

```text
-n    dry run; show what would be renamed, but do not rename
-v    verbose output
-a    replace all occurrences of FROM
-l    replace the last occurrence of FROM
-g    glob-template mode
-o    do not overwrite existing target files; this is the default
-f    force overwrite existing target files
```

`-a` and `-l` cannot be used together.

## Default mode: substring replacement

In default mode, `FROM` is not a regular expression. It is a plain substring.

Rename `.jpeg` suffixes to `.jpg`:

```sh
rename .jpeg .jpg *.jpeg
```

Rename `.txt` to `.text`:

```sh
rename .txt .text *.txt
```

Replace the first occurrence only:

```sh
rename foo bar *
```

Example:

```text
foo.txt        -> bar.txt
old-foo.txt    -> old-bar.txt
foo-foo.txt    -> bar-foo.txt
```

Replace all occurrences with `-a`:

```sh
rename -a foo bar *
```

Example:

```text
foo-foo.txt    -> bar-bar.txt
```

Replace only the last occurrence with `-l`:

```sh
rename -l foo bar *
```

Example:

```text
foo-foo.txt    -> foo-bar.txt
```

## Dry run

Use `-n` before doing a large rename:

```sh
rename -n .txt .text *.txt
```

This prints the planned renames without changing files.

Verbose mode can be combined with it:

```sh
rename -n -v .txt .text *.txt
```

## Overwrite behavior

By default, existing target files are not overwritten:

```sh
rename .txt .text *.txt
```

This is equivalent to:

```sh
rename -o .txt .text *.txt
```

To overwrite existing targets, use `-f`:

```sh
rename -f .txt .text *.txt
```

Use `-n` first if you are unsure:

```sh
rename -n -f .txt .text *.txt
```

## Glob-template mode: `-g`

Glob-template mode is intended for friendly filename transformations.

The source pattern may contain one `*`. The `*` captures the changing part of the filename.

The target pattern may also contain one `*`. That `*` is replaced with the captured part.

Rename `.txt` files to `.text`:

```sh
rename -g '*.txt' '*.text' *
```

Example:

```text
notes.txt      -> notes.text
book.txt       -> book.text
a.txt          -> a.text
```

Rename only names beginning with `a`:

```sh
rename -g 'a*.txt' 'a*.text' *
```

Example:

```text
abc.txt        -> abc.text
article.txt    -> article.text
b.txt          unchanged
```

Change a prefix while preserving the captured middle part:

```sh
rename -g 'a*.txt' 'b*.text' *
```

Example:

```text
abc.txt        -> bbc.text
article.txt    -> brticle.text
```

Rename camera images:

```sh
rename -g 'IMG_*.JPG' 'photo-*.jpg' *
```

Example:

```text
IMG_0001.JPG   -> photo-0001.jpg
IMG_0242.JPG   -> photo-0242.jpg
```

Remove a fixed prefix:

```sh
rename -g 'old-*.txt' '*.txt' *
```

Example:

```text
old-report.txt -> report.txt
old-notes.txt  -> notes.txt
```

Add a prefix:

```sh
rename -g '*.txt' 'new-*.txt' *
```

Example:

```text
report.txt     -> new-report.txt
notes.txt      -> new-notes.txt
```

## Important shell quoting note

Quote glob-template patterns.

Correct:

```sh
rename -g '*.txt' '*.text' *
rename -g 'a*.txt' 'a*.text' *
```

Usually wrong:

```sh
rename -g *.txt *.text *
```

Without quotes, the shell expands `*.txt` before `rename` sees it. For example, if the directory contains `a.txt` and `b.txt`, the program may receive `a.txt b.txt` instead of the pattern `*.txt`.

## Difference between glob mode and regular expressions

`-g` mode is not regexp mode.

In shell-style glob patterns:

```text
*.txt
```

means “anything ending in `.txt`”.

In regular expressions, the equivalent would be closer to:

```text
.*\.txt$
```

This program's `-g` mode uses the friendlier glob-template idea, not regexp substitution syntax like `s/pattern/replacement/`.

## Safe workflow

For many files, first run:

```sh
rename -n -g '*.txt' '*.text' *
```

Then, if the output looks correct, run:

```sh
rename -g '*.txt' '*.text' *
```

