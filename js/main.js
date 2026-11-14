/* Shared behaviour for all public pages */
(function () {
  "use strict";

  var root = document.documentElement;
  root.classList.add("js");

  /* Trigger the hero load sequence once fonts/layout are ready */
  function loaded() { root.classList.add("is-loaded"); }
  if (document.readyState === "complete") loaded();
  else window.addEventListener("load", loaded);
  setTimeout(loaded, 1500); // safety net if a resource is slow

  /* Observe a top-of-page marker instead of handling every scroll event. */
  var header = document.querySelector(".site-header");
  if (header && "IntersectionObserver" in window) {
    var scrollMarker = document.createElement("span");
    scrollMarker.setAttribute("aria-hidden", "true");
    scrollMarker.style.cssText = "position:absolute;top:24px;left:0;width:1px;height:1px;visibility:hidden;pointer-events:none";
    header.parentNode.insertBefore(scrollMarker, header);
    new IntersectionObserver(function (entries) {
      header.classList.toggle("is-scrolled", !entries[0].isIntersecting);
    }).observe(scrollMarker);
  } else if (header) {
    header.classList.toggle("is-scrolled", window.scrollY > 24);
  }

  /* Mobile navigation */
  var toggle = document.querySelector(".nav-toggle");
  var nav = document.getElementById("primary-nav");
  if (toggle && nav) {
    function setOpen(open) {
      toggle.setAttribute("aria-expanded", String(open));
      toggle.setAttribute("aria-label", open ? "Close menu" : "Open menu");
      nav.classList.toggle("is-open", open);
    }
    toggle.addEventListener("click", function () {
      setOpen(toggle.getAttribute("aria-expanded") !== "true");
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") {
        var openMenu = nav.querySelector(".nav-menu[open]");
        if (openMenu) {
          openMenu.open = false;
          openMenu.querySelector("summary").focus();
        }
      }
      if (e.key === "Escape" && toggle.getAttribute("aria-expanded") === "true") {
        setOpen(false); toggle.focus();
      }
    });
    nav.addEventListener("click", function (e) {
      if (e.target.closest("a")) {
        setOpen(false);
        nav.querySelectorAll(".nav-menu[open]").forEach(function (menu) { menu.open = false; });
      }
    });
    nav.querySelectorAll(".nav-menu").forEach(function (menu) {
      menu.addEventListener("toggle", function () {
        if (menu.open) {
          nav.querySelectorAll(".nav-menu[open]").forEach(function (other) {
            if (other !== menu) other.open = false;
          });
        }
      });
    });
  }

  /* Footer year */
  var yr = document.getElementById("year");
  if (yr) yr.textContent = new Date().getFullYear();

  /* ---------- Latest news from Supabase ---------- */
  var list = document.getElementById("news-list");
  var supabaseContent = window.DSCCSupabase;
  var client = supabaseContent && supabaseContent.client;

  function renderNewsItems(rows) {
    if (!list) return;
    list.textContent = "";
    if (!rows || !rows.length) {
      list.appendChild(make("p", "empty-state", "No published news is available yet."));
      return;
    }
    rows.slice(0, 3).forEach(function (n) {
      var art = document.createElement("article");
      art.className = "news-item reveal is-visible";
      var t = document.createElement("time");
      var dateVal = n.published_at || n.updated_at || new Date().toISOString();
      t.dateTime = dateVal;
      t.textContent = new Date(dateVal).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
      var h = document.createElement("h3");
      h.textContent = n.title;
      var p = document.createElement("p");
      p.textContent = n.summary || n.body || "";
      art.append(t, h, p);
      list.appendChild(art);
    });
  }

  if (list) {
    if (client) {
      supabaseContent.publicContent.news()
        .then(renderNewsItems)
        .catch(function (error) {
          console.error("Could not load public news from Supabase.", error);
          list.replaceChildren(make("p", "form-msg error", "News could not be loaded. Please try again later."));
        });
    } else {
      list.replaceChildren(make("p", "form-msg error", "News is unavailable because Supabase is not configured."));
    }
  }

  /* ---------- Urgent Announcement Banner ---------- */
  var banner = document.getElementById("site-notice-banner");
  var bannerText = document.getElementById("notice-text");
  var bannerTag = document.getElementById("notice-tag");
  var bannerClose = document.getElementById("notice-close");

  if (banner) {
    if (bannerClose) {
      bannerClose.addEventListener("click", function () {
        banner.classList.remove("is-active");
        sessionStorage.setItem("dscc_banner_dismissed", "1");
      });
    }
  }

  /* ---------- Shared helpers for backend-driven content ---------- */
  var configured = !!client;
  function make(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;   // textContent only: never inject HTML from the database
    return e;
  }
  function fmtDate(d) {
    return d ? new Date(d).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "";
  }

  if (configured && banner) {
    supabaseContent.publicContent.announcements()
      .then(function (rows) {
        var active = rows[0];
        if (!active || sessionStorage.getItem("dscc_banner_dismissed")) return;
        if (bannerText) bannerText.textContent = active.title + " — " + (active.body || "");
        if (bannerTag) bannerTag.textContent = active.priority || "Notice";
        banner.classList.add("is-active");
      })
      .catch(function (error) { console.error("Could not load the current public notice.", error); });
  }

  /* ---------- Page content (About, Academics, Contact, footer) ----------
   * Elements with data-content-key get their text from the page_content table.
   * Links only accept safe schemes (tel:, mailto:, https:). Maps only accept Google Maps embeds. */
  var cmsEls = document.querySelectorAll("[data-content-key]");
  function applyCmsMap(map) {
    cmsEls.forEach(function (el) {
      var key = el.getAttribute("data-content-key");
      var v = map[key];
      if (!v) return;
      var attr = el.getAttribute("data-content-attr");
      var fallback = el.previousElementSibling;
      var hasFallback = fallback && fallback.hasAttribute("data-fallback");
      if (attr === "src") {
        if (/^https:\/\/www\.google\.com\/maps\/embed/i.test(v)) {
          el.src = v; el.hidden = false;
          if (hasFallback) fallback.hidden = true;
        }
      } else if (attr === "href") {
        var prefix = el.getAttribute("data-prefix") || "";
        if (/^\[PLACEHOLDER/i.test(v)) return;
        var okLink = prefix ? true : /^https:\/\//i.test(v);
        if (!okLink) return;
        el.href = prefix + (prefix === "tel:" ? v.split(/[,;\/]/)[0].replace(/[^\d+]/g, "") : v);
        el.textContent = v; el.hidden = false;
        if (hasFallback) fallback.hidden = true;
      } else {
        el.textContent = v;
      }
    });
  }

  if (cmsEls.length) {
    if (configured) {
      supabaseContent.publicContent.pageContent().then(function (rows) {
        var map = {};
        rows.forEach(function (r) { map[r.key] = (r.value || "").trim(); });
        applyCmsMap(map);
      }).catch(function (error) { console.error("Could not load page content from Supabase.", error); });
    }
  }

  /* ---------- Academic resources ---------- */
  var academicResources = document.getElementById("academic-resources");
  if (academicResources) {
    var academicSections = {
      junior_secondary: "Junior Secondary (Grade 6 - 9)",
      senior_secondary: "Senior Secondary (Grade 10 - 11 / O/L)",
      advanced_level: "Advanced Level (Grade 12 - 13 / A/L)"
    };
    var academicTypes = {
      syllabus: "Syllabus",
      exam_notice: "Exam notice",
      study_material: "Study material"
    };

    function renderAcademicResources(rows) {
      var groups = {};
      Object.keys(academicSections).forEach(function (section) {
        groups[section] = [];
      });
      (rows || []).forEach(function (row) {
        if (!row || row.status !== "published") return;
        if (!Object.prototype.hasOwnProperty.call(groups, row.section) ||
            !Object.prototype.hasOwnProperty.call(academicTypes, row.resource_type) || typeof row.title !== "string") {
          console.error("Ignoring a published academic resource with an unsupported section, type, or title.", row);
          return;
        }
        try {
          var resourceUrl = new URL(row.file_url);
          if (resourceUrl.protocol !== "https:" || !resourceUrl.hostname) {
            console.error("Ignoring a published academic resource with an invalid HTTPS link.", row);
            return;
          }
        } catch (error) {
          console.error("Ignoring a published academic resource with an invalid URL.", error);
          return;
        }
        groups[row.section].push(row);
      });

      var hasResources = false;
      academicResources.querySelectorAll("[data-resource-section]").forEach(function (list) {
        var section = list.getAttribute("data-resource-section");
        list.textContent = "";
        groups[section].forEach(function (row) {
          hasResources = true;
          var item = make("li", "academic-resource-item");
          var link = make("a", null, row.title);
          link.href = row.file_url;
          link.target = "_blank";
          link.rel = "noopener noreferrer";
          item.appendChild(link);
          item.appendChild(make("span", "academic-resource-type", academicTypes[row.resource_type]));
          list.appendChild(item);
        });
        if (!groups[section].length) {
          list.appendChild(make("li", "academic-resource-empty", "No resources available yet."));
        }
      });
      academicResources.hidden = !hasResources;
    }

    if (configured) {
      supabaseContent.publicContent.academicResources()
        .then(renderAcademicResources)
        .catch(function (error) { console.error("Could not load academic resources from Supabase.", error); });
    }
  }

  /* ---------- Admissions page ---------- */
  var admissionsRoot = document.getElementById("admissions-list");
  if (admissionsRoot) {
    function renderAdmissions(rows) {
      admissionsRoot.textContent = "";
      if (!rows || !rows.length) {
        admissionsRoot.appendChild(make("p", "empty-state", "No admissions updates are available yet."));
        return;
      }
      rows.forEach(function (row) {
        var article = make("article", "activity-item admissions-item");
        article.appendChild(make("h2", null, row.title || "Admissions update"));
        if (row.target_grade) article.appendChild(make("p", "admissions-grade", row.target_grade));
        if (row.content) article.appendChild(make("p", null, row.content));
        if (row.image_url) {
          try {
            var imageUrl = new URL(row.image_url);
            if (imageUrl.protocol === "https:") {
              var image = document.createElement("img");
              image.src = imageUrl.href;
              image.alt = row.title || "Admissions information";
              image.loading = "lazy";
              article.appendChild(image);
            }
          } catch (error) {
            console.error("Ignoring an admissions image with an invalid URL.", error);
          }
        }
        admissionsRoot.appendChild(article);
      });
    }

    if (configured) {
      supabaseContent.publicContent.admissions()
        .then(renderAdmissions)
        .catch(function (error) {
          console.error("Could not load admissions updates from Supabase.", error);
          admissionsRoot.replaceChildren(make("p", "form-msg error", "Admissions updates could not be loaded."));
        });
    } else {
      admissionsRoot.replaceChildren(make("p", "form-msg error", "Admissions updates are unavailable because Supabase is not configured."));
    }
  }

  /* ---------- Activities page ---------- */
  var actRoot = document.getElementById("activities-list");
  if (actRoot) {
    var order = ["Sports", "Clubs", "Societies", "Achievements", "Events", "Extra-curricular"];
    var activityIds = { Sports: "sports", Clubs: "clubs", Societies: "societies", Achievements: "achievements", Events: "events", "Extra-curricular": "cadets" };
    function renderActivitiesList(rows) {
      if (!rows || !rows.length) {
        actRoot.replaceChildren(make("p", "empty-state", "No published activities are available yet."));
        Object.keys(activityIds).forEach(function (category) {
          var anchor = make("span", "activity-anchor");
          anchor.id = activityIds[category];
          actRoot.appendChild(anchor);
        });
        return;
      }
      var groups = {};
      rows.forEach(function (r) { (groups[r.category] = groups[r.category] || []).push(r); });
      var cats = order.filter(function (c) { return groups[c]; })
        .concat(Object.keys(groups).filter(function (c) { return order.indexOf(c) < 0; }));
      actRoot.textContent = "";
      cats.forEach(function (c) {
        var block = make("section", "group-block");
        if (activityIds[c]) block.id = activityIds[c];
        block.appendChild(make("h2", null, c));
        var grid = make("div", "activity-grid");
        groups[c].forEach(function (a) {
          var item = make("article", "activity-item");
          if (a.event_date) { var t = make("time", null, fmtDate(a.event_date)); t.dateTime = a.event_date; item.appendChild(t); }
          item.appendChild(make("h3", null, a.title));
          if (a.description) item.appendChild(make("p", null, a.description));
          grid.appendChild(item);
        });
        block.appendChild(grid);
        actRoot.appendChild(block);
      });
      Object.keys(activityIds).forEach(function (id) {
        if (!actRoot.querySelector("#" + activityIds[id])) {
          var anchor = make("span", "activity-anchor");
          anchor.id = activityIds[id];
          actRoot.appendChild(anchor);
        }
      });
    }

    if (configured) {
      supabaseContent.publicContent.activities()
        .then(renderActivitiesList)
        .catch(function (error) {
          console.error("Could not load public activities from Supabase.", error);
          actRoot.replaceChildren(make("p", "form-msg error", "Activities could not be loaded."));
        });
    } else {
      actRoot.replaceChildren(make("p", "form-msg error", "Activities are unavailable because Supabase is not configured."));
    }
  }

  /* ---------- Gallery page: category filter + lightbox ---------- */
  var gGrid = document.getElementById("gallery-grid");
  var gFilters = document.getElementById("gallery-filters");
  var box = document.getElementById("lightbox");
  if (gGrid && box) {
    var boxBody = box.querySelector(".lightbox-body");
    var lastTrigger = null;
    box.querySelector(".lightbox-close").addEventListener("click", function () { box.close(); });
    box.addEventListener("click", function (e) { if (e.target === box) box.close(); });  // click on backdrop
    box.addEventListener("close", function () { boxBody.textContent = ""; if (lastTrigger) lastTrigger.focus(); });

    function openItem(item, trigger) {
      lastTrigger = trigger;
      boxBody.textContent = "";
      if (item.media_type === "video") {
        var f = document.createElement("iframe");
        f.src = item.video_url; f.title = item.caption || "Video";
        f.allow = "accelerometer; encrypted-media; gyroscope; picture-in-picture"; f.allowFullscreen = true;
        boxBody.appendChild(f);
      } else {
        var im = document.createElement("img");
        im.src = item.image_url; im.alt = item.caption || "School gallery photo";
        boxBody.appendChild(im);
      }
      if (item.caption) boxBody.appendChild(make("p", "lightbox-caption", item.caption));
      box.showModal();
    }

    function safeVideo(u) { return /^https:\/\/(www\.youtube(-nocookie)?\.com\/embed\/|player\.vimeo\.com\/video\/)/i.test(u || ""); }
    function safeImage(u) { return /^https:\/\//i.test(u || ""); }

    function renderGallery(items, active) {
      gGrid.textContent = "";
      var shown = items.filter(function (i) { return active === "All" || i.category === active; });
      if (!shown.length) { gGrid.appendChild(make("p", "empty-state", "No items in this category yet.")); return; }
      shown.forEach(function (i) {
        var tile = make("button", "gallery-tile");
        tile.type = "button";
        tile.setAttribute("aria-label", (i.caption || "Gallery item") + (i.media_type === "video" ? " (video)" : ""));
        if (i.media_type !== "video") {
          var im = document.createElement("img");
          im.src = i.image_url; im.alt = ""; im.loading = "lazy";
          tile.appendChild(im);
        } else tile.appendChild(make("span", "badge", "Video"));
        if (i.caption) tile.appendChild(make("span", "cap", i.caption));
        tile.addEventListener("click", function () { openItem(i, tile); });
        gGrid.appendChild(tile);
      });
    }

    function setupGalleryData(items) {
      if (!items || !items.length) {
        gGrid.replaceChildren(make("p", "empty-state", "No gallery items are available yet."));
        if (gFilters) gFilters.textContent = "";
        return;
      }
      var cats = ["All"];
      items.forEach(function (i) { if (i.category && cats.indexOf(i.category) < 0) cats.push(i.category); });
      var active = "All";
      if (gFilters) {
        gFilters.textContent = "";
        cats.forEach(function (c) {
          var b = make("button", "filter-btn", c);
          b.type = "button"; b.setAttribute("aria-pressed", String(c === active));
          b.addEventListener("click", function () {
            active = c;
            gFilters.querySelectorAll(".filter-btn").forEach(function (x) { x.setAttribute("aria-pressed", String(x === b)); });
            renderGallery(items, active);
          });
          gFilters.appendChild(b);
        });
      }
      renderGallery(items, active);
    }

    if (configured) {
      supabaseContent.publicContent.gallery()
        .then(function (rows) {
          var items = rows.filter(function (r) { return r.media_type === "video" ? safeVideo(r.video_url) : safeImage(r.image_url); });
          setupGalleryData(items);
        }).catch(function (error) {
          console.error("Could not load gallery items from Supabase.", error);
          gGrid.replaceChildren(make("p", "form-msg error", "Gallery items could not be loaded."));
        });
    } else {
      gGrid.replaceChildren(make("p", "form-msg error", "The gallery is unavailable because Supabase is not configured."));
    }
  }

  /* ---------- Journey Video Modal ---------- */
  var journeyBtn = document.getElementById("play-journey-btn");
  var journeyDlg = document.getElementById("journey-dialog");
  var journeyClose = document.getElementById("journey-close-btn");
  var journeyIframe = document.getElementById("journey-iframe");

  if (journeyBtn && journeyDlg) {
    function stopJourneyVideo() {
      if (journeyIframe) journeyIframe.removeAttribute("src");
    }
    journeyBtn.addEventListener("click", function () {
      if (journeyIframe && !journeyIframe.src) {
        journeyIframe.src = journeyIframe.getAttribute("data-src");
      }
      journeyDlg.showModal();
    });
    if (journeyClose) {
      journeyClose.addEventListener("click", function () {
        journeyDlg.close();
        stopJourneyVideo();
      });
    }
    journeyDlg.addEventListener("click", function (e) {
      if (e.target === journeyDlg) {
        journeyDlg.close();
        stopJourneyVideo();
      }
    });
    journeyDlg.addEventListener("cancel", stopJourneyVideo);
    journeyDlg.addEventListener("close", stopJourneyVideo);
  }
})();
