# Agent Change Workflow

This repository is edited inside an isolated container. All patches, commits, and pull request metadata are generated locally:

- The agent applies code or documentation updates to the working tree in this sandboxed environment.
- Changes are committed to the local Git repository inside the container.
- A pull request description is prepared, but nothing is pushed to a remote or GitHub automatically.

To bring the modifications into your own clone or a GitHub repository, you still need to review the diff and push it yourself (for example, via `git push` or by copying the updated files).

## Supplying Finished Files to a Requester

When a user wants «чистый» (diff-free) код без доступа к GitHub, provide the final artifact directly:

- **Inline in chat** – paste the complete file contents inside a fenced code block so it can be copied immediately.
- **Downloadable artifact** – if the environment allows uploading artifacts, write the file to a temporary path (for example `/tmp/user_notifier.dart`) and share the download link or extraction instructions.

Always confirm which format the user prefers so follow-up answers match their workflow.
