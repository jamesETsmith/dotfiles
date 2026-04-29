---
name: self-evolving-skills
description: Use after completing any skill to run a retrospective and update the skill file based on what went well, what did not, and what the user had to re-prompt — reducing friction in future uses.
---

# Self-Evolving Skills

This skill is to help the agent evolve its own skills over time. After we use a skill, the agent should monitor the conversation to see if there are common follow up questions or requests from the users. If there are, we should update the skill to address the most common requests and reduce the need for the user to manually prompt after each use.

## Process

After using a skill, the agent should go through a "retrospective" on the process and evaluate how the skill was used. Use the questions below to guide the retrospective.

## Retrospective Questions

### What went well?
- What parts of the skill worked smoothly without user intervention?
- Which outputs matched or exceeded what the user expected?
- Were there steps that completed faster or more accurately than previous uses?

### What didn't go well?
- Where did the user need to correct, clarify, or re-prompt?
- Were there any errors, misunderstandings, or wasted steps?
- Did the skill produce output that the user ignored or discarded?

### What was confusing or unclear?
- Were there ambiguous instructions in the skill that led to wrong assumptions?
- Did the user ask follow-up questions that the skill should have preemptively addressed?
- Were there missing edge cases or scenarios the skill didn't account for?

### What should we start doing?
- Are there common follow-up requests that should be built into the skill?
- Should additional context or defaults be captured to reduce back-and-forth?
- Are there new patterns or tools that would improve the skill's effectiveness?

### What should we stop doing?
- Are there steps in the skill that consistently get skipped or overridden by the user?
- Is the skill producing unnecessary output or asking redundant questions?
- Are there assumptions baked in that no longer hold true?

### What should we change?
- Should the order of operations be adjusted based on observed usage?
- Do any parameters need different defaults or validation?
- Should the skill be split into smaller skills or merged with another?

## Applying Changes

After completing the retrospective, update the skill file to incorporate improvements. Prioritize changes that reduce user intervention and address the most frequently observed friction points.
