import XCTest
@testable import QuickLookHelpers

final class MarkdownTableEditorTests: XCTestCase {

    func testReplacesEditedCellAndPreservesSurroundingMarkdown() {
        let markdown = """
        # Title

        | Name | Count |
        | --- | --- |
        | Alpha | 1 |
        | Beta | 2 |

        After
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Name", "Count"],
                ["Alpha Prime", "1"],
                ["Beta", "2"],
            ])
        )

        XCTAssertEqual(updated, """
        # Title

        | Name | Count |
        | --- | --- |
        | Alpha Prime | 1 |
        | Beta | 2 |

        After
        """)
    }

    func testReplacesRequestedTableWhenMultipleTablesExist() {
        let markdown = """
        | A | B |
        | --- | --- |
        | 1 | 2 |

        | C | D |
        | --- | --- |
        | 3 | 4 |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 1, rows: [
                ["C", "D", "E"],
                ["3", "4", "5"],
            ])
        )

        XCTAssertEqual(updated, """
        | A | B |
        | --- | --- |
        | 1 | 2 |

        | C | D | E |
        | --- | --- | --- |
        | 3 | 4 | 5 |
        """)
    }

    func testIgnoresPipeTablesInsideFencedCode() {
        let markdown = """
        ```
        | Not | A Table |
        | --- | --- |
        | x | y |
        ```

        | Real | Table |
        | --- | --- |
        | old | value |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Real", "Table"],
                ["new", "value"],
            ])
        )

        XCTAssertEqual(updated, """
        ```
        | Not | A Table |
        | --- | --- |
        | x | y |
        ```

        | Real | Table |
        | --- | --- |
        | new | value |
        """)
    }

    func testFenceCloseRequiresMatchingLength() {
        let markdown = """
        ````
        | Not | A Table |
        | --- | --- |
        | x | y |
        ```

        | Real | Table |
        | --- | --- |
        | old | value |
        ````
        """

        XCTAssertNil(MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Real", "Table"],
                ["new", "value"],
            ])
        ))
    }

    func testIgnoresIndentedCodeTables() {
        let markdown = """
            | Not | A Table |
            | --- | --- |
            | x | y |

        | Real | Table |
        | --- | --- |
        | old | value |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Real", "Table"],
                ["new", "value"],
            ])
        )

        XCTAssertEqual(updated, """
            | Not | A Table |
            | --- | --- |
            | x | y |

        | Real | Table |
        | --- | --- |
        | new | value |
        """)
    }

    func testIndentedFenceOpenerDoesNotHideFollowingTable() {
        let markdown = """
            ```

        | Real | Table |
        | --- | --- |
        | old | value |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Real", "Table"],
                ["new", "value"],
            ])
        )

        XCTAssertEqual(updated, """
            ```

        | Real | Table |
        | --- | --- |
        | new | value |
        """)
    }

    func testReplacesBlockquotedTableByRenderedIndex() {
        let markdown = """
        > | A | B |
        > | --- | --- |
        > | old | y |

        | Real | Table |
        | --- | --- |
        | keep | value |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["A", "B"],
                ["new", "y"],
            ])
        )

        XCTAssertEqual(updated, """
        > | A | B |
        > | --- | --- |
        > | new | y |

        | Real | Table |
        | --- | --- |
        | keep | value |
        """)
    }

    func testPreservesUneditedInlineMarkdownCells() {
        let markdown = """
        | Link | Bold | Plain |
        | --- | --- | --- |
        | [site](https://example.com) | **bold** | old |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(
                tableIndex: 0,
                rows: [
                    ["Link", "Bold", "Plain"],
                    ["site", "bold", "new"],
                ],
                dirtyRows: [
                    [false, false, false],
                    [false, false, true],
                ]
            )
        )

        XCTAssertEqual(updated, """
        | Link | Bold | Plain |
        | --- | --- | --- |
        | [site](https://example.com) | **bold** | new |
        """)
    }

    func testPreservesExistingColumnAlignment() {
        let markdown = """
        | Left | Center | Right |
        | :--- | :---: | ---: |
        | a | b | c |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Left", "Center", "Right", "New"],
                ["aa", "bb", "cc", "dd"],
            ])
        )

        XCTAssertEqual(updated, """
        | Left | Center | Right | New |
        | :--- | :---: | ---: | --- |
        | aa | bb | cc | dd |
        """)
    }

    func testDoesNotAcceptSeparatorWithDifferentColumnCount() {
        let markdown = """
        a | b
        ---

        | Real | Table |
        | --- | --- |
        | old | value |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["Real", "Table"],
                ["new", "value"],
            ])
        )

        XCTAssertEqual(updated, """
        a | b
        ---

        | Real | Table |
        | --- | --- |
        | new | value |
        """)
    }

    func testEscapesPipesAndFlattensNewlinesInCells() {
        let markdown = """
        | A | B |
        | --- | --- |
        | 1 | 2 |
        """

        let updated = MarkdownTableEditor.replacingTable(
            in: markdown,
            with: .init(tableIndex: 0, rows: [
                ["A", "B"],
                ["a | b", "line\nbreak"],
            ])
        )

        XCTAssertEqual(updated, """
        | A | B |
        | --- | --- |
        | a \\| b | line break |
        """)
    }
}

