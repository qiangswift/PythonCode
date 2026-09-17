"""Check the Objective-C embedded WebView script with the runner's Node.js."""

import json
import re
import subprocess
from pathlib import Path


source = (Path(__file__).resolve().parents[1] / "Tweak.xm").read_text(encoding="utf-8")
script_function = source.split("static NSString *FMWebScript(void) {", 1)[1].split(
    "static NSDictionary *FMResponseFields", 1
)[0]
chunks = re.findall(r'@"((?:\\.|[^"\\])*)"', script_function)
assert len(chunks) > 5, "WebView script literals not found"
script = "".join(json.loads('"' + chunk + '"') for chunk in chunks)

smoke_test = r"""
const vm = require('vm');
const assert = require('assert');
const messages = [];
const vane = {call: function(c, m, p, ok) {ok({ret: ['ERROR_CODE::try later']});}};
function XMLHttpRequest() {}
XMLHttpRequest.prototype.open = function() {};
XMLHttpRequest.prototype.send = function() {};
const window = {WindVane: vane, webkit: {messageHandlers: {
  fmClaimProbe: {postMessage: x => messages.push(x)}
}}};
function MutationObserver() {}
MutationObserver.prototype.observe = function() {};
vm.runInNewContext(process.argv[1], {
  window, location: {hostname: 'ssr.m.goofish.com'},
  XMLHttpRequest, MutationObserver, document: {}, URL,
  setInterval: () => 0, setTimeout: () => 0
});
vane.call('WVTest', 'take', {}, function() {});
assert(messages.some(x => x.kind === 'bridge' && x.api === 'bridge:WVTest/take'));
assert(messages.some(x => x.kind === 'bridge-result' && x.fields.ret[0] === 'ERROR_CODE::try later'));
console.log('WEB_BRIDGE_SMOKE_OK');
"""
subprocess.run(["node", "-e", smoke_test, script], check=True)
