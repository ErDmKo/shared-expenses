// LiveView calls onDocumentPatch before applying a diff. Use its start callback
// so the browser captures the outgoing page before the DOM changes.
export function navigationTransitions(browserWindow = window, browserDocument = document) {
  let navigating = false
  let activeTransition = null

  browserWindow.addEventListener("phx:page-loading-start", ({detail}) => {
    if (detail?.kind === "redirect" || detail?.kind === "patch") navigating = true
  })

  browserWindow.addEventListener("phx:page-loading-stop", () => {
    navigating = false
  })

  return function onDocumentPatch(start) {
    const animate = navigating
      && typeof browserDocument.startViewTransition === "function"
      && browserDocument.visibilityState === "visible"
      && !browserWindow.matchMedia("(prefers-reduced-motion: reduce)").matches

    navigating = false

    if (!animate) {
      start()
      return
    }

    // Always apply each patch exactly once, even when a browser skips or rejects
    // the animation. Rapid navigation may interrupt the previous transition.
    let started = false
    const applyPatch = () => {
      if (started) return
      started = true
      start()
    }

    try {
      activeTransition?.skipTransition()
      const transition = browserDocument.startViewTransition(applyPatch)
      activeTransition = transition
      transition.ready.catch(() => {})
      transition.finished.catch(() => {}).finally(() => {
        if (activeTransition === transition) activeTransition = null
      })
    } catch {
      applyPatch()
    }
  }
}
