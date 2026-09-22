# Restaurant Recovery, In Plain Language

> Simplified from: [README](README.md) and [analytical contract](docs/04-COWORK-CONTRACT.md).

## One-Sentence Version

Ask CoWork what changed at fictional restaurants, inspect the evidence, and design a test instead of guessing the cause.

## The Story

Imagine a restaurant manager reviewing a carefully organized notebook.
One page records guests and sales; another records opening hours and staffing.
The pages use matching dates, so comparisons mean the same thing.

CoWork helps read that notebook and explain changes.
Missing pages stay missing rather than becoming zero sales.
Nearby patterns suggest questions, but they cannot prove why people stopped coming.

## The Cast

- Synthetic observations: invented notebook entries used to demonstrate the method.
- SQL views: repeatable calculations that organize the notebook.
- Semantic views: shared definitions for measures such as guest change.
- Agent and skills: the assistant and its investigative instructions.
- CoCo: the engineering workspace used to build and maintain the demonstration.
- CoWork: the conversation interface used to explore the results.

## What Changed

- Business users now ask CoWork questions instead of using the former map application.
- Deploy scripts rebuild the demonstration from its source files.
- Teardown scripts remove its cloud resources while preserving shared containers.

## What to Watch Out For

These are fictional restaurants, not customer findings.
Guests are not checks or unique people.
Similar restaurants are not automatically suitable experiment controls.
Skills guide answers; permissions control access.
Teardown removes the demonstration's data and access role.
Its live remove-and-rebuild cycle still needs execution testing.
Browser behavior remains unverified.

## The One Thing to Remember

Use evidence to narrow the question, then test the explanation.

> For the full technical details, see the source document.