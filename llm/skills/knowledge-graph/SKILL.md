---
name: knowledge-graph
description: Create a knowledge graph during a session or across sessions to reduce context requirements and make knowledge more accessible to agents and easier for humans to understand.
---

# Knowledge Graph

## Description
This skill is used to create a knowledge graph of the knowledge during a session or across multiple sessions.
The hope is that it reduces context requirements, but also makes the knowledge more accessible to agents and easier for humans to read and understand.

## When to use
- Use for any session other than the smallest tasks
- When exploring or onboarding to an unfamiliar codebase
- When a task spans multiple sessions and context must persist
- When relationships between concepts, files, or decisions need to be tracked

## File Schema

Each knowledge node is a markdown file stored in the `.kg/` directory (unless otherwise specified). Every file must follow this structure:

```markdown
---
name: <kebab-case-identifier>
type: <concept | decision | component | process | entity>
tags: [<tag1>, <tag2>]
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
status: <active | deprecated | draft>
---

# <Title>

## Summary
<1-3 sentence description of what this node represents>

## Details
<Longer explanation, context, or notes>

## Relationships
- depends-on: [[<node-name>]]
- used-by: [[<node-name>]]
- related: [[<node-name>]]
- contradicts: [[<node-name>]]
- implements: [[<node-name>]]
- supersedes: [[<node-name>]]
```

### Field Definitions

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique kebab-case identifier matching the filename (without `.md`) |
| `type` | Yes | Category of knowledge — see types below |
| `tags` | No | Freeform labels for filtering and grouping |
| `created` | Yes | Date the node was first created |
| `updated` | Yes | Date the node was last modified |
| `status` | Yes | `active` (current), `draft` (incomplete), or `deprecated` (superseded) |

### Node Types

| Type | Use for |
|------|---------|
| `concept` | Abstract ideas, patterns, or domain terms |
| `decision` | Architectural or design decisions with rationale |
| `component` | Concrete code modules, services, or files |
| `process` | Workflows, pipelines, or sequences of steps |
| `entity` | People, teams, external systems, or APIs |

### Relationship Types

| Relationship | Meaning |
|--------------|---------|
| `depends-on` | This node requires the linked node to function |
| `used-by` | The linked node consumes or references this node |
| `related` | Loosely connected — shared context but no hard dependency |
| `contradicts` | Conflicts with or is incompatible with the linked node |
| `implements` | This node is a concrete realization of the linked node |
| `supersedes` | This node replaces the linked node (mark the other as `deprecated`) |

## Rules

1. **One concept per file.** Never combine multiple distinct ideas in a single node.
2. **Filenames match the `name` field.** `authentication.md` must have `name: authentication`.
3. **Always bidirectional.** If A `depends-on` B, then B should have `used-by` A.
4. **Update timestamps.** Modify `updated` whenever the file content changes.
5. **Deprecate, don't delete.** Set `status: deprecated` and add a `supersedes` link from the replacement node.
6. **Keep summaries self-contained.** A reader should understand the node from the Summary alone without following links.
7. **Links use `[[name]]` syntax.** Reference other nodes by their `name` field, not file paths.
8. **Flat directory structure.** All nodes live directly in `.kg/` — do not nest subdirectories.
9. **No orphans.** Every node must have at least one relationship to another node (except the very first node created).
10. **Prune stale links.** When updating a node, verify its relationships still hold.

## How to use

1. **Starting a session:** Read existing `.kg/` files to load context before beginning work.
2. **During a session:** Create or update nodes as new knowledge emerges — don't batch it all at the end.
3. **After a session:** Review nodes touched during the session, ensure relationships are bidirectional, and update timestamps.
4. **Querying the graph:** Use glob patterns (`*.md`) and grep on frontmatter fields to find nodes by type, tag, or status.

## Directory Structure

```
.kg/
├── authentication.md
├── database-schema.md
├── api-routes.md
├── session-management.md
└── ...
```
