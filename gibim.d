module gibim.main;

import std.algorithm;
import std.stdio;
import std.process;
import std.range;
import std.string;
import std.typecons;

import std.c.stdlib : exit;

import help;

bool showUniqueBranches;

int main(string[] args)
{
    import std.getopt;

    bool verbose;
    bool dryRun;
    bool showGraph;

    try {
        getopt(args,
               config.caseSensitive,
               config.bundling,
               "help|h", { writeAndSucceed(helpText); },
               "version", { writeAndSucceed(versionString); },
               "dry-run|d", &dryRun,
               "show-unique|u", &showUniqueBranches,
               "graph|g", &showGraph,
               "verbose|v", &verbose);
    }
    catch (GetOptException ex) {
        writeAndFail(ex.msg, "\n\n", helpText);
    }

    enforceInRepo();
    auto remotes = getRemotes();
    assert(remotes.length == 2);

    auto pairs = getBranchPairs(remotes.front, remotes.back);

    foreach (pair; pairs) {

        // Draw the Git history between the head of the branch on one remote
        // and its head on the other.
        if (showGraph && pair.relation != BranchRelation.Identical)
            writeGraph(pair);

        string newer, older;

        final switch (pair.relation) {
            case BranchRelation.Identical:
                if (verbose)
                    writeln(pair.branchName, " is identical on both remotes");
                continue;

            case BranchRelation.Diverged:
                writeln(pair.branchName, " has diverged on the two remotes.");
                writeln("Please manually merge them.");
                continue;

            case BranchRelation.AIsNewer:
                if (verbose) {
                    writeln(pair.remoteA, " is behind ", pair.remoteB,
                            " for branch ", pair.branchName);
                }
                newer = pair.remoteA;
                older = pair.remoteB;
                break;

            case BranchRelation.BIsNewer:
                if (verbose) {
                    writeln(pair.remoteB, " is behind ", pair.remoteA,
                            " for branch ", pair.branchName);
                }
                newer = pair.remoteB;
                older = pair.remoteA;
                break;
        }

        assert(newer !is null);
        assert(older !is null);

        string pushCommand = buildPushCommand(pair.branchName, newer, older);

        if (dryRun) {
            writeln("To update ", older, " to ", newer, ", ", pushCommand);
        }
        else {
            writeln("Running ", pushCommand);
            auto pid = spawnProcess(pushCommand.split());
            wait(pid);
            writeln();
        }
    }

    return 0;
}

void writeGraph(const ref BranchPair pair)
{
    string fullAName = reinsertRemoteName(pair.remoteA, pair.branchName);
    string fullBName = reinsertRemoteName(pair.remoteB, pair.branchName);

    // Find the shortened SHAs

    auto shaRun = execute(["git", "rev-parse", "--short", fullAName]);
    if (shaRun.status != 0) {
        stderr.writeln("Couldn't get the SHA of ",
                       fullAName,
                       " to draw graph");
        return;
    }

    auto shaA = shaRun.output.strip();

    shaRun = execute(["git", "rev-parse", "--short", fullBName]);
    if (shaRun.status != 0) {
        stderr.writeln("Couldn't get the SHA of ",
                       fullBName,
                       " to draw graph");
        return;
    }

    auto shaB = shaRun.output.strip();

    writeln("Differing commits for ", pair.branchName, ":");
    auto graphProcess = pipeProcess(
        ["git", "log", "--graph", "--oneline",
         "--decorate", "--color=always", shaA, shaB],
        Redirect.stdout);
    // We want to kill the process when we leave this scope
    // since we likely won't run it to completion.
    scope (exit) { kill(graphProcess.pid); wait(graphProcess.pid); }

    auto graphLines = graphProcess.stdout.byLine();

    // Keep going until we see both SHAs
    bool sawA, sawB;

    do {
        sawA |= graphLines.front.canFind(shaA);
        sawB |= graphLines.front.canFind(shaB);

        writeln(graphLines.front);
        graphLines.popFront();
    } while (!sawA || !sawB);
}

/// Takes a branch name string and strips the remote off the front
string stripRemoteFromBranch(string branch) pure
{
    return branch[branch.indexOf('/') + 1 .. $];
}

// Opposite of above
string reinsertRemoteName(string remote, string branch) pure
{
    return remote ~ '/' ~ branch;
}

/// Builds a Git command to push "from"'s version of "branch" to "to"
string buildPushCommand(string branch, string from, string to) pure
{
    return "git push " ~ to ~ " " ~
        reinsertRemoteName(from, branch) ~ ":" ~ branch;
}


/// We need to make sure we're in a git repo before the fun begins
void enforceInRepo()
{
    // Run a fairly arbitrary Git command.
    auto rootFinder = execute(["git", "rev-parse", "--show-toplevel"]);

    // If it fails, we're not in a repo.
    if (rootFinder.status != 0 || rootFinder.output.strip().empty) {
        writeAndFail("Not in a Git repo");
    }
}

