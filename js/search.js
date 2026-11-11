/* Fast local search for public pages. */
(function () {
  "use strict";

  var navList = document.querySelector(".nav-list");
  if (!navList || document.getElementById("site-search-dialog")) return;

  var entries = [
    { category: "History", title: "School history", description: "Discover the history and traditions of D.S. Senanayake Central College.", url: "about.html#history", terms: "founders heritage past principals" },
    { category: "About", title: "Founders and past principals", description: "Learn about the people who shaped the college.", url: "about.html#history", terms: "history traditions leadership" },
    { category: "About", title: "School identity", description: "Explore the school profile, crest, motto, song, flag, and colours.", url: "about.html#identity", terms: "school profile identity crest emblem motto song flag colors colours" },
    { category: "About", title: "Vision and mission", description: "Read the college's vision and mission.", url: "about.html#vision", terms: "values direction purpose" },
    { category: "About", title: "School rules and regulations", description: "Find the school's rules and regulations.", url: "about.html#rules", terms: "conduct uniform house system" },
    { category: "Academics", title: "Academic sections", description: "Explore the school's primary and secondary sections.", url: "academics.html#sections", terms: "grades curriculum" },
    { category: "Academics", title: "Subjects and programmes", description: "Browse subjects and educational programmes.", url: "academics.html#programs", terms: "courses learning curriculum" },
    { category: "Academics", title: "Student performance", description: "Explore examination results and student performance.", url: "academics.html#performance", terms: "results gce ol al achievement" },
    { category: "Staff", title: "Principal and leadership", description: "Read the principal's message and learn about school leadership.", url: "about.html#principal-message", terms: "principal management staff" },
    { category: "Staff", title: "Academic and non-academic staff", description: "Find information about teachers and school staff.", url: "academics.html", terms: "teachers deputy principal prefects board" },
    { category: "News", title: "Latest news and college updates", description: "See the latest college news, events, and announcements.", url: "index.html#news-section", terms: "updates press stories" },
    { category: "Notices", title: "Notices and announcements", description: "Find current school notices and important announcements.", url: "index.html#site-notice-banner", terms: "urgent notice admissions" },
    { category: "Admissions", title: "Admissions and contact", description: "Find admissions information and contact the school.", url: "contact.html#contact", terms: "enrolment enrollment visit office" },
    { category: "Achievements", title: "School achievements", description: "Explore student and college achievements.", url: "activities.html#achievements", terms: "awards success recognition" },
    { category: "Clubs", title: "Clubs and societies", description: "Discover student clubs, societies, and activities.", url: "activities.html#clubs", terms: "ict science cultural extracurricular" },
    { category: "Sports", title: "Sports and athletics", description: "Explore sports, athletics, and school teams.", url: "activities.html#sports", terms: "cricket teams games" },
    { category: "Activities", title: "Cadets, scouting, and events", description: "Find information about cadeting and school events.", url: "activities.html#cadets", terms: "bands leadership events" },
    { category: "Downloads", title: "Downloads and learning resources", description: "Find school downloads, textbooks, and learning resources.", url: "contact.html#downloads", terms: "documents forms textbooks" },
    { category: "Gallery", title: "College gallery", description: "Browse photos and videos from college life.", url: "gallery.html", terms: "photos media campus" },
    { category: "Contact", title: "Contact the school", description: "Find the school address, phone number, and email.", url: "contact.html#contact", terms: "directions map phone email" }
  ];

  var trigger = document.createElement("button");
  trigger.className = "nav-search-trigger";
  trigger.type = "button";
  trigger.setAttribute("aria-label", "Search the website");
  trigger.setAttribute("aria-haspopup", "dialog");
  trigger.setAttribute("aria-controls", "site-search-dialog");
  trigger.setAttribute("aria-expanded", "false");
  var icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  icon.setAttribute("aria-hidden", "true");
  icon.setAttribute("viewBox", "0 0 24 24");
  icon.setAttribute("fill", "none");
  var lens = document.createElementNS("http://www.w3.org/2000/svg", "circle");
  lens.setAttribute("cx", "10.8");
  lens.setAttribute("cy", "10.8");
  lens.setAttribute("r", "6.8");
  var handle = document.createElementNS("http://www.w3.org/2000/svg", "path");
  handle.setAttribute("d", "m16 16 4.5 4.5");
  icon.append(lens, handle);
  var triggerLabel = document.createElement("span");
  triggerLabel.textContent = "Search";
  trigger.append(icon, triggerLabel);

  var navItem = document.createElement("li");
  navItem.className = "nav-search-item";
  navItem.appendChild(trigger);
  navList.appendChild(navItem);

  var dialog = document.createElement("dialog");
  dialog.className = "site-search-dialog";
  dialog.id = "site-search-dialog";
  dialog.setAttribute("aria-labelledby", "site-search-title");

  var panel = document.createElement("section");
  panel.className = "site-search-panel";
  var header = document.createElement("header");
  header.className = "site-search-header";
  var headingGroup = document.createElement("div");
  var heading = document.createElement("h2");
  heading.id = "site-search-title";
  heading.textContent = "Search the College";
  var subtitle = document.createElement("p");
  subtitle.textContent = "Find school information, updates, and resources.";
  headingGroup.append(heading, subtitle);

  var closeButton = document.createElement("button");
  closeButton.className = "site-search-close";
  closeButton.type = "button";
  closeButton.setAttribute("aria-label", "Close search");
  closeButton.textContent = "\u00d7";
  header.append(headingGroup, closeButton);

  var form = document.createElement("form");
  form.className = "site-search-form";
  form.setAttribute("role", "search");
  form.addEventListener("submit", function (event) { event.preventDefault(); });
  var searchIcon = document.createElement("span");
  searchIcon.className = "site-search-form-icon";
  searchIcon.setAttribute("aria-hidden", "true");
  searchIcon.appendChild(icon.cloneNode(true));
  var input = document.createElement("input");
  input.className = "site-search-input";
  input.type = "search";
  input.name = "q";
  input.placeholder = "Search history, academics, news...";
  input.autocomplete = "off";
  input.setAttribute("aria-label", "Search the college website");
  input.setAttribute("aria-describedby", "site-search-hint");
  form.append(searchIcon, input);

  var hint = document.createElement("p");
  hint.className = "site-search-hint";
  hint.id = "site-search-hint";
  hint.textContent = "Type to search. Press Esc to close.";
  var status = document.createElement("p");
  status.className = "site-search-status";
  status.setAttribute("role", "status");
  status.setAttribute("aria-live", "polite");
  var results = document.createElement("ul");
  results.className = "site-search-results";
  results.setAttribute("aria-label", "Search results");

  panel.append(header, form, hint, status, results);
  dialog.appendChild(panel);
  document.body.appendChild(dialog);

  function normalize(value) {
    return String(value || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim();
  }

  function addEntry(entry) {
    if (!entry || !entry.title || !entry.url) return;
    var url = entry.url.split("#")[0];
    var hash = entry.url.indexOf("#") >= 0 ? entry.url.slice(entry.url.indexOf("#")) : "";
    var duplicate = entries.find(function (item) {
      return item.title === entry.title && item.url === url + hash;
    });
    if (duplicate) {
      if (entry.description) duplicate.description = entry.description;
      if (entry.terms) duplicate.terms = [duplicate.terms, entry.terms].filter(Boolean).join(" ");
    } else {
      entries.push(entry);
    }
  }

  function readStoredArray(key) {
    try {
      var value = localStorage.getItem("dscc_" + key);
      if (!value) return [];
      var rows = JSON.parse(value);
      if (!Array.isArray(rows)) throw new TypeError("Expected an array.");
      return rows;
    } catch (error) {
      console.error("Could not read cached search " + key + " data.", error);
      return [];
    }
  }

  function indexPageContent() {
    document.querySelectorAll("main h1, main h2, main h3").forEach(function (element) {
      var title = element.textContent.trim();
      if (!title) return;
      var section = element.closest("section[id]") || element.closest("[id]");
      if (!section || !section.id) return;
      var contentRoot = element.closest("article") || section;
      var description = contentRoot.querySelector("p");
      addEntry({
        category: "Page",
        title: title,
        description: description ? description.textContent.trim().slice(0, 180) : "Explore " + title + " information.",
        url: location.pathname.split("/").pop() + "#" + section.id
      });
    });
  }

  function indexNotice() {
    var banner = document.getElementById("site-notice-banner");
    if (!banner || !banner.classList.contains("is-active")) return;
    var title = banner.querySelector("#notice-tag");
    var body = banner.querySelector("#notice-text");
    addEntry({
      category: "Notices",
      title: body ? body.textContent.trim() : "School notice",
      description: title ? title.textContent.trim() : "Current school announcement.",
      url: "index.html#site-notice-banner"
    });
  }

  function indexStoredContent() {
    readStoredArray("news").filter(function (item) { return item && item.status === "published"; })
      .forEach(function (item) {
        addEntry({
          category: "News",
          title: item.title,
          description: item.summary || item.body || "Read the latest college news.",
          url: "index.html#news-section"
        });
      });

    readStoredArray("announcements").filter(function (item) { return item && item.status === "active"; })
      .forEach(function (item) {
        addEntry({
          category: "Notices",
          title: item.title,
          description: item.body || "Read this school announcement.",
          url: "index.html#site-notice-banner"
        });
      });

    var activityIds = {
      Sports: "sports",
      Clubs: "clubs",
      Societies: "societies",
      Achievements: "achievements",
      Events: "events",
      "Extra-curricular": "cadets"
    };
    readStoredArray("activities").filter(function (item) { return item && item.status === "published"; })
      .forEach(function (item) {
        addEntry({
          category: item.category || "Activities",
          title: item.title,
          description: item.description || "Explore college activities.",
          url: "activities.html#" + (activityIds[item.category] || "activities-list")
        });
      });

    readStoredArray("page_content").forEach(function (item) {
      if (!item || typeof item.key !== "string" || typeof item.value !== "string" || !item.value.trim()) return;
      var match = item.key.match(/^(about|academics)\.(.+)$/);
      if (!match) return;
      var page = match[1] === "about" ? "about.html" : "academics.html";
      var section = match[2].replace(/_/g, "-");
      if (section === "intro") section = "";
      addEntry({
        category: match[1] === "about" ? "About" : "Academics",
        title: section ? section.replace(/-/g, " ") : "Academic overview",
        description: item.value.trim().slice(0, 180),
        url: page + (section ? "#" + section : "")
      });
    });
  }

  function indexNavigation() {
    navList.querySelectorAll("a[href]").forEach(function (link) {
      var url;
      try {
        url = new URL(link.href, location.href);
      } catch (error) {
        return;
      }
      if (url.origin !== location.origin) return;
      addEntry({
        category: "Pages",
        title: link.textContent.trim(),
        description: "Open " + link.textContent.trim() + " information.",
        url: url.pathname.split("/").pop() + url.hash
      });
    });
  }

  function score(entry, query) {
    var title = normalize(entry.title);
    var haystack = normalize([entry.category, entry.title, entry.description, entry.terms].join(" "));
    var tokens = query.split(/\s+/);
    if (!tokens.every(function (token) { return haystack.indexOf(token) >= 0; })) return -1;
    return (title.indexOf(query) === 0 ? 10 : 0) +
      (title.indexOf(query) >= 0 ? 5 : 0) +
      tokens.reduce(function (total, token) { return total + (title.indexOf(token) >= 0 ? 2 : 0); }, 0);
  }

  function renderResults() {
    var query = normalize(input.value);
    results.textContent = "";
    var matches = entries.map(function (entry) {
      return { entry: entry, score: query ? score(entry, query) : 0 };
    }).filter(function (match) {
      return match.score >= 0;
    }).sort(function (a, b) {
      return b.score - a.score || a.entry.title.localeCompare(b.entry.title);
    }).slice(0, 8);

    if (!query) {
      status.textContent = "Popular searches";
      matches = entries.filter(function (entry) {
        return ["History", "Academics", "Admissions", "Downloads"].indexOf(entry.category) >= 0;
      }).slice(0, 4).map(function (entry) { return { entry: entry }; });
    } else {
      status.textContent = matches.length
        ? matches.length + (matches.length === 1 ? " result" : " results")
        : "No results found. Try a different search.";
    }

    matches.forEach(function (match) {
      var item = document.createElement("li");
      var link = document.createElement("a");
      link.className = "site-search-result";
      link.href = match.entry.url;
      var copy = document.createElement("span");
      copy.className = "site-search-result-copy";
      var title = document.createElement("span");
      title.className = "site-search-result-title";
      title.textContent = match.entry.title;
      var description = document.createElement("span");
      description.className = "site-search-result-description";
      description.textContent = match.entry.description || "";
      copy.append(title, description);
      var category = document.createElement("span");
      category.className = "site-search-result-category";
      category.textContent = match.entry.category;
      link.append(copy, category);
      item.appendChild(link);
      results.appendChild(item);
    });
  }

  indexNavigation();
  indexPageContent();
  indexStoredContent();
  indexNotice();
  renderResults();

  var lastFocusedElement = null;
  function openSearch() {
    if (dialog.open) return;
    lastFocusedElement = document.activeElement;
    if (typeof dialog.showModal === "function") {
      dialog.showModal();
    } else {
      dialog.setAttribute("open", "");
    }
    trigger.setAttribute("aria-expanded", "true");
    renderResults();
    input.focus();
  }

  function closeSearch() {
    if (!dialog.open) return;
    if (typeof dialog.close === "function") dialog.close();
    else dialog.removeAttribute("open");
    trigger.setAttribute("aria-expanded", "false");
    if (lastFocusedElement && lastFocusedElement.isConnected) lastFocusedElement.focus();
  }

  trigger.addEventListener("click", openSearch);
  closeButton.addEventListener("click", closeSearch);
  input.addEventListener("input", renderResults);
  dialog.addEventListener("click", function (event) {
    if (event.target === dialog) closeSearch();
  });
  dialog.addEventListener("close", function () {
    trigger.setAttribute("aria-expanded", "false");
    if (lastFocusedElement && lastFocusedElement.isConnected) lastFocusedElement.focus();
  });
  dialog.addEventListener("cancel", function () {
    trigger.setAttribute("aria-expanded", "false");
  });

  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape" && dialog.open) {
      event.preventDefault();
      event.stopPropagation();
      closeSearch();
      return;
    }
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
      event.preventDefault();
      if (dialog.open) input.focus();
      else openSearch();
    }
  }, true);

  if ("MutationObserver" in window) {
    var refreshQueued = false;
    function refreshIndex() {
      if (refreshQueued) return;
      refreshQueued = true;
      window.requestAnimationFrame(function () {
        refreshQueued = false;
        indexPageContent();
        indexStoredContent();
        indexNotice();
        if (dialog.open) renderResults();
      });
    }

    var main = document.querySelector("main");
    if (main) {
      new MutationObserver(refreshIndex).observe(main, { childList: true, subtree: true, characterData: true });
    }
    var banner = document.getElementById("site-notice-banner");
    if (banner) {
      new MutationObserver(refreshIndex).observe(banner, { childList: true, subtree: true, characterData: true, attributes: true });
    }
    window.addEventListener("storage", function (event) {
      if (!event.key || event.key.indexOf("dscc_") === 0) {
        indexStoredContent();
        if (dialog.open) renderResults();
      }
    });
  }
})();
