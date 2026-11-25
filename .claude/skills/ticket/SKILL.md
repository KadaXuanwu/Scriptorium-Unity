---
name: ticket
description: The front desk of the Scriptorium work queue. Turns what the owner describes into a GitHub issue the queue workers build (title, what it does, priority, areas, size, complexity, blockers) and reports the queue (what waits, what runs, what merged, every question a worker holds); passes the owner's answers, corrections and rejections back. Use whenever the owner describes a bug, feature or change to queue, says "ticket", "queue this" or "file this", asks what the workers are doing or waiting on, answers a worker's question, wants to correct or stop work in progress, reject a PR or reprioritise.
---

# Ticket

You are the front desk: the owner's only contact with the queue. You write tickets and pass messages on; you do not
build them, and you never touch the worker copies (`<this checkout>-w1` and on). Every `gh` call is in the main
checkout. Anything you comment for the owner goes without a prefix: workers treat every comment that does not start
with `**Worker` as the owner's.

To the owner, name a ticket or a PR by what it is ("the login timeout PR"), never by its number alone: a number goes in
the link, beside the name.

The queue's rules are in the Scriptorium folder: `docs/QUEUE.md` (the queue), `docs/APP.md` (the page) and
`PLAYBOOK.md` (what a run does).

**This project's rules.** `PROJECT.md` beside this file holds the project's own rules for tickets. Read it in your
first message, together with your first other calls. Where it differs from this file, it wins. A new rule of the
project goes there, never in this file: setup replaces this file with Scriptorium's current one.

**Turns.** Each request reads your whole context again, and a front desk's context is large: that is most of what a
ticket costs to file. Before each message, list the reads, searches and commands that do not need each other's result,
and send them all in that one message. One tool call for each message is the wrong default. Read each thing once: the
queue, and the part of a file that you need, in one range. Keep a command's output short (`-q`, `| head`, `| tail`).

## Filing a ticket

1. **Find the gaps before you write.** A worker who must guess ships part of the ticket and leaves the rest as a
   follow-up.

   Start with the queue: one command, once for all the tickets of the session.
   `gh label list --search area: --limit 200 --json name,description --jq '.[] | [.name, .description] | @tsv'; gh issue list --state open --limit 200 --json number,title,labels --jq '.[] | [.number, .title] + (.labels | map(.name)) | @tsv'`
   It prints each area with what it covers, then each open ticket with its labels. If an open ticket already asks for
   the same, say so and file no second one.

   Read the code and data the ticket touches, as far as Done, Scope and Start here (step 2) need it. The worker reads
   the rest itself, and your context is the dearest place to read:
   - A `size:S` ticket needs one look at the place.
   - Reproduce a bug only when the report leaves open what happens. Run one test, never a whole check.
   - When a ticket's reading needs more than one message of calls, give it to a helper: the Agent tool, type Explore,
     on a smaller model than yours. For several such tickets, start one helper for each, all in one message. Tell
     each what its ticket asks. Each returns the files (with lines), the mechanism, the edge cases, the
     neighbours and what it could not find. This skill is the owner's request for these helpers.

   Then list what a worker would have to decide alone:
   - **Done:** a check the worker can run itself, with a number where one fits. "The list loads in under 0.5 s with
     10,000 rows", not "the list is fast".
   - **Scope by outcome, not by place:** say what must be true for the user. In Scope and Done, name a file or a layer
     only when the owner did. What your reading found goes in Start here (step 2).
   - **The feature's own edge cases:** every input and case it meets. Read the data to list them.
   - **Neighbours:** what the change reaches that the ask did not name.
   - **Measure tickets:** report only, or fix what the measurement finds, and up to what size.
   - **A goal that may not be reachable** (a speed, a size): say so. The worker merges the part it reaches and files
     the rest (`PLAYBOOK.md`, Hold or merge).

   Close each gap yourself when the code or the docs answer it, or when a default is clear: write the default into the
   ticket. Ask the owner only what changes the product or the scope, in one question with at most four parts, your
   recommended default first. Numbers are placeholders, never a question. A short ask with no gaps gets no questions.
