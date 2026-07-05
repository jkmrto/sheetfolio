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
      backgroundColor: ds.color,
      borderWidth: 2,
      pointRadius: 3,
      pointHoverRadius: 6,
      fill: false,
      tension: 0.3
    }))

    if (this.chart) this.chart.destroy()

    const ctx = this.el.querySelector("canvas").getContext("2d")
    this.chart = new Chart(ctx, {
      type: "line",
      data: {datasets},
      options: {
        responsive: true,
        interaction: {mode: "index", intersect: false},
        plugins: {
          legend: {position: "top"},
          title: {display: true, text: isPct ? "Gain/Loss evolution (%)" : "Value evolution (€)", font: {size: 18}},
          tooltip: {
            callbacks: {
              label: (ctx) => `${ctx.dataset.label}: ${fmt(ctx.parsed.y)}`
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
            ticks: {callback: (v) => fmt(v)}
          }
        }
      }
    })
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}, hooks: Hooks})
liveSocket.connect()
