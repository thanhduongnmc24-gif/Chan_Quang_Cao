document.addEventListener("DOMContentLoaded", async () => {
  const strictEl = document.getElementById("strictLockAllLinks");
  const extNavEl = document.getElementById("blockExternalNav");
  const zapEl = document.getElementById("longPressZapEnabled");
  const clearBtn = document.getElementById("clearZappedBtn");

  try {
    const state = await browser.runtime.sendMessage({ type: "GET_STATE" });
    if (state) {
      strictEl.checked = !!state.strictLockAllLinks;
      extElChecked(state);
    }
  } catch (e) {}

  function extElChecked(state) {
    extNavEl.checked = state.blockExternalNav !== false;
    zapEl.checked = state.longPressZapEnabled !== false;
  }

  function update() {
    browser.runtime.sendMessage({
      type: "SET_STATE",
      payload: {
        strictLockAllLinks: strictEl.checked,
        blockExternalNav: extNavEl.checked,
        longPressZapEnabled: zapEl.checked
      }
    });
  }

  strictEl.addEventListener("change", update);
  extNavEl.addEventListener("change", update);
  zapEl.addEventListener("change", update);

  clearBtn.addEventListener("click", async () => {
    await browser.runtime.sendMessage({ type: "CLEAR_ZAPPED_SELECTORS" });
    clearBtn.textContent = "✅ Đã xóa danh sách khung ẩn!";
  });
});
