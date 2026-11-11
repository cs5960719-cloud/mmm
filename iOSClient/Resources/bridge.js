(function () {
  'use strict';
  if (window.__iosSlotBridge) return;
  window.__iosSlotBridge = true;
  var token = __IOS_SESSION_TOKEN__;
  function send(method, detail) {
    try { window.webkit.messageHandlers.iosSlot.postMessage({token: token, method: method, detail: String(detail || '')}); }
    catch (_) {}
  }
  window.CdkBridge = {
    entered: function () { send('entered'); },
    needRole: function () { send('needRole'); },
    fail: function () { send('fail'); },
    restartGame: function () { send('restartGame'); }
  };
  var last = '';
  setInterval(function () {
    if (!window.__iosHelperInjected) return;
    var state = window.__hangjiModules ? window.__hangjiModules.status().status : 'legacy';
    if (state !== last) { last = state; send('health', state); }
  }, 5000);
})();
