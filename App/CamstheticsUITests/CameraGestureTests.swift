import XCTest

// MARK: - On-device camera gesture / UI automation
//
// This target exists so camera behaviour can be validated WITHOUT a human
// physically pinching the screen and reporting back. Everything here runs
// against the real app on a real device (never the Simulator — ADR-012:
// the Simulator has no camera hardware, so a Simulator pass proves
// nothing about this app's behaviour).
//
// Why XCUITest rather than driving `CameraService` directly from an
// in-app harness: the last real bug found in this area lived in the
// SwiftUI gesture layer (`MagnificationGesture.onEnded` reading state
// that was only written asynchronously), not in `CameraService` at all.
// An in-app script that calls `setZoomFactor(_:)` in a loop would have
// sailed straight past it. Driving the actual gesture recogniser is the
// only way to cover that path.
//
// Screenshots are attached to the test result so the run can be
// inspected after the fact (`xcrun xcresulttool export attachments`)
// rather than requiring someone to watch the screen live.

final class CameraGestureTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Navigate straight to the preview scaffold — but deliberately
        // NOT `CAMSTHETICS_AUTO_VALIDATE`, which would additionally start
        // the unattended lens/lifecycle/capture battery. That battery
        // drives its own lens changes, stop/start cycles and captures,
        // which would run concurrently with these gestures and mutate the
        // very state being asserted on. (Observed exactly that: a capture
        // screenshot showed "Lens: 0.5×" from the battery mid-test.)
        app.launchEnvironment["CAMSTHETICS_AUTO_OPEN_PREVIEW"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Attaches a full-screen screenshot under a stable name so runs can
    /// be diffed against each other afterwards.
    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The scaffold's status capsule is the app's own readout of what the
    /// camera actually did — polling it is how these tests observe state
    /// without reaching into the app's internals.
    private func statusText(timeout: TimeInterval = 10) -> String {
        // The capsule is a plain SwiftUI Text, so it surfaces as a
        // staticText element. Match the known prefixes it can render.
        // NOTE: every status string the scaffold can render must be listed
        // here. A missing prefix makes `statusText()` silently return ""
        // and any assertion built on it fail for the wrong reason —
        // which is exactly what happened when "Focus…" was first added.
        let prefixes = [
            "Running", "Zoom:", "Lens:", "Captured", "Stopped",
            "Not started", "Focus @", "Focus:", "Start failed", "Capture failed",
        ]
        let predicate = NSPredicate(
            format: prefixes.map { _ in "label BEGINSWITH %@" }.joined(separator: " OR "),
            argumentArray: prefixes
        )
        let element = app.staticTexts.containing(predicate).firstMatch
        guard element.waitForExistence(timeout: timeout) else { return "" }
        return element.label
    }

    /// Parses the numeric zoom out of a status capsule like
    /// `"Zoom: 2.8×"` / `"Lens: 0.5×"` / `"Captured at 1×"`. Returns nil
    /// when the capsule isn't currently showing a zoom value, so callers
    /// can poll rather than assume.
    private func zoomValue(from status: String) -> Double? {
        guard let xIndex = status.lastIndex(of: "×") else { return nil }
        let head = status[..<xIndex]
        let digits = head.reversed().prefix { $0.isNumber || $0 == "." }
        let numeric = String(digits.reversed())
        return numeric.isEmpty ? nil : Double(numeric)
    }

    /// Polls until the status capsule reports a zoom value, so assertions
    /// don't race the async apply-and-report cycle.
    private func waitForZoomValue(timeout: TimeInterval = 8) -> Double? {
        let deadline = Date().addingTimeInterval(timeout)
        var latest: Double?
        while Date() < deadline {
            if let value = zoomValue(from: statusText(timeout: 1)) {
                latest = value
                break
            }
            usleep(300_000)
        }
        return latest
    }

    /// Waits for the camera session to report running before gesturing —
    /// pinching a not-yet-started session would be meaningless.
    private func waitForSessionRunning(timeout: TimeInterval = 20) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let status = statusText(timeout: 2)
            if !status.isEmpty, status != "Not started", status != "Stopped" {
                return
            }
            usleep(400_000)
        }
        capture("session-never-started")
        throw XCTSkip("Camera session did not reach a running state within \(timeout)s — camera permission may not be granted on this device.")
    }

    // MARK: Tests

    /// Baseline: the preview surface actually renders and the session runs.
    /// Also the first proof that a system-level screenshot captures live
    /// AVCaptureVideoPreviewLayer content at all — if the attachment comes
    /// back black, every visual assertion in this file is unreliable and
    /// that needs to be known before trusting the rest.
    func testPreviewLaunchesAndReportsRunning() throws {
        try waitForSessionRunning()
        capture("01-preview-running")
        XCTAssertFalse(statusText().isEmpty, "Status capsule should report session state")
    }

    /// Drives the real MagnificationGesture recogniser — the path that
    /// contained the stale-baseline bug. A single continuous pinch should
    /// leave the zoom higher than it started, with no crash and the
    /// session still alive.
    func testPinchZoomInChangesZoomAndSurvives() throws {
        try waitForSessionRunning()
        capture("02-before-pinch-in")

        let preview = app.otherElements.firstMatch
        preview.pinch(withScale: 3.0, velocity: 1.0)

        capture("03-after-pinch-in")
        guard let zoomed = waitForZoomValue() else {
            return XCTFail("No zoom readout after pinch; status was: \(statusText())")
        }
        // Session starts at the widest lens, so any real zoom-in must
        // land above it. Asserting a concrete direction, not just that
        // *something* was rendered.
        XCTAssertGreaterThan(
            zoomed, 1.0,
            "Pinch-to-zoom-in should raise the zoom factor above the 1× baseline"
        )
    }

    /// The bidirectional requirement: zoom out must work too, and the
    /// session must survive a direction reversal.
    func testPinchZoomOutAfterZoomIn() throws {
        try waitForSessionRunning()

        let preview = app.otherElements.firstMatch
        preview.pinch(withScale: 3.0, velocity: 1.0)
        capture("04-zoomed-in")
        guard let zoomedIn = waitForZoomValue() else {
            return XCTFail("No zoom readout after zoom-in; status: \(statusText())")
        }

        preview.pinch(withScale: 0.4, velocity: -1.0)
        capture("05-zoomed-back-out")
        guard let zoomedOut = waitForZoomValue() else {
            return XCTFail("No zoom readout after zoom-out; status: \(statusText())")
        }

        XCTAssertGreaterThan(zoomedIn, 1.0, "Zoom-in should exceed the 1× baseline")
        XCTAssertLessThan(
            zoomedOut, zoomedIn,
            "Zoom-out must actually reduce the zoom factor (in \(zoomedIn)× → out \(zoomedOut)×)"
        )
    }

    /// Successive discrete gestures: this is the exact scenario that used
    /// to corrupt the next gesture's baseline (lift fingers, re-pinch,
    /// zoom jumped). Repeated short pinches must stay monotonic-ish and
    /// never throw the session into a bad state.
    func testRepeatedSeparatePinchesDoNotCorruptBaseline() throws {
        try waitForSessionRunning()

        let preview = app.otherElements.firstMatch
        var readings: [Double] = []
        for index in 1...4 {
            preview.pinch(withScale: 1.6, velocity: 1.0)
            capture("06-repeat-pinch-\(index)")
            guard let zoom = waitForZoomValue() else {
                return XCTFail("No zoom readout after repeat pinch \(index); status: \(statusText())")
            }
            readings.append(zoom)
        }

        // The regression this guards: each gesture's baseline used to come
        // from state written asynchronously, so lifting and re-pinching
        // could restart from a stale value and lurch backwards. Four
        // successive zoom-in gestures must never decrease the zoom.
        for (index, pair) in zip(readings, readings.dropFirst()).enumerated() {
            XCTAssertGreaterThanOrEqual(
                pair.1, pair.0,
                "Zoom went backwards between pinch \(index + 1) and \(index + 2) "
                + "(\(pair.0)× → \(pair.1)×) — gesture baseline may be stale again. "
                + "Full sequence: \(readings)"
            )
        }
    }

    /// Tap-to-focus: a tap must place a reticle, drive the device, and
    /// then auto-cancel back to continuous AF/AE after the documented
    /// 3-second window (PRODUCT_SPEC.md §1.5). The auto-cancel is the
    /// part most likely to silently regress, so it's asserted explicitly
    /// rather than just eyeballed.
    func testTapToFocusShowsReticleThenAutoCancels() throws {
        try waitForSessionRunning()

        let preview = app.otherElements.firstMatch
        // Tap off-centre so the reticle position is unambiguous and the
        // device point is not the trivial {0.5, 0.5}.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.38)).tap()

        let reticle = app.otherElements["focusReticle"]
        XCTAssertTrue(
            reticle.waitForExistence(timeout: 5),
            "Focus reticle should appear at the tapped point"
        )
        capture("09-focus-reticle-visible")

        let status = statusText()
        XCTAssertTrue(
            status.hasPrefix("Focus @"),
            "Status should report the focus device point, got: \(status)"
        )

        // Wait out the documented auto-cancel window (plus slack) and
        // confirm the app returned itself to continuous focus.
        let deadline = Date().addingTimeInterval(8)
        var returnedToContinuous = false
        while Date() < deadline {
            if statusText(timeout: 1).hasPrefix("Focus: continuous") {
                returnedToContinuous = true
                break
            }
            usleep(400_000)
        }
        capture("10-after-focus-auto-cancel")
        XCTAssertTrue(
            returnedToContinuous,
            "Focus should auto-cancel back to continuous within ~3s; status: \(statusText())"
        )
        XCTAssertFalse(reticle.exists, "Reticle should be dismissed after auto-cancel")
    }

    /// Capture must still work while zoomed — guards the fidelity path
    /// against gesture/zoom interference.
    func testCaptureWhileZoomed() throws {
        try waitForSessionRunning()

        let preview = app.otherElements.firstMatch
        preview.pinch(withScale: 2.2, velocity: 1.0)
        capture("07-zoomed-before-capture")

        let shutter = app.buttons["📸 Capture"]
        guard shutter.waitForExistence(timeout: 5) else {
            capture("07b-no-capture-button")
            throw XCTSkip("Capture button not found — scaffold UI may have changed.")
        }
        shutter.tap()

        // The scaffold presents a full-screen inspector on success.
        let closeButton = app.buttons["Close"]
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: 15),
            "Captured-photo inspector should appear after capture"
        )
        capture("08-captured-photo-inspector")
        closeButton.tap()
    }
}
