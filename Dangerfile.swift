// swiftlint:disable all
import Danger
import DangerXCodeSummary // package: https://github.com/f-meloni/danger-swift-xcodesummary.git

let danger = Danger()

// Ensure no copyright header
let changedFiles = (danger.git.modifiedFiles + danger.git.createdFiles).filter {
    $0 != "Dangerfile.swift"
}
let swiftFilesWithCopyright = changedFiles.filter {
    return $0.fileType == .swift && danger.utils.readFile($0).contains("//  Created by")
}
if swiftFilesWithCopyright.count > 0 {
    let files = swiftFilesWithCopyright.joined(separator: ", ")
    fail("Please remove the copyright header in: \(files)")
}

// Encourage smaller PRs
var bigPRThreshold = 1000;
if (danger.github.pullRequest.additions! + danger.github.pullRequest.deletions! > bigPRThreshold) {
    warn("> Pull Request size seems relatively large. If this Pull Request contains multiple changes, please split each into separate PR will helps faster, easier review.");
}

// DangerXCodeSummary
let summary = XCodeSummary(filePath: "result.json")
if summary.warningsCount > 0 {
    fail("Your PR has warnings")
}
if summary.errorsCount > 0 {
    fail("Your PR has errors")
}

