import XCTest

final class WorkoutFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCoreStrengthWorkoutFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-store"]
        app.launch()

        let planTab = app.tabBars.buttons["Plan"]
        XCTAssertTrue(planTab.waitForExistence(timeout: 8))
        planTab.tap()

        let template = app.staticTexts["Full Body Strength"].firstMatch
        XCTAssertTrue(template.waitForExistence(timeout: 6))
        template.tap()

        let start = app.buttons["template.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let exercise = app.staticTexts["workout.exerciseName"]
        XCTAssertTrue(exercise.waitForExistence(timeout: 5))
        // Wait for the name rather than sampling it once: the element exists
        // before the new workout's first exercise has been laid into it, and
        // reading it immediately made this fail only when the whole suite ran.
        let named = expectation(
            for: NSPredicate(format: "label CONTAINS %@", "Goblet Squat"),
            evaluatedWith: exercise
        )
        XCTAssertEqual(XCTWaiter.wait(for: [named], timeout: 8), .completed)

        let complete = app.buttons["workout.completeSet"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        XCTAssertTrue(app.staticTexts["workout.restTimer"].waitForExistence(timeout: 3))

        if app.buttons["workout.skipRest"].waitForExistence(timeout: 2) {
            app.buttons["workout.skipRest"].tap()
        }

        if complete.waitForExistence(timeout: 3) {
            complete.tap()
        }

        if app.buttons["workout.finishExercise"].waitForExistence(timeout: 3) {
            app.buttons["workout.finishExercise"].tap()
        }

        app.buttons["workout.menu"].tap()
        app.buttons["Finish workout"].tap()

        let save = app.buttons["workout.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 6))
        save.tap()

        app.tabBars.buttons["History"].tap()
        // The row reads "<date> — <name>, <summary>", so assert on the row's
        // identifier and match the name by containment rather than equality.
        let historyRow = app.buttons["history.row"].firstMatch
        XCTAssertTrue(historyRow.waitForExistence(timeout: 6))
        XCTAssertTrue(historyRow.label.contains("Full Body Strength"))
    }

    /// The plank timer is useless if you have to scroll to start it. This broke
    /// twice while the hold timer was being laid out, so it is asserted.
    func testPlankHoldTimerIsReachableWithoutScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--reset-store"]
        app.launch()

        // Started from the template rather than `today.start`: the plank only
        // exists in the strength workout, so going through Today made this pass
        // on Mondays and Thursdays and fail every other day — on Tuesday it
        // opened Easy Cardio and skipped straight past the end of the workout.
        let planTab = app.tabBars.buttons["Plan"]
        XCTAssertTrue(planTab.waitForExistence(timeout: 10))
        planTab.tap()

        let template = app.staticTexts["Full Body Strength"].firstMatch
        XCTAssertTrue(template.waitForExistence(timeout: 6))
        template.tap()

        let start = app.buttons["template.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        XCTAssertTrue(app.staticTexts["workout.exerciseName"].waitForExistence(timeout: 6))

        // Skip the six weighted exercises to reach the plank.
        for _ in 0..<6 {
            app.buttons["workout.menu"].tap()
            app.buttons["Skip exercise"].tap()
        }

        let startHold = app.buttons["workout.startHold"]
        XCTAssertTrue(startHold.waitForExistence(timeout: 5))
        XCTAssertTrue(startHold.isHittable, "START HOLD must be on screen without scrolling")

        startHold.tap()
        XCTAssertTrue(app.buttons["workout.stopHold"].waitForExistence(timeout: 3))
    }

}
