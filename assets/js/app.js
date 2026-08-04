import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

const Hooks = {}

Hooks.HistoryChart = {
  mounted() { this.render() },
  updated() { this.render() },
  destroyed() { if (this.chart) this.chart.destroy() },
  render() {
    const payload = JSON.parse(this.el.dataset.chart)
    const isPct = payload.metric === "pct"
    const fmt = (v) => isPct ? `${v.toLocaleString("es-ES")}%` : `€${v.toLocaleString("es-ES")}`

    const datasets = payload.datasets.map((ds) => ({
      label: ds.label,
      data: ds.data,
      borderColor: ds.color,
      backgroundColor: ds.fill ? ds.color + "26" : ds.color,
      borderWidth: 2,
      pointRadius: ds.data.length > 60 ? 0 : 3,
      pointHoverRadius: 6,
      fill: !!ds.fill,
      tension: 0.3
    }))

    if (this.chart) this.chart.destroy()

    // payload.labels switches the x axis from time scale to categories (e.g. month names)
    const xScale = payload.labels
      ? {title: {display: true, text: payload.xTitle || "Month"}}
      : {
          type: "time",
          time: {minUnit: "day", unit: payload.timeUnit, tooltipFormat: "dd/MM/yyyy", displayFormats: {day: "dd MMM", month: "MMM yyyy"}},
          title: {display: true, text: "Date"}
        }

    const ctx = this.el.querySelector("canvas").getContext("2d")
    // Only charts that ask for it become clickable; the rest keep no handler.
    const pushOnClick = payload.clickEvent
      ? (evt, _els, chart) => {
          const points = chart.getElementsAtEventForMode(evt, "index", {intersect: false}, true)
          if (!points.length) return
          const point = chart.data.datasets[points[0].datasetIndex].data[points[0].index]
          const date = point && point.x
          if (date) this.pushEvent(payload.clickEvent, {date: String(date).slice(0, 10)})
        }
      : undefined

    this.chart = new Chart(ctx, {
      type: "line",
      data: {labels: payload.labels, datasets},
      options: {
        responsive: true,
        onClick: pushOnClick,
        interaction: {mode: "index", intersect: false},
        plugins: {
          legend: {position: "top"},
          title: {display: true, text: payload.title || (isPct ? "Gain/Loss evolution (%)" : "Value evolution (€)"), font: {size: 18}},
          tooltip: {
            callbacks: {
              label: (ctx) => `${ctx.dataset.label}: ${fmt(ctx.parsed.y)}`
            }
          }
        },
        scales: {
          x: xScale,
          y: {
            ticks: {callback: (v) => fmt(v)}
          }
        }
      }
    })
  }
}

Hooks.CategoryPie = {
  mounted() { this.render() },
  updated() { this.render() },
  destroyed() { if (this.chart) this.chart.destroy() },
  render() {
    const {labels, values, colors} = JSON.parse(this.el.dataset.chart)
    const total = values.reduce((a, b) => a + b, 0)

    if (this.chart) this.chart.destroy()

    const ctx = this.el.querySelector("canvas").getContext("2d")
    this.chart = new Chart(ctx, {
      type: "doughnut",
      data: {
        labels,
        datasets: [{
          data: values,
          backgroundColor: colors,
          // A surface-coloured gap keeps adjacent slices separable, which
          // matters more than usual with this many categories.
          borderColor: "#ffffff",
          borderWidth: 2
        }]
      },
      options: {
        responsive: true,
        cutout: "55%",
        plugins: {
          // The table beside the chart already names every slice with its
          // value and share, so a second legend would just repeat it.
          legend: {display: false},
          tooltip: {
            callbacks: {
              label: (ctx) => {
                const v = ctx.parsed
                const pct = total > 0 ? (v / total * 100).toFixed(1) : "0.0"
                return `${ctx.label}: €${v.toLocaleString("es-ES")} (${pct}%)`
              }
            }
          }
        }
      }
    })
  }
}

