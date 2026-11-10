(* prcheck_tests -- the tests of bats prcheck (bats-lang/bats#424; keyword: prcheck tests) *)

#include "share/atspre_staload.hats"

staload "prcheck.sats"

(* ------------------------------------------------------------------ *)
(* Tests (keyword: prcheck tests): one rejecting fixture for each check and the accepting ones; each runs the checks over a diff, a body
   and a ticket held in memory, with the check it tests the only one on, and answers the checks that found something. The
   fixtures of checks 6 and 9 read a file of the working tree, which the test writes under build/prcheck-tests first. They are in
   a module of their own, which does not staload helpers.sats (see prcheck.bats). *)

$UNITTEST.run begin

fn run_fixture {a,b,c:nat | a < 4096; b < 4096; c < 4096}
  (diff: string a, body: string b, ticket: string c, checks: int): int =
  prcheck_fixture(diff, body, ticket, checks, false)

fn plant {d,p,t:nat | p < 4096} (dir: string d, path: string p, text: string t): bool =
  prcheck_plant(dir, path, text)

val ticket_ok = "# T\n\n## Done when\n\n1. COMMAND: `bats test` runs\n2. MEASURE: the share is 25%\n"
val body_ok = "Fixes #3\n\n## Done when results\n\n1. a\n2. b\n"
val diff_ok = "diff --git a/src/x.bats b/src/x.bats\n--- a/src/x.bats\n+++ b/src/x.bats\n@@ -1,0 +2,2 @@\n+(* a fine comment (keyword: x) *)\n+val x = 1\n"

val diff_pins = "diff --git a/build/prcheck-tests/.github/workflows/unpinned.yml b/build/prcheck-tests/.github/workflows/unpinned.yml\nnew file mode 100644\n--- /dev/null\n+++ b/build/prcheck-tests/.github/workflows/unpinned.yml\n@@ -0,0 +1 @@\n+name: x\n"

(* The accepting fixture: every check that needs no file of the working tree is on, and none finds anything *)
fn test_accepting (): bool = run_fixture(diff_ok, body_ok, ticket_ok, 1470) = 0

(* Check 1: a comment of more than one line *)
fn test_check_1_comment_over_lines (): bool =
  run_fixture("diff --git a/src/x.bats b/src/x.bats\n@@ -1,0 +2 @@\n+(* a comment that goes\n", body_ok, ticket_ok, 2) = 2

(* Check 1: a closed comment over the width is rejected, and one of exactly the width is not *)
fn test_check_1_comment_over_width (): bool =
  run_fixture("diff --git a/src/x.bats b/src/x.bats\n@@ -1,0 +2 @@\n+(* aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa *)\n", body_ok, ticket_ok, 2) = 2

fn test_check_1_comment_at_width_accepted (): bool =
  run_fixture("diff --git a/src/x.bats b/src/x.bats\n@@ -1,0 +2 @@\n+(* aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa *)\n", body_ok, ticket_ok, 2) = 0

(* Check 2: a date and a verdict opener in a comment *)
fn test_check_2_status_word (): bool =
  run_fixture("diff --git a/src/x.bats b/src/x.bats\n@@ -1,0 +2 @@\n+(* Flake: it failed on 2026-11-09 *)\n", body_ok, ticket_ok, 4) = 4

(* Check 2: the verdict opener alone (no date, run id or status word) is rejected, and the word Flake not as the opener is not *)
fn test_check_2_verdict_opener (): bool =
  run_fixture("diff --git a/src/x.bats b/src/x.bats\n@@ -1,0 +2 @@\n+(* Flake: the harness *)\n", body_ok, ticket_ok, 4) = 4

fn test_check_2_flake_not_opener_accepted (): bool =
  run_fixture("diff --git a/src/x.bats b/src/x.bats\n@@ -1,0 +2 @@\n+(* the harness has a Flake in it *)\n", body_ok, ticket_ok, 4) = 0

(* Check 2: a run id and a status word in a comment *)
fn test_check_2_run_id (): bool =
  run_fixture("diff --git a/src/x.bats b/src/x.bats\n@@ -1,0 +2 @@\n+(* it passed on run 1234567 *)\n", body_ok, ticket_ok, 4) = 4

fn test_check_2_status_word_currently (): bool =
  run_fixture("diff --git a/src/x.bats b/src/x.bats\n@@ -1,0 +2 @@\n+(* this is currently off *)\n", body_ok, ticket_ok, 4) = 4

(* Check 3: a comment that names a section of CLAUDE.md *)
fn test_check_3_names_a_place (): bool =
  run_fixture("diff --git a/src/x.bats b/src/x.bats\n@@ -1,0 +2 @@\n+(* see the section of CLAUDE.md *)\n", body_ok, ticket_ok, 8) = 8

(* Check 3: below that points (the nearest to the accepted form) is rejected, below that says where a thing is is not *)
fn test_check_3_pointer_below_rejected (): bool =
  run_fixture("diff --git a/src/x.bats b/src/x.bats\n@@ -1,0 +2 @@\n+(* the lock is taken below. *)\n", body_ok, ticket_ok, 8) = 8

fn test_check_3_place_below_accepted (): bool =
  run_fixture("diff --git a/src/x.bats b/src/x.bats\n@@ -1,0 +2 @@\n+(* the strip lies below the handles *)\n", body_ok, ticket_ok, 8) = 0

(* Check 3 with --resolve: an injected resolver answers not found (rejected) or found (accepted) for the #<n> of a comment *)
fn test_check_3_unresolved_issue_rejected (): bool =
  prcheck_fixture_resolved("diff --git a/src/x.bats b/src/x.bats\n@@ -1,0 +2 @@\n+(* the cause is #12 *)\n", body_ok, ticket_ok, 8, false) = 8

fn test_check_3_resolved_issue_accepted (): bool =
  prcheck_fixture_resolved("diff --git a/src/x.bats b/src/x.bats\n@@ -1,0 +2 @@\n+(* the cause is #12 *)\n", body_ok, ticket_ok, 8, true) = 0

(* Check 7 reads JavaScript and TypeScript tests: a Python checker that names waitForTimeout is not a test that sleeps *)
fn test_check_7_python_checker_accepted (): bool =
  run_fixture("diff --git a/tests/static/waits.py b/tests/static/waits.py\n@@ -1,0 +2 @@\n+NAME = \"waitForTimeout\"\n", "Exhausted: none\nFixes #1\n", ticket_ok, 128) = 0

fn test_check_7_wait_for_timeout_rejected (): bool =
  run_fixture("diff --git a/e2e/a.spec.ts b/e2e/a.spec.ts\n@@ -0,0 +1 @@\n+  await page.waitForTimeout(500);\n", body_ok, ticket_ok, 128) = 128

(* Check 4: a new shell script without the body's Exhausted: line, and the same with it *)
fn test_check_4_shell_of_ours (): bool =
  run_fixture("diff --git a/scripts/x.sh b/scripts/x.sh\nnew file mode 100755\n@@ -0,0 +1 @@\n+echo hi\n", body_ok, ticket_ok, 16) = 16

fn test_check_4_exhausted_allows (): bool =
  run_fixture("diff --git a/scripts/x.sh b/scripts/x.sh\nnew file mode 100755\n@@ -0,0 +1 @@\n+echo hi\n",
    "Fixes #3\nExhausted: the bats process package has no pipe\n", ticket_ok, 16) = 0

(* Check 4: sed in a workflow file *)
fn test_check_4_sed_in_workflow (): bool =
  run_fixture("diff --git a/.github/workflows/x.yml b/.github/workflows/x.yml\n@@ -0,0 +1 @@\n+      - run: sed -i s/a/b/ f\n", body_ok, ticket_ok, 16) = 16

(* Check 5: a symlink added *)
fn test_check_5_symlink (): bool =
  run_fixture("diff --git a/link b/link\nnew file mode 120000\n@@ -0,0 +1 @@\n+target\n", body_ok, ticket_ok, 32) = 32

(* Check 6: a workflow file with a runner and an action that move, and one that does not *)
fn test_check_6_floating_pins (): bool =
  plant("build/prcheck-tests/.github/workflows", "build/prcheck-tests/.github/workflows/unpinned.yml",
    "name: x\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n")
  && run_fixture(diff_pins, body_ok, ticket_ok, 64) = 64

fn test_check_6_pinned_accepted (): bool =
  plant("build/prcheck-tests/.github/workflows", "build/prcheck-tests/.github/workflows/unpinned.yml",
    "name: x\non: push\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2\n")
  && run_fixture(diff_pins, body_ok, ticket_ok, 64) = 0

(* Check 7: an expect of a literal in a test *)
fn test_check_7_assertion_of_a_literal (): bool =
  run_fixture("diff --git a/e2e/a.spec.ts b/e2e/a.spec.ts\n@@ -0,0 +1 @@\n+  expect(true).toBe(true);\n", body_ok, ticket_ok, 128) = 128

fn test_check_7_expect_of_a_value_accepted (): bool =
  run_fixture("diff --git a/e2e/a.spec.ts b/e2e/a.spec.ts\n@@ -0,0 +1 @@\n+  expect(await page.title()).toBe('x');\n", body_ok, ticket_ok, 128) = 0

(* Check 7: a fixed duration bound in a test *)
fn test_check_7_fixed_duration (): bool =
  run_fixture("diff --git a/e2e/a.spec.ts b/e2e/a.spec.ts\n@@ -0,0 +1 @@\n+  expect(Date.now() - start).toBeLessThan(500);\n", body_ok, ticket_ok, 128) = 128

(* Check 8: a body with no closing line, and one with only Refs *)
fn test_check_8_no_closing_line (): bool = run_fixture(diff_ok, "Some text\n", ticket_ok, 256) = 256

fn test_check_8_refs_never_close (): bool = run_fixture(diff_ok, "Refs #3\n", ticket_ok, 256) = 256

fn test_check_8_relock_branch_exempt (): bool =
  prcheck_fixture(diff_ok, "The daily relock\n", ticket_ok, 256, true) = 0

fn test_check_8_no_ticket_line_accepted (): bool = run_fixture(diff_ok, "No ticket: a typo\n", ticket_ok, 256) = 0

(* Check 9: a line a diff adds to a rule file that names a file its paths: do not cover, one whose paths: do, and older text *)
fn test_check_9_uncovered_path (): bool =
  plant("build/prcheck-tests/.claude/rules", "build/prcheck-tests/.claude/rules/uncovered.md",
    "---\npaths:\n  - src/prcheck.bats\n---\n\nIt reads `src/prcheck.bats` and `scripts/other.sh`.\n")
  && run_fixture("diff --git a/build/prcheck-tests/.claude/rules/uncovered.md b/build/prcheck-tests/.claude/rules/uncovered.md\n@@ -0,0 +1 @@\n+It reads `scripts/other.sh`.\n",
    body_ok, ticket_ok, 512) = 512

fn test_check_9_covered_accepted (): bool =
  plant("build/prcheck-tests/.claude/rules", "build/prcheck-tests/.claude/rules/uncovered.md",
    "---\npaths:\n  - src/prcheck.bats\n  - tests/prcheck/**\n---\n\nIt reads `src/prcheck.bats` and `tests/prcheck/run.sh`.\n")
  && run_fixture("diff --git a/build/prcheck-tests/.claude/rules/uncovered.md b/build/prcheck-tests/.claude/rules/uncovered.md\n@@ -0,0 +1 @@\n+It reads `tests/prcheck/run.sh`.\n",
    body_ok, ticket_ok, 512) = 0

fn test_check_9_older_text_not_charged (): bool =
  plant("build/prcheck-tests/.claude/rules", "build/prcheck-tests/.claude/rules/uncovered.md",
    "---\npaths:\n  - src/prcheck.bats\n---\n\nOlder text reads `scripts/other.sh`.\nA new line.\n")
  && run_fixture("diff --git a/build/prcheck-tests/.claude/rules/uncovered.md b/build/prcheck-tests/.claude/rules/uncovered.md\n@@ -7,0 +8 @@\n+A new line.\n",
    body_ok, ticket_ok, 512) = 0

(* Check 10: a Done when line that is no one of the four forms, and a body without a row for each line *)
fn test_check_10_line_of_no_form (): bool =
  run_fixture(diff_ok, body_ok, "## Done when\n\n1. it works\n", 1024) = 1024

fn test_check_10_fewer_rows (): bool =
  run_fixture(diff_ok, "Fixes #3\n\n## Done when results\n\n1. a\n", ticket_ok, 1024) = 1024

fn test_check_10_no_done_when (): bool = run_fixture(diff_ok, body_ok, "# T\n\nbody\n", 1024) = 1024

(* --checklist (keyword: prcheck checklist): the line of each check is its rule, the text its finding uses; a subset prints only
   its lines (exit 0); an unknown number and a file option given with --checklist are exit 2 *)
fn test_checklist_rule_1 (): bool =
  prcheck_rule_is(1, "a comment goes on over more than one line: it is one line with its keyword")

fn test_checklist_rule_2 (): bool =
  prcheck_rule_is(2, "a comment states the status of the code: it says what is true, in one line, with its keyword")

fn test_checklist_rule_3 (): bool =
  prcheck_rule_is(3, "a comment names no CLAUDE.md, rule file, section or place above or below: it carries its reason and a keyword")

fn test_checklist_rule_4 (): bool =
  prcheck_rule_is(4, "code of ours that is not bats (a script, sed or awk) needs a line Exhausted: <avenue> in the pull request body")

fn test_checklist_rule_5 (): bool = prcheck_rule_is(5, "a symlink escapes the checkout and the review: none is added")

fn test_checklist_rule_6 (): bool =
  prcheck_rule_is(6, "a workflow or action file has no floating pin (a runner, action or version that moves): check-pins reads it")

fn test_checklist_rule_7 (): bool =
  prcheck_rule_is(7, "a test asserts no literal, sleeps for no fixed time and bounds no duration with a number")

fn test_checklist_rule_8 (): bool =
  prcheck_rule_is(8, "This PR closes no ticket. Either it is not finished (finish it on this PR), or the ticket should be broken up first: file the pieces as tickets, then this PR fixes one of them. The body needs a line Fixes #<n>, or No ticket: <reason>.")

fn test_checklist_rule_9 (): bool =
  prcheck_rule_is(9, "the paths: of a rule file cover every file its added text names")

fn test_checklist_rule_10 (): bool =
  prcheck_rule_is(10, "each line of the ticket's Done when is a COMMAND:, MEASURE:, TEST: or SEARCH: line, and the body has a row in ## Done when results for each")

(* The nearest wrong text is not the rule: the rule of check 5 with its last word cut *)
fn test_checklist_rule_not_a_prefix (): bool =
  ~prcheck_rule_is(5, "a symlink escapes the checkout and the review: none is")

fn test_checklist_all_checks_exit_0 (): bool = prcheck_checklist_fixture(2046, false) = 0

fn test_checklist_subset_exit_0 (): bool = prcheck_checklist_fixture(10, false) = 0

fn test_checklist_unknown_number (): bool = prcheck_checks_fixture("1 2 11") = ~1

fn test_checklist_known_numbers (): bool = prcheck_checks_fixture("1 2 3 4 5 6 7 8 9 10") = 2046

fn test_checklist_with_diff (): bool = prcheck_checklist_fixture(2046, true) = 2

fn test_checklist_no_check_on (): bool = prcheck_checklist_fixture(0, false) = 2

(* --review (keyword: prcheck review): checks 1, 2 and 5 are on (mask 38); a complete review exits 0, any other exits 1 *)

fn test_review_every_line_exit_0 (): bool =
  prcheck_review_fixture("Reviewer: claude-opus-4\nCost: 41000 tokens, 6 minutes\n\n1. a comment goes on over more than one line: it is one line with its keyword: checked, ok\n2. a comment states the status of the code: it says what is true, in one line, with its keyword: checked, ok\n5. a symlink escapes the checkout and the review: none is added: checked, ok\n", 38) = 0

fn test_review_line_missing_exit_1 (): bool =
  prcheck_review_fixture("Reviewer: claude-opus-4\nCost: 41000 tokens, 6 minutes\n\n1. a comment goes on over more than one line: it is one line with its keyword: checked, ok\n5. a symlink escapes the checkout and the review: none is added: checked, ok\n", 38) = 1

fn test_review_finding_exit_1 (): bool =
  prcheck_review_fixture("Reviewer: claude-opus-4\nCost: 41000 tokens, 6 minutes\n\n1. a comment goes on over more than one line: it is one line with its keyword: checked, ok\n2. a comment states the status of the code: it says what is true, in one line, with its keyword: src/x.bats:5 states a date\n5. a symlink escapes the checkout and the review: none is added: checked, ok\n", 38) = 1

fn test_review_stale_list_exit_1 (): bool =
  prcheck_review_fixture("Reviewer: claude-opus-4\nCost: 41000 tokens, 6 minutes\n\n1. a comment goes on over more than one line: it is one line with its keyword: checked, ok\n2. a comment states a date or a run: checked, ok\n5. a symlink escapes the checkout and the review: none is added: checked, ok\n", 38) = 1

(* The nearest wrong forms: no Reviewer: line, no Cost: line, ok with a full stop, the line of check 10 for check 1 *)
fn test_review_no_reviewer_exit_1 (): bool =
  prcheck_review_fixture("Cost: 1 minute\n1. a comment goes on over more than one line: it is one line with its keyword: checked, ok\n", 2) = 1

fn test_review_no_cost_exit_1 (): bool =
  prcheck_review_fixture("Reviewer: claude-opus-4\n1. a comment goes on over more than one line: it is one line with its keyword: checked, ok\n", 2) = 1

fn test_review_ok_with_full_stop_exit_1 (): bool =
  prcheck_review_fixture("Reviewer: m\nCost: 1\n1. a comment goes on over more than one line: it is one line with its keyword: checked, ok.\n", 2) = 1

fn test_review_line_of_check_10_is_not_check_1 (): bool =
  prcheck_review_fixture("Reviewer: m\nCost: 1\n10. a comment goes on over more than one line: it is one line with its keyword: checked, ok\n", 2) = 1

fn test_review_trailing_blank_exit_0 (): bool =
  prcheck_review_fixture("Reviewer: m\nCost: 1\n1. a comment goes on over more than one line: it is one line with its keyword: checked, ok  \r\n", 2) = 0

end
