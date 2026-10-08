defmodule SharedExpensesWeb.HealthController do
  use SharedExpensesWeb, :controller

  def show(conn, _params), do: send_resp(conn, 200, "ok")
end
