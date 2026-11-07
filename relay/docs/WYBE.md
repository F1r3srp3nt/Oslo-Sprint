# Wybe Night Shift — status and runner design

## What is known (from the event briefing only)

- Join page: `https://nightshift-board.wybe.me/join`
- The agent must discover which commands the robot understands.
- Tasks include towels, lost items and room checks; there are more tasks than the robot can finish.
- Good judgement earns points; careless actions lose points.
- Practice closes Sunday 8 November, 11:45 Oslo time. Final: 12:00–13:00, ten secret shifts,
  highest average final score wins. The agent runs autonomously in the final.
- Do not attack or overload the server.

## What could not be verified

The join page could not be read from the build environment: the host
`nightshift-board.wybe.me` is blocked by that environment's network policy, so the request
never reached Wybe. That means **no public instructions were read**. Nothing in Relay assumes
Wybe endpoints, payloads, command names or scoring rules.

To build the live adapter, the following must come from the organisers, probably through
team registration on the join page. Registering is your decision, so Relay has not done it:

1. API base URL and transport (HTTP/WebSocket), and how practice and final shifts are started.
2. How the agent authenticates (team token? per-shift key?) and where that credential comes from.
3. How to discover the robot's commands (a help or describe call?) and their argument formats.
4. The observation format: tasks, their states, deadlines, room/location flags, robot state.
5. The action request and response format, including how refusals are reported.
6. Whether actions are idempotent, accept an idempotency key, or can be status-checked after
   a lost response.
7. Rate limits and any "careless action" penalties for invalid or repeated commands.
8. How scores are reported, so that only service-reported numbers are ever shown as live.

## Runner architecture (implemented, simulated)

```
ChallengeAdapter (protocol)        ShiftPolicy (protocol)
  discoverCapabilities()             decide(observation, usable, excluded) -> act | finish
  observe()                          reconcile(request, before, after) -> applied | notApplied | unknown
  perform(request)
  status(of: idempotencyKey)
  scoreReport() -> LabeledScore?     AutonomousRunner (actor) — headless
                                       allow-list ∩ discovered commands
                                       precondition check against the latest observation
                                       rate limiter (min interval + server pause)
                                       timeout on every request
                                       bounded retries with exponential backoff
                                       ambiguous-failure reconciliation
                                       stop signal checked before every request
                                       action history + mode-labelled log
```

- **Observations and task state:** `Observation` / `ChallengeTask`.
- **Allowed actions and preconditions:** `ActionSpec` (with `consequential` flag and
  `Precondition`s) plus `RunnerConfiguration.allowedActions`. A command that wasn't discovered,
  or isn't in the allow-list, or whose preconditions fail, is recorded as blocked and never sent.
- **Prioritisation:** `SimulatedShiftPolicy` estimates value per minute from kind, priority and
  deadline, skips infeasible tasks, finishes carried items first, and never enters a
  do-not-disturb room (it defers those instead). It uses only what the observation shows.
- **Timeouts, retries, backoff:** every request has a timeout. A transient or rate-limited
  failure is retried at most `retry.maxAttempts` times in total, with exponential backoff.
- **Ambiguous failures:** after a timeout or lost response, a *consequential* action is never
  simply resent. The runner asks `status(of:)` if the service supports it, otherwise compares
  observations. If it was applied → recorded as confirmed. If it definitely wasn't → retry
  (same idempotency key, still bounded). If unknown → the task is set aside and the action is
  **not** repeated.
- **Stop control:** `StopSignal` is checked before every request, including retries. CLI:
  Ctrl-C (second press exits), `--stop-file PATH`, `--stop-after N`. App: Stop button / ⌘.
  An in-flight request cannot be recalled; if it is interrupted, its outcome is recorded as
  unknown and not repeated.
- **Separation of simulation and live:** every report, record and log entry carries an
  `ExecutionMode`. The runner refuses to start when the adapter's mode differs from the
  configured one. Scores are `LabeledScore`s whose only text form says "SIMULATED — … not a
  challenge result". The live placeholder returns no score.

## The simulator (clearly not Wybe)

`SimulatedNightShift` is deterministic per seed. Its hotel layout, `sim.`-prefixed commands
(`sim.move`, `sim.pickup`, `sim.deliver`, `sim.inspect`, `sim.defer`), task values, penalties
(unknown command, failed precondition, repeating a finished task, entering a do-not-disturb
room) and fault injection (refused, rate-limited, hung, applied-but-response-lost) were all
invented to exercise the runner. Its scores do not predict challenge performance.

## Adding the live adapter later

1. Implement `ChallengeAdapter` against the official contract (`mode = .live`). Map the
   service's errors onto `ChallengeError` carefully: only report `.transient` when the
   service guarantees the action was not applied.
2. Write a `ShiftPolicy` for the real command vocabulary.
3. Configure `RunnerConfiguration(expectedMode: .live, allowedActions: [...exact names...])`
   with a conservative `minRequestInterval` that matches the published rate limits.
4. Add a CLI command that requires an explicit flag to start a live run. Practice and
   final runs must not start unless you say so.