final class MarkdownTaskListEditorTests: XCTestCase {
    func testTogglesRequestedTask() {
        let markdown = """
        - [ ] First
        - [x] Second
        """

        XCTAssertEqual(
            MarkdownTaskListEditor.togglingTask(in: markdown, taskIndex: 1, checked: false),
            """
            - [ ] First
            - [ ] Second
            """
        )
    }

    func testPreservesMarkerStyleAndCaseByOnlyReplacingCheckmark() {
        let markdown = """
        1. [ ] Ordered
        * [X] Star
        """

        XCTAssertEqual(
            MarkdownTaskListEditor.togglingTask(in: markdown, taskIndex: 0, checked: true),
            """
            1. [x] Ordered
            * [X] Star
            """
        )
    }

    func testIgnoresTasksInsideFencedAndIndentedCode() {
        let markdown = """
        ```
        - [ ] Not task
        ```

            - [ ] Not task either

        - [ ] Real task
        """

        XCTAssertEqual(
            MarkdownTaskListEditor.togglingTask(in: markdown, taskIndex: 0, checked: true),
            """
            ```
            - [ ] Not task
            ```

                - [ ] Not task either

            - [x] Real task
            """
        )
    }

    func testTogglesNestedAndBlockquotedTasksByRenderedIndex() {
        let markdown = """
        - [ ] Parent
          - [ ] Nested
        > - [x] Quoted
        """

        XCTAssertEqual(
            MarkdownTaskListEditor.togglingTask(in: markdown, taskIndex: 2, checked: false),
            """
            - [ ] Parent
              - [ ] Nested
            > - [ ] Quoted
            """
        )
    }

    func testTogglesTaskInNestedBlockquote() {
        let markdown = """
        > > - [ ] Nested quote
        - [ ] Plain
        """

        XCTAssertEqual(
            MarkdownTaskListEditor.togglingTask(in: markdown, taskIndex: 0, checked: true),
            """
            > > - [x] Nested quote
            - [ ] Plain
            """
        )
    }

    func testTogglesTaskInCRLFDocumentWithoutChangingLineEndings() {
        let markdown = "- [ ] First\r\n- [x] Second\r\n"

        XCTAssertEqual(
            MarkdownTaskListEditor.togglingTask(in: markdown, taskIndex: 0, checked: true),
            "- [x] First\r\n- [x] Second\r\n"
        )
    }
}

final class RenderedEditHistoryTests: XCTestCase {
    func testRecordsUndoAndRedoStatesInOrder() {
        var history = RenderedEditHistory()

        history.record(before: "one", after: "two", actionName: "Edit Table")
        history.record(before: "two", after: "three", actionName: "Check Task")

        XCTAssertEqual(history.nextUndoActionName, "Check Task")

        let firstUndo = history.undo()
        XCTAssertEqual(firstUndo?.before, "two")
        XCTAssertEqual(firstUndo?.after, "three")
        XCTAssertEqual(history.nextRedoActionName, "Check Task")

        let secondUndo = history.undo()
        XCTAssertEqual(secondUndo?.before, "one")
        XCTAssertEqual(secondUndo?.after, "two")
        XCTAssertFalse(history.canUndo)

        let firstRedo = history.redo()
        XCTAssertEqual(firstRedo?.after, "two")
        XCTAssertEqual(history.nextUndoActionName, "Edit Table")

        let secondRedo = history.redo()
        XCTAssertEqual(secondRedo?.after, "three")
        XCTAssertFalse(history.canRedo)
    }

    func testLongUndoRedoChainHasNoArtificialCap() {
        var history = RenderedEditHistory()
        let states = (0...80).map { "state-\($0)" }

        for index in 1..<states.count {
            history.record(before: states[index - 1],
                           after: states[index],
                           actionName: "Edit \(index)")
        }

        for expectedIndex in stride(from: states.count - 1, through: 1, by: -1) {
            let edit = history.undo()
            XCTAssertEqual(edit?.before, states[expectedIndex - 1])
            XCTAssertEqual(edit?.after, states[expectedIndex])
        }
        XCTAssertFalse(history.canUndo)

        for expectedIndex in 1..<states.count {
            let edit = history.redo()
            XCTAssertEqual(edit?.before, states[expectedIndex - 1])
            XCTAssertEqual(edit?.after, states[expectedIndex])
        }
        XCTAssertFalse(history.canRedo)
    }

    func testNewEditAfterUndoClearsRedoStack() {
        var history = RenderedEditHistory()

        history.record(before: "one", after: "two", actionName: "Edit Table")
        history.record(before: "two", after: "three", actionName: "Check Task")
        _ = history.undo()

        history.record(before: "two", after: "four", actionName: "Uncheck Task")

        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.nextUndoActionName, "Uncheck Task")
        XCTAssertEqual(history.undo()?.before, "two")
    }

    func testNoOpAndInitialLoadsDoNotCreateUndoEntries() {
        var history = RenderedEditHistory()

        history.record(before: nil, after: "loaded", actionName: "Load Document")
        history.record(before: "same", after: "same", actionName: "Edit Table")

        XCTAssertFalse(history.canUndo)
        XCTAssertNil(history.undo())
        XCTAssertNil(history.redo())
    }

    func testClearDropsBothStacks() {
        var history = RenderedEditHistory()

        history.record(before: "one", after: "two", actionName: "Edit Table")
        _ = history.undo()
        history.clear()

        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }
}
