module gibim.main;

import std.algorithm;
import std.stdio;
import std.process;
import std.range;
import std.string;
import std.typecons;

import std.c.stdlib : exit;

/// We need to make sure we're in a git repo before the fun begins
void enforceInRepo()
{
    // Run a fairly arbitrary Git command.
    auto rootFinder = execute(["git", "rev-parse", "--show-toplevel"]);

    // If it fails, we're not in a repo.
    if (rootFinder.status != 0 || rootFinder.output.strip().empty) {
        stderr.writeln("Not in a Git repo");
        exit(1);
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
        stderr.writeln("The repo must have exactly two remotes (has ", lineCount, ")");
        exit(1);
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

    // We'll keep track of branches we've seen
    bool[string] commonMap;

    foreach(branch; remoteBranchFinder.stdout.byLine()) {
        // Strip "remote/" from the front of the branch name
        string nameWithoutRemote = branch[branch.indexOf('/') + 1 .. $].idup;

        bool* inMap = nameWithoutRemote in commonMap; // map lookup

        if (inMap) // If the map contains the branch, mark that we found it twice.
            *inMap = true;
        else // Otherwise create an entry in the map.
            commonMap[nameWithoutRemote] = false;
    }

    return commonMap.byKeyValue()
        // Filter out branch names which were not seen twice
        .filter!(p => p.value == true)
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
    string a;
    string b;
    BranchRelation relation;
}

BranchPair relateBranches(string branchA, string branchB)
{
    BranchPair ret;
    ret.a = branchA;
    ret.b = branchB;

    auto runAProcess = pipeProcess(["git", "rev-list", branchA], Redirect.stdout);
    scope(exit) { kill(runAProcess.pid); wait(runAProcess.pid); }

    auto runBProcess = pipeProcess(["git", "rev-list", branchB], Redirect.stdout);
    scope(exit) { kill(runBProcess.pid); wait(runBProcess.pid); }

    auto logA = runAProcess.stdout.byLine();
    auto logB = runBProcess.stdout.byLine();

    string tipA = logA.front.idup;
    string tipB = logB.front.idup;

    // If both branches have the same HEAD, they're identical.
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
/// remotes and their 
auto getBranchPairs(string remoteA, string remoteB)
{
    static pure string reinsertRemoteName(string branch, string remote) {
        return remote ~ '/' ~ branch;
    }

    return findCommonBranches()
        .map!(b => relateBranches(reinsertRemoteName(b, remoteA),
                                  reinsertRemoteName(b, remoteB)));
}

int main()
{

    enforceInRepo();
    auto remotes = getRemotes();
    assert(remotes.length == 2);

    auto pairs = getBranchPairs(remotes.front, remotes.back);
    foreach (pair; pairs) {
        final switch (pair.relation) {
            case BranchRelation.Identical:
                writeln(pair.a, " and ", pair.b, " are identical");
                break;

            case BranchRelation.Diverged:
                writeln(pair.a, " and ", pair.b, " have diverged");
                break;

            case BranchRelation.AIsNewer:
                writeln(pair.a, " is newer than ", pair.b);
                break;

            case BranchRelation.BIsNewer:
                writeln(pair.b, " is newer than ", pair.a);
                break;
        }
    }

    return 0;
}
