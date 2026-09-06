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
        XCTAssertTrue(exercise.label.contains("Goblet Squat"))

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
        XCTAssertTrue(app.staticTexts["Full Body Strength"].waitForExistence(timeout: 6))
    }
}
