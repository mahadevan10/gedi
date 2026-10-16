import Testing
@testable import GediCore

@Test func parsesCleanJSON() {
    let r = GediReply.parse(#"{"speak": true, "line": "എന്തൂട്ടാ ഗഡീ?", "clip": "none"}"#)
    #expect(r == GediReply(speak: true, line: "എന്തൂട്ടാ ഗഡീ?", clip: nil))
}

@Test func keepsRealClipID() {
    let r = GediReply.parse(#"{"speak": true, "line": "x", "clip": "shorts_again"}"#)
    #expect(r?.clip == "shorts_again")
}

@Test func clipIsOptional() {
    #expect(GediReply.parse(#"{"speak": false, "line": ""}"#) == GediReply(speak: false, line: ""))
}

@Test func extractsJSONFromSurroundingText() {
    let r = GediReply.parse("Sure!\n```json\n{\"speak\": true, \"line\": \"കൊള്ളാട്ടാ\"}\n```")
    #expect(r?.line == "കൊള്ളാട്ടാ")
}

@Test func emptyLineMeansSilent() {
    #expect(GediReply.parse(#"{"speak": true, "line": "   "}"#)?.speak == false)
}

@Test func bareMalayalamIsAccepted() {
    #expect(GediReply.parse("പിന്നേം ഷോർട്സ്?") == GediReply(speak: true, line: "പിന്നേം ഷോർട്സ്?"))
}

@Test func garbageIsRejected() {
    #expect(GediReply.parse("I cannot help with that.") == nil)
    #expect(GediReply.parse("") == nil)
}
