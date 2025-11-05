import { Controller } from "@hotwired/stimulus"

// This controller will be attached to the main search form.
export default class extends Controller {
  static targets = [ "resultsFrame" ]

  // This function is automatically called when a Turbo Frame is successfully replaced.
  // We use data-action="turbo:submit-end->search#scrollToTop" on the form.
  scrollToTop(event) {
    if (event.detail.success) {
      // Find the results frame by its ID and scroll it into view.
      const resultsFrame = document.getElementById('organization_search_results');
      if (resultsFrame) {
        // Use resultsFrame.scrollIntoView() or:
        window.scrollTo({
            top: resultsFrame.offsetTop - 100, // Scroll to the frame's top, minus a small buffer (100px) for fixed headers.
            behavior: 'smooth'
        });
      }
    }
  }
}