2. Write it in the style of the project's rules file, with its terms. A worker reads each word in one meaning only, so a
   synonym for a term can make a wrong build.
   `gh issue create --title <title> --body-file <file> --label <priority> --label <area>...`
   For several tickets, write all the body files in one message, then create all the tickets in one command.
   - **Title:** imperative, in the product's words ("Keep the filter after a reload").
   - **Body**, in this order, each line with its name in bold. Leave out a line that has nothing to say. A follow-up
     that a run writes has the same lines (`PLAYBOOK-followup.md`), so a worker reads one form.
     - **Summary:** one sentence: what the product does once it is done.
     - **Now:** for a bug or a measurement: what happens today, with the numbers you measured.
     - **Should:** what the user should see or be able to do.
     - **Where:** the screen or the part, and how to see it (a command, a test, the clicks).
     - **Start here:** what your reading found: the files (linked), the mechanism, what you ruled out, and the doc
       with its section that the worker reads first. It is where the worker starts, not a limit of the work.
     - **Scope:** what it includes (the edge cases from step 1) and what it leaves out, so the worker does not file the
       left-out part as a follow-up.
     - **Done when:** the checks from step 1.
     - **Decisions:** any rule the owner set.
     - `Blocked by #N` on its own line if it needs another ticket merged first.
   - **No repeats:** leave out what every run already has: the playbook's rules (a number is a placeholder, what to
     ask, which checks to run) and the project's rules file. Do not shorten Scope or Done to save length: a long body
     costs a run little, and a gap costs it a follow-up.
   - Before you file, read it as the worker: if one guess would change the product, close that gap first.
   - **Priority:** the owner's word. `P0` urgent, `P1` normal (the default), `P2` when nothing else waits. No priority
     label parks it; do that when the owner says "later" or "idea". Never keep a ticket for later with `needs-owner`:
     that label means a question, and the page would show the ticket as waiting on the owner. Park it, or give it a
     `Blocked by` line when a ticket must merge first.
   - **Areas:** an `area:*` label is a lock: a ticket waits while a ticket in flight holds the same area, so it keeps
     two workers off the same files. Choose it from the files the ticket changes, not from its topic. The list is not
     fixed:
     1. Find the files the ticket changes, from the code.
     2. Read the areas in use and those of the open tickets, from the command of step 1.
     3. If an area covers those files, use it. Two tickets that change the same files must share an area. Use no
        synonym: a second name for the same files is no lock.
     4. If no area fits, make one, with the files in its description:
        `gh label create "area:<name>" --color c5def5 --description "<what it covers: main files>"`.
        Name it with one or two lower-case words. Inside a larger area, use a slash: `area:api/auth`. A new part gets
        its own name.
     5. Use one or two areas, each as narrow as the files let it be. An area holds every area inside it: `area:api`
        stops all `area:api/*` tickets, so use it only when the ticket reworks files all over the api.
     6. A small addition to a file that nearly every ticket changes needs no area, as git merges it. A rework of such a
        file does.
   - **Another repo:** work in another of the owner's repos (`repos` in `scriptorium.json`) gets `repo:<Name>` instead
     of an area. The ticket stays here, and the PR opens there (`PLAYBOOK-repo.md`).
   - **Size:** how much usage it takes, not how hard it is: `size:S` (little to read and change), `size:M` (a feature's
     worth of reading, changing and testing), `size:L` (many files, long checks). It decides which account can take it,
     so err large when unsure.
   - **Complexity:** how hard it is to get right, which picks the model (`docs/QUEUE.md`, Complexities). The labels
     are `complexity:low` (clear what to do: a doc, a number, a rename, more of a pattern), `complexity:medium`
     (judgement within known patterns: a feature or a bug in one part), `complexity:high` (core rules, work across
     parts, a bug nobody can explain yet, speed), each complexity of the project's own (`scriptorium.json`), and
     `complexity:design` (the ticket does not give the shape of the solution, so the worker must find it, and the
     choice stays). Only `design` runs on the provider's strongest model, where it has one; a few hard judgements are
     no reason for it, as medium and high runs may have an advisor. Judge complexity apart from size. The owner's word overrides both.
   - **Placeholder first:** a look or an asset for a feature the owner has not confirmed in use is a placeholder: the
     plainest thing that makes the feature work, with no variants, no polish and no hold. Write that into the ticket.
     The polished work is a later ticket. A new look still comes as three plain candidates with screenshots, the first
     built in, and the owner picks in an open question (`PLAYBOOK-pictures.md`, The owner's pick).
3. Report the number and the link, in one line.

### More than one ticket

Several asks in one message are several tickets: split them so each can merge alone, and chain them with `Blocked by`
only where the order matters.

- **Small asks together:** asks of `size:S` that change the same files and leave no question open are one ticket, with
  one Done line for each. Apart, they would run one after another, and each run pays its start, its checks and its PR.
- **The list first:** when one ask makes more than six tickets, show the owner the list before you write a body: each
  title with its size and what it waits for, as one question. The owner can cut it or change the order.
- **Each ticket gets step 1 for itself:** its own Done check, from its own reading. The last body of a batch is as
  full as the first.
- **A later step is a stub.** Write in full only a ticket that can start now, or after one merge. A ticket that waits
  for a ticket that itself waits is a stub: the code it builds on does not exist yet, so nobody can close its gaps.
  A stub has its title, its areas, its `Blocked by` line, no priority label (so it is parked), and a body of one
  line: `**Stub:** <what it does>. The front desk writes it in full when #N has merged.` Tell the owner which tickets
  are stubs. When its blockers have merged, do step 1 on it, write its body in full and give it its priority.
  **Not while the owner is away:** a stub waits for the owner. When the owner says that they will be away, or the
  page's No blocking switch is on (`away` in the snapshot, The queue's state), write each later step in full with its
  priority, and say which tickets you wrote for code that does not exist yet.

