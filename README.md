# gibim

## What the?

**gibim - Git Bidirectional Mirror**

Generally, mirrors of Git repos are read-only to avoid the madness of syncing
changes in both directions.
But we're completely insane, so we're going to do just that.

This tool is run in a Git repository and does the following:

1. Ensure there are two remotes (and bails if there isn't)

2. Fetch from both remotes

3. For each each branch in each remote,

    1. If the other remote does not have this branch, carry on. Otherwise,

    2. Figure out which version is newer by going through the history of both.
       If the tip of one of the remotes' branch is in the history of the other's,
       this means we can fast forward.
       If not, a manual merge resolution is needed. Let the user know.
       Otherwise,

    3. "Fast forward" the lagging branch with
       `git push <older remote> <newer remote>/<branch>:<branch>`

Note that this is hilariously naïve.
It should automate most of the work, but will require some human intervention.
For example, if you create a branch
delete it from the other so that the tool does not re-add it to the one you just
deleted from.

## How do I build it?

1. [Get a D compiler.](http://dlang.org/download.html)

2. Run `make`.

## How do I run it?

See `gibim --help`

## That's a terrible name.

Yep. Feel free to suggest a better one.

## License

zlib (Use it for whatever but don't claim you wrote it.)
See `LICENSE.md`
