function updateClock() {
  const now = new Date();

  document.getElementById("time").textContent =
    now.toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
      hour12: false
    });

  document.getElementById("date").textContent =
    now.toLocaleDateString([], {
      weekday: "long",
      day: "numeric",
      month: "long"
    });
}

function updateMode() {
  const dark = window.matchMedia("(prefers-color-scheme: dark)").matches;

  document.getElementById("mode").textContent =
    dark ? "Niveth Dark · System" : "Niveth Light · System";
}

document.getElementById("searchForm").addEventListener("submit", event => {
  event.preventDefault();

  const query = document.getElementById("searchInput").value.trim();

  if (query) {
    window.location.href =
      "https://search.brave.com/search?q=" +
      encodeURIComponent(query);
  }
});

const media = window.matchMedia("(prefers-color-scheme: dark)");
media.addEventListener("change", updateMode);

updateClock();
updateMode();

setInterval(updateClock, 1000);
