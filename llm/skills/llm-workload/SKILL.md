---
name: llm-workload
description: Use when running LLM inference workloads to capture performance and accuracy metrics, especially with YAML-defined benchmark recipes, vLLM, perf-eval, lm-eval, BFCL, traces, logs, and organized workload artifacts.
---

# LLM Workload

## Purpose

Use this skill when running an LLM inference workload where the goal is to capture repeatable performance and accuracy metrics. Prefer concrete workload definitions over ad hoc scripts so the run can be reviewed by customers, developers, operators, and other stakeholders.

## Default Approach

- Prefer existing tools and harnesses before writing custom runners.
- Use `vllm-project/perf-eval` as the default reference for vLLM inference workloads when applicable.
- Define workloads as simple YAML recipes whenever possible. Avoid a hodgepodge of one-off bash scripts.
- Capture both performance and accuracy when the workload supports it.
- Keep every run reproducible: record model, hardware, container image, commit SHA, serve args, benchmark args, eval tasks, and environment overrides.

## Required Preflight

Before running or designing the workload, check with the user about model weights:

1. Where do the model weights live?
2. Are they already present on the node or shared filesystem where the workload will run?
3. If not, what is the expected download or staging path, and who owns access credentials?
4. Is the cache persistent across runs, or will it be reclaimed when the job exits?

Do not assume weights can be downloaded cheaply or quickly. Prefer using weights already staged on the target node. For sharded checkpoints, validate every filename referenced by the weight index rather than treating the snapshot directory's presence as proof that staging completed. Report missing shards and block expensive submission until the checkpoint is complete.

For scope-only or planning phases that do not submit work, record unresolved weight location, completeness, credentials, and cache persistence as explicit execution prerequisites rather than blocking the analysis. Resolve and validate them before any expensive submission.

Avoid memory-mapped tensor loading whenever the runtime provides a practical alternative, especially for weights on network filesystems. Prefer eager or sequential whole-file loading, validate that the resolved runtime configuration actually disables memory mapping, and monitor initial shard throughput before committing to a long run. Record the selected loading strategy in reproducibility metadata.

When large weights are on network storage, inspect node-local NVMe before accepting slow startup. If enough space exists, stage checkpoint files with bounded parallel copies, copy metadata and refs, validate every indexed shard and file size, and point the runtime cache at the local copy. Check `/dev/shm` capacity before proposing RAM staging; do not assume it can hold the checkpoint.

## Model Identity and Local Weights

Always use the model's standard registry identifier in workload recipes and benchmark metadata, such as `amd/GLM-5.2-MXFP4`, rather than a cache directory, snapshot path, symlink target, or other machine-specific filesystem path. Dashboards and result adapters commonly preserve the recipe's model field verbatim, so putting a local path there creates the wrong model identity in packaged and published results.

Keep logical model identity separate from physical weight resolution:

- Set the recipe's model field and benchmark `--model` value to the standard model identifier.
- Point Hugging Face at an existing cache with `HF_HOME`, `HF_HUB_CACHE`, or the harness's cache-volume and bind-mount options.
- Set `HF_HUB_OFFLINE=1` or use the relevant CLI offline or local-files-only option when downloads must be prohibited.
- When mounting a read-only Hugging Face cache for a model that uses remote code, set `HF_MODULES_CACHE` to a separate writable path and verify startup remains offline.
- Pin a revision or commit through the recipe or CLI when reproducibility requires an exact snapshot.
- If a runner cannot resolve a standard identifier from the staged cache, pass the local weight path through a distinct environment variable or CLI override supported by the harness. Do not overload the model identity field with the path.
- Record both the standard model identifier and resolved local snapshot path in reproducibility metadata.

Before submission, parse the final recipe and verify that generated server and benchmark commands retain the standard identifier while the configured cache resolves to the intended local snapshot. Before packaging or publishing, inspect the workload artifact and confirm its model field is still the standard identifier.

When a workload is intended to exercise a non-default model implementation, do not infer the selected implementation from the image commit, optimization environment variables, or resolved architecture name alone. Capture the explicit model-class override in the recipe, inspect the generated server command for correct quoting, and require runtime log evidence that the override was applied. Treat results from the default class as invalid for claims about the alternate implementation.