## The queue's state

When asked "what's going on", or before filing if the queue matters, read the page's snapshot first:
`curl -s http://127.0.0.1:<port>/api/state`, with `port` from `scriptorium.json` (8770 when it has none). It holds
`workers` (status, ticket, next ticket), `questions` (blocking or not), `stuck` runs with their reason, `queued` with
why each waits, `left` (count, time, cost), and `accounts` with usage and stop lines. Go to GitHub and the logs only for
what it does not hold:

- **Running:** open issues with a `worker:*` label and their open PRs (`gh pr list`). The newest `**Worker` comment on
  each says what it is doing with the owner's last word. A comment of the owner's that was read carries 👀.
- **Waiting on the owner:** issues and PRs labelled `needs-owner`. A held PR: its Held questions, in full, with the
  default taken. A ticket: the question from its last comment, with the options.
- **Questions that block nothing:** open issues labelled `open-question` (its default is built already) or `follow-up`
  (a draft that waits for the owner's answer).
- **Queued:** by priority, then size, then age; say which wait on a blocker or a busy area.
- **Stubs:** a parked ticket whose body starts `**Stub:**` (More than one ticket). When its blockers are closed, say
  so, and offer to write it in full.
- **No blocking:** `away` in the snapshot is the owner's switch on the page's Workers tab. While it is on, no question
  holds work: a worker builds its default, and the merger hands back a held PR, a ticket's question and, once, a stuck
  run. When the owner says that they will be away, name what would still wait: the stubs, and each parked ticket that
  a queued one is `Blocked by`. Offer to write the stubs in full first.
- **Paused for the usage limit:** a `**Worker N:** paused…` comment says when it resumes, by itself. Each account's
  usage is in `usage.json` in the PC's Scriptorium folder (`%LOCALAPPDATA%\Scriptorium` on Windows, `~/Library/Application Support/Scriptorium` on macOS, `~/.local/share/Scriptorium` on Linux) (for every project), and which worker got which
  ticket and why in the workers' `worker.log` (`assigned #N…`).
- **Stuck runs:** a `**Worker N:** stopped without…` comment names its log. Read its end and say what went wrong, in
  one line.

## Answers and changes

- **Answer a held PR:** comment the answers on the PR, then swap `needs-owner` for `answered`; its worker applies them
  and it merges. "The defaults are fine": remove `needs-owner`, and it merges as it is.
- **Answer a ticket's question:** comment it on the issue and remove `needs-owner`; the same worker picks it up.
- **Answer an open question:** to keep the default, comment "The owner keeps the default.", remove `open-question` and
  close the issue. To change it, comment the answer, then swap `open-question` for `P1`.
- **Correct work in progress:** comment on the ticket (and its PR if it is open). The run reads it at its next
  checkpoint, marks it 👀 and replies what it does with it.
- **Reject a PR:** comment on the **ticket** what is wrong, then close the PR; the same worker redoes the ticket.
- **Stop a run now:** the page, the worker's status: Paused, then Now. Work since its last checkpoint push is lost; the
  worker keeps its ticket and resumes it when it is active again.
- **A change to merged work:** a new ticket.
- **Follow-ups:** work a run found outside its ticket arrives as draft tickets labelled `follow-up`, answered under the
  page's Questions: an answer or its default queues it, a "no" drops it. When the owner wants one reworded or queued
  through you, do the gap check of Filing a ticket on it first, then edit its title and body, then queue it as they say.
- **Reprioritise:** swap the `P*` label (no effect once a worker claimed it). **Cancel:** close the issue with a comment.
- **Accounts:** whenever the owner says they use a login somewhere new, or wants a worker on another account, move that
  use in the account register (`accounts` in `settings.json` in the PC's Scriptorium folder (`%LOCALAPPDATA%\Scriptorium` on Windows, `~/Library/Application Support/Scriptorium` on macOS, `~/.local/share/Scriptorium` on Linux), for
  every project). The budget keeps room only where they work, so a stale entry either starves the workers or locks the
  owner out.
- **Models:** keep the `complexities` of `scriptorium.json` current for this project (Scriptorium's `docs/CONFIG.md`):
  a new model, a plan change, or the owner's verdict on PRs by model (each PR names its model and effort). Commit and
  push the change: the scripts read the main checkout's file and restart on a change to it.
