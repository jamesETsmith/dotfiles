---
name: multiagent-review
description: Use when the user asks for a multi-agent or multi-model review of code, a document, a design, or any artifact — orchestrating 2-3 reviewer models from different families and synthesizing their feedback.
---

# Multi-Agent Review

## Description
This skill is used to facilitate a review of code changes, data, or any arbitrary artifact. When asking for a multiagent review, please pick 2-3 other models of a comparable quality to the one in the current session, preferably from different model families.
For example, if the current model is Claude Opus 4.6, you should pick GPT 5.4, Gemini 3.1 Pro, GLM 5.1, Kimi 2.6, etc.

## Orchestrating the subagents
We want to craft the best product possible, so we need to reviewers to be critical and think antagonistically here.

Ask questions like:
- What are the strongest and weakest parts of the artifact?
- Are there other things we could/should try? Are those critical to making a final decision?
- Separate big picture and detailed concerned. Focus on the big picture first, then get into the details.
- Imagine that every product is being handed to a customer, we want to avoid any mistakes or omissions that would lose their trust. The better product we give them, the more business they give us.
- Ask if we're reviewing a short term fix or a long term one. Cater the critique to the situation. If we're trying to land something quickly, we need to be more lenient with the details. If we're trying to land something long term, we need to be more critical with the details.

## Product of the review

We want to know how the ensemble of reviewers thought about the artifact. Was there consensus? Were there disagreements? What were the key points of disagreement?

Provide a summary of the review in a markdown file.

Provide options for addressing the review comments.

If we're operating in YOLO mode (or ralph wiggum style run), then make check to checkpoint the artifact (e.g. with git if appropriate) before making any changes.
