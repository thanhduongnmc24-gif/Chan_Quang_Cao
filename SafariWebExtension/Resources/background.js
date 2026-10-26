const DEFAULT_STATE = {
  blockExternalNav: true,
  strictLockAllLinks: false,
  longPressZapEnabled: true,
  autoRemoveFloatingBanners: true,
  customBlockedSelectors: []
};

// Sync with native iOS App Group if available, and persist in browser.storage.local
async function getState() {
  try {
    const data = await browser.storage.local.get(DEFAULT_STATE);
    return { ...DEFAULT_STATE, ...data };
  } catch (e) {
    return DEFAULT_STATE;
  }
}

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === "GET_STATE") {
    getState().then(state => sendResponse(state));
    return true;
  }

  if (message.type === "SET_STATE") {
    browser.storage.local.set(message.payload).then(async () => {
      const updated = await getState();
      // Broadcast to all active tabs
      try {
        const tabs = await browser.tabs.query({});
        for (const tab of tabs) {
          if (tab.id) {
            browser.tabs.sendMessage(tab.id, { type: "STATE_UPDATED", payload: updated }).catch(() => {});
          }
        }
      } catch (e) {}
      sendResponse(updated);
    });
    return true;
  }

  if (message.type === "ADD_ZAPPED_SELECTOR") {
    getState().then(async state => {
      const list = Array.isArray(state.customBlockedSelectors) ? state.customBlockedSelectors : [];
      if (message.selector && !list.includes(message.selector)) {
        list.push(message.selector);
        await browser.storage.local.set({ customBlockedSelectors: list });
      }
      // Also notify native container if available
      try {
        browser.runtime.sendNativeMessage("com.adshield.pro", {
          action: "saveZappedSelector",
          selector: message.selector
        }).catch(() => {});
      } catch (e) {}
      sendResponse({ customBlockedSelectors: list });
    });
    return true;
  }

  if (message.type === "CLEAR_ZAPPED_SELECTORS") {
    browser.storage.local.set({ customBlockedSelectors: [] }).then(() => {
      sendResponse({ customBlockedSelectors: [] });
    });
    return true;
  }
});
