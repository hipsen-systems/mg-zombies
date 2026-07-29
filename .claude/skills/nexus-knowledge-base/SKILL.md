---
name: nexus-knowledge-base
description: Read and write your team's shared Flowdex knowledge base via its MCP tools. Use at the start of a task to load relevant project context before acting, and to save durable decisions, learnings, and activity back to Flowdex.
---

# Flowdex — team knowledge base

Flowdex is your team's shared, AI-readable knowledge base, exposed through MCP tools.
Use it so you build on what the team already knows and leave durable knowledge behind —
don't start from zero, and don't let what you learn evaporate when the chat ends.

## Golden rules
1. **Read before you act.** At the start of a task, load the project context first — get_project_structure, then read_index on the relevant pages — so you build on what the team already knows instead of starting from zero.
2. **Write durable knowledge back.** When you learn or decide something that outlives the current chat (architecture, conventions, how-tos, decisions), save it with write_index as a focused markdown page.
3. **Log meaningful activity.** After a substantive change, record it with append_changelog so teammates — and their agents — can see what happened.
4. **Link concepts with [[wiki-links]].** Reference other pages, people, and systems with [[Double Brackets]]. That is what turns isolated notes into a navigable knowledge graph.
5. **Keep pages small and focused.** One concept per index page. Small, well-linked pages beat one giant page — easier for both humans and agents to find and keep current.
6. **Don't duplicate — extend.** Before writing a new page, check the graph and existing pages. Update or link an existing page rather than creating a near-duplicate.

## At the start of a task
1. `list_projects` to find the project, then `get_project_structure` to see what exists.
2. `read_index` the pages relevant to the task.
3. Summarize what you found before proposing changes.

## As you work
- Save durable decisions and learnings with `write_index` — small, focused markdown pages.
- Record meaningful changes with `append_changelog`.
- Link related pages, people, and systems with [[wiki-links]].
- Before creating a page, check `get_wiki_graph` and existing pages, and extend rather than duplicate.

## Tools
### Discover
- `list_projects` — List the projects you can access. (use when: First call in a new workspace.)
- `get_capabilities` — Server capabilities and usage guidance. (use when: When unsure what the server supports.)
- `get_project_structure` — Files, index pages, and stats for a project. (use when: At the start of a task.)
- `get_wiki_graph` — The project’s pages and [[wiki-link]] edges. (use when: To navigate related knowledge.)

### Read
- `read_index` — Read an index (wiki) page. (use when: To load specific context before working.)
- `read_changelog` — Recent activity for a project. (use when: To catch up on what changed.)

### Write
- `write_index` — Create or update an index page (markdown). (use when: To save durable knowledge or decisions.)
- `append_changelog` — Append an activity entry. (use when: After a meaningful change.)
- `delete_index_page` — Remove an index page. (use when: When a page is obsolete (editor+).)

### Files
- `prepare / execute / complete_file_upload` — Upload a raw file (direct-to-storage). (use when: To add source documents to keep.)
- `archive_file` — Move a file to the archive. (use when: To retire a file without deleting it.)

### Team
- `list_organization_members / list_project_members` — See who is in the org / project. (use when: To understand the team.)
- `create_project / add_project_member` — Create a project or add a member. (use when: Create: org owner/admin. Add member: a project lead, or org owner/admin.)
