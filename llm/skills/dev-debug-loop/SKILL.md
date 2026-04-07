# Dev Debug Loop

## Description
This skill used to incrementally build and tests a new feature or fix. It acts like a local CI for agent/user and make code changes, checks them against the tests, checks in the code to git, moves on to the next change, and repeats until complete.

## When to Use
- Use when the user asks wants to implement a new feature or fix a bug and track tests along the way.

## Instructions
Detailed instructions for the AI on how to execute this skill:

1. Establish the plan for the feature or fix.
2. Decide on the tests we want to verify the feature or fix. This should usually be the whole test suite unless the user specifies otherwise. Save the output of the tests to a file and collect a summary of the tests that are easy to compare from run to run.
3. Check the code into git. If you're not on a feature branch, create one and check it out.
4. Make incremental changes to the code (if the changes in the plan are small you can make them all at once of course). But for larger changes, break them up accordingly.
5. Re-run the tests and compare the results to the previous run. If the results are the same, move on to the next change. If the results are different, go back and fix the code.
6. Repeat 3-5 until the feature or fix is complete.

At the end of this process the agent should produce a report markdown file with the following sections:
- A summary of the feature or fix
- A summary of the tests that were run and the results
- A link to the full test output for reference
- If it couldn't achieve the goal, report what it tried and what didn't work.
-
