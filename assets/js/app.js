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
      pointRadius: ds.data.length > 60 ? 0 : 3,
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

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}, hooks: Hooks})
liveSocket.connect()
