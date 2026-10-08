defmodule SharedExpensesWeb.HealthControllerTest do
  use SharedExpensesWeb.ConnCase

  test "GET /healthz responds without exposing event data", %{conn: conn} do
    conn = get(conn, ~p"/healthz")
    assert response(conn, 200) == "ok"
  end
end
