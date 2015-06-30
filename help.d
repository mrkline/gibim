import std.stdio;
import std.c.stdlib : exit;

/// Writes whatever you tell it and then exits the program successfully
void writeAndSucceed(S...)(S toWrite)
{
	writeln(toWrite);
	exit(0);
}

/// Writes the help text and fails.
/// If the user explicitly requests help, we'll succeed (see writeAndSucceed),
/// but if what they give us isn't valid, bail.
void writeAndFail(S...)(S helpText)
{
	stderr.writeln(helpText);
	exit(1);
}

string versionString = q"EOS
gibim 0.1 by Matt Kline, Fluke Networks
EOS";

string helpText = q"EOS
Usage: gibim [--dry-run]

gibim is a Git Bidirectional Mirror - it attempts to keep two Git repositories,
neither of which are read-only, in sync so long as branches in the two don't
diverge.

When run in a Git repository that has two remotes, it will find branches that
trail behind their corresponding versions in the other remote and attempt to
fast-forward them. Branches that only exist on one remote and branches that
exist on both remotes but have diverged are ignored and left to the user.

Options:

  --help, -h
    Display this help text.

  --version
    Display version information.

  --dry-run, -d
    Just display the Git commands that would to sync the remotes instead
    of actually running them.

  --show-unique, -u
    Print a list of branches found on one remote but not on the other.

  --graph, -g
    Display a graph of Git history between corresponding branches on the two
    remotes.

  --verbose, -v
    Print extra info, such as branches that are identical on both remotes and
    which remote is behind the other for branches that can be fast-forwarded.

EOS";
