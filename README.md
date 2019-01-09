![Art Institute of Chicago](https://raw.githubusercontent.com/Art-Institute-of-Chicago/template/master/aic-logo.gif)

# aic-bash
> A bash script to query our API for artworks and render them as ASCII art

Just a small side-project we did to show what could be done with our API.

![Screenshot](example.png)


## Requirements

 * A terminal with [truecolor (24bit) support](https://gist.github.com/XVilka/8346728)
 * [Bash v4.2](https://www.tldp.org/LDP/abs/html/bashver4.html#AEN21220) (Feb. 2011) or higher
 * [jq](https://stedolan.github.io/jq/)
 * [jp2a](https://csl.name/jp2a/)

**Not all terminals support truecolor!** See [TrueColor.md](https://gist.github.com/XVilka/8346728) for more information.

New to the command-line life? From testing, we recommend the following:

 * **macOS**: [iTerm2 v3](https://www.iterm2.com/)
 * **Win 10**: [Cmder + WSL](https://conemu.github.io/en/BashOnWindows.html#true-color) (see [Maximus5/ConEmu#920](https://github.com/Maximus5/ConEmu/issues/920))

Note that the default [Terminal.app](https://en.wikipedia.org/wiki/Terminal_(macOS)) which ships with macOS does *not* support truecolor.

Likewise, macOS's default bash is locked to `3.2.57(1)-release` due to licensing issues. Instructions for upgrading:

 * [macos - Update bash to version 4.0 on OSX - Ask Different](https://apple.stackexchange.com/questions/193411/update-bash-to-version-4-0-on-osx)

Lastly, **jq** and **jp2a** must be reachable via `$PATH`. You can install them using a package manager of your choice.

```bash
# macOS with Homebrew
brew install jq jp2a

# Ubuntu with APT
sudo apt-get install jq jp2a
```


## Installation

For now, just clone this repository to wherever you store code on your system:

```bash
git clone git@github.com:art-institute-of-chicago/aic-bash.git
```

If you'd like to run `aic.sh` from anywhere, you can add the repository directory to your `$PATH`:

```bash
# Add this to your ~/.bashrc or equivalent, then open a new terminal instance
export PATH=/path/to/aic-bash:$PATH
```

You can also run `aic.sh` when you start a new terminal session:

```bash
# Add this to your ~/.bashrc or equivalent, then open a new terminal instance
/path/to/aic-bash/aic.sh --quality medium
```

Adjust `quality` to reduce color artifacts or improve performance.


## Usage

```bash
$ ./aic.sh -h
usage: aic.sh [-i id] [-j file] [-n] [query]
  -i, --id <id>         Retrive specific artwork via numeric id.
  -j, --json <path>     Path to JSON file containing a query to run.
  -n, --no-fill         Disable background color fill.
  -q, --quality <enum>  Affects width of image retrieved from server.
                        Reduces color artifacts. Valid options:
                          h, high   = 843x (default)
                          m, medium = 400x
                          l, low    = 200x
  [query]               (Optional) Full-text search string.
```

`aic.sh` has four modes of operation:

 1. Running it without any arguments will return a random public domain oil painting.

 2. Running it with the `-i` or `--id` option will look up a specific artwork by its identifier:

    ```bash
    # Nighthawks by Edward Hopper
    ./aic.sh --id 111628
    ```

 3. Running it with a string argument will perform a full-text search and show the first result:

    ```bash
    # The Bedroom by Vincent Van Gogh
    ./aic.sh bedroom

    # Be sure to use quotes when searching for phrases!
    ./aic.sh "american gothic"
    ```

 4. Running it with `-j` or `--json` will query our API using a query stored in the specified JSON file:

    ```bash
    # Just some example queries we included for reference
    ./aic.sh --json "queries/default-random-asian-art.json"
    ./aic.sh --json "queries/default-random-landscapes.json"
    ```

Under the hood, all of its queries are stored as JSON files in the `./queries` directory.

We treat JSON files as query templates. Before executing a JSON query, we replace the following text:

 * `VAR_FULLTEXT` is replaced by whatever is specified in the `[query]` argument
 * `VAR_NOW` is replaced with the current Unix timestamp
 * `VAR_ID` is replaced by the value of the `--id` option

So if the query supports it, you can combine `--json` with full-text search:

```bash
# Flower Girl in Holland by George Hitchcock
./aic.sh --json "queries/default-fulltext-landscape.json" "holland"
```

If you'd like to write custom queries for use with `--json`, feel free to store them in the `queries` directory. Any file there that doesn't begin with `default-*` will be ignored by version control.
