---
name: record
description: Record what this conversation produced in the docs vault, through the vault-keeper. It sends the keeper the outcomes that git can't show, and the keeper decides what, if anything, to write.
argument-hint: "[anything to emphasise]"
disable-model-invocation: true
---

# Record this work

Write down what this conversation produced, through the `docs-vault:vault-keeper` agent.
You never write to `docs/` yourself: send the keeper a `record` request as its whole task,
one JSON object and nothing else, and run it in the background.

Load the `docs-vault:keeper-contract` skill for the request's format. Build the request from
this conversation: git shows the keeper what changed in the repository, so send what git
can't show, meaning the facts that changed, the decisions and why, what was dropped, what's
left open, which follow-ups were finished or reopened, and which notes proved wrong.

The user added: $ARGUMENTS

If nothing in the conversation fits any list, because it was routine work git explains,
tell the user there's nothing to record, and send nothing. Otherwise tell them it's
recording in the background. When the keeper replies, report what it wrote in a line or
two. If it asks questions, ask the user them word for word, and send the answers to the
same keeper with SendMessage, as the contract describes.
