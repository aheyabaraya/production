/* Founder visual review board — shared lightbox. Structure shell only. */
(function () {
  function padIndex(value) {
    return String(value).padStart(2, "0");
  }

  function refreshCarousel(carousel) {
    const track = carousel.querySelector("[data-carousel-track]");
    const previous = carousel.querySelector("[data-carousel-prev]");
    const next = carousel.querySelector("[data-carousel-next]");
    const status = carousel.querySelector("[data-carousel-status]");
    if (!track || !previous || !next || !status) return;

    const panels = Array.from(track.querySelectorAll(":scope > .media-panel"));
    const count = panels.length;
    panels.forEach(function (panel, index) {
      const badge = panel.querySelector(":scope > .media-index");
      if (!badge) return;
      badge.setAttribute("aria-label", `Image ${index + 1} of ${count}`);
      badge.textContent = `${padIndex(index + 1)} / ${padIndex(count)}`;
    });
    const firstPanel = panels[0];
    const secondPanel = panels[1];
    const step = firstPanel
      ? (secondPanel ? secondPanel.offsetLeft - firstPanel.offsetLeft : firstPanel.getBoundingClientRect().width)
      : track.clientWidth;
    const declaredSlots = Number.parseInt(
      window.getComputedStyle(carousel).getPropertyValue("--visible-slots"),
      10
    );
    const visible = Math.max(
      1,
      Math.min(count || 1, declaredSlots || Math.floor((track.clientWidth + 1) / Math.max(step, 1)))
    );
    const first = count ? Math.min(count - 1, Math.max(0, Math.round(track.scrollLeft / Math.max(step, 1)))) : 0;
    const last = count ? Math.min(count, first + visible) : 0;
    const overflow = track.scrollWidth > track.clientWidth + 2;

    previous.hidden = !overflow;
    next.hidden = !overflow;
    previous.disabled = !overflow || first <= 0;
    next.disabled = !overflow || last >= count;
    status.textContent = count ? `${padIndex(first + 1)}–${padIndex(last)} / ${padIndex(count)}` : "00 / 00";

    if (!carousel.dataset.carouselReady) {
      const move = function (direction) {
        track.scrollBy({ left: direction * track.clientWidth, behavior: "smooth" });
      };
      previous.addEventListener("click", function () { move(-1); });
      next.addEventListener("click", function () { move(1); });
      track.addEventListener("scroll", function () {
        window.requestAnimationFrame(function () { refreshCarousel(carousel); });
      }, { passive: true });
      carousel.dataset.carouselReady = "true";
    }
  }

  function refreshCarousels() {
    document.querySelectorAll("[data-carousel]").forEach(refreshCarousel);
  }

  window.IDOLFounderWorkbench = Object.assign(window.IDOLFounderWorkbench || {}, {
    refreshCarousels: refreshCarousels
  });
  window.addEventListener("resize", refreshCarousels);
  window.addEventListener("load", refreshCarousels);
  refreshCarousels();

  const lb = document.getElementById("lb");
  const img = document.getElementById("lb-img");
  const cap = document.getElementById("lb-cap");
  if (!lb || !img) return;

  let openSrc = "";

  function isOpen() {
    return lb.classList.contains("open");
  }

  function openLb(src, caption) {
    openSrc = src || "";
    img.src = src;
    if (cap) cap.textContent = caption || "";
    lb.classList.add("open");
    document.body.style.overflow = "hidden";
  }

  function closeLb() {
    lb.classList.remove("open");
    img.removeAttribute("src");
    openSrc = "";
    document.body.style.overflow = "";
  }

  function toggleFromThumb(src, caption) {
    if (isOpen() && openSrc && src && (openSrc === src || openSrc.endsWith(src) || src.endsWith(openSrc))) {
      closeLb();
      return;
    }
    openLb(src, caption);
  }

  document.addEventListener("click", function (e) {
    const t = e.target;
    if (!t) return;

    // Close: any click while open on overlay, X, caption, or the enlarged image itself
    if (isOpen()) {
      if (
        t === lb ||
        t === img ||
        t.id === "lb-x" ||
        t.id === "lb-cap" ||
        t.classList.contains("lb-cap") ||
        t.classList.contains("lb-x") ||
        t.classList.contains("lb-hint") ||
        (t.closest && t.closest("#lb"))
      ) {
        // If click is on a different page thumb while open, switch instead of only close
        if (t.tagName === "IMG" && t.classList.contains("zoomable") && t.id !== "lb-img") {
          e.preventDefault();
          const fig = t.closest("figure");
          const c =
            fig && fig.querySelector("figcaption")
              ? fig.querySelector("figcaption").textContent
              : t.alt || "";
          toggleFromThumb(t.currentSrc || t.src, c);
          return;
        }
        e.preventDefault();
        closeLb();
        return;
      }
    }

    if (t.tagName === "IMG" && t.classList.contains("zoomable") && t.id !== "lb-img") {
      e.preventDefault();
      const fig = t.closest("figure");
      const c =
        fig && fig.querySelector("figcaption")
          ? fig.querySelector("figcaption").textContent
          : t.alt || "";
      toggleFromThumb(t.currentSrc || t.src, c);
    }
  });

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && isOpen()) closeLb();
  });

  function placeHashBelowStickyNavigation() {
    if (!location.hash) return;
    const target = document.getElementById(decodeURIComponent(location.hash.slice(1)));
    if (!target) return;
    const sticky = document.querySelector(".cycle-nav");
    const offset = (sticky ? sticky.getBoundingClientRect().height : 0) + 16;
    window.scrollTo({
      top: target.getBoundingClientRect().top + window.scrollY - offset,
      behavior: "auto"
    });
  }

  function stabilizeHashPlacement() {
    [0, 120, 400, 1000, 1800].forEach(function (delay) {
      window.setTimeout(placeHashBelowStickyNavigation, delay);
    });
  }

  window.addEventListener("hashchange", stabilizeHashPlacement);
  window.addEventListener("load", function () {
    requestAnimationFrame(function () {
      requestAnimationFrame(stabilizeHashPlacement);
    });
  });
})();