/// We need two remotes. No less, no more.
auto getRemotes()
{
    // List the remotes
    auto remoteFinder = execute(["git", "remote"]);

    // We should have two of them
    immutable lineCount = remoteFinder.output
        .filter!(c => c == '\n')
        .map!(c => 1).sum();

    if (remoteFinder.status != 0 || lineCount != 2) {
        writeAndFail("The repo must have exactly two remotes (has ", lineCount, ")");
    }

    // Pull out the first (and only) two
    auto lines = splitter(remoteFinder.output, '\n');
    return lines.takeExactly(2).array;
}

/// Returns a range of branches that are on both remotes
auto findCommonBranches()
{
    // -r lists remote branches
    auto remoteBranchFinder = pipeProcess(["git", "branch", "-r"], Redirect.stdout);
    // Make sure the process dies with us
    scope (failure) kill(remoteBranchFinder.pid);
    scope (exit) wait(remoteBranchFinder.pid);

    // We'll keep track of branches we've seen twice with this map.
    // When we first see a branch, we'll put its full name (with remote)
    // in the map as the value with the shared name (without remote) as the key.
    // Then, if we see the same branch on the other remote, we'll null the value.
    // The reason we use this wonky scheme instead of a bool as the value
    // is so that we can hold onto the full names for when showUniqueBranches
    // is true.
    string[string] commonMap;

    auto remoteBranches = remoteBranchFinder.stdout
        .byLine()
        // Filter out tracking branches (e.g. origin/HEAD -> origin/something)
        .filter!(b => !b.canFind("->"))
        // git branch -r puts whitespace on the left. Strip that.
        .map!(b => stripLeft(b));

    foreach(branch; remoteBranches) {

        // The idup (immutable duplicate) is because byLine() returns char[],
        // and map keys must be immutable, so we need an immutable char[]
        // (i.e. string)
        string fullName = branch.idup;

        string nameWithoutRemote = stripRemoteFromBranch(fullName);

        string* inMap = nameWithoutRemote in commonMap; // map lookup

        if (inMap) // If the map contains the branch, mark that we found it twice.
            *inMap = null;
        else // Otherwise store the full (unstripped) branch name
            commonMap[nameWithoutRemote] = fullName;
    }

    if (showUniqueBranches) {
        auto uniqueBranches = commonMap.byKeyValue()
            // See commonMap comment
            .filter!(p => p.value !is null)
            .map!(p => p.value);

        writeln("Branches unique to one remote:");

        foreach (unique; uniqueBranches)
            writeln(unique);

        writeln();
    }

    return commonMap.byKeyValue()
        // Filter out branch names which were not seen twice
        .filter!(p => p.value is null)
        // Get the branch name, discard the bool
        .map!(p => p.key);
}

enum BranchRelation {
    AIsNewer,
    BIsNewer,
    Diverged,
    Identical
}

struct BranchPair {
    string branchName;
    BranchRelation relation;

    // We probably don't need to keep carrying around copies of the remote names,
    // but it arguably makes life easier, is just a pair of pointers for each,
    // and makes clear what the relation means when it refers to "A" and "B".
    string remoteA;
    string remoteB;
}

BranchPair relateBranches(string branchName, string remoteA, string remoteB)
{
    BranchPair ret;
    ret.branchName = branchName;
    ret.remoteA = remoteA;
    ret.remoteB = remoteB;

    // To find how branches relate to each other, we'll run "git rev-list"
    // (basically "git log" with just the SHAs) and look for the head of one
    // in the history of the other.

    auto runAProcess = pipeProcess(
        ["git", "rev-list", reinsertRemoteName(remoteA, branchName)],
        Redirect.stdout);
    scope(exit) { kill(runAProcess.pid); wait(runAProcess.pid); }

    auto runBProcess = pipeProcess(
        ["git", "rev-list", reinsertRemoteName(remoteB, branchName)],
        Redirect.stdout);
    scope(exit) { kill(runBProcess.pid); wait(runBProcess.pid); }

    auto logA = runAProcess.stdout.byLine();
    auto logB = runBProcess.stdout.byLine();

    string tipA = logA.front.idup;
    string tipB = logB.front.idup;

    // If both branches have the same head, they're identical.
    if (tipA == tipB) {
        ret.relation = BranchRelation.Identical;
        return ret;
    }

    foreach (e; zip(StoppingPolicy.longest, logA, logB)) {
        // If the current commit in log B is the tip of A,
        // A is an ancestor of B
        if (tipA == e[1]) {
            ret.relation = BranchRelation.BIsNewer;
            return ret;
        }

        // If the current commit in log A is the tip of B,
        // B is an ancestor of A
        if (tipB == e[0]) {
            ret.relation = BranchRelation.AIsNewer;
            return ret;
        }
    }

    // One is not the ancestor of the other - these branches have diverged
    ret.relation = BranchRelation.Diverged;
    return ret;
}

/// Returns a range of branch pairs indicating common branches between the two
/// remotes and their relation to each other
auto getBranchPairs(string remoteA, string remoteB)
{
    return findCommonBranches()
        .map!(b => relateBranches(b, remoteA, remoteB));
}
