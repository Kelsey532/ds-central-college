/* ==========================================================
   D.S. Senanayake Central College, Mirigama
   animations.js - Scroll Reveals & Micro-Interactions
   Respects prefers-reduced-motion
   ========================================================== */

(function () {
  "use strict";

  var prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /**
   * Initialize Scroll Reveals for sections and card elements
   */
  function initScrollReveals() {
    if (prefersReducedMotion) {
      document.querySelectorAll(".reveal").forEach(function (el) {
        el.classList.add("is-visible");
      });
      return;
    }

    if ("IntersectionObserver" in window) {
      var revealObserver = new IntersectionObserver(
        function (entries, observer) {
          entries.forEach(function (entry) {
            if (entry.isIntersecting) {
              entry.target.classList.add("is-visible");
              observer.unobserve(entry.target);
            }
          });
        },
        {
          threshold: 0.12,
          rootMargin: "0px 0px -40px 0px"
        }
      );

      document.querySelectorAll(".reveal").forEach(function (el) {
        revealObserver.observe(el);
      });
    } else {
      document.querySelectorAll(".reveal").forEach(function (el) {
        el.classList.add("is-visible");
      });
    }
  }

  /**
   * Subtle Button Hover & Ripple Interaction
   */
  function initInteractiveButtons() {
    if (prefersReducedMotion) return;

    var buttons = document.querySelectorAll(".btn, .feature-tile, .news-item, .quick-links a");
    buttons.forEach(function (btn) {
      btn.addEventListener("pointerdown", function (e) {
        this.style.transition = "transform 0.1s ease";
        this.style.transform = "scale(0.98)";
      });
      btn.addEventListener("pointerup", function (e) {
        this.style.transform = "";
      });
      btn.addEventListener("pointerleave", function (e) {
        this.style.transform = "";
      });
    });
  }

  /**
   * Page Loaded Entrance Trigger
   */
  function initEntrance() {
    document.documentElement.classList.add("js");
    if (document.readyState === "complete") {
      document.documentElement.classList.add("is-loaded");
    } else {
      window.addEventListener("load", function () {
        document.documentElement.classList.add("is-loaded");
      });
    }
  }

  // Run on DOM Content Loaded
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      initEntrance();
      initScrollReveals();
      initInteractiveButtons();
    });
  } else {
    initEntrance();
    initScrollReveals();
    initInteractiveButtons();
  }
})();
