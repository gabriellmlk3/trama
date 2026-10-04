import Foundation
import XCTest
@testable import trama

final class AgentAttachmentsTests: XCTestCase {
    func testStoreCopiesFileKeepingItsName() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let source = Paths.join(lab.root, "relatório final.pdf")
        try Data("pdf".utf8).write(to: URL(fileURLWithPath: source))
        let directory = AgentAttachments.directory(root: lab.root)

        let attachment = try AgentAttachments.store(file: source, in: directory)
        XCTAssertEqual(attachment.name, "relatório final.pdf")
        XCTAssertTrue(attachment.path.hasPrefix(directory))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: attachment.path)), Data("pdf".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source))

        AgentAttachments.discard(attachment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachment.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source))
    }

    func testStoreRejectsFoldersAndMissingFiles() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let directory = AgentAttachments.directory(root: lab.root)
        XCTAssertThrowsError(try AgentAttachments.store(file: lab.root, in: directory))
        XCTAssertThrowsError(try AgentAttachments.store(file: Paths.join(lab.root, "nao-existe.png"), in: directory))
    }

    func testStoreDataSanitizesTheName() throws {
        let lab = try Lab()
        defer { lab.cleanup() }
        let directory = AgentAttachments.directory(root: lab.root)
        let attachment = try AgentAttachments.store(data: Data([1, 2, 3]), name: "a/b.png", in: directory)
        XCTAssertEqual(attachment.name, "a-b.png")
        XCTAssertTrue(attachment.isImage)
    }

    func testPromptListsEveryFilePath() {
        let files = [AgentAttachment(path: "/x/1/a.png", name: "a.png"), AgentAttachment(path: "/x/2/b.pdf", name: "b.pdf")]
        let prompt = AgentAttachments.prompt(text: "o que mudou?", files: files)
        XCTAssertTrue(prompt.hasPrefix("o que mudou?"))
        XCTAssertTrue(prompt.contains("- /x/1/a.png"))
        XCTAssertTrue(prompt.contains("- /x/2/b.pdf"))
        XCTAssertEqual(AgentAttachments.prompt(text: "oi", files: []), "oi")
        XCTAssertTrue(AgentAttachments.prompt(text: "  ", files: files).hasPrefix("Veja os arquivos anexados."))
    }

    func testUserItemKeepsAttachmentNames() {
        var conversation = AgentConversation()
        conversation.addUser("olha isso", attachments: ["a.png"])
        XCTAssertEqual(conversation.items.first?.attachments, ["a.png"])
    }
}
