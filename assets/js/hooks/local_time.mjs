const LocalTime = {
  mounted() {
    this.renderTime()
  },

  updated() {
    this.renderTime()
  },

  renderTime() {
    const timestamp = new Date(this.el.dateTime)

    if (Number.isNaN(timestamp.getTime())) {
      this.el.textContent = "—"
      this.el.removeAttribute("title")
      return
    }

    this.el.textContent = new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "short",
      hourCycle: "h23",
    }).format(timestamp)

    this.el.title = new Intl.DateTimeFormat(undefined, {
      dateStyle: "full",
      timeStyle: "long",
      hourCycle: "h23",
    }).format(timestamp)
  },
}

export default LocalTime