Hooks.CategoryHistoryChart = {
  mounted() { this.render() },
  updated() { this.render() },
  destroyed() { if (this.chart) this.chart.destroy() },
  render() {
    const payload = JSON.parse(this.el.dataset.chart)
    const fmt = (v) => `€${Math.round(v).toLocaleString("es-ES")}`
    // Stacked: filled bands whose heights add up to the portfolio. Unstacked:
    // one line per category read against a shared axis, so the fills would
    // hide each other.
    const stacked = payload.stacked

    if (this.chart) this.chart.destroy()

    const ctx = this.el.querySelector("canvas").getContext("2d")
    this.chart = new Chart(ctx, {
      type: "line",
      data: {
        labels: payload.labels,
        // A dataset can opt out of the stack (`stack` in its own group, and
        // `fill: false`) to ride over the bands as a reference line instead of
        // adding to them — the invested line on the Bitcoin page does this.
        datasets: payload.datasets.map((ds) => ({
          label: ds.label,
          data: ds.data,
          borderColor: ds.color,
          backgroundColor: stacked ? ds.color + "cc" : ds.color,
          borderWidth: ds.width || (stacked ? 1 : 2),
          borderDash: ds.dash || [],
          stack: ds.stack,
          // ~570 daily points: markers would be noise, and the bands carry
          // the shape on their own.
          pointRadius: 0,
          pointHoverRadius: 4,
          fill: ds.fill === undefined ? stacked : ds.fill,
          tension: 0.2
        }))
      },
      options: {
        responsive: true,
        interaction: {mode: "index", intersect: false},
        plugins: {
          legend: {position: "top"},
          tooltip: {
            callbacks: {
              label: (ctx) => `${ctx.dataset.label}: ${fmt(ctx.parsed.y)}`,
              // Only the filled bands make up the total; an unstacked
              // reference line sits alongside them and must not be added in.
              footer: (items) => {
                const bands = items.filter((i) => i.dataset.fill)
                return stacked && bands.length ? `Total: ${fmt(bands.reduce((a, i) => a + i.parsed.y, 0))}` : null
              }
            }
          }
        },
        scales: {
          x: {
            type: "time",
            time: {minUnit: "day", tooltipFormat: "dd/MM/yyyy", displayFormats: {day: "dd MMM", month: "MMM yyyy"}},
            title: {display: true, text: "Date"}
          },
          y: {
            stacked,
            // Stacked areas encode magnitude by area, so the axis has to start
            // at zero or the bottom band is silently clipped.
            beginAtZero: true,
            ticks: {callback: (v) => fmt(v)}
          }
        }
      }
    })
  }
}

Hooks.DcaChart = {
  mounted() {
    const ctx = this.el.getContext('2d')
    this.chart = new Chart(ctx, {
      type: 'line',
      data: { datasets: [] },
      options: {
        responsive: true,
        interaction: { mode: 'index', intersect: false },
        plugins: {
          legend: { position: 'top' },
          tooltip: {
            callbacks: {
              label: item => {
                const v = item.parsed.y
                if (item.dataset.label === 'S&P500 (USD)') return `S&P500: $${v.toFixed(0)}`
                if (item.dataset.label === 'Invested (€)') return `Invested: ${v.toFixed(2)} €`
                return `${item.dataset.label}: ${v.toFixed(2)} €`
              }
            }
          }
        },
        scales: {
          x: {
            type: 'time',
            time: { unit: 'month', tooltipFormat: 'dd/MM/yyyy' },
            ticks: { maxTicksLimit: 12 }
          },
          y: {
            position: 'left',
            ticks: { callback: v => v.toFixed(0) + ' €' }
          },
          y1: {
            position: 'right',
            grid: { drawOnChartArea: false },
            ticks: { callback: v => '$' + v.toFixed(0) }
          },
          y2: {
            display: false
          }
        }
      }
    })

    this.handleEvent("update_dca_chart", ({ labels, baseline, actual, sp500, invested }) => {
      this.chart.data.labels = labels
      this.chart.data.datasets = [
        {
          label: '250 €/week (baseline)',
          data: baseline,
          borderColor: '#94a3b8',
          borderWidth: 2,
          pointRadius: 2,
          fill: false,
          tension: 0.1,
          yAxisID: 'y'
        },
        {
          label: 'With extra DCA',
          data: actual,
          borderColor: '#6366f1',
          borderWidth: 2,
          pointRadius: 2,
          fill: false,
          tension: 0.1,
          yAxisID: 'y'
        },
        {
          label: 'S&P500 (USD)',
          data: sp500,
          borderColor: '#f59e0b',
          borderWidth: 1.5,
          pointRadius: 2,
          fill: false,
          tension: 0.1,
          borderDash: [4, 3],
          yAxisID: 'y1'
        },
        {
          label: 'Invested (€)',
          data: invested,
          borderColor: '#34d399',
          borderWidth: 1.5,
          pointRadius: 3,
          fill: false,
          tension: 0,
          yAxisID: 'y2'
        }
      ]
      this.chart.update()
    })
  }
}

