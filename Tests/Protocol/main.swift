import Foundation

func accepts(_ json: String) -> Bool { validatedRequest(Data(json.utf8)) != nil }
func check(_ result: Bool, _ message: String) { if !result { fatalError(message) } }
check(accepts("{\"command\":\"status\"}\n"), "Status must be accepted")
check(accepts("{\"command\":\"begin\",\"seconds\":30}\n"), "Valid bounded lease rejected")
check(accepts("{\"command\":\"renew\",\"seconds\":900,\"lease\":\"A4B694A3-4619-4C49-A06B-737FE1B4291B\"}\n"), "Valid renewal rejected")
for text in [
    "{\"command\":\"status\"}",
    "{\"command\":\"begin\",\"seconds\":true}\n",
    "{\"command\":\"begin\",\"seconds\":\"60\"}\n",
    "{\"command\":\"begin\",\"seconds\":null}\n",
    "{\"command\":\"begin\",\"seconds\":901}\n",
    "{\"command\":\"begin\",\"seconds\":0}\n",
    "{\"command\":\"begin\",\"password\":\"not accepted\"}\n",
    "{\"command\":\"end\"}\n",
    "{\"command\":\"end\",\"lease\":\"bad\"}\n",
    "{\"command\":\"unknown\"}\n",
    "{\"command\":1}\n", "[]\n", "{}\n", "null\n",
    "{\"command\":\"status\"}\n{\"command\":\"begin\"}\n",
    String(repeating: " ", count: 4096) + "{\"command\":\"status\"}\n"
] { check(!accepts(text), "Malformed request must never become an unlock request") }
print("PASS: protocol type, duration, field, lease, framing and size rejection")
