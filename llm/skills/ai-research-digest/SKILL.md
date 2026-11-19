---
name: ai-research-digest
description: Summarize the latest posts from tracked AI research and inference-engineering blogs (Hazy Research, vLLM, Liquid AI, Wafer, Qwen, MiniMax, Thinking Machines, Together AI, Base Labs, LMCache, llm-d, Fireworks AI) in a fixed digest format focused on performance and algorithmic changes. Use when the user asks for a research digest, what is new on AI research blogs, a daily or weekly roundup of AI blog posts, or a summary of recent posts from any of these sources.
---

# AI Research Digest

Builds a digest of recent posts from a fixed list of AI research blogs. It focuses on
**performance changes** (throughput, latency, memory, cost, kernels, serving systems) and
**algorithmic changes** (architectures, training and RL methods, decoding, quantization).
Every run uses the same output format (see [Output format](#output-format)) so digests can be
compared from one day to the next.

## Scope

Cover only these 13 sources. Do not use web search, arXiv listings, Hugging Face papers, news
sites, or any other source to find posts. If the scripts cannot run, fetch the homepages below
directly and report failures in Source status; never substitute a general search.

| Source | Homepage |
|---|---|
| Hazy Research | https://hazyresearch.stanford.edu/blog |
| vLLM | https://vllm.ai/blog |
| Liquid AI Engineering | https://www.liquid.ai/engineering |
| Liquid AI Research | https://www.liquid.ai/research |
| Wafer | https://www.wafer.ai/blog |
| Qwen | https://qwen.ai/research |
| MiniMax | https://www.minimax.io/blog |
| Thinking Machines | https://thinkingmachines.ai/blog/ |
| Together AI | https://www.together.ai/blog (feed: https://www.together.ai/blog/rss.xml) |
| Base Labs (Baseten) | https://labs.baseten.co/articles |
| LMCache | https://blog.lmcache.ai/en/ |
| llm-d | https://llm-d.ai/blog |
| Fireworks AI | https://fireworks.ai/research |

`sources.json` is the machine-readable copy of this list; keep the two in sync. The only arXiv
links that belong in a digest are Liquid AI Research publications whose listing entry points to
arXiv.

## Files

| Path | Purpose |
|---|---|
| `sources.json` | The tracked blogs and how to list their posts (RSS, HTML scrape, or JSON API). |
| `scripts/fetch_index.py` | Lists recent posts from every source, with dates, per-source status, and a "new since last digest" flag. Stdlib only. |
| `scripts/read_post.py` | Prints the readable text of one post. Required for Qwen (the site is rendered client-side); works as a fallback for any other site. |

Seen-URL state lives in `~/.local/state/ai-research-digest/seen.json` (or under `$XDG_STATE_HOME`).
Saved digests go to `${AI_DIGEST_DIR:-$HOME/ai-research-digest}/YYYY-MM-DD.md`.

## Workflow

1. **List posts.** Pick the window: the user's request if given, otherwise 7 days.

   ```bash
   SKILL=~/.agents/skills/ai-research-digest
   python3 $SKILL/scripts/fetch_index.py --days 7 --format json > /tmp/ai-digest-index.json
   python3 $SKILL/scripts/fetch_index.py --days 7 --format md   # human-readable view
   ```

   Useful flags: `--since YYYY-MM-DD`, `--source "vLLM"` (repeatable), `--per-source N`,
   `--include-undated`. Each post has `"new": true` when its URL is not in the seen state.

2. **Check source health.** Any source with status other than `ok`, or with `dated` well below
   `count`, goes in the Source status table as a failure. Try the source's `homepage` with the
   `fetch` tool before giving up on it. Do not silently drop a source.

3. **Triage.** By default only posts with `"new": true` are candidates; include already-seen
   posts only if the user asks for a full window. Sort each candidate into one tier:

   - **Full summary:** the post reports a performance result, a new algorithm or method, a new
     kernel or serving technique, or a model release with stated architecture or efficiency
     details. Kernels, inference serving, KV cache, parallelism, quantization, speculative
     decoding, attention variants, training efficiency, and RL methods all qualify.
   - **Skimmed:** product launches, partnerships, funding, events, hiring, customer stories,
     model-vs-model eval comparisons without a method contribution, tutorials that repeat
     known material, and design or architecture overviews that report no measured results.

   Cap full summaries at 12. If more qualify, keep the ones with the largest or most novel
   results and move the rest to Skimmed with the reason "over cap".

4. **Read every full-summary post in full.** Use the `fetch` tool (markdown) on the URL. For
   `qwen.ai/blog?id=...` URLs, or when `fetch` returns only scripts or navigation, run:

   ```bash
   python3 $SKILL/scripts/read_post.py "<url>"
   ```

   If a post cannot be read, summarize it from the index `summary` only and mark the card
   `(index summary only)`. Never invent numbers.

5. **Write the digest** in the exact format below. Print it in the chat and save it:

   ```bash
   mkdir -p "${AI_DIGEST_DIR:-$HOME/ai-research-digest}"
   # write the digest to "${AI_DIGEST_DIR:-$HOME/ai-research-digest}/$(date +%F).md"
   ```

   If a file for today already exists, overwrite it only if the window is the same; otherwise
   use `$(date +%F)-<since>.md`.

6. **Mark posts as seen** only after the digest is saved, using the same window and filters as
   step 1:

   ```bash
   python3 $SKILL/scripts/fetch_index.py --days 7 --mark-seen > /dev/null
   ```

## Output format

Use this structure exactly. Keep section order and headings, even when a section is empty
(write `None in this window.`). Replace `<...>` placeholders. Dates are `YYYY-MM-DD`.

```markdown
# AI Research Digest: <today>

**Window:** <since> to <until> | **Sources:** <ok>/<total> ok | **Posts in window:** <n> | **New:** <n> | **Summarized:** <n>

## TL;DR

- **<Source>: <short title>.** <Single most important performance or algorithmic takeaway, with its key number.>
- <3 to 5 bullets total, ordered by impact. Only full-summary posts appear here.>

## Performance and Systems

### [<Post title>](<url>)

**Source:** <source> | **Date:** <date> | **Area:** <Kernels / Serving / KV cache / Parallelism / Quantization / Speculative decoding / Hardware / Other> | **Hardware:** <GPUs or accelerators, or "not stated"> | **Models:** <models, or "not stated">

- **What changed:** <1 to 2 sentences on the new technique, system, or result.>
- **Key numbers:** <metric: baseline -> result (conditions such as hardware, batch size, ISL/OSL, concurrency, precision). One line per headline number. "None reported" if the post has none.>
- **How it works:** <1 to 3 bullets on the mechanism.>
- **Caveats:** <missing baselines, vendor-run benchmarks, preview status, narrow workloads, quality tradeoffs. "None noted" if none.>
- **AMD/ROCm:** <AMD Instinct or ROCm results or support stated in the post, or "not mentioned".>

## Algorithms and Training

### [<Post title>](<url>)

**Source:** <source> | **Date:** <date> | **Area:** <Architecture / Training / RL / Distillation / Decoding / Quantization / Data / Evaluation / Other> | **Models:** <models or scale, or "not stated">

- **What changed:** <1 to 2 sentences.>
- **Key results:** <metric: baseline -> result (setting). "None reported" if none.>
- **How it works:** <1 to 3 bullets on the method.>
- **Caveats:** <scale of experiments, missing ablations, unreleased code or weights. "None noted" if none.>
- **Practical impact:** <one sentence on what this could change for training or serving.>

## Skimmed

| Date | Source | Title | Why skimmed |
|---|---|---|---|
| <date> | <source> | [<title>](<url>) | <Product launch / Partnership / Funding / Event / Eval comparison / Tutorial / No results / Over cap / Outside window> |

## Source status

| Source | Status | Posts in window | Notes |
|---|---|---|---|
| <source> | <ok / error / empty / partial> | <n> | <failure detail, or blank> |
```

### Format rules

- Put each full-summary post under exactly one of the two main sections, by its primary
  contribution. Speculative decoding and quantization go under Performance when the headline is a
  speed or cost result, and under Algorithms when the headline is a new method.
- Within a section, order cards by impact (largest or most novel result first), not by date.
- Every number must come from the post, with units and the comparison baseline. If the post
  gives no baseline, say so in Caveats.
- Label vendor self-benchmarks as such in Caveats (for example, a provider benchmarking its own
  serving stack against competitors).
- Use plain, specific language. No hype words ("groundbreaking", "game-changing"). No emojis.
- When several posts report the same result (for example, the same benchmark numbers on a
  vendor blog and on vLLM), give it one card and list the other posts on the Source line:
  `**Source:** Qwen (also: vLLM, llm-d)`. Posts on the same model that report different work
  (a training recipe vs. serving kernels) get separate cards.
- The Source status table lists all tracked sources, every run, including healthy ones.

## Maintaining sources

Edit `sources.json`. Each entry needs `name`, `homepage`, and a `strategy`:

| Strategy | Required fields | Optional fields |
|---|---|---|
| `rss` | `feed` (RSS or Atom URL) | |
| `html` | `listing`, `link_regex` (matches post hrefs) | `title_regex`, `summary_regex`, `require_title`, `date_position` (`after` default, or `before`), `date_window` (chars, default 600), `item_split` (regex that splits the page into one block per post), `date_precision` (`month` when the listing shows no day) |
| `qwen_api` | `api`, `post_url` (with `{path}`) | |

Prefer an RSS feed when the site has one (look for `<link rel="alternate" type="application/rss+xml">`).
After editing, verify with:

```bash
python3 $SKILL/scripts/fetch_index.py --days 0 --per-source 3 --format md --include-undated --source "<name>"
```

Check that titles are clean, dates are present, and URLs open the right post.

## Troubleshooting

- **A source returns `empty` or loses its dates:** the site layout changed. Download the listing
  page, look at the markup around one post link, and update `link_regex`, `title_regex`, or the
  date settings.
- **Qwen fails:** qwen.ai serves a JavaScript app; post data comes from
  `https://qwen.ai/api/v2/article/retrieval?type=qwen_ai&language=en-US` (about 5 MB). If the
  endpoint moves, find the new one by searching the site's JS bundles for `/api/`.
  `qwenlm.github.io/blog` stopped updating in 2025 and is not a substitute.
- **Truncated reads (`IncompleteRead`):** `fetch_index.py` retries three times. If a source keeps
  failing, report it in Source status and continue with the rest.
- **Base Labs dates:** its listing shows only month and year (`"date_precision": "month"`).
  `fetch_index.py` reads each candidate post's `article:published_time` metadata to get the exact
  date. If that fails, the post keeps month precision, counts as in-window if its month overlaps
  the window, and carries `"date_precision": "month"` in JSON. In that case, get the real date
  from the post before writing the card, and move the post to Skimmed as "Outside window" if it
  is older than the window.
- **Together AI:** the feed covers the whole company blog. Most product and partnership posts
  belong in Skimmed.
- **Fireworks AI:** the research page has no feed. Featured cards link without a trailing slash
  and the full list links with one; `fetch_index.py` treats both as the same post.
  `https://fireworks.ai/research.md` is a plain-text copy of the listing if the HTML changes.
