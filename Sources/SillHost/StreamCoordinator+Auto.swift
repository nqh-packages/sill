import Foundation
import StreamProtocol

// Auto's shell (docs/adaptive-quality-plan.md, "codebase-design check"): everything the coordinator does
// with `AutoQuality`, in one place. The policy itself is pure (AutoQuality.swift); this file feeds it each
// second, turns its step into a live lower or a restart, and is the one place what runs moves
// (`commitRunning`). Tests/checks/auto-seam declares and enforces who may call `lowerBitrate(`, who may
// assign `autoRunning` and who may construct `AutoQuality(`.
extension StreamCoordinator {
    /// The place `awayWanted` names runs Auto: the target's quality for it is Auto and it is the place
    /// the pipeline runs (a flip still waiting for its restart is not governed yet).
    func autoGoverns(away: Bool) -> Bool {
        target.choice(away: away) == .auto && awayWanted == away
    }

    /// The rung the pair `away` is told (`settingsState`): the running one when Auto runs that place,
    /// else nil (`HostConfig.running(away:auto:)` then gives the place's start, or the fixed rate).
    func autoRung(forAway away: Bool) -> AutoQuality.Rung? {
        autoGoverns(away: away) ? autoRunning : nil
    }

    /// Auto wants a rung the pipeline does not run: `applyPending` wakes for it, and `restartNeeded`
    /// resolves the target through `running(away:auto:)`.
    var autoStepPending: Bool {
        guard let auto, awayRunning == awayWanted, config.choice(away: awayRunning) == .auto else { return false }
        return auto.rung != autoRunning
    }

    /// After `setTarget`, a flip between home and away, and a stream's start or stop: makes an
    /// AutoQuality when the target's quality for the place `awayWanted` names is Auto and there is none
    /// for that place and the Mac's Resolution; drops it when the quality is fixed or nothing streams, so
    /// the next stream starts at the start (decision 4). Logs `startLine` when it makes one. Idempotent.
    /// `streaming`: whether a stream runs (or is about to, inside `select`); `active` by default.
    func syncAuto(streaming: Bool? = nil) {
        let t = target
        let away = awayWanted
        guard streaming ?? (active != .none), t.choice(away: away) == .auto else { auto = nil; return }
        let retina = (away ? t.awayCaptureScale : t.captureScale) >= 1.5
        let place: AutoQuality.Place = away ? .away : .home
        if let auto, auto.place == place, auto.ladder == AutoQuality.ladder(retina: retina) { return }
        let made = AutoQuality(place: place, retina: retina)
        auto = made
        print(AutoQuality.startLine(place: place, rung: made.rung))
    }

    /// `StreamServer.onSecond`, on the main actor: each device's verdict first ("Link to …" lines, the
    /// card's rows), then the second goes to Auto, so a step's line always follows the lines that explain it.
    func serverSecond(_ closed: [ObjectIdentifier: StreamServer.ClosedSecond]) {
        for (id, entry) in closed { if let verdict = entry.verdict { linkChanged(id, verdict) } }
        autoSecond(closed.mapValues(\.second))
    }

    /// Closes one second for Auto. A step prints its line, bumps `auto.live` or `auto.restart`, and is
    /// taken: lowered live in place, or through `applyPending`, whose guard wakes for `autoStepPending`.
    private func autoSecond(_ seconds: [ObjectIdentifier: LinkJudge.Second]) {
        guard var a = auto, let running = autoRunning, active != .none, !switching, !shuttingDown,
              awayRunning == awayWanted, config.choice(away: awayRunning) == .auto else { return }
        let step = a.close(seconds, governing: AutoQuality.governing(routes.mapValues(\.isAway)), running: running, fps: fps)
        auto = a
        guard let step else { return }
        print(AutoQuality.stepLine(step) { id in
            let device = status.snapshot.devices.first { $0.id == id }
            return device?.name ?? device?.endpoint ?? "a device"
        })
        Stats.shared.bump(step.how == .live ? "auto.live" : "auto.restart")
        switch step.how {
        case .live: lowerLive(step.to)
        case .restart: Task { @MainActor in await applyPending() }
        }
    }

    /// A live step: the running session's rate lowered in place (`lowerBitrate`), then `commitRunning`.
    /// When the encoder says no (none running, not a lower) the step goes by `applyPending` instead.
    private func lowerLive(_ rung: AutoQuality.Rung) {
        if encoder?.lowerBitrate(to: rung.bitrate * fps / 60) == true {
            commitRunning(rung, streaming: true)
        } else {
            Task { @MainActor in await applyPending() }
        }
    }

    /// THE commit point of what runs, called by `select`'s commit (the rung Auto wants, or nil for a fixed
    /// quality), `applyPending`'s no-restart adoption, and `lowerLive`. In one go: `autoRunning` moves;
    /// the devices' links are judged at what runs now (their reports start afresh, as for any new
    /// quality: `judgeLinks`); the menu's stream line shows the new rate; and every device is told
    /// (`publishSettings`). `restartNeeded`, the link filter in `settingsState` and every reader of
    /// `bitrate` then agree. `streaming`: a stream runs, or is about to (`select` has not set `active`).
    func commitRunning(_ rung: AutoQuality.Rung?, streaming: Bool) {
        autoRunning = rung
        judgeLinks(streaming ? LinkJudge.Quality(bitrate: bitrate, fps: fps, captureScale: Double(captureScale)) : nil)
        if !switching, status.snapshot.stream != nil {
            let mbps = bitrate * fps / 60 / 1_000_000
            status.update { $0.stream?.mbps = mbps }
        }
        publishSettings()
    }
}