For fixed-output performance workloads, verify the generated benchmark command includes `--ignore-eos`, then validate every raw result has the expected successful request count, zero failures, and exactly `num_prompts * output_len` generated tokens. Treat early EOS, HTTP 400 responses, and partial request counts as invalid results. Set server `max_model_len` above `input_len + output_len` to allow tokenizer or protocol overhead, rather than using the exact sum as the limit.

Validate lm-eval output recursively because results are commonly nested under a sanitized model-name directory. Keep variant execution resumable so a post-run harness validation error can be corrected without rerunning already validated expensive variants.

## Workload Definition

When creating or modifying a workload:

1. Start from an existing recipe that matches the model family, GPU type, or benchmark style.
2. Keep hardware variants in separate YAML files.
3. Include server configuration, perf benchmark configuration, and accuracy eval configuration in the recipe instead of separate shell fragments.
4. Make the optimization target explicit: throughput, latency, cost per token, accuracy, function-calling quality, long-context behavior, or reliability.
5. Validate the recipe with the harness's parser or smoke tests before launching expensive GPU work.
6. For context and concurrency sweeps, anchor context lengths to the production range and use the measured KV token capacity to choose concurrency points that cross the expected pressure boundary. Do not substitute extreme context lengths for sufficient concurrency without an explicit long-context objective.
7. Before launching directly on a compute node, verify that allocated GPUs are idle and have negligible VRAM use. Treat scheduler allocation as insufficient proof of GPU isolation when containers can access host-wide device nodes.

For `perf-eval`-style workloads, prefer the established blocks:

- `vllm` for model serving configuration.
- `vllm_bench` for throughput and latency measurements.
- `lm_eval` for accuracy tasks.
- `bfcl` for function-calling quality.

## Profiling Defaults

When enabling profiling, default to these profiler args unless the user specifies otherwise:

```text
--profiler-config.torch_profiler_with_stack false
--profiler-config.torch_profiler_use_gzip true
--profiler-config.torch_profiler_dump_cuda_time_total true
```

For `vllm bench serve` profiling:

- Add `--profile` to the benchmark so profiling starts after benchmark warmups and covers the measured requests.
- Set `--profiler-config.profiler torch` and an absolute `torch_profiler_dir` on the server.
- For a containerized server, bind-mount the profiler directory to a persistent host artifact directory.
- Preserve both gzip-compressed Perfetto traces and CUDA-time-total text tables, and fail the run if either output type is missing.
- Record trace filenames and sizes in an artifact manifest because full-request traces can be large.
- For text-table comparisons, remove overlapping annotation rows such as `execute_context_*`, renormalize displayed percentages, and state any profiler row-limit coverage.
- For cross-hardware comparisons, document differences in model weights, quantization, software versions, parallelism, scheduler settings, available ranks, and generated token counts before interpreting kernel times.

## Project Organization

Give each experiment its own descriptive, named subdirectory. Within that experiment directory, use these standard subdirectories only when they contain relevant files:

```text
<experiment-name>/
  docker/   # custom Dockerfiles and Docker build inputs
  configs/  # YAML workload and runtime configuration files
  traces/   # profiling traces and processed trace tables
  logs/     # stdout, stderr, server, benchmark, and scheduler logs
  data/     # CSV, JSON, and other machine-readable outputs
  scripts/  # launch, processing, validation, and analysis scripts
  figures/  # generated plots and figures
```

Do not create empty standard subdirectories. Create each directory when its first artifact is written. Store submission records and scheduler-default output under `logs/`, moving default scheduler files there after dispatch if Slurm cannot target that directory safely. Do not scatter generated outputs across the project root. If a project already has a stricter convention, preserve it while maintaining one isolated directory per experiment.

## Run Report

At the end of a workload run, summarize:

- The workload recipe and any local changes.
- Model, hardware, image, commit, serve args, and model weight location.
- Perf metrics captured, including throughput, latency, concurrency, input length, and output length where available.
- Accuracy metrics captured, including task names, scores, and whether results are partial or full evals.
- Artifact locations for logs, traces, raw results, Dockerfiles, and reports.
- Failures, retries, missing data, and any reasons the run is not comparable to prior runs.

When publishing results to an issue tracker, prepare the exact executed YAML, unmodified
raw JSON results, and a consolidated CSV that preserves every JSON field. Validate the
CSV field-for-field against its source JSON files. Confirm that the available integration
supports binary attachments before promising an upload; if it does not, post the summary
and leave a clearly identified local attachment set for manual upload.
