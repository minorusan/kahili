# Investigation: ScoreMaster presenter NRE during live-op flow
## TLDR
High-volume, ongoing NREs are coming from ScoreMaster live-op presentation and are likely non-fatal, but they interrupt the live-op flow. The presenter is trying to use a ScoreMaster tournament that has already been completed/disposed, leaving null controllers and causing the null dereference. This likely blocks the ScoreMaster popup (and possibly the rest of the trigger flow) for affected users.
## Risk Assessment
High frequency (23k+ events, 747 users) in production; likely does not crash the app but prevents ScoreMaster live-op presentation, which can block or skip subsequent live-op popups in the same trigger flow.
## Release Branch
v3.34.7
## Release Version
3.29.5
## Error Summary
NullReferenceException in `ScoreMasterLiveOpsPresenter.ProcessPresentationAsync` during `LiveOpsPresenter.IterateDynamicInApps`, triggered after `PersonalOffersLogic.Close` while iterating dynamic in-app operations.
## Root Cause
`ScoreMasterLiveOpsPresenter` assumes the tournament’s controllers are alive. When a tournament is completed, `ScoreMasterTournament.Dispose()` sets `GameRewardsGiveawaySequenceOperationController`, `LeaderboardController`, and related members to null, but the tournament can remain in `ScoreMasterLiveOpsModel` (notably for non-participated tournaments, where `ScoreMasterEndedTournamentsFinalizer` calls `Complete()` without removing the tournament). Subsequent trigger flows call `ProcessPresentationAsync`, retrieve the disposed tournament from the model, and dereference null controllers (e.g., `tournament.GameRewardsGiveawaySequenceOperationController.IsSequenceActive`).
## Affected Code
- `Assets/Scripts/LiveOps/ScoreMaster/ScoreMasterLiveOpsPresenter.cs`
- `Assets/Scripts/LiveOps/ScoreMaster/ScoreMasterLiveOpsController.cs`
- `Assets/Scripts/LiveOps/ScoreMaster/ScoreMasterEndedTournamentsFinalizer.cs`
- `Assets/Scripts/LiveOps/ScoreMaster/ScoreMasterTournament.cs`
## Suggested Fix
Ensure completed tournaments are removed from the live-ops model when they are completed (or guard against disposed tournaments before use).
- Preferred: In `ScoreMasterLiveOpsController.OnTournamentCompleted`, remove the tournament from the model and use the removed instance’s `InAppOperation` to continue notification logic:
  - `var tournament = _liveOpsModel.RemoveTournament(liveOpId);`
  - `var inAppOperation = tournament?.TournamentModel?.InAppOperation ?? _liveOpsModel.FindOperationByLiveOpId(liveOpId);`
  - proceed only if `inAppOperation` is not null.
- Defensive: In `ScoreMasterLiveOpsPresenter.ProcessPresentationAsync`, return early if `tournament.GameRewardsGiveawaySequenceOperationController`, `tournament.LeaderboardModel`, or `tournament.LeaderboardController` is null (and log once).
This removes the disposed objects from iteration and prevents the null dereference.
## Suggested Assignee
Artem Sukhliak (recent commits on affected files; Sentry issue already assigned)
