(function () {
  "use strict";

  let state = {
    blockExternalNav: true,      // Chặn mở trang khác (khác tên miền & tab mới _blank / window.open)
    strictLockAllLinks: false,   // Khóa toàn bộ liên kết: Bấm vào bất kỳ liên kết nào cũng không mở trang khác
    longPressZapEnabled: true,   // Nhấn giữ (650ms) vào bất kỳ panel/khung nào trên web để chặn & xóa
    autoRemoveFloatingBanners: true, // Tự động quét và tiêu diệt khung quảng cáo nổi/nhà cái
    customBlockedSelectors: []
  };

  // Load settings from storage or localStorage fallback
  function loadState() {
    try {
      const localSaved = localStorage.getItem("__adshield_local_state__");
      if (localSaved) {
        const parsed = JSON.parse(localSaved);
        state = { ...state, ...parsed };
      }
    } catch (e) {}

    if (typeof browser !== "undefined" && browser.runtime && browser.runtime.sendMessage) {
      browser.runtime.sendMessage({ type: "GET_STATE" }).then(res => {
        if (res) {
          state = { ...state, ...res };
          applySavedSelectors();
          updateFloatingPill();
        }
      }).catch(() => {});
    }
  }

  function saveLocalStateFallback() {
    try {
      localStorage.setItem("__adshield_local_state__", JSON.stringify(state));
    } catch (e) {}
  }

  // 1. OVERRIDE window.open to stop popups/new tab redirects immediately
  try {
    const originalWindowOpen = window.open;
    Object.defineProperty(window, "open", {
      configurable: true,
      writable: true,
      value: function (url, target, features) {
        if (state.strictLockAllLinks || state.blockExternalNav) {
          showToast("🛡️ Đã chặn tự động mở trang mới!");
          return null;
        }
        return originalWindowOpen.call(window, url, target, features);
      }
    });
  } catch (e) {}

  // 2. INTERCEPT ALL CLICKS ON LINKS (<a>) AND INVISIBLE OVERLAYS
  function handleLinkClick(e) {
    // Do not block clicks on our own AdShield UI
    if (e.target && e.target.closest && e.target.closest("#__adshield_ui_root__")) {
      return;
    }

    const anchor = e.target && e.target.closest ? e.target.closest("a[href]") : null;
    if (!anchor) return;

    const rawHref = (anchor.getAttribute("href") || "").trim();
    if (!rawHref || rawHref === "#" || rawHref.startsWith("javascript:")) {
      if (state.strictLockAllLinks) {
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
      }
      return;
    }

    // Mode A: Strict Lock All Links ("Bấm vào liên kết cũng không mở")
    if (state.strictLockAllLinks) {
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();
      showToast("🔒 Đang bật Khóa Liên Kết: Đã chặn mở trang!");
      return false;
    }

    // Mode B: Block External Navigation / New Tab / Ad Redirects
    if (state.blockExternalNav) {
      try {
        const targetURL = new URL(anchor.href, window.location.href);
        const currentHost = window.location.hostname.replace(/^www\./, "");
        const targetHost = targetURL.hostname.replace(/^www\./, "");
        const isBlankTarget = (anchor.getAttribute("target") || "").toLowerCase() === "_blank";

        if (targetHost && targetHost !== currentHost) {
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          showToast("🛡️ Đã chặn chuyển hướng sang: " + targetHost);
          return false;
        }

        if (isBlankTarget) {
          // Force same-domain _blank links to stay in or get blocked if suspicious
          anchor.removeAttribute("target");
        }
      } catch (err) {}
    }
  }

  window.addEventListener("click", handleLinkClick, true);
  window.addEventListener("auxclick", handleLinkClick, true);
  window.addEventListener("touchend", function (e) {
    if (longPressTriggered) {
      e.preventDefault();
      e.stopPropagation();
      longPressTriggered = false;
    }
  }, true);

  // 3. LONG-PRESS ELEMENT ZAPPER ("Nhấn giữ vào 1 panel trên web thì chặn cái đó")
  let pressTimer = null;
  let pressStartX = 0;
  let pressStartY = 0;
  let longPressTriggered = false;
  let highlightedEl = null;

  function buildUniqueSelector(el) {
    if (!el || el === document.body || el === document.documentElement) return null;
    if (el.id && !/^\d/.test(el.id)) {
      return "#" + CSS.escape(el.id);
    }
    if (el.classList && el.classList.length > 0) {
      const validClasses = Array.from(el.classList).filter(c => c && !c.startsWith("__adshield"));
      if (validClasses.length > 0) {
        return el.tagName.toLowerCase() + "." + validClasses.map(c => CSS.escape(c)).join(".");
      }
    }
    // Fallback to structural path
    const path = [];
    let curr = el;
    while (curr && curr !== document.body && path.length < 4) {
      let tag = curr.tagName.toLowerCase();
      if (curr.parentElement) {
        const siblings = Array.from(curr.parentElement.children).filter(c => c.tagName === curr.tagName);
        if (siblings.length > 1) {
          const idx = siblings.indexOf(curr) + 1;
          tag += `:nth-of-type(${idx})`;
        }
      }
      path.unshift(tag);
      curr = curr.parentElement;
    }
    return path.join(" > ");
  }

  function findBestPanelContainer(target) {
    if (!target) return null;
    // Walk up slightly if user long-pressed an inner <img> or <span> inside a floating banner/panel
    let curr = target;
    while (curr && curr.parentElement && curr.parentElement !== document.body) {
      const style = window.getComputedStyle(curr);
      if (style.position === "fixed" || style.position === "sticky" || curr.tagName === "A" || curr.tagName === "IFRAME") {
        return curr;
      }
      curr = curr.parentElement;
    }
    return target;
  }

  window.addEventListener("touchstart", function (e) {
    if (!state.longPressZapEnabled) return;
    if (!e.touches || e.touches.length !== 1) return;
    const touch = e.touches[0];
    if (touch.target && touch.target.closest && touch.target.closest("#__adshield_ui_root__")) return;

    pressStartX = touch.clientX;
    pressStartY = touch.clientY;
    longPressTriggered = false;

    clearTimeout(pressTimer);
    pressTimer = setTimeout(() => {
      const rawTarget = document.elementFromPoint(pressStartX, pressStartY);
      if (!rawTarget || rawTarget === document.body || rawTarget === document.documentElement) return;
      if (rawTarget.closest("#__adshield_ui_root__")) return;

      longPressTriggered = true;
      const panel = findBestPanelContainer(rawTarget) || rawTarget;
      openZapConfirmModal(panel);
    }, 650);
  }, { passive: true, capture: true });

  window.addEventListener("touchmove", function (e) {
    if (!e.touches || e.touches.length !== 1) return;
    const dx = Math.abs(e.touches[0].clientX - pressStartX);
    const dy = Math.abs(e.touches[0].clientY - pressStartY);
    if (dx > 12 || dy > 12) {
      clearTimeout(pressTimer);
    }
  }, { passive: true, capture: true });

  window.addEventListener("touchend", function () {
    clearTimeout(pressTimer);
  }, { passive: true, capture: true });

  // 4. AUTO-SCANNER FOR FLOATING GAMBLING BANNERS & POPUP OVERLAYS ON VIETNAMESE SITES
  const BET_PATTERNS = /k88|du88|man88|xibet|uk88|ok9|shbet|hi88|jun88|new88|f8bet|789bet|mb66|8kbet|go88|sunwin|rikvip|hitclub|b52club|kubet|bong88|w88|m88|fun88|fb88|188bet|vn88|bk8|dabet|fabet|debet|red88|zbet|five88|lucky88|oxbet|sin88|sky88|ta88|xo88|bet88/i;

  function sweepDynamicAdPanels() {
    if (!state.autoRemoveFloatingBanners) return;
    try {
      // Remove any<a> or <img> matching betting keywords
      const linksAndImgs = document.querySelectorAll("a[href], img[src], iframe[src], div[id], div[class]");
      for (const el of linksAndImgs) {
        if (el.closest && el.closest("#__adshield_ui_root__")) continue;
        const href = el.getAttribute("href") || "";
        const src = el.getAttribute("src") || "";
        const idCls = (el.id || "") + " " + (typeof el.className === "string" ? el.className : "");
        if (BET_PATTERNS.test(href) || BET_PATTERNS.test(src) || BET_PATTERNS.test(idCls)) {
          const container = findBestPanelContainer(el) || el;
          container.style.setProperty("display", "none", "important");
          container.remove();
        }
      }

      // Check fixed/sticky full-width bottom catfish or centered popup overlays that contain GIFs/external links
      const allDivs = document.querySelectorAll("div, aside, section, center");
      for (const div of allDivs) {
        if (div.id === "__adshield_ui_root__" || (div.closest && div.closest("#__adshield_ui_root__"))) continue;
        const st = window.getComputedStyle(div);
        const zIndex = parseInt(st.zIndex, 10) || 0;
        if ((st.position === "fixed" || st.position === "sticky") && zIndex > 90) {
          // Avoid hiding video players or main navbars
          if (div.querySelector("video")) continue;
          const hasGifOrAdLink = div.querySelector("img[src*='.gif'], a[target='_blank']");
          if (hasGifOrAdLink && div.offsetHeight < window.innerHeight * 0.75) {
            div.style.setProperty("display", "none", "important");
          }
        }
      }
    } catch (e) {}
  }

  function applySavedSelectors() {
    if (!Array.isArray(state.customBlockedSelectors) || state.customBlockedSelectors.length === 0) return;
    let styleEl = document.getElementById("__adshield_custom_css__");
    if (!styleEl) {
      styleEl = document.createElement("style");
      styleEl.id = "__adshield_custom_css__";
      (document.head || document.documentElement).appendChild(styleEl);
    }
    styleEl.textContent = state.customBlockedSelectors.map(s => `${s} { display: none !important; visibility: hidden !important; pointer-events: none !important; }`).join("\n");
  }

  // 5. IN-PAGE FLOATING CONTROL PILL & ZAPPER MODAL
  let uiRoot = null;
  let toastEl = null;
  let modalEl = null;
  let pillBtn = null;

  function ensureUIRoot() {
    if (uiRoot && document.body && document.body.contains(uiRoot)) return;
    if (!document.body) return;

    uiRoot = document.createElement("div");
    uiRoot.id = "__adshield_ui_root__";
    uiRoot.style.cssText = "all: initial; position: fixed; z-index: 2147483647; bottom: 18px; right: 14px; font-family: -apple-system, BlinkMacSystemFont, sans-serif;";

    // Floating quick toggle pill
    pillBtn = document.createElement("button");
    pillBtn.style.cssText = "display: flex; align-items: center; gap: 6px; padding: 8px 12px; border-radius: 999px; border: 1px solid rgba(16, 212, 153, 0.5); background: rgba(10, 18, 24, 0.92); color: #10d499; font-size: 12px; font-weight: 700; box-shadow: 0 4px 16px rgba(0,0,0,0.45); backdrop-filter: blur(8px); -webkit-backdrop-filter: blur(8px); cursor: pointer;";
    pillBtn.addEventListener("click", function (e) {
      e.preventDefault();
      e.stopPropagation();
      state.strictLockAllLinks = !state.strictLockAllLinks;
      saveLocalStateFallback();
      if (typeof browser !== "undefined" && browser.runtime) {
        browser.runtime.sendMessage({ type: "SET_STATE", payload: { strictLockAllLinks: state.strictLockAllLinks } }).catch(() => {});
      }
      updateFloatingPill();
      showToast(state.strictLockAllLinks
        ? "🔒 Đã BẬT Khóa Liên Kết: Bấm vào bất kỳ link nào cũng không mở trang!"
        : "🛡️ Đã TẮT Khóa Liên Kết (Vẫn chặn nhảy sang trang quảng cáo ngoài)");
    });

    toastEl = document.createElement("div");
    toastEl.style.cssText = "display: none; position: fixed; bottom: 64px; right: 14px; max-width: 290px; padding: 10px 14px; border-radius: 12px; background: rgba(12, 20, 28, 0.95); color: #fff; font-size: 12px; font-weight: 600; border: 1px solid #10d499; box-shadow: 0 6px 20px rgba(0,0,0,0.5); z-index: 2147483647;";

    modalEl = document.createElement("div");
    modalEl.style.cssText = "display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.55); z-index: 2147483647; align-items: center; justify-content: center; padding: 20px;";

    uiRoot.appendChild(pillBtn);
    uiRoot.appendChild(toastEl);
    uiRoot.appendChild(modalEl);
    document.body.appendChild(uiRoot);
    updateFloatingPill();
  }

  function updateFloatingPill() {
    if (!pillBtn) return;
    if (state.strictLockAllLinks) {
      pillBtn.style.background = "rgba(220, 38, 38, 0.95)";
      pillBtn.style.color = "#ffffff";
      pillBtn.style.borderColor = "#f87171";
      pillBtn.textContent = "🔒 Đang Khóa Mọi Link";
    } else {
      pillBtn.style.background = "rgba(10, 18, 24, 0.92)";
      pillBtn.style.color = "#10d499";
      pillBtn.style.borderColor = "rgba(16, 212, 153, 0.5)";
      pillBtn.textContent = "🛡️ AdShield";
    }
  }

  let toastTimer = null;
  function showToast(msg) {
    ensureUIRoot();
    if (!toastEl) return;
    toastEl.textContent = msg;
    toastEl.style.display = "block";
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      toastEl.style.display = "none";
    }, 2600);
  }

  function openZapConfirmModal(targetEl) {
    ensureUIRoot();
    if (!modalEl || !targetEl) return;

    highlightedEl = targetEl;
    const prevOutline = targetEl.style.outline;
    targetEl.style.setProperty("outline", "3px dashed #ef4444", "important");

    const selector = buildUniqueSelector(targetEl) || targetEl.tagName.toLowerCase();

    modalEl.innerHTML = `
      <div style="background: #111827; color: #f9fafb; border: 1px solid #374151; border-radius: 16px; padding: 18px; width: 100%; max-width: 340px; box-shadow: 0 12px 32px rgba(0,0,0,0.65); font-family: -apple-system, sans-serif;">
        <div style="font-size: 16px; font-weight: 700; margin-bottom: 6px; color: #10d499;">🛡️ Chặn Khung / Panel Này?</div>
        <div style="font-size: 12px; color: #9ca3af; margin-bottom: 10px;">Bạn vừa nhấn giữ vào một khung trên trang. Bạn muốn ẩn vĩnh viễn khung này khỏi trang web?</div>
        <div style="font-size: 11px; font-family: monospace; background: #1f2937; padding: 6px 8px; border-radius: 8px; color: #e5e7eb; word-break: break-all; margin-bottom: 14px;">${selector}</div>
        <div style="display: flex; gap: 8px;">
          <button id="__adshield_zap_cancel__" style="flex: 1; padding: 10px; border-radius: 10px; border: 1px solid #4b5563; background: transparent; color: #d1d5db; font-weight: 600; font-size: 13px;">Hủy</button>
          <button id="__adshield_zap_parent__" style="flex: 1; padding: 10px; border-radius: 10px; border: 1px solid #f59e0b; background: rgba(245, 158, 11, 0.15); color: #fbbf24; font-weight: 600; font-size: 13px;">Khung Lớn Hơn</button>
          <button id="__adshield_zap_confirm__" style="flex: 1; padding: 10px; border-radius: 10px; border: none; background: #ef4444; color: #fff; font-weight: 700; font-size: 13px;">Chặn Ngay</button>
        </div>
      </div>
    `;
    modalEl.style.display = "flex";

    document.getElementById("__adshield_zap_cancel__").onclick = function (e) {
      e.stopPropagation();
      targetEl.style.outline = prevOutline;
      modalEl.style.display = "none";
    };

    document.getElementById("__adshield_zap_parent__").onclick = function (e) {
      e.stopPropagation();
      targetEl.style.outline = prevOutline;
      if (targetEl.parentElement && targetEl.parentElement !== document.body) {
        openZapConfirmModal(targetEl.parentElement);
      }
    };

    document.getElementById("__adshield_zap_confirm__").onclick = function (e) {
      e.stopPropagation();
      targetEl.style.setProperty("display", "none", "important");
      targetEl.remove();
      modalEl.style.display = "none";

      if (selector) {
        if (!state.customBlockedSelectors.includes(selector)) {
          state.customBlockedSelectors.push(selector);
        }
        saveLocalStateFallback();
        applySavedSelectors();
        if (typeof browser !== "undefined" && browser.runtime) {
          browser.runtime.sendMessage({ type: "ADD_ZAPPED_SELECTOR", selector }).catch(() => {});
        }
      }
      showToast("✅ Đã chặn và xóa khung quảng cáo!");
    };
  }

  if (typeof browser !== "undefined" && browser.runtime && browser.runtime.onMessage) {
    browser.runtime.onMessage.addListener((msg) => {
      if (msg.type === "STATE_UPDATED" && msg.payload) {
        state = { ...state, ...msg.payload };
        saveLocalStateFallback();
        applySavedSelectors();
        updateFloatingPill();
      }
    });
  }

  loadState();

  document.addEventListener("DOMContentLoaded", () => {
    ensureUIRoot();
    applySavedSelectors();
    sweepDynamicAdPanels();
    const obs = new MutationObserver(() => {
      sweepDynamicAdPanels();
    });
    obs.observe(document.documentElement, { childList: true, subtree: true });
  });
})();
