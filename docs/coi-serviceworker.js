/*! coi-serviceworker - based on v0.1.7 by Guido Zuidhof (MIT), hardened for GitHub Pages.
   Adds Cross-Origin-Opener-Policy / Cross-Origin-Embedder-Policy headers via a service worker
   so SharedArrayBuffer (the threaded Godot 4 web build) works on static hosts that don't send
   those headers. The window side hides the page until isolation is active (so Godot's
   "features missing" error never flashes) and reloads reliably once the SW is ready. */
let coepCredentialless = false;
if (typeof window === 'undefined') {
    // ---- service worker side: rewrite responses to add the isolation headers ----
    self.addEventListener("install", () => self.skipWaiting());
    self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));
    self.addEventListener("message", (ev) => {
        if (!ev.data) return;
        if (ev.data.type === "deregister") {
            self.registration.unregister()
                .then(() => self.clients.matchAll())
                .then(clients => clients.forEach(client => client.navigate(client.url)));
        } else if (ev.data.type === "coepCredentialless") {
            coepCredentialless = ev.data.value;
        }
    });
    self.addEventListener("fetch", function (event) {
        const r = event.request;
        if (r.cache === "only-if-cached" && r.mode !== "same-origin") return;
        const request = (coepCredentialless && r.mode === "no-cors")
            ? new Request(r, { credentials: "omit" })
            : r;
        event.respondWith(fetch(request).then((response) => {
            if (response.status === 0) return response;
            const newHeaders = new Headers(response.headers);
            newHeaders.set("Cross-Origin-Embedder-Policy",
                coepCredentialless ? "credentialless" : "require-corp");
            if (!coepCredentialless) newHeaders.set("Cross-Origin-Resource-Policy", "cross-origin");
            newHeaders.set("Cross-Origin-Opener-Policy", "same-origin");
            return new Response(response.body, {
                status: response.status, statusText: response.statusText, headers: newHeaders,
            });
        }).catch((e) => console.error(e)));
    });
} else {
    // ---- window side: ensure the page becomes cross-origin isolated, no error flash ----
    (() => {
        if (window.crossOriginIsolated) {
            window.sessionStorage.removeItem("coiReloads");
            return; // already isolated: let Godot boot normally
        }
        // Hide everything until we reload isolated, so Godot's "missing features" error never
        // shows. Reveal after a few seconds as a fallback (so a browser without SW support
        // still shows *something* instead of a permanently blank page).
        const html = document.documentElement;
        html.style.visibility = "hidden";
        setTimeout(() => { html.style.visibility = ""; }, 4000);

        if (!window.isSecureContext || !navigator.serviceWorker) { html.style.visibility = ""; return; }
        const scriptSrc = document.currentScript && document.currentScript.src;
        const tries = parseInt(window.sessionStorage.getItem("coiReloads") || "0", 10);
        if (tries >= 3) { html.style.visibility = ""; return; } // give up (avoid reload loops)

        const reload = () => {
            window.sessionStorage.setItem("coiReloads", (tries + 1).toString());
            window.location.reload();
        };
        navigator.serviceWorker.register(scriptSrc).then(() => {
            if (navigator.serviceWorker.controller) { reload(); return; }
            navigator.serviceWorker.ready.then(reload);
        }).catch((err) => { console.error("COOP/COEP SW register failed:", err); html.style.visibility = ""; });
    })();
}