Hooks.DcaBitcoinChart = {
  mounted() {
    const ctx = this.el.getContext('2d')
    this.chart = new Chart(ctx, {
      type: 'line',
      data: { datasets: [] },
      options: {
        responsive: true,
        interaction: { mode: 'index', intersect: false },
        plugins: {
          legend: { position: 'top' },
          tooltip: {
            callbacks: {
              label: item => {
                const v = item.parsed.y
                if (item.dataset.label === 'Bitcoin (USD)') return `Bitcoin: $${v.toFixed(0)}`
                return `${item.dataset.label}: ${v.toFixed(2)} €`
              }
            }
          }
        },
        scales: {
          x: {
            type: 'time',
            time: { unit: 'month', tooltipFormat: 'dd/MM/yyyy' },
            ticks: { maxTicksLimit: 12 }
          },
          y: {
            position: 'left',
            ticks: { callback: v => v.toFixed(0) + ' €' }
          },
          y1: {
            position: 'right',
            grid: { drawOnChartArea: false },
            ticks: { callback: v => '$' + v.toFixed(0) }
          }
        }
      }
    })

    this.handleEvent("update_btc_dca_chart", ({ labels, invested, value, btc }) => {
      this.chart.data.labels = labels
      this.chart.data.datasets = [
        {
          label: 'Invested (€)',
          data: invested,
          borderColor: '#94a3b8',
          borderWidth: 2,
          pointRadius: 2,
          fill: false,
          tension: 0.1,
          yAxisID: 'y'
        },
        {
          label: 'Value (€)',
          data: value,
          borderColor: '#6366f1',
          borderWidth: 2,
          pointRadius: 2,
          fill: false,
          tension: 0.1,
          yAxisID: 'y'
        },
        {
          label: 'Bitcoin (USD)',
          data: btc,
          borderColor: '#f59e0b',
          borderWidth: 1.5,
          pointRadius: 2,
          fill: false,
          tension: 0.1,
          borderDash: [4, 3],
          yAxisID: 'y1'
        }
      ]
      this.chart.update()
    })
  }
}

// A dd/mm/yyyy text field over a hidden native date input. The text is what
// the user reads and types; the native input carries the ISO value the form
// submits and provides the calendar popup, which browsers render in their own
// locale but which we only open on demand.
Hooks.SpanishDate = {
  mounted() {
    this.text = this.el.querySelector(".es-date-text")
    this.native = this.el.querySelector(".es-date-native")

    this.el.querySelector(".es-date-btn").addEventListener("click", () => {
      try { this.native.showPicker() } catch (_) { this.native.focus() }
    })

    // A calendar pick already reaches the form's phx-change through the native
    // input; just mirror it into the text field for instant feedback.
    this.native.addEventListener("input", () => this.toText())

    this.text.addEventListener("change", () => this.commit())
    this.text.addEventListener("keydown", (e) => { if (e.key === "Enter") this.commit() })
  },
  toText() {
    this.text.value = this.native.value ? this.native.value.split("-").reverse().join("/") : ""
  },
  commit() {
    const m = this.text.value.trim().match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/)
    if (!m) return this.toText()

    let iso = `${m[3]}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`
    if (this.native.min && iso < this.native.min) iso = this.native.min
    if (this.native.max && iso > this.native.max) iso = this.native.max
    if (iso === this.native.value) return this.toText()

    this.native.value = iso
    this.native.dispatchEvent(new Event("input", { bubbles: true }))
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}, hooks: Hooks})
liveSocket.connect()
