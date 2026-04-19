defmodule SheetfolioWeb do
  def controller do
    quote do
      use Phoenix.Controller, formats: [:html]
      import Plug.Conn
    end
  end

  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import Phoenix.HTML
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView, layout: false
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
